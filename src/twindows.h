#ifndef twindows_h
#define twindows_h

#pragma pack(push)
#pragma pack(8)
#define WINVER 0x0600  //_WIN32_WINNT_VISTA
#define _WIN32_WINNT 0x0600
#define NTDDI_VERSION 0x06000100  // NTDDI_VISTASP1
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX  // Some compilers enable this by default
#define NOMINMAX
#endif
#define NODRAWTEXT
#define NOBITMAP
#define NOMCX
#define NOSERVICE
#define NOHELP
#include <Windows.h>
#pragma pack(pop)

#endif