{ pkgs, photoprismModule }:
{ ... }:
let photoprismPort = 8080;
in {
  name = "photoprism-test";
  hostPkgs = pkgs;
  nodes.machine = { config, pkgs, ... }: {
    imports = [ photoprismModule ];
    services.photoprism = {
      enable = true;
      port = photoprismPort;
      adminPasswordFile = pkgs.writeText "admin-password" "insecure";
    };
  };

  testScript = ''
    machine.wait_for_open_port(${toString photoprismPort})
    assert "PhotoPrism" in machine.succeed("curl -L -f http://localhost:${toString photoprismPort}")
  '';
}
