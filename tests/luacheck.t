local List = require("terralist")
function failit(match : "string",fn : "function")
	local success,msg = xpcall(fn,debug.traceback)
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end
local asdl = require('asdl')
local T = asdl.NewContext()
T:Define [[
    Exp = Apply(Exp l, Exp r)
        | Var(string a)
        | Lambda(string v, Exp b)
]]

local a = { b = {} }
a.b.foo = function(x : "number", y : "boolean") : "number","boolean"
    local function bar( a : "int") : "bool" return true end
    do
        return 1,true
    end
end

a.b.bar = a.b.foo

function bar()
a.b.foo(1,true)
end
bar()

failit("bad argument #2 to 'foo' expected 'boolean' but found 'nil'",function() a.b.foo(1) end)
failit("bad argument #2 to 'foo' expected 'boolean' but found 'table' %(metatable = Var%)",function() a.b.foo(1,T.Var("a")) end)
failit("bad argument #1 to 'foo' expected 'number' but found 'string'",function() a.b.foo("hi",true) end)

function interpret(env,exp : T.Exp) : T.Lambda
    if exp.kind == "Var" then
        return env(exp.a)
    elseif exp.kind == "Lambda" then
        return exp
    elseif exp.kind == "Apply" then
        local lambda = interpret(env,exp.l)
        local arg = interpret(env,exp.r)
        local function nenv(s : "string") : T.Lambda
            if lambda.v == s then
                return arg
            else
                return env(s)
            end
        end
        return interpret(nenv,lambda.b)
    end
    error("kind?")
end
local function undef(s : "string") error("undefined symbol "..s) end
-- \x.x
local ident = T.Lambda("x",T.Var("x"))
assert(ident ==interpret(undef,T.Apply(ident,ident)))


local Any = { isclassof = function() return true end }
local function a( what : Any ) : "string"
    return what
end

a("hi")
failit("bad value being returned #1 to '%?' expected 'string' but found 'number'",function() a(1) end)

local function two( a : Any, b :Any) : "string","boolean"
    return a,b
end

two("hi",true)
failit("bad value being returned #1 to '%?' expected 'string' but found 'number'",function() two(1,2) end)
failit("bad value being returned #2 to '%?' expected 'boolean' but found 'number'",function() two("hi",2) end)

function what(a : ListOf("int")) : ListOf("bool")
    return a:map(function(x) return x > 4 end)
end

failit("bad argument #1 to 'what' expected 'int' but found 'number' as first element of ListOf%(int%)",function()what(List {1,2,5,6})end)
function what(a : ListOf("number")) : ListOf("boolean")
    return a:map(function(x) return x > 4 end)
end
failit("bad argument #1 to 'what' expected 'ListOf%(number%)' but found 'number'",function()what(4)end)
what(List{1,2,3})
what(List{})
function what2(a : ListOf(ListOf("number"))) return 4 end
what2(List{List{3}})
failit("bad argument #1 to 'what2' expected 'number' but found 'string' .* as first element of ListOf%(number%) as first element of ListOf%(ListOf%(number%)%)",
    function() what2(List{List{""}}) end)

function op(a : OptionOf("number")) : OptionOf("boolean")
    if a and a > 3 then return true end
end
op(nil)
op(3)
failit("bad argument #1 to 'op' expected 'number' but found 'string'",function() op("") end)


function takemap( a : MapOf('string','number')) : OptionOf('number')
    return a["hi"]
end

assert(3 == takemap( { hi = 3 }))
assert(nil == takemap( {} ))

failit("bad argument #1 to 'takemap' expected 'MapOf%(string,number%)' but found 'number'", function() takemap(3) end)
failit("bad argument #1 to 'takemap' expected 'string' but found 'number' as key of MapOf%(string,number%)", function()
    takemap({ [3] = "hi" })
end)
failit("bad argument #1 to 'takemap' expected 'number' but found 'string' .* as value of MapOf%(string,number%)", function()
    takemap({ hi = "hi" })
end)

function takemap( a : MapOf('string',ListOf('number'))) : OptionOf('number')
end

takemap( { a = List {1,2,3} } )

local T = terralib.types
function takeTerraStuff( a : T.Quote,
								 b  : T.Function,
							    c  : T.Type,
							    d  : T.GlobalVariable,
							    e  : T.Struct,
							    f :  T.Symbol) : T.Quote
	return `1
end
takeTerraStuff(`3+4,terra() end, int, global(int), struct {}, symbol(int))
