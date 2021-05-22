{ sources ? import ./nix/sources.nix, enableCUDA ? false }:

let

  overlay = _: pkgs: { niv = (import sources.niv { }).niv; };

  pkgs = import sources.nixpkgs {
    overlays = [ overlay ];
    config = { };
  };

  inherit (pkgs)
    lib fetchurl fetchFromGitHub ncurses cmake libxml2 symlinkJoin cudaPackages;

  llvmPackages = pkgs.llvmPackages_10;
  stdenv = llvmPackages.stdenv;
  cuda = cudaPackages.cudatoolkit_11;

  luajitRev = "9143e86498436892cb4316550be4d45b68a61224";
  luajitArchive = "LuaJIT-${luajitRev}.tar.gz";
  luajitSrc = fetchurl {
    url = "https://github.com/LuaJIT/LuaJIT/archive/${luajitRev}.tar.gz";
    sha256 = "0kasmyk40ic4b9dwd4wixm0qk10l88ardrfimwmq36yc5dhnizmy";
  };

in stdenv.mkDerivation rec {
  pname = "terra";
  version = "1.0.0-beta3";

  src = ./.;

  nativeBuildInputs = [ cmake ];
  buildInputs = [
    (symlinkJoin {
      name = "llvmClangMerged";
      paths = with llvmPackages; [ llvm clang-unwrapped ];
    })
    ncurses
    libxml2
  ] ++ lib.optional enableCUDA cuda;

  cmakeFlags = [
    "-DHAS_TERRA_VERSION=0"
    "-DTERRA_VERSION=release-1.0.0-beta3"
    "-DTERRA_LUA=luajit"
  ] ++ lib.optional enableCUDA "-DTERRA_ENABLE_CUDA=ON";

  doCheck = true;
  enableParallelBuilding = true;
  hardeningDisable = [ "fortify" ];
  outputs = [ "bin" "dev" "out" "static" ];

  patches = [ ./nix-cflags.patch ./disable-luajit-file-download.patch ];
  postPatch = ''
    substituteInPlace src/terralib.lua \
      --subst-var-by NIX_LIBC_INCLUDE ${lib.getDev stdenv.cc.libc}/include
  '';

  preConfigure = ''
    mkdir -p build
    cp ${luajitSrc} build/${luajitArchive}
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
