# frozen_string_literal: true

require "concurrent/map"
require "action_view/path_set"
require "ripper"

module ActionView
  module RipperASTParser
    class Node < ::Array
      attr_reader :type

      def initialize(type, arr, opts = {})
        @type = type
        super(arr)
      end

      def children
        to_a
      end

      def inspect
        typeinfo = type && type != :list ? ':' + type.to_s + ', ' : ''
        's(' + typeinfo + map(&:inspect).join(", ") + ')'
      end

      def fcall?
        type == :command || type == :fcall
      end

      def fcall_named?(name)
        fcall? &&
          self[0].type == :@ident &&
          self[0][0] == name
      end

      def argument_nodes
        raise unless fcall?
        return [] if self[1].nil?
        if self[1].last == false || self[1].last.type == :vcall
          self[1][0...-1]
        else
          self[1][0..-1]
        end
      end

      def string?
        type == :string_literal
      end

      def variable_reference?
        type == :var_ref
      end

      def vcall?
        type == :vcall
      end

      def call?
        type == :call
      end

      def variable_name
        self[0][0]
      end

      def call_method_name
        self.last.first
      end

      def to_string
        raise unless string?
        raise "fixme" unless self[0].type == :string_content
        raise "fixme" unless self[0][0].type == :@tstring_content
        self[0][0][0]
      end

      def hash?
        type == :bare_assoc_hash || type == :hash
      end

      def to_hash
        if type == :bare_assoc_hash
          hash_from_body(self[0])
        elsif type == :hash && self[0] == nil
          {}
        elsif type == :hash && self[0].type == :assoclist_from_args
          hash_from_body(self[0][0])
        else
          raise "not a hash? #{inspect}"
        end
      end

      def hash_from_body(body)
        body.map do |hash_node|
          return nil if hash_node.type != :assoc_new

          [hash_node[0], hash_node[1]]
        end.to_h
      end

      def symbol?
        type == :@label || type == :symbol_literal
      end

      def to_symbol
        if type == :@label && self[0] =~ /\A(.+):\z/
          $1.to_sym
        elsif type == :symbol_literal && self[0].type == :symbol && self[0][0].type == :@ident
          self[0][0][0].to_sym
        else
          raise "not a symbol?: #{self.inspect}"
        end
      end
    end

    class NodeParser < ::Ripper
      PARSER_EVENTS.each do |event|
        arity = PARSER_EVENT_TABLE[event]
        if /_new\z/ =~ event.to_s && arity == 0
          module_eval(<<-eof, __FILE__, __LINE__ + 1)
            def on_#{event}(*args)
              Node.new(:list, args, lineno: lineno(), column: column())
            end
          eof
        elsif /_add(_.+)?\z/ =~ event.to_s
          module_eval(<<-eof, __FILE__, __LINE__ + 1)
            begin; undef on_#{event}; rescue NameError; end
            def on_#{event}(list, item)
              list.push(item)
              list
            end
          eof
        else
          module_eval(<<-eof, __FILE__, __LINE__ + 1)
            begin; undef on_#{event}; rescue NameError; end
            def on_#{event}(*args)
              Node.new(:#{event}, args, lineno: lineno(), column: column())
            end
          eof
        end
      end

      SCANNER_EVENTS.each do |event|
        module_eval(<<-End, __FILE__, __LINE__ + 1)
          def on_#{event}(tok)
            Node.new(:@#{event}, [tok], lineno: lineno(), column: column())
          end
        End
      end
    end

    class RenderCallParser < NodeParser
      attr_reader :render_calls

      METHODS_TO_PARSE = %w(render render_to_string layout)

      def initialize(*args)
        super

        @render_calls = []
      end

      private

      def on_fcall(name, *args)
        on_render_call(super)
      end

      def on_command(name, *args)
        on_render_call(super)
      end

      def on_render_call(node)
        METHODS_TO_PARSE.each do |method|
          if node.fcall_named?(method)
            @render_calls << [method, node]
            return node
          end
        end
        node
      end

      def on_arg_paren(content)
        content
      end

      def on_paren(content)
        content
      end
    end

    extend self

    def parse_render_nodes(code)
      parser = RenderCallParser.new(code)
      parser.parse

      parser.render_calls.group_by(&:first).collect do |method, nodes|
        [ method.to_sym, nodes.collect { |v| v[1] } ]
      end.to_h
    end
  end

  RenderCall = Struct.new(:virtual_path, :locals_keys)

  class RenderParser
    def initialize(name, code, parser: RipperASTParser, from_controller: false)
      @name = name
      @code = code
      @parser = parser
      @from_controller = from_controller
    end

    def render_calls
      render_nodes = @parser.parse_render_nodes(@code)
      render_nodes.map do |method, nodes|
        parse_method = case method
                       when :layout
                         :parse_layout
                       else
                         :parse_render
                       end
        nodes.map { |n| send(parse_method, n) }
      end.flatten.compact
    end

    private

    def directory
      @name.split("/")[0..-2].join("/")
    end

    def resolve_path_directory(path)
      if path.match?("/")
        path
      else
        "#{directory}/#{path.singularize}"
      end
    end

    # Convert
    #   render("foo", ...)
    # into either
    #   render(template: "foo", ...)
    # or
    #   render(partial: "foo", ...)
    # depending on controller or view context
    def normalize_args(string, options_hash)
      if @from_controller
        if options_hash
          options = parse_hash_to_symbols(options_hash)
        else
          options = {}
        end
        return nil unless options
        options.merge(template: string)
      else
        if options_hash
          { partial: string, locals: options_hash }
        else
          { partial: string }
        end
      end
    end

    def parse_render(node)
      node = node.argument_nodes
      if (node.length == 1 || node.length == 2) && !node[0].hash?
        if node.length == 1
          options = normalize_args(node[0], nil)
        elsif node.length == 2
          return unless node[1].hash?
          options = normalize_args(node[0], node[1])
        end
        return nil unless options
        return parse_render_from_options(options)
      elsif node.length == 1 && node[0].hash?
        options = parse_hash_to_symbols(node[0])
        return nil unless options
        return parse_render_from_options(options)
      else
        nil
      end
    end

    def parse_layout(node)
      return nil unless from_controller?

      template = parse_str(node.argument_nodes[0])
      return nil unless template

      virtual_path = layout_to_virtual_path(template)
      RenderCall.new(virtual_path, [])
    end

    def parse_hash(node)
      node.hash? && node.to_hash
    end

    def parse_hash_to_symbols(node)
      hash = parse_hash(node)
      return unless hash
      hash.transform_keys do |key_node|
        key = parse_sym(key_node)
        return unless key
        key
      end
    end

    ALL_KNOWN_KEYS = [:partial, :template, :layout, :formats, :locals, :object, :collection, :as, :status, :content_type, :location, :spacer_template]

    def parse_render_from_options(options_hash)
      renders = []
      keys = options_hash.keys

      render_type_keys =
        if from_controller?
          [:partial, :template]
        else
          [:partial, :template, :layout]
        end

      if (keys & render_type_keys).size < 1
        # Must have at least one of render keys
        return nil
      end

      unless (keys - ALL_KNOWN_KEYS).empty?
        # de-opt in case of unknown option
        return nil
      end

      render_type = (keys & render_type_keys)[0]

      node = options_hash[render_type]
      if node.string?
        if @from_controller
          template = node.to_string
        else
          template = resolve_path_directory(node.to_string)
        end
      else
        if node.variable_reference?
          dependency = node.variable_name.sub(/\A(?:\$|@{1,2})/, "")
        elsif node.vcall?
          dependency = node.variable_name
        elsif node.call?
          dependency = node.call_method_name
        else
          return
        end
        object_template = true
        template = "#{dependency.pluralize}/#{dependency.singularize}"
      end

      return unless template

      if options_hash.key?(:locals)
        locals = options_hash[:locals]
        parsed_locals = parse_hash(locals)
        return nil unless parsed_locals
        locals_keys = parsed_locals.keys.map do |local|
          return nil unless local.symbol?
          local.to_symbol
        end
      else
        locals = nil
        locals_keys = []
      end

      if spacer_template = render_template_with_spacer?(options_hash)
        virtual_path = partial_to_virtual_path(:partial, spacer_template)
        # Locals keys should not include collection keys
        renders << RenderCall.new(virtual_path, locals_keys.dup)
      end

      if options_hash.key?(:object) || options_hash.key?(:collection) || object_template
        return nil if options_hash.key?(:object) && options_hash.key?(:collection)
        return nil unless options_hash.key?(:partial)

        as = if options_hash.key?(:as)
               parse_str(options_hash[:as]) || parse_sym(options_hash[:as])
             elsif File.basename(template) =~ /\A_?(.*?)(?:\.\w+)*\z/
               $1
             end

        return nil unless as

        locals_keys << as.to_sym
        if options_hash.key?(:collection)
          locals_keys << :"#{as}_counter"
          locals_keys << :"#{as}_iteration"
        end
      end

      virtual_path = partial_to_virtual_path(render_type, template)
      renders << RenderCall.new(virtual_path, locals_keys)

      # Support for rendering multiple templates (i.e. a partial with a layout)
      if layout_template = render_template_with_layout?(render_type, options_hash)
        virtual_path = if from_controller?
                         layout_to_virtual_path(layout_template)
                       else
                         if !layout_template.include?("/") &&
                            partial_prefix = template.match(%r{(.*)/([^/]*)\z})
                           # TODO: use the file path that this render call was found in to
                           # generate the partial prefix instead of rendered partial.
                           partial_prefix = partial_prefix[1]
                           layout_template = "#{partial_prefix}/#{layout_template}"
                         end
                         partial_to_virtual_path(:layout, layout_template)
                       end

        renders << RenderCall.new(virtual_path, locals_keys)
      end

      renders
    end

    def parse_str(node)
      node.string? && node.to_string
    end

    def parse_sym(node)
      node.symbol? && node.to_symbol
    end

    private

    def debug(message)
      warn message
    end

    def from_controller?
      @from_controller
    end

    def render_template_with_layout?(render_type, options_hash)
      if render_type != :layout && options_hash.key?(:layout)
        parse_str(options_hash[:layout])
      end
    end

    def render_template_with_spacer?(options_hash)
      if !from_controller? && options_hash.key?(:spacer_template)
        parse_str(options_hash[:spacer_template])
      end
    end

    def partial_to_virtual_path(render_type, partial_path)
      if render_type == :partial || render_type == :layout
        partial_path.gsub(%r{(/|^)([^/]*)\z}, '\1_\2')
      else
        partial_path
      end
    end

    def layout_to_virtual_path(layout_path)
      "layouts/#{layout_path}"
    end
  end

  class DependencyTracker # :nodoc:
    @trackers = Concurrent::Map.new

    def self.find_dependencies(name, template, view_paths = nil)
      tracker = @trackers[template.handler]
      return [] unless tracker

      tracker.call(name, template, view_paths)
    end

    def self.register_tracker(extension, tracker)
      handler = Template.handler_for_extension(extension)
      if tracker.respond_to?(:supports_view_paths?)
        @trackers[handler] = tracker
      else
        @trackers[handler] = lambda { |name, template, _|
          tracker.call(name, template)
        }
      end
    end

    def self.remove_tracker(handler)
      @trackers.delete(handler)
    end

    class RipperTracker
      EXPLICIT_DEPENDENCY = /# Template Dependency: (\S+)/
      def self.call(name, template, view_paths = nil)
        if template.source.include?("render") || true
          compiled_source = template.handler.call(template, template.source)
          RenderParser.new(name, compiled_source).render_calls + explicit_dependencies(template.source, view_paths)
        else
          []
        end
      end

      def self.supports_view_paths? # :nodoc:
        true
      end

      def self.explicit_dependencies(source, view_paths)
        dependencies = source.scan(EXPLICIT_DEPENDENCY).flatten.uniq

        wildcards, explicits = dependencies.partition { |dependency| dependency.end_with?("/*") }

        (explicits + resolve_directories(wildcards, view_paths)).uniq
      end

      def self.resolve_directories(wildcard_dependencies, view_paths)
        return [] unless view_paths
        return [] if wildcard_dependencies.empty?

        # Remove trailing "/*"
        prefixes = wildcard_dependencies.map { |query| query[0..-3] }

        view_paths.flat_map(&:all_template_paths).uniq.filter_map { |path|
          path.to_s if prefixes.include?(path.prefix)
        }.sort
      end
    end

    class ERBTracker # :nodoc:
      EXPLICIT_DEPENDENCY = /# Template Dependency: (\S+)/

      # A valid ruby identifier - suitable for class, method and specially variable names
      IDENTIFIER = /
        [[:alpha:]_] # at least one uppercase letter, lowercase letter or underscore
        [[:word:]]*  # followed by optional letters, numbers or underscores
      /x

      # Any kind of variable name. e.g. @instance, @@class, $global or local.
      # Possibly following a method call chain
      VARIABLE_OR_METHOD_CHAIN = /
        (?:\$|@{1,2})?            # optional global, instance or class variable indicator
        (?:#{IDENTIFIER}\.)*      # followed by an optional chain of zero-argument method calls
        (?<dynamic>#{IDENTIFIER}) # and a final valid identifier, captured as DYNAMIC
      /x

      # A simple string literal. e.g. "School's out!"
      STRING = /
        (?<quote>['"]) # an opening quote
        (?<static>.*?) # with anything inside, captured as STATIC
        \k<quote>      # and a matching closing quote
      /x

      # Part of any hash containing the :partial key
      PARTIAL_HASH_KEY = /
        (?:\bpartial:|:partial\s*=>) # partial key in either old or new style hash syntax
        \s*                          # followed by optional spaces
      /x

      # Part of any hash containing the :layout key
      LAYOUT_HASH_KEY = /
        (?:\blayout:|:layout\s*=>)   # layout key in either old or new style hash syntax
        \s*                          # followed by optional spaces
      /x

      # Matches:
      #   partial: "comments/comment", collection: @all_comments => "comments/comment"
      #   (object: @single_comment, partial: "comments/comment") => "comments/comment"
      #
      #   "comments/comments"
      #   'comments/comments'
      #   ('comments/comments')
      #
      #   (@topic)         => "topics/topic"
      #    topics          => "topics/topic"
      #   (message.topics) => "topics/topic"
      RENDER_ARGUMENTS = /\A
        (?:\s*\(?\s*)                                  # optional opening paren surrounded by spaces
        (?:.*?#{PARTIAL_HASH_KEY}|#{LAYOUT_HASH_KEY})? # optional hash, up to the partial or layout key declaration
        (?:#{STRING}|#{VARIABLE_OR_METHOD_CHAIN})      # finally, the dependency name of interest
      /xm

      LAYOUT_DEPENDENCY = /\A
        (?:\s*\(?\s*)                                  # optional opening paren surrounded by spaces
        (?:.*?#{LAYOUT_HASH_KEY})                      # check if the line has layout key declaration
        (?:#{STRING}|#{VARIABLE_OR_METHOD_CHAIN})      # finally, the dependency name of interest
      /xm

      def self.supports_view_paths? # :nodoc:
        true
      end

      def self.call(name, template, view_paths = nil)
        new(name, template, view_paths).dependencies
      end

      def initialize(name, template, view_paths = nil)
        @name, @template, @view_paths = name, template, view_paths
      end

      def dependencies
        render_dependencies + explicit_dependencies
      end

      attr_reader :name, :template
      private :name, :template

      private
      def source
        template.source
      end

      def directory
        name.split("/")[0..-2].join("/")
      end

      def render_dependencies
        render_dependencies = []
        render_calls = source.split(/\brender\b/).drop(1)

        render_calls.each do |arguments|
          add_dependencies(render_dependencies, arguments, LAYOUT_DEPENDENCY)
          add_dependencies(render_dependencies, arguments, RENDER_ARGUMENTS)
        end

        render_dependencies.uniq
      end

      def add_dependencies(render_dependencies, arguments, pattern)
        arguments.scan(pattern) do
          match = Regexp.last_match
          add_dynamic_dependency(render_dependencies, match[:dynamic])
          add_static_dependency(render_dependencies, match[:static], match[:quote])
        end
      end

      def add_dynamic_dependency(dependencies, dependency)
        if dependency
          dependencies << "#{dependency.pluralize}/#{dependency.singularize}"
        end
      end

      def add_static_dependency(dependencies, dependency, quote_type)
        if quote_type == '"'
          # Ignore if there is interpolation
          return if dependency.include?('#{')
        end

        if dependency
          if dependency.include?("/")
            dependencies << dependency
          else
            dependencies << "#{directory}/#{dependency}"
          end
        end
      end

      def resolve_directories(wildcard_dependencies)
        return [] unless @view_paths
        return [] if wildcard_dependencies.empty?

        # Remove trailing "/*"
        prefixes = wildcard_dependencies.map { |query| query[0..-3] }

        @view_paths.flat_map(&:all_template_paths).uniq.filter_map { |path|
          path.to_s if prefixes.include?(path.prefix)
        }.sort
      end

      def explicit_dependencies
        dependencies = source.scan(EXPLICIT_DEPENDENCY).flatten.uniq

        wildcards, explicits = dependencies.partition { |dependency| dependency.end_with?("/*") }

        (explicits + resolve_directories(wildcards)).uniq
      end
    end

    register_tracker :erb, RipperTracker
  end
end
