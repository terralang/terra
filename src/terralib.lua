print ("loaded terra lib")
terra = {}
function printElement(t) 
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
function terra.newfunction(x)
	printElement(x)
end