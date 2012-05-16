print ("loaded terra lib")
_G.terra = {}

terra.default = {} --default match value
terra.tree = {}
function terra.tree:match(tbl)
	fn = tbl[self.kind] or tbl[terra.default] or function() print("match error:"..self.kind) end
	fn(tbl)
end
terra._metatree = { __index = terra.tree }

function terra.printElement(t) 
	local function header(t)
		if type(t) == "table" then
			return t["kind"] or ""
		else
			return tostring(t)
		end
 	end
 	local function isList(t)
 		return type(t) == "table" and #t ~= 0
 	end
	local function printElem(t,spacing)
		if(type(t) == "table") then
			for k,v in pairs(t) do
				if k ~= "kind" then
					local prefix = spacing..k..": "
					print(prefix..header(v))
					if isList(v) then
						printElem(v,string.rep(" ",2+#spacing))
					else
						printElem(v,string.rep(" ",2+#prefix))
					end
				end
			end
		end
	end
	print(header(t))
	if type(t) == "table" then
		printElem(t,"  ")
	end
end

function terra.newfunction(olddef,newvariant,env)
    print("previous object: "..tostring(olddef))
	terra.printElement(newvariant)
	print("local environment:")
	local e = env()
	terra.printElement(e)
	return newvariant
end

function terra.resolvetype(type_tree)
	
end