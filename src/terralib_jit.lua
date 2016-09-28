local util = require("util")
--debug wrapper around cdef function to print out all the things being defined
local ffi = require("ffi")
local T = terra.irtypes

local oldcdef = ffi.cdef
ffi.cdef = function(...)
    util.dbprint(2,...)
    return oldcdef(...)
end

-- Translate a Terra type to a LuaJIT FFI c definition:

function T.struct:definecstruct(layout)
    local nm = assert(self.cachedcstring)
    local str = "struct "..nm.." { "
    local entries = layout.entries
    for i,v in ipairs(entries) do
    
        local prevalloc = entries[i-1] and entries[i-1].allocation
        local nextalloc = entries[i+1] and entries[i+1].allocation

        if v.inunion and prevalloc ~= v.allocation then
            str = str .. " union { "
        end
        
        local keystr = terra.islabel(v.key) and v.key:tocname() or v.key
        str = str..v.type:cstring().." "..keystr.."; "
        
        if v.inunion and nextalloc ~= v.allocation then
            str = str .. " }; "
        end
        
    end
    str = str .. "};"
    local status,err = pcall(ffi.cdef,str)
    if not status then 
        if err:match("attempt to redefine") then
            print(("warning: attempting to define a C struct %s that has already been defined by the luajit ffi, assuming the Terra type matches it."):format(nm))
        else error(err) end
    end
end

local uniquetypenameset = util.uniquenameset("_") 
--sanitize a string, making it a valid lua/C identifier
local function tovalididentifier(name)
    return tostring(name):gsub("[^_%w]","_"):gsub("^(%d)","_%1"):gsub("^$","_") --sanitize input to be valid identifier
end
local function uniquecname(name) --used to generate unique typedefs for C
    return uniquetypenameset(tovalididentifier(name))
end
 --map from luajit ffi ctype objects to corresponding terra type
local ctypetoterra = {}
   
function T.Type:cstring()
    if not self.cachedcstring then
        --assumption: cstring needs to be an identifier, it cannot be a derived type (e.g. int*)
        --this makes it possible to predict the syntax of subsequent typedef operations
        if self:isintegral() then
            self.cachedcstring = tostring(self).."_t"
        elseif self:isfloat() then
            self.cachedcstring = tostring(self)
        elseif self:ispointer() and self.type:isfunction() then --function pointers and functions have the same typedef
            local ftype = self.type
            local rt = (ftype.returntype:isunit() and "void") or ftype.returntype:cstring()
            local function getcstring(t)
                if t == terra.types.rawstring then
                    --hack to make it possible to pass strings to terra functions
                    --this breaks some lesser used functionality (e.g. passing and mutating &int8 pointers)
                    --so it should be removed when we have a better solution
                    return "const char *"
                else
                    return t:cstring()
                end
            end
            local pa = ftype.parameters:map(getcstring)
            if not self.cachedcstring then
                pa = util.mkstring(pa,"(",",","")
                if ftype.isvararg then
                    pa = pa .. ",...)"
                else
                    pa = pa .. ")"
                end
                local ntyp = uniquecname("function")
                local cdef = "typedef "..rt.." (*"..ntyp..")"..pa..";"
                ffi.cdef(cdef)
                self.cachedcstring = ntyp
            end
        elseif self:isfunction() then
            error("asking for the cstring for a function?",2)
        elseif self:ispointer() then
            local value = self.type:cstring()
            if not self.cachedcstring then
                local nm = uniquecname("ptr_"..value)
                ffi.cdef("typedef "..value.."* "..nm..";")
                self.cachedcstring = nm
            end
        elseif self:islogical() then
            self.cachedcstring = "bool"
        elseif self:isstruct() then
            local nm = uniquecname(tostring(self))
            ffi.cdef("typedef struct "..nm.." "..nm..";") --just make a typedef to the opaque type
                                                          --when the struct is 
            self.cachedcstring = nm
            if self.cachedlayout then
                self:definecstruct(self.cachedlayout)
            end
        elseif self:isarray() then
            local value = self.type:cstring()
            if not self.cachedcstring then
                local nm = uniquecname(value.."_arr")
                ffi.cdef("typedef "..value.." "..nm.."["..tostring(self.N).."];")
                self.cachedcstring = nm
            end
        elseif self:isvector() then
            local value = self.type:cstring()
            local elemSz = ffi.sizeof(value)
            local nm = uniquecname(value.."_vec")
            local pow2 = 1 --round N to next power of 2
            while pow2 < self.N do pow2 = 2*pow2 end
            ffi.cdef("typedef "..value.." "..nm.." __attribute__ ((vector_size("..tostring(pow2*elemSz)..")));")
            self.cachedcstring = nm 
        elseif self == terra.types.niltype then
            local nilname = uniquecname("niltype")
            ffi.cdef("typedef void * "..nilname..";")
            self.cachedcstring = nilname
        elseif self == terra.types.opaque then
            self.cachedcstring = "void"
        elseif self == terra.types.error then
            self.cachedcstring = "int"
        else
            error("NYI - cstring")
        end
        if not self.cachedcstring then error("cstring not set? "..tostring(self)) end
        
        --create a map from this ctype to the terra type to that we can implement terra.typeof(cdata)
        local ctype = ffi.typeof(self.cachedcstring)
        ctypetoterra[tonumber(ctype)] = self
        local rctype = ffi.typeof(self.cachedcstring.."&")
        ctypetoterra[tonumber(rctype)] = self
        
        if self:isstruct() then
            local function index(obj,idx)
                local method = self:getmethod(idx)
                if terra.ismacro(method) then
                    error("calling a terra macro directly from Lua is not supported",2)
                end
                return method
            end
            ffi.metatype(ctype, self.metamethods.__luametatable or { __index = index })
        end
    end
    return self.cachedcstring
end
for _,typ in ipairs(terra.types.integraltypes) do
    typ:cstring() --pre-register with LuaJIT FFI to make typeof work for 1ULL, etc.
end

function T.terrafunction:__call(...)
    local ffiwrapper = self:getpointer()
    return ffiwrapper(...)
end

-- equivalent to ffi.typeof, takes a cdata object and returns associated terra type object
function terra.typeof(obj)
    if type(obj) ~= "cdata" then
        error("cannot get the type of a non cdata object")
    end
    return ctypetoterra[tonumber(ffi.typeof(obj))]
end
function terra.string(ptr,len)
    return ffi.string(ptr,len)
end
function terra.new(terratype,...)
    terratype:complete()
    local typ = terratype:cstring()
    return ffi.new(typ,...)
end
function terra.offsetof(terratype,field)
    terratype:complete()
    local typ = terratype:cstring()
    if terra.islabel(field) then
        field = field:tocname()
    end
    return ffi.offsetof(typ,field)
end
function terra.cast(terratype,obj)
    terratype:complete()
    local ctyp = terratype:cstring()
    return ffi.cast(ctyp,obj)
end