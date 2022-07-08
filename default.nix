{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib
, fetchFromGitHub ? pkgs.fetchFromGitHub, ncurses ? pkgs.ncurses
, cmake ? pkgs.cmake, libxml2 ? pkgs.libxml2, symlinkJoin ? pkgs.symlinkJoin
, cudaPackages ? pkgs.cudaPackages, enableCUDA ? false }:

let

  llvmPackages = pkgs.llvmPackages_10;
  stdenv = llvmPackages.stdenv;
  cuda = if cudaPackages ? cudatoolkit_11 then [
           cudaPackages.cudatoolkit_11
         ] else [
           cudaPackages.cuda_nvcc
           cudaPackages.cuda_cudart
         ];

  luajitRev = "6053b04815ecbc8eec1e361ceb64e68fb8fac1b3";
  luajitBase = "LuaJIT-${luajitRev}";
  luajitArchive = "${luajitBase}.tar.gz";
  luajitSrc = fetchFromGitHub {
    owner = "LuaJIT";
    repo = "LuaJIT";
    rev = luajitRev;
    sha256 = "1caxm1js877mky8hci1km3ycz2hbwpm6xbyjha72gfc7lr6pc429";
  };
  llvmMerged = symlinkJoin {
    name = "llvmClangMerged";
    paths = with llvmPackages;
      if llvm ? dev then [
        llvm.out
        llvm.dev
        llvm.lib
        clang-unwrapped.out
        clang-unwrapped.dev
        clang-unwrapped.lib
      ] else [
        llvm
        clang-unwrapped
      ];
  };

  clangVersion = llvmPackages.clang-unwrapped.version;

in stdenv.mkDerivation rec {
  pname = "terra";
  version = "1.0.4";

  src = ./.;

  nativeBuildInputs = [ cmake ];
  buildInputs = [ llvmMerged ncurses libxml2 ] ++ lib.optionals enableCUDA cuda;

  cmakeFlags = [
    "-DHAS_TERRA_VERSION=0"
    "-DTERRA_VERSION=${version}"
    "-DTERRA_LUA=luajit"
    "-DCLANG_RESOURCE_DIR=${llvmMerged}/lib/clang/${clangVersion}"
  ] ++ lib.optional enableCUDA "-DTERRA_ENABLE_CUDA=ON";

  doCheck = true;
  enableParallelBuilding = true;
  hardeningDisable = [ "fortify" ];
  outputs = [ "bin" "dev" "out" "static" ];

  patches = [ ./nix/cflags.patch ];

  postPatch = ''
    sed -i '/file(DOWNLOAD "''${LUAJIT_URL}" "''${LUAJIT_TAR}")/d' \
      cmake/Modules/GetLuaJIT.cmake

    substituteInPlace src/terralib.lua \
      --subst-var-by NIX_LIBC_INCLUDE ${lib.getDev stdenv.cc.libc}/include
  '';

  preConfigure = ''
    mkdir -p build
    ln -s ${luajitSrc} build/${luajitBase}
    tar --mode="a+rwX" -chzf build/${luajitArchive} -C build ${luajitBase}
    rm build/${luajitBase}
  '';

  installPhase = ''
    install -Dm755 -t $bin/bin bin/terra
    install -Dm755 -t $out/lib lib/terra${stdenv.hostPlatform.extensions.sharedLibrary}
    install -Dm644 -t $static/lib lib/libterra_s.a

    mkdir -pv $dev/include
    cp -rv include/terra $dev/include
  '';

  meta = with lib; {
    description = "A low-level counterpart to Lua";
    homepage = "http://terralang.org/";
    platforms = platforms.x86_64;
    maintainers = with maintainers; [ jb55 thoughtpolice ];
    license = licenses.mit;
  };
}
