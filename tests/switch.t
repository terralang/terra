local test = require 'test'

function dotest(fn, a, b, c, d)
  test.eq(fn(1), a)
  test.eq(fn(2), b)
  test.eq(fn(3), c)
  test.eq(fn(4), d)
end

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

dotest(foo, 2, 5, 3, 3)

terra empty(a: int): int
  switch a do
  end
  return -1
end

dotest(empty, -1, -1, -1, -1)

terra single(a: int): int
  switch a do
    case 1 then 
      return 2
  end
  return -1
end

dotest(single, 2, -1, -1, -1)

terra justelse(a: int): int
  switch a do
    else
      return 3
  end
  return -1
end

dotest(justelse, 3, 3, 3, 3)

terra values(a: int): int
  switch a + (a + a) do
    case 1 + (1 + 1) then
      return 2
    case 2 + (2 + 2) then
      return 5
    else
      return 3
  end
  return -1
end

dotest(values, 2, 5, 3, 3)

function returnval() return `8 end

terra values2(a: int): int
  switch a * (a + a) do
    case 2 then
      return 2
    case [returnval()] then
      return 5
  end
  return -1
end

dotest(values2, 2, 5, -1, -1)

terra nested(a: int): int
  switch a do
    case 1 then
      switch a + a do
        case 2 then
          return 2
      end
  end
  return -1
end

dotest(nested, 2, -1, -1, -1)

terra nested2(a: int): int
  switch a do
    case 1 then
      switch a + a do
        case 2 then
          return 2
      end
    case 1 + 1 then
      switch a * a do
        case 4 then
          return 5
      end
  end
  return -1
end

dotest(nested2, 2, 5, -1, -1)

terra nested3(a: int): int
  switch a do
    case 1 then
      switch a + a do
        case 1 then
          return -2
        else
          return 2
      end
    case 2 then
      switch a * a do
        case 89 + 1 then
          return -5
        else
          return 5
      end
    else
      return 3
  end
  return -1
end

dotest(nested3, 2, 5, 3, 3)