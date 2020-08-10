require "minitest/autorun"


class Post
  def inititalize
    foo = 1
  end

  attr_reader :foo
end

p = Post.new

m = Marshal.dump(p)

class Post
  def inititalize
    @foo = 1
  end
  end
