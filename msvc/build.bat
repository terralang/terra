if "%VS_MAJOR_VERSION%"=="" set VS_MAJOR_VERSION=14
if "%VS_MINOR_VERSION%"=="" set VS_MINOR_VERSION=0
call "C:\Program Files (x86)\Microsoft Visual Studio %VS_MAJOR_VERSION%.%VS_MINOR_VERSION%\VC\vcvarsall.bat" x86_amd64
call nmake
echo Done.