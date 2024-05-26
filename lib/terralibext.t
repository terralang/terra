local std = {
    io  = terralib.includec("stdio.h")
}

local function ondemand(fn)
    local method
    return macro(function(self,...)
        if not method then
            method = fn()
        end
        local args = {...}
        return `method(&self,[args])
    end)
end

local function addmissinginit(T)

    local generate = false

    local runinit = macro(function(self)
        local T = self:gettype()
        --avoid generating code for empty array initializers
        local function hasinit(T)
            if T:isstruct() then return T.methods.__init
            elseif T:isarray() then return hasinit(T.type)
            else return false end
        end
        if T:isstruct() then
            if not T.methods.__init then
                addmissinginit(T)
            end
            if T.methods.__init then
                return quote
                    self:__init()
                end
            end
        elseif T:isarray() and hasinit(T) then
            return quote
                var pa = &self
                for i = 0,T.N do
                    runinit((@pa)[i])
                end
            end
        elseif T:ispointer() then
            return quote
                self = nil
            end
        end
        return quote end
    end)

    local generateinit = macro(function(self)
        local T = self:gettype()
        local stmts = terralib.newlist()
        local entries = T:getentries()
        for i,e in ipairs(entries) do
            if e.field then
                local expr = `runinit(self.[e.field])
                if #expr.tree.statements > 0 then
                    generate = true
                end
                stmts:insert(
                    expr
                )
            end
        end
        return stmts
    end)

    if T:isstruct() and not T.methods.__init then
        local method = terra(self : &T)
            std.io.printf("%s:__init - default\n", [tostring(T)])
            generateinit(@self)
        end
        if generate then
            T.methods.__init = method
        end
    end
end


local function addmissingdtor(T)

    local generate = false

    local rundtor = macro(function(self)
        local T = self:gettype()
        --avoid generating code for empty array initializers
        local function hasdtor(T)
            if T:isstruct() then return T.methods.__dtor
            elseif T:isarray() then return hasdtor(T.type)
            else return false end
        end
        if T:isstruct() then
            if not T.methods.__dtor then
                addmissingdtor(T)
            end
            if T.methods.__dtor then
                return quote
                    self:__dtor()
                end
            end
        elseif T:isarray() and hasdtor(T) then
            return quote
                var pa = &self
                for i = 0,T.N do
                    rundtor((@pa)[i])
                end
            end
        end
        return quote end
    end)

    local generatedtor = macro(function(self)
        local T = self:gettype()
        local stmts = terralib.newlist()
        local entries = T:getentries()
        for i,e in ipairs(entries) do
            if e.field then
                local expr = `rundtor(self.[e.field])
                if #expr.tree.statements > 0 then
                    generate = true
                    stmts:insert(expr)
                end
            end
        end
        return stmts
    end)

    if T:isstruct() and not T.methods.__dtor then
        local method = terra(self : &T)
            std.io.printf("%s:__dtor - default\n", [tostring(T)])
            generatedtor(@self)
        end
        if generate then
            T.methods.__dtor = method
        end
    end
end

local function addmissingcopy(T)

    local generate = false

    local runcopy = macro(function(from, to)
        local V = from:gettype()
        --avoid generating code for empty array initializers
        local function hascopy(U)
            if U:isstruct() then return U.methods.__copy
            elseif U:isarray() then return hascopy(U.type)
            else return false end
        end
        if V:isstruct() then
            if not V.methods.__copy then
                addmissingcopy(V)
            end
            local method = V.methods.__copy
            if method then
                generate = true
                return quote
                    method(&from, &to)
                end
            else
                return quote
                    to = from
                end
            end
        elseif V:isarray() and hasdtor(V) then
            return quote
                var pa = &self
                for i = 0,V.N do
                    rundtor((@pa)[i])
                end
            end
        else
            return quote
                to = from
            end
        end
        return quote end
    end)

    local generatecopy = macro(function(from, to)
        local stmts = terralib.newlist()
        local entries = T:getentries()
        for i,e in ipairs(entries) do
            local field = e.field
            local expr = `runcopy(from.[field], to.[field])
            print(expr)
            if expr and #expr.tree.statements > 0 then
                stmts:insert(expr)
            end
        end
        return stmts
    end)

    if T:isstruct() and not T.methods.__copy then
        local method = terra(from : &T, to : &T)
            std.io.printf("%s:__copy - default\n", [tostring(T)])
            generatecopy(@from, @to)
        end
        if generate then
            T.methods.__copy = method
        end
    end
end

terralib.ext = {
    addmissing = {
        __init = addmissinginit,
        __dtor = addmissingdtor,
        __copy = addmissingcopy
    }
}