if not require("fail") then return end

thea = nil
function store(a)
	thea = a
	return a
end
function load()
	return thea
end
store = macro(store)
load = macro(load)

terra nonsense()
	for i = 0,10 do
		var a = i
		store(a)
	end
	return load()
end

print(nonsense())
