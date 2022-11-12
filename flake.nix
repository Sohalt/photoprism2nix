{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: {
    nixosModules.photoprism = import ./module.nix;

    checks.x86_64-linux.integration = let
      nixos-lib = import (nixpkgs + "/nixos/lib") {};
    in
      nixos-lib.runTest (import ./integration-test.nix {
	pkgs = import nixpkgs { system = "x86_64-linux"; };
        photoprismModule = self.nixosModules.photoprism;
      });
  };
}
