local test = require 'test'

terra foo(a: int): int
  switch a do
    case 1 then
      return 2
    case 2 then
      return 5
    else
      return 3
  end
end

test.eq(foo(1), 2)
test.eq(foo(2), 5)
test.eq(foo(3), 3)
test.eq(foo(4), 3)
