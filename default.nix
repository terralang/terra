{ pkgs ? import <nixpkgs> { } }:

let

  luajit = (import ./lib.nix { pkgs = pkgs; }).luajit;
  llvmPackages = pkgs.llvmPackages_9;
  stdenv = llvmPackages.stdenv;

in stdenv.mkDerivation rec {
  pname = "terra";
  name = "terra";

  src = ./.;

  depsBuildBuild = [ pkgs.pkg-config ];

  buildInputs = with llvmPackages; [
    luajit
    llvm
    clang-unwrapped
    pkgs.libxml2
    pkgs.ncurses
    pkgs.cmake
    pkgs.cudaPackages.cudatoolkit_11
  ];

  #doCheck = true;
  enableParallelBuilding = true;
  hardeningDisable = [ "fortify" ];
  outputs = [ "bin" "dev" "out" ];

  postPatch = ''
    substituteInPlace src/terralib.lua \
      --subst-var-by NIX_LIBC_INCLUDE ${
        stdenv.lib.getDev stdenv.cc.libc
      }/include
  '';

  cmakeFlags = stdenv.lib.concatStringsSep " " [
    "-DTERRA_ENABLE_CMAKE=ON"
    "-DTERRA_ENABLE_CUDA=ON"
  ];

  # checkPhase = "(cd tests && ../terra run)";

  meta = with stdenv.lib; {
    description = "A low-level counterpart to Lua";
    homepage = "http://terralang.org/";
    platforms = platforms.x86_64;
    maintainers = with maintainers; [ jb55 thoughtpolice seylerius ];
    license = licenses.mit;
  };
}
