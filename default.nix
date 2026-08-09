{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib
, fetchFromGitHub ? pkgs.fetchFromGitHub, ncurses ? pkgs.ncurses
, cmake ? pkgs.cmake, libxml2 ? pkgs.libxml2, symlinkJoin ? pkgs.symlinkJoin
, cudaPackages ? pkgs.cudaPackages, enableCUDA ? false }:

let

  llvmPackages = pkgs.llvmPackages_20;
  stdenv = llvmPackages.stdenv;
  cuda = if cudaPackages ? cudatoolkit_12 then [
           cudaPackages.cudatoolkit_12
         ] else [
           cudaPackages.cuda_nvcc
           cudaPackages.cuda_cudart
         ];

  luajitRev = "14d8a7a27dc8c626ab9e7c7e9e50b6df6def4f03";
  luajitBase = "LuaJIT-${luajitRev}";
  luajitArchive = "${luajitBase}.tar.gz";
  luajitSrc = fetchFromGitHub {
    owner = "LuaJIT";
    repo = "LuaJIT";
    rev = luajitRev;
    sha256 = "0faij1v5qq7jd4h0np6dnbxfdjd707bjrwmasy32zj43530gsrvk";
  };
  llvmMerged = symlinkJoin {
    name = "llvmClangMerged";
    paths = with llvmPackages; [
      llvm.out
      llvm.dev
      llvm.lib
      clang-unwrapped.out
      clang-unwrapped.dev
      clang-unwrapped.lib
    ];
  };

  clangVersion = llvmPackages.clang-unwrapped.version;

in stdenv.mkDerivation rec {
  pname = "terra";
  version = "1.2.1";

  src = ./.;

  nativeBuildInputs = [ cmake ] ++ lib.optionals enableCUDA [ cudaPackages.cuda_nvcc ];
  buildInputs = [ llvmMerged ncurses libxml2 ]
    ++ lib.optionals enableCUDA [ cudaPackages.cuda_nvcc cudaPackages.cuda_cudart ];

  cmakeFlags = [
    "-DHAS_TERRA_VERSION=0"
    "-DTERRA_VERSION=${version}"
    "-DTERRA_LUA=luajit"
    "-DTERRA_SKIP_LUA_DOWNLOAD=ON"
    "-DCLANG_RESOURCE_DIR=${llvmMerged}/lib/clang/${lib.versions.major clangVersion}"
  ] ++ lib.optional enableCUDA "-DTERRA_ENABLE_CUDA=ON";

  doCheck = true;
  enableParallelBuilding = true;
  hardeningDisable = [ "fortify" ];
  outputs = [ "bin" "dev" "out" "static" ];

  patches = [ ./nix/cflags.patch ];

  postPatch = ''
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
    platforms = platforms.all;
    maintainers = with maintainers; [ jb55 thoughtpolice ];
    license = licenses.mit;
  };
}
