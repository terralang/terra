local std = {
    io  = terralib.includec("stdio.h")
}

local function addmissinginit(T)

    --flag that signals that a missing __init method needs to
    --be generated
    local generate = false

    local runinit = macro(function(self)
        local V = self:gettype()
        --avoid generating code for empty array initializers
        local function hasinit(U)
            if U:isstruct() then return U.methods.__init
            elseif U:isarray() then return hasinit(U.type)
            else return false end
        end
        if V:isstruct() then
            if not V.methods.__init then
                addmissinginit(V)
            end
            local method = V.methods.__init
            if method then
                generate = true
                return quote
                    self:__init()
                end
            end
        elseif V:isarray() and hasinit(V) then
            return quote
                var pa = &self
                for i = 0,T.N do
                    runinit((@pa)[i])
                end
            end
        elseif V:ispointer() then
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
                if expr and #expr.tree.statements > 0 then
                    stmts:insert(expr)
                end
            end
        end
        return stmts
    end)

    if T:isstruct() and T.methods.__init == nil then
        local method = terra(self : &T)
            std.io.printf("%s:__init - generated\n", [tostring(T)])
            generateinit(@self)
        end
        if generate then
            T.methods.__init = method
        else
            --set T.methods.__init to false. This means that addmissinginit(T) will not
            --attempt to generate 'T.methods.__init' twice
            T.methods.__init = false
        end
    end
end


local function addmissingdtor(T)

    --flag that signals that a missing __dtor method needs to
    --be generated
    local generate = false

    local rundtor = macro(function(self)
        local V = self:gettype()
        --avoid generating code for empty array destructors
        local function hasdtor(U)
            if U:isstruct() then return U.methods.__dtor
            elseif U:isarray() then return hasdtor(U.type)
            else return false end
        end
        if V:isstruct() then
            if not V.methods.__dtor then
                addmissingdtor(V)
            end
            local method = V.methods.__dtor
            if method then
                generate = true
                return quote
                    self:__dtor()
                end
            end
        elseif V:isarray() and hasdtor(V) then
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
                if expr and #expr.tree.statements > 0 then
                    stmts:insert(expr)
                end
            end
        end
        return stmts
    end)

    if T:isstruct() and T.methods.__dtor==nil then
        local method = terra(self : &T)
            std.io.printf("%s:__dtor - generated\n", [tostring(T)])
            generatedtor(@self)
        end
        if generate then
            T.methods.__dtor = method
        else
            --set T.methods.__dtor to false. This means that addmissingdtor(T) will not
            --attempt to generate 'T.methods.__dtor' twice
            T.methods.__dtor = false
        end
    end
end

local function addmissingcopy(T)

    --flag that signals that a missing __copy method needs to
    --be generated
    local generate = false

    local runcopy = macro(function(from, to)
        local U = from:gettype()
        local V = to:gettype()
        --avoid generating code for empty array initializers
        local function hascopy(W)
            if W:isstruct() then return W.methods.__copy
            elseif W:isarray() then return hascopy(W.type)
            else return false end
        end
        if V:isstruct() and U==V then
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
            if field then
                local expr = `runcopy(from.[field], to.[field])
                if expr and #expr.tree.statements > 0 then
                    stmts:insert(expr)
                end
            end
        end
        return stmts
    end)

    if T:isstruct() and T.methods.__copy==nil then
        local method = terra(from : &T, to : &T)
            std.io.printf("%s:__copy - generate\n", [tostring(T)])
            generatecopy(@from, @to)
        end
        if generate then
            T.methods.__copy = method
        else
            --set T.methods.__copy to false. This means that addmissingcopy(T) will not
            --attempt to generate 'T.methods.__copy' twice
            T.methods.__copy = false
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