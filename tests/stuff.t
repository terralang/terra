function foo(T)
  local fn = terra(base : &int8, size : int64) : T
    -- works if attributes are an immediate table
    return terralib.attrload([&T](base + 64), { isvolatile = true })
  end
  return fn
end

function bar(T, attrs)
  local fn = terra(base : &int8, size : int64) : T
    -- doesn't work if attributs are a table that's passed in
    return terralib.attrload([&T](base + 64), attrs)
  end
  return fn
end

foo(int64):disas()
bar(int64, `{ isvolatile = true }):disas()