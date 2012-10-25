local g=_G
module("Strict")
strict,strong=true,false

function handler(m,n,v)
	m=getModulename(m)
	if m=="_G" then m=" in main program"
	else m=" in module "..m end
	if (v~=nil) then g.error("invalid assignment to "..n..m,3)
	else g.error(n.." not declared"..m,3) end
end

local function noaccess1() -- for __newindex
	local d=g.debug.getinfo(3,"S")
	local w=d and d.what or "C"
	if strong then return w~="C" end
	return w~="main" and w~="C"
end

local function noaccess2() -- for __index
	local d=g.debug.getinfo(3,"S")
	local w=d and d.what or "C"
	return w~="C"
end

function declareGlobal(n,v,m)
	m=m or g; -- no module means n will go into _G
	if not isDeclared(n,m) then -- if not there, go ahead
		g.getmetatable(m).__Idle_declared[n]=true
		if v~=nil then g.rawset(m,n,v) end
	end
end

function registerModule(m)
	-- based on Roberto's code in etc/strict.lua
	if g.type(m)~="table" then return end
	local mt=g.getmetatable(m)
	if mt==nil then
		mt={}
		g.setmetatable(m,mt)
	end
	if mt.__Idle_declared==nil then mt.__Idle_declared={}
	else return end -- already registered
	mt.__newindex=function (t,n,v)
		if not mt.__Idle_declared[n] then
			if strict and noaccess1() then handler(t,n,v)
			else mt.__Idle_declared[n]=true end
		end
		-- the call to g.rawget() seems superfluous but if the call to handler()
		-- already initialised n it'll not be overwritten here
		if mt.__Idle_declared[n] and g.rawget(t,n)==nil then g.rawset(t,n,v) end
	end
	mt.__index=function (t,n)
		if strict and not mt.__Idle_declared[n] and noaccess2() then handler(t,n,nil)
		else return g.rawget(t,n) end
	end
end

function getModulename(m)
	for k,v in g.pairs(g.package.loaded) do
		if m==v then return k end
	end
	return "<UNKNOWN>"
end

function isDeclared(n,m)
	m=m or g;
	return g.getmetatable(m).__Idle_declared[n] or g.rawget(m,n)~=nil
end

-- Register loaded modules (may be too much hand-holding for some)
for k,v in g.pairs(g.package.loaded) do if k ~= "table" then registerModule(v) end end
