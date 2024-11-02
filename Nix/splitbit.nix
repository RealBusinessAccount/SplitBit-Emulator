{ lib, stdenv }:

stdenv.mkDerivation {
  pname = "splitbit";
  version = "v1.0.0";
  src = ../.;
  env.PREFIX = builtins.placeholder "out";
}
