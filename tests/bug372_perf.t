-- This test exercises a compile time performance regression. The
-- large structs in the C include in this file result in very bad
-- compile times (in the tens of minutes) if the LLVM IR is not
-- generated very carefully. This is due to an LLVM SROA optimization
-- which takes the code and produces tens of thousands of lines of
-- LLVM IR (which then must pass through the entire LLVM compiler
-- backend). With proper LLVM code generation the test should compile
-- instantly and generate short LLVM IR/machine code.

local C = terralib.includecstring
[[
#ifndef __CONFIG_SCHEMA_H__
#define __CONFIG_SCHEMA_H__

#include <stdbool.h>
#include <stdint.h>

typedef int TurbForcingModel;
#define TurbForcingModel_OFF 0
#define TurbForcingModel_CHANNEL 1

typedef int FlowBC;
#define FlowBC_IsothermalWall 4
#define FlowBC_Dirichlet 0
#define FlowBC_NSCBC_Outflow 6
#define FlowBC_Periodic 1
#define FlowBC_SuctionAndBlowingWall 7
#define FlowBC_AdiabaticWall 3
#define FlowBC_NSCBC_Inflow 5
#define FlowBC_Symmetry 2

typedef int ViscosityModel;
#define ViscosityModel_PowerLaw 1
#define ViscosityModel_Constant 0
#define ViscosityModel_Sutherland 2

typedef int TempProfile;
#define TempProfile_File 0
#define TempProfile_Constant 1
#define TempProfile_Incoming 2

typedef int MixtureProfile;
#define MixtureProfile_File 0
#define MixtureProfile_Constant 1
#define MixtureProfile_Incoming 2

typedef int FlowInitCase;
#define FlowInitCase_Perturbed 3
#define FlowInitCase_TaylorGreen2DVortex 4
#define FlowInitCase_ChannelFlow 13
#define FlowInitCase_GrossmanCinnellaProblem 12
#define FlowInitCase_VortexAdvection2D 11
#define FlowInitCase_Restart 2
#define FlowInitCase_RiemannTestOne 6
#define FlowInitCase_SodProblem 8
#define FlowInitCase_LaxProblem 9
#define FlowInitCase_ShuOsherProblem 10
#define FlowInitCase_Random 1
#define FlowInitCase_TaylorGreen3DVortex 5
#define FlowInitCase_RiemannTestTwo 7
#define FlowInitCase_Uniform 0

typedef int GridType;
#define GridType_Uniform 0
#define GridType_TanhPlus 3
#define GridType_Tanh 4
#define GridType_TanhMinus 2
#define GridType_Cosine 1

typedef int InflowProfile;
#define InflowProfile_File 0
#define InflowProfile_Constant 1
#define InflowProfile_SuctionAndBlowing 2
#define InflowProfile_Incoming 3

struct TurbForcingModel {
  int32_t type;
  struct  {
    struct  {
      int32_t __dummy;
    } OFF;
    struct  {
      double Forcing;
      double RhoUbulk;
    } CHANNEL;
  } u;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_TurbForcingModel(struct TurbForcingModel*, char*);
#ifdef __cplusplus
}
#endif

struct Window {
  int32_t uptoCell[2];
  int32_t fromCell[2];
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_Window(struct Window*, char*);
#ifdef __cplusplus
}
#endif

struct TempProfile {
  int32_t type;
  struct  {
    struct  {
      int8_t FileDir[256];
    } File;
    struct  {
      double temperature;
    } Constant;
    struct  {
      int32_t __dummy;
    } Incoming;
  } u;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_TempProfile(struct TempProfile*, char*);
#ifdef __cplusplus
}
#endif

struct InflowProfile {
  int32_t type;
  struct  {
    struct  {
      int8_t FileDir[256];
    } File;
    struct  {
      double velocity[3];
    } Constant;
    struct  {
      double sigma;
      struct  {
        uint32_t length;
        double values[20];
      } beta;
      struct  {
        uint32_t length;
        double values[20];
      } omega;
      struct  {
        uint32_t length;
        double values[20];
      } A;
      double Xmax;
      double X0;
      double Zw;
      double Xmin;
    } SuctionAndBlowing;
    struct  {
      double addedVelocity;
    } Incoming;
  } u;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_InflowProfile(struct InflowProfile*, char*);
#ifdef __cplusplus
}
#endif

struct Species {
  int8_t Name[10];
  double MolarFrac;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_Species(struct Species*, char*);
#ifdef __cplusplus
}
#endif

struct Mixture {
  struct  {
    uint32_t length;
    struct Species values[10];
  } Species;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_Mixture(struct Mixture*, char*);
#ifdef __cplusplus
}
#endif

struct MixtureProfile {
  int32_t type;
  struct  {
    struct  {
      int8_t FileDir[256];
    } File;
    struct  {
      struct Mixture Mixture;
    } Constant;
    struct  {
      int32_t __dummy;
    } Incoming;
  } u;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_MixtureProfile(struct MixtureProfile*, char*);
#ifdef __cplusplus
}
#endif

struct BCStruct {
  struct TempProfile yBCRightHeat;
  struct TempProfile zBCRightHeat;
  struct InflowProfile yBCRightInflowProfile;
  double yBCRightP;
  double xBCRightP;
  double xBCLeftP;
  struct InflowProfile xBCLeftInflowProfile;
  double zBCLeftP;
  double yBCLeftP;
  int32_t xBCRight;
  int32_t zBCRight;
  int32_t yBCRight;
  struct MixtureProfile zBCRightMixture;
  double zBCRightP;
  struct InflowProfile zBCRightInflowProfile;
  struct MixtureProfile zBCLeftMixture;
  struct MixtureProfile xBCRightMixture;
  struct MixtureProfile yBCRightMixture;
  int32_t yBCLeft;
  struct InflowProfile zBCLeftInflowProfile;
  int32_t zBCLeft;
  struct TempProfile zBCLeftHeat;
  struct MixtureProfile yBCLeftMixture;
  struct TempProfile xBCLeftHeat;
  struct TempProfile yBCLeftHeat;
  struct InflowProfile yBCLeftInflowProfile;
  int32_t xBCLeft;
  struct InflowProfile xBCRightInflowProfile;
  struct MixtureProfile xBCLeftMixture;
  struct TempProfile xBCRightHeat;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_BCStruct(struct BCStruct*, char*);
#ifdef __cplusplus
}
#endif

struct Volume {
  int32_t uptoCell[3];
  int32_t fromCell[3];
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_Volume(struct Volume*, char*);
#ifdef __cplusplus
}
#endif

struct Config {
  struct BCStruct BC;
};

#ifdef __cplusplus
extern "C" {
#endif
void parse_Config(struct Config*, char*);
#ifdef __cplusplus
}
#endif

#endif // __CONFIG_SCHEMA_H__
]]

terra unpack_param(fixed_ptr : &opaque) : C.BCStruct
    var result : C.BCStruct = @[&C.BCStruct](fixed_ptr)
    return result
end
unpack_param:printpretty(false)
-- unpack_param:setoptimized(false)
unpack_param:compile()
unpack_param:disas()
