require "active_record"
require "minitest/autorun"
require "logger"
# This connection will do for database-independent bug reports.
ActiveRecord::Base.establish_connection(adapter: "mysql2", username: "rails", database: "activerecord_unittest")
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Schema.define do
  create_table :a_posts, force: true do |t|
    t.text :title
    t.text :body

    t.timestamps
  end

  create_table :b_posts, force: true do |t|
    t.text :body
    t.text :title

    t.timestamps
  end
end

class APost < ActiveRecord::Base
end

class BPost < ActiveRecord::Base
end


class BugTest < Minitest::Test
  # A POSTS
  def test_title_defined_first_without_reload_updating_title_first
    post = APost.create

    post.title = "foo"
    post.body = "bar"

    post.save

    assert_equal ["title", "body", "updated_at"], post.saved_changes.keys
  end

  def test_title_defined_first_without_reload_updating_body_first
    post = APost.create

    post.body = "bar"
    post.title = "foo"

    post.save

    assert_equal ["title", "body", "updated_at"], post.saved_changes.keys
  end


  def test_title_defined_first_with_reload_updating_title_first
    post = APost.create

    post.reload

    post.title = "foo"
    post.body = "bar"

    post.save

    assert_equal ["title", "body", "updated_at"], post.saved_changes.keys
  end

  def test_title_defined_first_with_reload_updating_body_first
    post = APost.create

    post.reload

    post.body = "bar"
    post.title = "foo"

    post.save

    assert_equal ["title", "body", "updated_at"], post.saved_changes.keys
  end

  # B POSTS
  def test_body_defined_first_without_reload_updating_title_first
    post = BPost.create

    post.title = "foo"
    post.body = "bar"

    post.save

    assert_equal ["body", "title", "updated_at"], post.saved_changes.keys
  end

  def test_body_defined_first_without_reload_updating_body_first
    post = BPost.create

    post.body = "bar"
    post.title = "foo"

    post.save

    assert_equal ["body", "title", "updated_at"], post.saved_changes.keys
  end

  def test_body_defined_first_with_reload_updating_title_first
    post = BPost.create

    post.reload

    post.title = "foo"
    post.body = "bar"

    post.save

    assert_equal ["body", "title", "updated_at"], post.saved_changes.keys
  end

  def test_body_defined_first_with_reload_updating_body_first
    post = BPost.create

    post.reload

    post.body = "bar"
    post.title = "foo"

    post.save

    assert_equal ["body", "title", "updated_at"], post.saved_changes.keys
  end
end
