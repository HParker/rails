# frozen_string_literal: true

require "concurrent/map"
require "action_view/path_set"
require "action_view/ripper_ast_parser"
require "action_view/render_parser"

module ActionView
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

    class RipperTracker # :nodoc:
      def initialize(name, template, view_paths = nil)
        @name, @template, @view_paths = name, template, view_paths
      end

      EXPLICIT_DEPENDENCY = /# Template Dependency: (\S+)/
      def self.call(name, template, view_paths = nil)
        new(name, template, view_paths).dependencies
      end

      def dependencies
        if template.source.include?("render") || true
          render_dependencies + explicit_dependencies
        else
          []
        end
      end

      def self.supports_view_paths? # :nodoc:
        true
      end

      attr_reader :template, :name, :view_paths
      private :template, :name, :view_paths

      private
        def render_dependencies
          compiled_source = template.handler.call(template, template.source)
          RenderParser.new(@name, compiled_source).render_calls.filter_map do |render_call|
            next if render_call.end_with?("/_")
            render_call.gsub(%r|/_|, "/")
          end
        end
        def explicit_dependencies
          dependencies = template.source.scan(EXPLICIT_DEPENDENCY).flatten.uniq

          wildcards, explicits = dependencies.partition { |dependency| dependency.end_with?("/*") }

          (explicits + resolve_directories(wildcards)).uniq
        end

        def resolve_directories(wildcard_dependencies)
          return [] unless view_paths
          return [] if wildcard_dependencies.empty?

          # Remove trailing "/*"
          prefixes = wildcard_dependencies.map { |query| query[0..-3] }

          view_paths.flat_map(&:all_template_paths).uniq.filter_map { |path|
            path.to_s if prefixes.include?(path.prefix)
          }.sort
        end
    end

    register_tracker :erb, RipperTracker
  end
end
