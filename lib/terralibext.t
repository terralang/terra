-- terralibext.t enables Terra code generation for terralib without having to 
-- use asdl. The following methods are generated:
-- __init :: {&A} -> {}

local addmissinginit

-- A struct is managed if it implements __dtor
local function ismanaged(T)
    if T:isstruct() then
        addmissingdtor(T)
        if T.methods.__dtor then
            addmissinginit(T)
            return true
        end
    elseif T:isarray() then
        return ismanaged(T.type)
    end
    return false
end

-- Are any fields of the struct managed?
local function hasmanagedfields(V)
    for i,e in ipairs(V:getentries()) do
        if ismanaged(e.type) then
            return true
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

--check if we are dealing with a union field. We do not allow union fields inside a 
--managed type
local function checkuniontypelist(t)
    assert(terralib.israwlist(t) and #t > 0, "CompileError: expected a union type.")
    assert(t[1].type, "CompileError: expected a valid type.")
    local size = sizeof(t[1].type)
    for i,e in ipairs(t) do
        local T = e.type
        if T then
            assert(not ismanaged(T), "CompileError: managed types not allowed in union type.")
            --assert(sizeof(T) == size, "CompileError: expected union types to have identical size.")
        else
            error("CompileError: expected a valid type.")
        end
    end
end

--------------------------------------------------------------------------------
------------------- Generate __init, __dtor, __copy, __move --------------------
--------------------------------------------------------------------------------

--__create a missing __init for struct 'T' and all its entries
addmissinginit = terralib.memoize(function(T)
    local generated = false --flag that tracks if non-trivial code has been generated
    local runinit
    runinit = macro(function(receiver)
        local V = receiver:gettype()
        if V:isstruct() then
            addmissinginit(V)
            if hasmethod(V, "__init") then
                generated = true
                return `receiver:__init()
            end
        elseif V:isarray() then
            addmissinginit(V.type)
            if hasmethod(V, "__init") then
                generated = true
                return quote
                    for i = 0, V.N do
                        runinit(receiver[i])
                    end
                end
            end
        elseif V:ispointer() then
            generated = true
            return quote receiver = nil end
        end
        return quote end
    end)
    --generate __init method
    if T:isstruct() and not T.methods.__init and not T.__init_generated then
        local imp = terra(self : &T)
            escape
                for i,e in ipairs(T:getentries()) do
                    if e.field then
                        --regular fields
                        emit quote runinit(self.[e.field]) end
                    else
                        --take care of 'union' types
                        checkuniontypelist(e)
                        emit quote runinit(self.[e[1].field]) end
                    end
                end
            end
        end
        --flag that `addmissinginit` already has been called
        T.__init_generated = true
        --only add implementation of __init and __init_generated if a non-trivial one was generated
        if generated then
            T.methods.__init_generated = imp
            T.methods.__init = T.methods.__init_generated
        end
    end
end)

--------------------------------------------------------------------------------
------------------------- Add methods to terralib ------------------------------
--------------------------------------------------------------------------------

--add definitions such that we can access them from terralib
terralib.ext = {
    addmissing = {
        __init = addmissinginit,
    }
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