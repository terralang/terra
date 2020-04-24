local test = require 'test'

local function dotest(fn, a, b, c, d)
  test.eq(fn(1), a)
  test.eq(fn(2), b)
  test.eq(fn(3), c)
  test.eq(fn(4), d)
end

local terra foo(a: int): int
  switch a do
    case 1 then
      return 2
    case 2 then
      return 5
    end
  else
    return 3
  end
end

dotest(foo, 2, 5, 3, 3)

local terra empty(a: int): int
  switch a do
  end
  return -1
end

dotest(empty, -1, -1, -1, -1)

local terra single(a: int): int
  switch a do
    case 1 then 
      return 2
    end
  end
  return -1
end

dotest(single, 2, -1, -1, -1)

local terra justelse(a: int): int
  switch a do
    else
      return 3
  end
  return -1
end

dotest(justelse, 3, 3, 3, 3)

local terra values(a: int): int
  switch a + (a + a) do
    case 1 + (1 + 1) then
      return 2
    case 2 + (2 + 2) then
      return 5
    end
  else
    return 3
  end
  return -1
end

dotest(values, 2, 5, 3, 3)

local function returnval() return `8 end

local terra values2(a: int): int
  switch a * (a + a) do
    case 2 then
      return 2
    case [returnval()] then
      return 5
    end
  end
  return -1
end

dotest(values2, 2, 5, -1, -1)

local terra nested(a: int): int
  switch a do
    case 1 then
      switch a + a do
        case 2 then
          return 2
        end
      end
    end
  end
  return -1
end

dotest(nested, 2, -1, -1, -1)

local terra nested2(a: int): int
  switch a do
    case 1 then
      switch a + a do
        case 2 then
          return 2
        end
      end
    case 1 + 1 then
      switch a * a do
        case 4 then
          return 5
        end
      end
    end
  end
  return -1
end

dotest(nested2, 2, 5, -1, -1)

local terra nested3(a: int): int
  switch a do
    case 1 then
      switch a + a do
        case 1 then
          return -2
        end
      else
        return 2
      end
    case 2 then
      switch a * a do
        case 89 + 1 then
          return -5
        end
      else
        return 5
      end
    end
  else
    return 3
  end
  return -1
end

dotest(nested3, 2, 5, 3, 3)

local terra case_end_elision(a: int): int
  switch a do
    case 1 then
      return 1
  else
    return 2
  end
end

dotest(case_end_elision, 1, 2, 2, 2)

local case_quote_1 = quote
  case 1 then
    return 2
  case 2 then
    return 1
  end
end
local case_quote_2 = quote case 4 then return 5 end end
local terra quoted_cases(a: int): int
  switch a do
    [case_quote_1]
    case 3 then
      return 3
    end
    [case_quote_2]
  end
end

dotest(quoted_cases, 2, 1, 3, 5)

local terra escaped_cases(a: int): int
  switch a do
    escape
      local tbl = {4, 3, 2, 1}
      for i, v in ipairs(tbl) do
        emit quote case [i] then return [v] end end
      end
    end
  end
end

dotest(escaped_cases, 4, 3, 2, 1)
