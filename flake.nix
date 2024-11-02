{
  description = "SplitBit emulator and assembler";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts }:
    flake-parts.lib.mkFlake { inherit inputs; } {
        imports = [ inputs.flake-parts.flakeModules.easyOverlay ];
        systems = [
          "x86_64-linux"
          "x86_64-darwin"
          "aarch64-linux" # untested
          "aarch64-darwin" # untested
        ];

        perSystem = { config, system, pkgs, ... }:
          {
            packages.default = pkgs.callPackage ./Nix/splitbit.nix {};
            overlayAttrs.splitbit = config.packages.default;
            devShells.default = pkgs.mkShell {
              inputsFrom = [config.packages.default];
            };
          };
      };
}
