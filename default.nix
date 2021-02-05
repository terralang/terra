{ pkgs ? import <nixpkgs> { }, lib ? stdenv.lib
  # Supports LLVM up to 11, recommends at least 6
, llvmPackages ? pkgs.llvmPackages_9, stdenv ? llvmPackages.stdenv
, enableCUDA ? false, cuda ? pkgs.cudaPackages.cudatoolkit_11 }:

let

  luajit = pkgs.luajit.overrideAttrs (old: rec {
    preBuild = ''
      substituteInPlace ./src/Makefile \
        --replace "default all:	$(TARGET_T)" "default all:	$(ALL_T)"
    '';
    buildFlags = [ ];
  });

in stdenv.mkDerivation rec {
  pname = "terra";
  name = "terra";

  src = ./.;

  depsBuildBuild = [ pkgs.pkg-config ];

  nativeBuildInputs = [ pkgs.cmake ];

  buildInputs = with llvmPackages;
    [ luajit llvm clang-unwrapped pkgs.libxml2 pkgs.ncurses ]
    ++ lib.optional enableCUDA cuda;

  #doCheck = true;
  enableParallelBuilding = true;
  hardeningDisable = [ "fortify" ];
  outputs = [ "bin" "dev" "out" ];

  patches = [ ./nix-cflags.patch ];
  postPatch = ''
    substituteInPlace src/terralib.lua \
      --subst-var-by NIX_LIBC_INCLUDE ${lib.getDev stdenv.cc.libc}/include
  '';

  cmakeFlags = lib.concatStringsSep " " ([ "-DTERRA_ENABLE_CMAKE=ON" ]
    ++ lib.optional enableCUDA "-DTERRA_ENABLE_CUDA=ON");

  # checkPhase = "(cd tests && ../terra run)";

  meta = with lib; {
    description = "A low-level counterpart to Lua";
    homepage = "http://terralang.org/";
    platforms = platforms.x86_64;
    maintainers = with maintainers; [ jb55 thoughtpolice seylerius ];
    license = licenses.mit;
  };
}
