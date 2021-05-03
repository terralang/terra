{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell { buildInputs = [ pkgs.cntr pkgs.luajit pkgs.gdb ]; }
