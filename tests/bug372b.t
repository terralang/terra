-- Tests fix for bug #372.

local C = terralib.includecstring [[
#include "stdio.h"
#include "string.h"

struct Config {
  union  {
    char FileDir[16];
    struct  {
      unsigned int length;
      double values;
    } s;
  } u;
};
]]

terra f()
  var config : C.Config
  C.memcpy(&(config.u.FileDir[0]), "String111222333", 16)
  C.printf("orig: %s\n", config.u.FileDir)
  var copy = config
  C.printf("copy: %s\n", copy.u.FileDir)
  return C.strcmp(config.u.FileDir, copy.u.FileDir)
end

local test = require("test")
test.eq(f(),0)
