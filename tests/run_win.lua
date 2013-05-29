
local function getcommand(file)
    local h = io.open(file, "r")
    local line = h:read()
    io.close(h)
    if line and string.sub(line,1,1) == "#" then
        return "cmd /c " .. string.gsub(string.sub(line, 3, -2), "/", "\\\\")
    else
        return "cmd /c ..\\\\terra"
    end
end

local results = {}
local failed,passed = 0,0
for line in io.popen("cmd /c dir /b /s"):lines() do
    if string.sub(line, -3, -2) == ".t" then
        local file = string.gsub(string.sub(line, 1, -2), "\\", "/")
        local e = { k = file }
        table.insert(results,e)
        print(e.k..":")
        
        local execstring = getcommand(file) .. " " .. file

        --things in the fail directory should cause terra compiler errors
        --we dont check for the particular error
        --but we do check to see that the "Errors reported.." message prints
        --which suggests that the error was reported gracefully
        --(if the compiler bites it before it finishes typechecking then it will not print this)
        if string.find(file, "fails") then
            if os.execute(execstring.." | grep 'Errors reported during'") ~= 0 then
                e.v = "FAIL"
                failed = failed + 1
            else
                e.v = "pass"
                passed = passed + 1
            end
        else
            if os.execute(execstring) ~= 0 then
                e.v = "FAIL"
                failed = failed + 1
            else
                e.v = "pass"
                passed = passed + 1
            end
        end
    end
end

for i,e in ipairs(results) do
    if e.v then
        print(i,e.v,e.k)
    end
end
print()
print(tostring(passed).." tests passed. "..tostring(failed).." tests failed.")