{ pkgs ? import <nixpkgs> {}
}:
with pkgs;
let
  ruby = ruby_2_7;
  rubyEnv = bundlerEnv {
    name = "script-conversion-systems-bundler-env";
    inherit ruby;
    gemdir = ./.;
    groups = [ "default" ];
    src = if lib.inNixShell then null else ./.;
  };
in
  stdenv.mkDerivation {
    name = "script-conversion-systems";
    buildInputs = [ rubyEnv ruby ];
  }
