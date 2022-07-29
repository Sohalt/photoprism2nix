{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.services.photoprism;
  settingsFormat = pkgs.formats.yaml {};
in {
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

      adminPasswordFile = mkOption {type = types.path;};

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/photoprism";
      };

      settings = mkOption {
        type = settingsFormat.type;
        description = ''
          Settings for Photoprism. See <link xlink:href="https://docs.photoprism.app/getting-started/config-options/" /> for available options.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.photoprism;
        description = "The photoprism package.";
      };
    };
  };

  config = with lib;
    mkIf cfg.enable {
      services.photoprism.settings = {
        DatabaseDriver =
          if cfg.mysql
          then "mysql"
          else "sqlite";
        DatabaseDSN =
          if cfg.mysql
          then "${cfg.dataDir}/photoprism.sqlite"
          else "photoprism@unix(/run/mysqld/mysqld.sock)/photoprism?charset=utf8mb4,utf8&parseTime=true";
        HttpHost = cfg.host;
        HttpPort = cfg.port;
        HttpMode = "release";
        AssetsPath = cfg.package.assets;
        Public = mkDefault false;
        Readonly = mkDefault false;
        SiteUrl = mkDefault "http://${cfg.host}:${toString cfg.port}";
        SidecarPath = mkDefault "${cfg.dataDir}/sidecar";
        StoragePath = mkDefault "${cfg.dataDir}/storage";
        OriginalsPath = mkDefault "${cfg.dataDir}/originals";
        ImportPath = mkDefault "${cfg.dataDir}/import";
        UploadNsfw = mkDefault true;
      };

      users.users.photoprism = {
        isSystemUser = true;
        group = "photoprism";
      };

      users.groups.photoprism = {};

      services.mysql = mkIf cfg.mysql {
        enable = true;
        package = mkDefault pkgs.mysql;
        ensureDatabases = ["photoprism"];
        ensureUsers = [
          {
            name = "photoprism";
            ensurePermissions = {"photoprism.*" = "ALL PRIVILEGES";};
          }
        ];
      };

      systemd.services.photoprism = {
        enable = true;
        after =
          ["network-online.target"]
          ++ optional cfg.mysql "mysql.service";
        wantedBy = ["multi-user.target"];

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

        script = ''
          PHOTOPRISM_ADMIN_PASSWORD=$(cat $CREDENTIALS_DIRECTORY/admin_password) ${cfg.package}/bin/photoprism --defaults-yaml ${
            settingsFormat.generate "defaults.yaml" cfg.settings
          } --assets-path ${cfg.package.assets} start
        '';

        serviceConfig = {
          User = "photoprism";
          BindPaths =
            [cfg.dataDir]
            ++ lib.optionals cfg.mysql [
              "-/run/mysqld"
              "-/var/run/mysqld"
            ];
          LoadCredential = ["admin_password:${cfg.adminPasswordFile}"];
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
          MemoryDenyWriteExecute = false;
          RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
          RestrictSUIDSGID = true;
          NoNewPrivileges = true;
          RemoveIPC = true;
          LockPersonality = true;
          ProtectHome = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
          SystemCallErrorNumber = "EPERM";
        };
      };
    };
}
