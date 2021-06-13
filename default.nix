{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib, fetchurl ? pkgs.fetchurl
, fetchFromGitHub ? pkgs.fetchFromGitHub, ncurses ? pkgs.ncurses
, cmake ? pkgs.cmake, libxml2 ? pkgs.libxml2, symlinkJoin ? pkgs.symlinkJoin
, cudaPackages ? pkgs.cudaPackages, enableCUDA ? false }:

let

  llvmPackages = pkgs.llvmPackages_10;
  stdenv = llvmPackages.stdenv;
  cuda = cudaPackages.cudatoolkit_11;

  luajitRev = "9143e86498436892cb4316550be4d45b68a61224";
  luajitArchive = "LuaJIT-${luajitRev}.tar.gz";
  luajitSrc = fetchurl {
    url = "https://github.com/LuaJIT/LuaJIT/archive/${luajitRev}.tar.gz";
    sha256 = "0kasmyk40ic4b9dwd4wixm0qk10l88ardrfimwmq36yc5dhnizmy";
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
        libclang.dev
      ] else [
        llvm
        clang-unwrapped
      ];
  };

in stdenv.mkDerivation rec {
  pname = "terra";
  version = "1.0.0-beta3";

  src = ./.;

  nativeBuildInputs = [ cmake ];
  buildInputs = [ llvmMerged ncurses libxml2 ] ++ lib.optional enableCUDA cuda;

  cmakeFlags = [
    "-DHAS_TERRA_VERSION=0"
    "-DTERRA_VERSION=release-1.0.0-beta3"
    "-DTERRA_LUA=luajit"
    "-DLLVM_INSTALL_PREFIX=${llvmMerged}"
  ] ++ lib.optional enableCUDA "-DTERRA_ENABLE_CUDA=ON";

  doCheck = true;
  enableParallelBuilding = true;
  hardeningDisable = [ "fortify" ];
  outputs = [ "bin" "dev" "out" "static" ];

  patches = [
    ./nix/cflags.patch
    ./nix/disable-luajit-file-download.patch
    # ./nix/add-test-paths.patch
  ];

  INCLUDE_PATH = "${llvmMerged}/lib/clang/10.0.1/include";

  postPatch = ''
    substituteInPlace src/terralib.lua \
      --subst-var-by NIX_LIBC_INCLUDE ${lib.getDev stdenv.cc.libc}/include
  '';

  preConfigure = ''
    mkdir -p build
    cp ${luajitSrc} build/${luajitArchive}
  '';

  installPhase = ''
    exit 1
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
