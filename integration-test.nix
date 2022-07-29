{ photoprismModule }:
{ ... }:
let photoprismPort = 8080;
in {
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
    assert "PhotoPrism" in machine.succeed("curl -f http://localhost:${toString photoprismPort}")
  '';
}
