# Change that broke this: https://github.com/rails/rails/pull/39820/files#diff-abb244a8c26afeef0165452650430244R185
# Created here: https://github.com/github/github/blob/9bc11753a49808d04f513595c25b668b40eb0696/app/models/newsies/notification_entry.rb#L180

# Changing
# attribute(attr, **default) do |subtype|
# To
# decorate_attribute_type(attr, :enum) do |subtype|
# fixes this issue

# THIS SCRIPT DOES NOT REPRODUCE THE ISSUE, INSTEAD IT HAS CORRECT BEHAVIOR.

require "active_record"
require "minitest/autorun"
require "logger"

# This connection will do for database-independent bug reports.
ActiveRecord::Base.establish_connection(adapter: "mysql2", username: "rails", database: "activerecord_unittest")
ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.column :state, "TINYINT(1)"
  end
end

class Post < ActiveRecord::Base
  attribute :unread, :integer
  enum state: {
         start: 0,
         middle: 1,
         finish: 2
       }
end

class BugTest < Minitest::Test
  def test_association_stuff
    p = Post.create(state: :middle)

    assert_equal "middle", p.state
  end
end
