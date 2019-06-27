-- Tests fix for bug #372.

local C = terralib.includecstring [[
#include "stdio.h"
#include "string.h"
]]

struct st
{
  length : uint;
  values : double;
}

struct Config
{
  union {
    FileDir : int8[16],
    s : st,
  }
}

terra f()
  var config : Config
  C.memcpy(&(config.FileDir[0]), "String111222333", 16)
  C.printf("orig: %s\n", config.FileDir)
  var copy = config
  C.printf("copy: %s\n", copy.FileDir)
  return C.strcmp(config.FileDir, copy.FileDir)
end

local test = require("test")
test.eq(f(),0)
