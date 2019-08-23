local C = terralib.includecstring
[[
#include "stdbool.h"
#include "stdint.h"
#include "stdlib.h"
#include "stdio.h"
#include "string.h"

typedef int TempProfile;
#define TempProfile_File 0

typedef int InflowProfile;
#define InflowProfile_File 0
#define InflowProfile_SuctionAndBlowing 1

struct Config {
  struct  {
    struct  {
      int32_t type;
      union  {
        struct  {
          int8_t FileDir[256];
        } File;
      } u;
    } xBCLeftHeat;
    struct  {
      int32_t type;
      union  {
        struct  {
          double addedVelocity;
          int8_t FileDir[256];
        } File;
        struct  {
          double sigma;
          struct  {
            uint32_t length;
            double values[10];
          } beta;
          double Zw;
          struct  {
            uint32_t length;
            double values[10];
          } A;
          struct  {
            uint32_t length;
            double values[10];
          } omega;
        } SuctionAndBlowing;
      } u;
    } yBCLeftInflowProfile;
    struct  {
      int32_t type;
      union  {
        struct  {
          double addedVelocity;
          int8_t FileDir[256];
        } File;
        struct  {
          double sigma;
          struct  {
            uint32_t length;
            double values[10];
          } beta;
          double Zw;
          struct  {
            uint32_t length;
            double values[10];
          } A;
          struct  {
            uint32_t length;
            double values[10];
          } omega;
        } SuctionAndBlowing;
      } u;
    } xBCLeftInflowProfile;
  } BC;
};
]]

local Config = C.Config

terra out(input : &Config)
  var config : Config = terralib.attrload(input, { align = 1 })
  C.printf("\nInside the task:\n")
  C.printf("%s\n", config.BC.xBCLeftInflowProfile.u.File.FileDir)
  C.printf("%s\n", config.BC.xBCLeftHeat.u.File.FileDir)
  C.printf("\n")
  return C.strcmp(config.BC.xBCLeftInflowProfile.u.File.FileDir, "String1111111111111111111111111111111111111111") == 0 and
    C.strcmp(config.BC.xBCLeftHeat.u.File.FileDir, "String2222222222222222222222222222222222222222") == 0
end

terra main()
  var config : Config
  C.memcpy(&(config.BC.xBCLeftInflowProfile.u.File.FileDir[0]), "String1111111111111111111111111111111111111111", 47)
  C.memcpy(&(config.BC.xBCLeftHeat.u.File.FileDir[0]), "String2222222222222222222222222222222222222222", 47)

  var buffer = [&Config](C.malloc(terralib.sizeof(Config)))
  if buffer == nil then C.abort() end
  terralib.attrstore(buffer, config, { align = 1 })

  C.printf("Expect this ouput:\n")
  C.printf("%s\n", config.BC.xBCLeftInflowProfile.u.File.FileDir)
  C.printf("%s\n", config.BC.xBCLeftHeat.u.File.FileDir)
  C.printf("\n")
  return out(buffer) and
    C.strcmp(config.BC.xBCLeftInflowProfile.u.File.FileDir, "String1111111111111111111111111111111111111111") == 0 and
    C.strcmp(config.BC.xBCLeftHeat.u.File.FileDir, "String2222222222222222222222222222222222222222") == 0
end
local test = require("test")
test.eq(main(),true)
