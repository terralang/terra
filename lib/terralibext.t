-- terralibext.t enables Terra code generation for terralib without having to 
-- use asdl. The following methods are generated:
-- __init :: {&A} -> {}
-- __dtor :: {&A} -> {}
-- __copy :: {&A, &A} -> {}
-- __move :: {&A, &A} -> {}
-- In addition, (incomplete) named and unnamed constructors are generated

local C = terralib.includecstring [[
   #include <string.h>
]]

local addmissingdtor, addmissinginit

-- A struct is managed if it implements __dtor
local function ismanaged(T)
    if T:isstruct() then
        addmissingdtor(T)
        if T.methods.__dtor then
            return true
        end
    elseif T:isarray() then
        return ismanaged(T.type)
    end
    return false
end

--is this a regular entry
local function isregularentry(entry)
    if entry.field and entry.type then
        return true
    end
    return false
end

--is this a valid union entry
local function validateunionentry(entry)
    assert(not isregularentry(entry) and terralib.israwlist(entry) and #entry > 0, "CompileError: not a valid union field.")
    for i,e in ipairs(entry) do
        assert(isregularentry(e), "CompileError: expected a regular entry.")
        assert(not ismanaged(e.type), "CompileError: managed types not allowed in union type.")
    end
end

--select the {field, type} in a union that forms the largest allocation
local function selectunionmaxentry(entry)
    validateunionentry(entry)
    local size, index = 0, 1
    for i,e in ipairs(entry) do
        if sizeof(e.type) > size then 
            size, index = sizeof(e.type), i
        end
    end
    return entry[index]
end

--return a valid entry {field, type} for regular as well as union fields
local function selectvalidentry(entry)
    if isregularentry(entry) then
        return entry
    else
        return selectunionmaxentry(entry)
    end
end

-- Are any fields of the struct managed?
local function hasmanagedfields(V)
    for i,e in ipairs(V:getentries()) do
        if isregularentry(e) then
            if ismanaged(e.type) then
                return true --return early
            end
        else
            validateunionentry(e) --check the union field - it's not supposed to be managed
        end
    end
    return false
end

--check of a type W that is a struct or an array implements a certain method
local function hasmethod(W, method)
    if W:isstruct() then return W.methods[method]
    elseif W:isarray() then return hasmethod(W.type, method)
    else return false end
end

--check if object is a pointer (not a function pointer) or has pointer
--fields or elements.
local function haspointers(T)
    if T:isstruct() then
        for i,e in ipairs(T:getentries()) do
            if e.type and haspointers(e.type) then
                return true
            end
        end
        return false
    elseif T:isarray() then
        return haspointers(T.type)
    elseif T:ispointer() and not T:ispointertofunction() then
        return true
    else
        return false
    end
end

--------------------------------------------------------------------------------
------------------- Generate __init, __dtor, __copy, __move --------------------
--------------------------------------------------------------------------------

--__create a missing __init for struct 'T' and all its entries
addmissinginit = terralib.memoize(function(T)
    local runinit
    runinit = macro(function(receiver)
        local V = receiver:gettype()
        if V:isstruct() and ismanaged(V) then
            addmissinginit(V)
            if hasmethod(V, "__init") then
                return `receiver:__init()
            end
        elseif V:isarray() and ismanaged(V.type) then
            addmissinginit(V.type)
            if hasmethod(V, "__init") then
                return quote
                    for i = 0, V.N do
                        runinit(receiver[i])
                    end
                end
            end
        else
            return `C.memset(&receiver, 0, [sizeof(V)])
        end
    end)
    --generate __init method
    if T:isstruct() and not T.methods.__init and not T.__init_generated then
        if sizeof(T) > 0 then --no need to generate an `__init` if there is no data
            if hasmanagedfields(T) then
                T.methods.__init = terra(self : &T)
                    escape
                        for i,e in ipairs(T:getentries()) do
                            local entry = selectvalidentry(e) --select a valid entry (max of the union or regular entry)
                            emit quote runinit(self.[entry.field]) end
                        end
                    end
                end
            else
                T.methods.__init = terra(self : &T)
                    C.memset(self, 0, [sizeof(T)])
                end
            end
        end
        T.__init_generated = true --flag that signals that `__init is generated`
    end
end)

--__create a missing __dtor for 'T' and all its entries
addmissingdtor = terralib.memoize(function(T)
    local generated = false --flag that tracks if non-trivial code has been generated
    local rundtor
    rundtor = macro(function(receiver)
        local V = receiver:gettype()
        if V:isstruct() then
            addmissingdtor(V)
            if hasmethod(V, "__dtor") then
                generated = true
                return `receiver:__dtor()
            end
        elseif V:isarray() then
            addmissingdtor(V.type)
            if hasmethod(V, "__dtor") then
                generated = true
                return quote
                    for i = 0, V.N do
                        rundtor(receiver[i])
                    end
                end
            end
        end
        return quote end
    end)
    --generate __dtor
    if T:isstruct() and not T.methods.__dtor and not T.__dtor_generated then
        local imp = terra(self : &T)
            escape
                for i,e in ipairs(T:getentries()) do
                    if isregularentry(e) then --union's are skipped
                        emit quote rundtor(self.[e.field]) end
                    end
                end
            end
        end
        --flag that `addmissingdtor` already has been called
        T.__dtor_generated = true
        --if non-trivial destructor code was actually generated then
        --set assign the implementation to '__dtor' and '__dtor_generated'
        if generated then
            T.methods.__dtor_generated = imp
            T.methods.__dtor = T.methods.__dtor_generated
        end
    end
end)

--create a missing __move for 'T'
local addmissingmove
addmissingmove = terralib.memoize(function(T)
    if T:isstruct() and ismanaged(T) then
        if not T.methods.__move and not T.__move_generated then
            if sizeof(T)>0 then
                addmissinginit(T)
                T.methods.__move = terra(from : &T, to : &T)
                    to:__dtor()                         --clear old resources of 'to', just-in-case
                    C.memcpy(to, from, [sizeof(T)])     --copy data over
                    from:__init()                       --re-initializing bits of 'from'
                end
            end
            T.__move_generated = true
        elseif T.methods.__move and not T.__move_generated and not T.__move_overload then
            --`__move` cannot be user-implemented unless the `__move_overload` trait is set to true
            error("Compile Error: `"..tostring(T) ..".methods.__move` cannot be overloaded.")
        end
    end
end)


--__create a missing __copy for 'T' and all its entries
--a type T is copyable if all its fields are copyable.
--a `field` is copyable if:
--      [1] `field` is a struct and implements a __copy or by induction it is copyable.
--      [2] `field` is a primitive type or a simd vector which is trivially copyable.
--      [3] `field` is an array of copyable objects.
--vice versa, a `field` is not copyable when it is a pointer or a struct that does not
--have a (generated) __copy or an array of objects that are not copyable.
local addmissingcopy
addmissingcopy = terralib.memoize(function(T)
    local generated = false --flag to check if actual copy-constructors are called
    local copyable = true  --flag to check if the type T is unambiguously copyable
    local runcopy
    runcopy = macro(function(from, to)
        local V = from:gettype()
        if V:isstruct() then
            addmissingcopy(V)
            if hasmethod(V, "__copy") then
                generated = true
                return quote
                    [V.methods.__copy](&from, &to)
                end
            else
                --bit-copies for unmanaged structs
                if not ismanaged(V) and not haspointers(V) then
                    return quote
                        to = from --perform a bitcopy
                    end
                else
                    --managed structs without (generated) __copy or unmanaged
                    --structs containing pointers are not copyable
                    copyable = false
                    return quote end
                end                
            end
        elseif V:isarray() then
            return quote
                for i = 0, V.N do
                    runcopy(from[i], to[i])
                end
            end
        elseif V:ispointer() and not V:ispointertofunction() then
            copyable = false --pointers are not copyable
            return quote end
        else
            return quote
                to = from --perform a bitcopy
            end
        end
    end)
    --generate a __copy
    if T:isstruct() and not T.methods.__copy and not T.__copy_generated then
        local imp = terra(from : &T, to : &T)
            escape
                for i,e in ipairs(T:getentries()) do
                    local entry = selectvalidentry(e) --select a valid entry (max of the union or regular entry)
                    emit quote runcopy(from.[entry.field], to.[entry.field]) end
                end
            end
        end
        --flag that `addmissingcopy` has already been called
        T.__copy_generated = true
        --if non-trivial and valid copy-assignment code was actually generated then
        --set assign the implementation to '__copy' and '__copy_generated'
        if generated and copyable then
            T.methods.__copy_generated = imp
            T.methods.__copy = T.methods.__copy_generated
        end
    end
end)


--------------------------------------------------------------------------------
----------------------------- Generate constructors ----------------------------
--------------------------------------------------------------------------------

local constructor = terralib.memoize(function(from, to)
    assert(from:isstruct(), tostring(from) .. " is not a valid struct.")
    assert(to:isstruct(), tostring(to) .. " is not a valid struct.")
    --get layout of structs
    local from_layout, to_layout = from:getlayout(), to:getlayout()
    --from here on we use 'T' for 'to' type
    local T = to
    --check input
    assert(#from_layout.entries <= #to_layout.entries, "number of arguments exceeds number of struct entries.")
    --add 'constructor' table
    if not T.constructor then T.constructor = {} end
    --extract symbols for the argument list
    local argumentlist, keys = terralib.newlist{}, terralib.newlist{}
    for i,entry in ipairs(from_layout.entries) do
        argumentlist:insert(symbol(entry.type))
        local offset = from.convertible == "tuple" and i - 1 or to_layout.keytoindex[entry.key]
        assert(offset, "structural cast invalid, result structure has no key ".. tostring(entry.key))
        keys:insert(to_layout.entries[offset+1].key)
    end
    --generate a constructor if it has not been generated before
    local sig = table.concat(keys, "+") --serialize keys to get a unique key
    if not T.constructor[sig] then
        local nargs = #argumentlist --number of function arguments
        addmissinginit(T) --add empty initializer
        --generate implementation
        T.constructor[sig] = terra([argumentlist])
            var v : T --initializer will be auto-generated
            escape
                for i=1,nargs do
                    local key, rhs = keys[i], argumentlist[i]
                    emit quote
                        v.[key] = __move__([rhs]) --__move constructor will be used for struct objects
                    end
                end
            end
            return v
        end
    end
    return T.constructor[sig]
end)

--------------------------------------------------------------------------------
------------------------- Add methods to terralib ------------------------------
--------------------------------------------------------------------------------

--add definitions such that we can access them from terralib
terralib.ext = {
    addmissing = {
        __init = addmissinginit,
        __dtor = addmissingdtor,
        __copy = addmissingcopy,
        __move = addmissingmove,
        constructor = constructor
    },
    ismanaged = ismanaged,
    hasmanagedfields = hasmanagedfields
}

--------------------------------------------------------------------------------
------------------------- Generate Array methods -------------------------------
--------------------------------------------------------------------------------

local generate_array_method_implementation = function(V, method)
    if terralib.isfunction(method) then
        local nargs = #method.type.parameters
        if nargs == 1 then
            return terra(array : &V)
                for i = 0, V.N do
                    method(&((@array)[i]))
                end
            end
        elseif nargs==2 then
            return terra(source : &V, receiver : &V)
                for i = 0, V.N do
                    method(&((@source)[i]), &((@receiver)[i]))
                end
            end
        end
    end
end

--generate an array initializer or destructor, recursively.
local generatearraymethod
generatearraymethod = terralib.memoize(function(V, method)
    assert(V:isarray())
    local T = V.type
    if T:isstruct() then
        terralib.ext.addmissing[method](T)
        return generate_array_method_implementation(V, T.methods[method])
    elseif T:isarray() then
        return generate_array_method_implementation(V, generatearraymethod(T, method))
    end
end)

--add to addmissing exported methods
terralib.ext.addmissing.arraymethod = generatearraymethod