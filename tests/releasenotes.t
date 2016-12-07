--[[
Struct Consistency Changes
==========================

This release has changes to how meta-methods, macros, and overloaded operators are dispatched to make their declaration and definition more consistent.

Normal method declaration is unchanged, so will not need to be updated.

Meta-behavior, static methods, and macros may need some syntactic adjustments, but all the functionality is still present.

Here is an example:
]]

local C = terralib.includecstring [[
   #include <stdio.h>
   #include <stdlib.h>
]]

struct Complex {
   real : float
   imag : float
}

-- 'static' method definition (used to be Complex.methods.alloc)
terra Complex.create(r : float, i : float)
   return Complex { r,i }
end

-- standard method (unchanged)
terra Complex:printmethod()
   C.printf("{%f %f}\n",self.real,self.imag)
   return self
end

-- operators (can now be defined as a method, used to be in meta-methods)
terra Complex:__add(rhs : &Complex)
   return Complex.create(self.real+rhs.real, self.imag + rhs.imag)
end

-- Methods and operators can be macros (unchanged)
-- but Lua functions are now assumed to be macros _by default_ (used to be an error)
-- defining a MACRO

function Complex:printmacro()
   -- 'self' is a quote of the object
   assert(self:gettype() == Complex)
   local typename = tostring(Complex)
   return quote
      -- self is a quote whose type is a pointer to the object
      -- put it in a variable so it only executes once
      var self = self
      C.printf("%s {%f %f}\n",typename,self.real,self.imag)
   end
end

-- metamethods like __getmethod are now defined directly on Complex. Default behaviors are predefined in Complex.__getmethod and can be used as a chain of command
local getdefault = Complex.__getmethod -- default
function Complex:__getmethod(name)
   local m = getdefault(self,name)
   if not m then
      terra m(s : &Complex)
         C.printf("missing: %s\n",name)
      end
   end
   return m
end

-- You are free to store any meta-data about your type as methods or fields directly in the type object:
function Complex:elementtype()
   return float
end

-- You will get an error of you try to define a non-overridable method on Terra Type objects
--[[ error:
function Complex:isprimitive()
   return false
end
]]

terra uses()
   var a = Complex.create(1,3)
   var b = Complex.create(2,4)
   var c = a + b
   c:printmethod()
   c:printmacro()
   c:doesntexist()
end
uses()


--[[
-- support for luarocks install
-- support for LLVM 3.8 (experimental 3.9 support)
-- Terra path is configured to match lua path for installing mixed Lua-Terra packages
-- better debug info support with LLVM 3.8 (use -gg on osx, on linux use -g with gdb or -gg with any debugger)
-- experimental support for Lua type annotations (behavior may change in the future)
-- a more powerful Lua List data-type with functional language features (:map, :filter, etc.) useful for meta-programming
]]
