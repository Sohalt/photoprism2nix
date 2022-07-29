{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    npmlock2nix = {
      url = "github:nix-community/npmlock2nix";
      flake = false;
    };
    photoprism = {
      url = "github:photoprism/photoprism/220728-729ddd920";
      flake = false;
    };
    #flake-compat = {
    #  url = "github:edolstra/flake-compat";
    #  flake = false;
    #};
    flake-utils.url = "github:numtide/flake-utils";
    gomod2nix = {
      url = "github:tweag/gomod2nix/v1.0.0-rc1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils
    , gomod2nix, ... }@inputs:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" "i686-linux" ]
    (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ gomod2nix.overlays.default self.overlays.default ];
          config = { allowUnsupportedSystem = true; };
        };
      in with pkgs; rec {
        packages = flake-utils.lib.flattenTree {
          default = pkgs.photoprism;
          photoprism = pkgs.photoprism;
          gomod2nix = pkgs.gomod2nix;
        };

        checks.build = packages.photoprism;
        checks.integration = pkgs.nixosTest (import ./integration-test { photoprismModule = self.nixosModules.photoprism; });

        devShells.default = mkShell {
          shellHook = ''
            # ${pkgs.photoprism}/bin/photoprism --admin-password photoprism --import-path ~/Pictures \
            #  --assets-path ${pkgs.photoprism.assets} start
          '';
        };
      #   devShells.npm = npmlock2nix.shell {
      #     src = inputs.photoprism + "/frontend";
      #   };
      }) // {
        nixosModules.photoprism = import ./module.nix;

        overlays.default = final: prev: {
          #go = prev.go_1_18;
          npmlock2nix = final.callPackage inputs.npmlock2nix { pkgs = prev; };
          photoprism = final.callPackage ./package.nix { src = inputs.photoprism; };
        };

        checks.x86_64-linux.integration = let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ gomod2nix.overlays.default self.overlays.default ];
          };
        in pkgs.nixosTest (import ./integration-test.nix {
          photoprismModule = self.nixosModules.photoprism;
        });
      };
}
