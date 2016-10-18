local F = io.open("_terraforcpp.txt")
local O = io.open("terraforcpp.html","w")
local cur
local function next()
    repeat
        cur = F:read("*line")
    until cur == nil or cur:sub(1,2) ~= "//"
end

next()

local function write(fmt,...)
    O:write(fmt:format(...))
end

local function parseHeader()
    local header,rest = cur:match("^(#+)%s+(.*)")  
    local level = #header
    write("<h%d>%s</h%d>\n",level,rest,level)
    next()
end

local function endsCodeBlock()
    return not cur:match("^    ")
end

local function parseCodeBlock()
    local blocks = terralib.newlist()
    
    local function startSection()
        blocks:insert(terralib.newlist())
    end
    startSection()
    local maxlines = 0
    while true do
        blocks[#blocks]:insert(cur)
        maxlines = math.max(maxlines,#blocks[#blocks])
        next()
        if endsCodeBlock() then
            break
        elseif cur == "    ###" then
            next()
            startSection()
        end
    end
    local kind = { "C++", "Terra", "Meta-programmed" }
    
    write('<div style="width: 100%%; margin-left: 40px;";>')
    for i,b in ipairs(blocks) do
        write('<div class="highlighter-rouge" style="margin: 0; display: inline-block;"><small>%s</small><pre class="highlight"><code>'--[[,100/#blocks]],kind[i])
        for i = 1,maxlines do
            local line = b[i]
            if line then
                local str = line:sub(5,-1):gsub("<","&lt"):gsub(">","&gt")
                write("%s\n",str)
            else
                write("\n")
            end
        end
        write("</code></pre></div>\n")
    end
    write("</div>\n")
    
end

local function endsPara()
    return cur == "" or cur:match("^#") or cur:match("^    ") or cur == nil 
end

local function parsePara()
    write("<p> %s\n",cur)
    while true do
        next()
        if endsPara() then
            write(" </p>\n")
            return
        end
        write("%s",cur)
    end
end
local function parseTop()
    while cur ~= nil do
        if cur:match("^#") then
            parseHeader()
        elseif cur:match("^    ") then
            parseCodeBlock()
        elseif cur == "" then
            next()
        else
            parsePara()
        end
    end
end
write("%s",[[
---
layout: post
title: Terra
---
]])
parseTop()
O:close()