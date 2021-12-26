{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-21.11";
    npmlock2nix = { url = "github:nix-community/npmlock2nix"; flake = false; };
    photoprism = { url = "github:photoprism/photoprism"; flake = false; };
    flake-compat = { url = "github:edolstra/flake-compat"; flake = false; };
    flake-utils.url = "github:numtide/flake-utils";
    gomod2nix = { url = "github:tweag/gomod2nix"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = inputs@{ self, nixpkgs, npmlock2nix, photoprism, flake-utils, gomod2nix, flake-compat }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "x86_64-darwin" "i686-linux" ]
      (
        system:
        let
          pkgs = import nixpkgs
            {
              inherit system; overlays = [
              self.overlay
              gomod2nix.overlay
            ];
              config = {
                allowUnsupportedSystem = true;
              };
            };
        in
        with pkgs;
        rec {
          packages = flake-utils.lib.flattenTree {
            photoprism = pkgs.photoprism;
            gomod2nix = pkgs.gomod2nix;
          };

          defaultPackage = packages.photoprism;

          checks.build = packages.photoprism;

          devShell = mkShell {
            shellHook = ''
              # ${pkgs.photoprism}/bin/photoprism --admin-password photoprism --import-path ~/Pictures \
              #  --assets-path ${pkgs.photoprism.assets} start
            '';
          };
        }
      ) // {
      nixosModules.photoprism = { lib, pkgs, config, ... }:
        let
          cfg = config.services.photoprism;
        in
        {
          options = with lib; {
            services.photoprism = {
              enable = mkEnableOption "photoprism personal photo management";

              mysql = mkOption {
                type = types.bool;
                default = false;
              };

              port = mkOption {
                type = types.port;
                default = 2342;
              };

              host = mkOption {
                type = types.str;
                default = "127.0.0.1";
              };

              adminPasswordFile = mkOption {
                type = types.path;
                description = ''
                  path to file containing
                  PHOTOPRISM_ADMIN_PASSWORD=<password>
                '';
              };

              dataDir = mkOption {
                type = types.path;
                default = "/var/lib/photoprism";
                description = ''
                  Data directory for photoprism
                '';
              };

	      settings = mkOption {
	        apply = recursiveUpdate default;
	        default = {
                  SSL_CERT_DIR = "${pkgs.cacert}/etc/ssl/certs";

                  DATABASE_DRIVER = if !cfg.mysql then "sqlite" else "mysql";
                  DATABASE_DSN =
                    if !cfg.mysql then "${cfg.dataDir}/photoprism.sqlite"
                    else
                      "photoprism@unix(/run/mysqld/mysqld.sock)/photoprism?charset=utf8mb4,utf8&parseTime=true";
                  DETECT_NSFW = "true";
                  ORIGINALS_LIMIT = "1000000";
                  HTTP_HOST = "${cfg.host}";
                  HTTP_PORT = "${toString cfg.port}";
                  HTTP_MODE = "release";
                  PUBLIC = "false";
                  READONLY = "false";
                  SIDECAR_JSON = "true";
                  SIDECAR_YAML = "true";
                  SIDECAR_PATH = "${cfg.dataDir}/sidecar";
                  SITE_URL = "http://${cfg.host}:${toString cfg.port}";
                  STORAGE_PATH = "${cfg.dataDir}/storage";
                  ASSETS_PATH = "${cfg.package.assets}";
                  ORIGINALS_PATH = "${cfg.dataDir}/originals";
                  IMPORT_PATH = "${cfg.dataDir}/import";
                  UPLOAD_NSFW = "true";
                };
		example = {
		  SITE_URL = "http://example.com";
		  THUMB_SIZE = 1024;
		};
	        description = ''
		  settings as described on <link xlink:href="https://docs.photoprism.app/getting-started/config-options/"/> without the PHOTOPRISM_ prefix
		'';
	      };

              package = mkOption {
                type = types.package;
                default = self.outputs.packages."${pkgs.system}".photoprism;
                description = "The photoprism package.";
              };
            };
          };

          config = with lib; mkIf cfg.enable {
            users.users.photoprism = { isSystemUser = true; group = "photoprism"; };

            users.groups.photoprism = { };

            services.mysql = mkIf cfg.mysql {
              enable = true;
              package = mkDefault pkgs.mysql;
              ensureDatabases = [ "photoprism" ];
              ensureUsers = [{
                name = "photoprism";
                ensurePermissions = { "photoprism.*" = "ALL PRIVILEGES"; };
              }];
            };

            systemd.services.photoprism = {
              enable = true;
              after = [
                "network-online.target"
                (if cfg.mysql then
                  "mysql.service"
                else "")
              ];
              wantedBy = [ "multi-user.target" ];

              confinement = {
                enable = true;
                binSh = null;
                packages = [
                  pkgs.libtensorflow-bin
                  pkgs.darktable
                  pkgs.ffmpeg
                  pkgs.exiftool
                  cfg.package
                  pkgs.cacert
                ];
              };

              path = [
                pkgs.libtensorflow-bin
                pkgs.darktable
                pkgs.ffmpeg
                pkgs.exiftool
              ];

              script =
                ''
                  exec ${cfg.package}/bin/photoprism --assets-path ${cfg.package.assets} start
                '';

              serviceConfig = {
                User = "photoprism";
                BindPaths = [
                  "/var/lib/photoprism"
                ] ++ lib.optionals cfg.mysql [
                  "-/run/mysqld"
                  "-/var/run/mysqld"
                ];
                RuntimeDirectory = "photoprism";
                CacheDirectory = "photoprism";
                StateDirectory = "photoprism";
                SyslogIdentifier = "photoprism";
                PrivateTmp = true;
                PrivateUsers = true;
                PrivateDevices = true;
                ProtectClock = true;
                ProtectKernelLogs = true;
                SystemCallArchitectures = "native";
                RestrictNamespaces = true;
                MemoryDenyWriteExecute = true;
                RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
                RestrictSUIDSGID = true;
                NoNewPrivileges = true;
                RemoveIPC = true;
                LockPersonality = true;
                ProtectHome = true;
                ProtectHostname = true;
                RestrictRealtime = true;
                SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
                SystemCallErrorNumber = "EPERM";
                EnvironmentFile = cfg.adminPasswordFile;
              };

              environment = lib.mapAttrs' (n: v: lib.nameValuePair "PHOTOPRISM_${n}" (toString v)) cfg.settings;
            };
          };
        };

      overlay = final: prev: {
        photoprism = with final;
          (
            let
              src = pkgs.fetchFromGitHub {
                owner = "photoprism";
                repo = "photoprism";
                rev = photoprism.rev;
                sha256 = photoprism.narHash;
              };
            in
            buildGoApplication {
              name = "photoprism";
              inherit src;

              subPackages = [ "cmd/photoprism" ];

              modules = ./gomod2nix.toml;

              CGO_ENABLED = "1";
              # https://github.com/mattn/go-sqlite3/issues/803
              CGO_CFLAGS = "-Wno-return-local-addr";

              buildInputs = [
                #https://github.com/andir/infra/blob/master/nix/packages/photoprism/default.nix
                (libtensorflow-bin.overrideAttrs (oA: {
                  # 21.05 does not have libtensorflow-bin 1.x anymore & photoprism isn't compatible with tensorflow 2.x yet
                  # https://github.com/photoprism/photoprism/issues/222
                  src = fetchurl {
                    url = "https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-cpu-linux-x86_64-1.14.0.tar.gz";
                    sha256 = "04bi3ijq4sbb8c5vk964zlv0j9mrjnzzxd9q9knq3h273nc1a36k";
                  };
                }))
              ];

              prePatch = ''
                substituteInPlace internal/commands/passwd.go --replace '/bin/stty' "${coreutils}/bin/stty"
                sed -i 's/zip.Deflate/zip.Store/g' internal/api/zip.go
              '';

              passthru = rec {

                frontend = (callPackage npmlock2nix {}).build {
                  name = "photoprism-frontend";
		  src = src + "/frontend";
                  nodejs = nodejs-14_x;

                  postUnpack = ''
                    chmod -R +rw .
                  '';

                  NODE_ENV = "production";

                  buildCommands = [ "npm run build" ];
                  installPhase = ''
                    cp -rv ../assets/static/build $out
                  '';
                };

                assets =
                  let
                    nasnet = fetchzip {
                      url = "https://dl.photoprism.org/tensorflow/nasnet.zip";
                      sha256 = "09cnr2wpc09xrv1crms3mfcl61rxf4nr5j51ppy4ng6bxg9rq5s1";
                    };

                    nsfw = fetchzip {
                      url = "https://dl.photoprism.org/tensorflow/nsfw.zip";
                      sha256 = "0j0r39cgrr0zf2sc1hpr8jh19lr3jxdw9wz6sq3s7kkqay324ab8";
                    };

                  in
                  runCommand "photoprims-assets" { } ''
                    cp -rv ${src}/assets $out
                    chmod -R +rw $out
                    rm -rf $out/static/build
                    cp -rv ${frontend} $out/static/build
                    ln -s ${nsfw} $out/nsfw
                    ln -s ${nasnet} $out/nasnet
                  '';
              };
            }
          );
      };

      checks.x86_64-linux.integration = let
        pkgs = import nixpkgs
          {
            system = "x86_64-linux";
	    overlays = [ self.overlay ];
          };
	in
      pkgs.nixosTest (import ./integration-test.nix { photoprismModule = self.nixosModules.photoprism; });
    };
}
