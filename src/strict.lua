--
-- strict.lua (adapted from LuaJIT-2.0.0-beta10)
-- checks uses of undeclared global variables
-- All global variables must be 'declared' through a regular assignment
-- (even assigning nil will do) in a main chunk before being used
-- anywhere or assigned to inside a function.
--

local getinfo, error, rawset, rawget = debug.getinfo, error, rawset, rawget

if getmetatable(_G) ~= nil then -- if another package has already altered the global environment then don't try to install the strict module
    return
end

local mt = { strict = true }
Strict = mt
setmetatable(_G, mt)

mt.__declared = {}

local function what ()
  local d = getinfo(3, "S")
  return d and d.what or "C"
end

mt.__newindex = function (t, n, v)
  if not mt.__declared[n] then
    local w = what()
    if mt.strict and w ~= "main" and w ~= "C" then
      error("Attempting to assign to previously undeclared global variable '"..n.."' from inside a function. If this variable is local to the function, it needs to be tagged with the 'local' keyword. If it is a global variable, it needs to be defined at the global scope before being used in a function.", 2)
    end
    mt.__declared[n] = true
  end
  rawset(t, n, v)
end

mt.__index = function (t, n)
  if mt.strict and not mt.__declared[n] and what() ~= "C" then
    error("Global variable '"..n.."' is not declared. Global variables must be 'declared' through a regular assignment (even to nil) at global scope before being used.", 2)
  end
  return rawget(t, n)
end

