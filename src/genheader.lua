local in_filename,out_filename = arg[1],arg[2]

local in_file = io.open(in_filename)
local contents = in_file:read("*all")
in_file:close()

local n_bytes = string.len(contents)
local encoded_bytes = {}
for i = 1, n_bytes do
  local byte = string.byte(contents, i)
  assert(byte >= 0 and byte < 256)
  table.insert(encoded_bytes, string.format("%d", byte))
end
local template = [[
#define luaJIT_BC_%s_SIZE %d
static const unsigned char luaJIT_BC_%s[] = {
%s
};
]]

local basename = string.gsub(string.gsub(in_filename, ".*/", ""), "[.].*", "")

local out_file = io.open(out_filename, "w")
out_file:write(string.format(template, basename, n_bytes, basename, table.concat(encoded_bytes, ",")))
out_file:close()
