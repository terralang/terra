c = global(int,0)

terra up()
    c = c + 1
end
function failit(match,fn)
	local success,msg = pcall(fn)
	if success then
		error("failed to fail.",2)
	elseif not string.match(msg,match) then
		error("failed wrong: "..msg,2)
	end
end
local df = "defer statements are not allowed in conditional expressions"
failit(df,function()
    local terra foo()
        if [quote defer up() in true end] then end
    end
    foo:printpretty()
end)