require "active_record"
require "minitest/autorun"
require "logger"

# This connection will do for database-independent bug reports.
ActiveRecord::Base.establish_connection(adapter: "mysql2", username: "rails", database: "activerecord_unittest")
ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.text :title
    t.integer :state
  end
end

module MyStateMachine
  def self.included(base)
    base.extend(ClassMethods)
    base.include(InstanceMethods)

    base.before_validation :write_initial_state
  end

  module ClassMethods
    def define_workflow_methods
      ["start", "middle", "end"].each do |event|
        module_eval do
          define_method "#{event}!".to_sym do |*args|
            process_event!(event, *args)
          end
        end
      end
    end
  end

  module InstanceMethods
    def write_initial_state
      write_attribute("state", 1)
    end

    def process_event!(name, *args)
      puts "BEFORE TRANSITION"

      update_column("state", ["start", "middle", "end"].index(name))
      # transition_value = persist_workflow_state(["start", "middle", "end"].index("middle"))

      puts "AFTER TRANSITION"
    end
  end

  def persist_workflow_state(new_value)
    update_column("state", new_value)
  end
end

class Post < ActiveRecord::Base
  include MyStateMachine
  define_workflow_methods

  attr_reader :callbacks_called

  def clear_callbacks
    @callbacks_called = []
  end

  before_validation { |post|
    puts "call callback before_validation"
    @callbacks_called ||= []
    @callbacks_called << "before_validation"
  }
  after_validation { |post|
    puts "call callback after_validation"
    @callbacks_called ||= []
    @callbacks_called << "after_validation"
  }
  before_save { |post|
    puts "call callback before_save"
    @callbacks_called ||= []
    @callbacks_called << "before_save"
  }
  # around_save { |post| puts "call callback after_save" }
  before_create { |post|
    puts "call callback before_create"
    @callbacks_called ||= []
    @callbacks_called << "before_create"
  }
  # around_create { |post| puts "call callback around_create" }
  @callbacks_called ||= []
  @callbacks_called << []
  after_create { |post|
    puts "call callback after_create"
    @callbacks_called ||= []
    @callbacks_called << "after_create"
  }
  after_save { |post|
    puts "call callback after_save"
    @callbacks_called ||= []
    @callbacks_called << "after_save"
  }
  before_update { |post|
    puts "call callback before_update"
    @callbacks_called ||= []
    @callbacks_called << "before_update"
  }
  # around_update { |post| puts "call callback around_update" }
  after_update { |post|
    puts "call callback after_update"
    @callbacks_called ||= []
    @callbacks_called << "after_update"
  }
  before_destroy { |post|
    puts "call callback before_destroy"
    @callbacks_called ||= []
    @callbacks_called << "before_destroy"
  }
  # around_destroy { |post| puts "call callback around_destroy" }
  after_destroy { |post|
    puts "call callback after_destroy"
    @callbacks_called ||= []
    @callbacks_called << "after_destroy"
  }
  after_commit { |post|
    puts "call callback after_commit"
    @callbacks_called ||= []
    @callbacks_called << "after_commit"
  }

  after_rollback { |post|
    puts "call callback after_rollback"
    @callbacks_called ||= []
    @callbacks_called << "after_rollback"
  }
end


class BugTest < Minitest::Test
  def test_standard_create
    post = Post.create
    expected_callbacks = ["before_validation", "after_validation", "before_save", "before_create", "after_create", "after_save", "after_commit"]
    assert_equal expected_callbacks, post.callbacks_called

    assert_equal [], post.saved_changes.keys
  end

  def test_standard_update
    post = Post.create
    post.clear_callbacks

    post.update(title: "new title")

    expected_callbacks = ["before_validation", "after_validation", "before_save", "before_update", "after_update", "after_save", "after_commit"]
    assert_equal expected_callbacks, post.callbacks_called
  end

  def test_standard_update
    post = Post.create
    post.clear_callbacks

    post.update(title: "new title")

    expected_callbacks = ["before_validation", "after_validation", "before_save", "before_update", "after_update", "after_save", "after_commit"]
    assert_equal expected_callbacks, post.callbacks_called
  end

  # TODO TEST DESTROY

  def test_state_transition
    post = Post.create
    post.clear_callbacks

    post_updated = post.updated_at

    post.middle!

    asssert_equal post.updated_at, post_updated

    expected_callbacks = []
    assert_equal [], post.saved_changes.keys
    assert_equal expected_callbacks, post.callbacks_called
  end

  def test_state_transition_in_transaction
    post = Post.create
    post.clear_callbacks

    Post.transaction do
      post.middle!
    end

    expected_callbacks = []
    assert_equal expected_callbacks, post.callbacks_called
  end

  def test_state_transition_with_other_changes
    post = Post.create
    post.clear_callbacks

    post.title = "new title"
    post.middle!

    expected_callbacks = []
    assert_equal expected_callbacks, post.callbacks_called
  end

  def test_state_transition_with_other_changes_save
    post = Post.create
    post.clear_callbacks

    post.title = "new title"
    post.middle!

    expected_callbacks = []
    assert_equal expected_callbacks, post.callbacks_called

    post.save

    expected_callbacks = ["before_validation", "after_validation", "before_save", "before_update", "after_update", "after_save", "after_commit"]
    assert_equal expected_callbacks, post.callbacks_called
  end

  def test_state_transition_with_other_changes_transaction
    post = Post.create
    post.clear_callbacks

    Post.transaction do
      post.title = "new title"
      post.middle!
    end

    expected_callbacks = []
    assert_equal expected_callbacks, post.callbacks_called
  end
end
