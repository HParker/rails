require "active_record"
require "minitest/autorun"
require "logger"

# This connection will do for database-independent bug reports.
ActiveRecord::Base.establish_connection(adapter: "mysql2", username: "rails", database: "activerecord_unittest")
ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.integer :state
  end
end

class Post < ActiveRecord::Base
  before_validation { |post| puts "call callback before_validation" }
  after_validation { |post| puts "call callback after_validation" }
  before_save { |post| puts "call callback before_save" }
  # around_save { |post| puts "call callback after_save" }
  before_create { |post| puts "call callback before_create" }
  # around_create { |post| puts "call callback around_create" }
  after_create { |post| puts "call callback after_create" }
  after_save { |post| puts "call callback after_save" }
  before_update { |post| puts "call callback before_update" }
  # around_update { |post| puts "call callback around_update" }
  after_update { |post| puts "call callback after_update" }
  before_destroy { |post| puts "call callback before_destroy" }
  # around_destroy { |post| puts "call callback around_destroy" }
  after_destroy { |post| puts "call callback after_destroy" }
  after_commit { |post| puts "call callback after_commit" }
  after_rollback { |post| puts "call callback after_rollback" }
end


class BugTest < Minitest::Test
  def test_association_stuff
    Post.create!
  end
end
