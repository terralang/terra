{ pkgs ? import <nixpkgs> { } }:

{
  luajit = pkgs.luajit.overrideAttrs (old: rec {
    preBuild = ''
      substituteInPlace ./src/Makefile \
        --replace "default all:	$(TARGET_T)" "default all:	$(ALL_T)"
    '';
    buildFlags = [ ];
  });
}
