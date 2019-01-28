
codes = true

std = 'luajit'

max_line_length = 200

ignore = {
    '611',      -- line contains only whitespace
    '612',      -- line contains trailing whitespace
    '613',      -- trailing whitespace in a string
    '614',      -- trailing whitespace in a comment
}

globals = {
    'terra',
    'terralib',
    'cudalib',
}

self = false

files['src/cudalib.lua'].read_globals = { 'opaque', 'uint' }
files['src/cudalib.lua'].ignore = {
    '212/cudahome',     -- unused argument cudahome
}
files['src/strict.lua'].max_line_length = 400
files['src/strict.lua'].ignore = { '111/Strict' }  -- setting non-standard global variable Strict
files['src/terralib.lua'].max_line_length = 300
files['src/terralib.lua'].ignore = {
    '113/Strict',       -- accessing undefined variable Strict
    '122/debug',        -- setting read-only field traceback of global debug
    '142/package',      -- setting undefined field terrapath of global package
    '143/package',      -- accessing undefined field terrapath.gmatch of global package
    '211/meet',         -- unused variable meet
    '211/orig',         -- unused variable orig
    '212',              -- unused argument
    '421/result',       -- shadowing definition of variable result
    '422/e',            -- shadowing definition of argument e
    '422/v',            -- shadowing definition of argument v
    '423/i',            -- shadowing definition of loop variable i
    '431',              -- shadowing upvalue
    '432',              -- shadowing upvalue argument
    '511',              -- unreachable code
    '542',              -- empty if branch
}
