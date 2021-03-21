{config, pkgs, ...}:

let
  unstable = import <unstable> { config = { allowUnfree = true; }; };
in

{
  imports = [
    <unstable/nixos/modules/services/networking/nomad.nix>
  ];

  nixpkgs.config.packageOverrides = pkgs: {
    formats = unstable.formats;
  };

  environment = {
    etc = {
      "docker/daemon.json" = {
        text = ''
          {
            "bip": "172.17.0.1/24",
            "dns": ["172.17.0.1"]
          }
        '';
      };
    };
  };

  networking = {
    firewall = {
      trustedInterfaces = [
        "docker0"
      ];
      allowedTCPPortRanges = [
        { from = 1024; to = 65535; }
      ];
      allowedUDPPortRanges = [
        { from = 1024; to = 65535; }
      ];
    };
    resolvconf = {
      useLocalResolver = true;
    };
  };

  services = {
    consul = {
      enable = true;
      dropPrivileges = false;
      extraConfig = {
        bootstrap = true;
        bootstrap_expect = 1;
        recursors = [ "10.0.2.3" ];
        server = true;
        addresses = {
          http = "0.0.0.0";
          dns = "0.0.0.0";
        };
        ports = {
          dns = 53;
        };
        advertise_addr = "{{ GetPrivateInterfaces | include \"network\" \"172.16.0.0/16\" | attr \"address\" }}";
      };
      webUi = true;
    };
    vault = {
      enable = true;
      package = unstable.vault-bin;
      address = "0.0.0.0:8200";
      storageBackend = "consul";
      extraConfig = ''
        api_addr = "http://172.17.0.1:8200"
        ui = true
        service_registration "consul" {
          address = "127.0.0.1:8500"
        }
      '';
    };
    nomad = {
      enable = true;
      settings = {
        server = {
          enabled = true;
          bootstrap_expect = 1;
        };
        client = {
          enabled = true;
        };
        vault = {
          enabled = true;
          address = "http://vault.service.consul:8200";
          token = "s.jkwi6CVRokaF9VPIKUQbSfVO";
        };
        advertise = {
          http = "172.17.0.1";
        };
      };
    };
  };

  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      listenOptions = [
        "/run/docker.sock"
        "0.0.0.0:2375"
      ];
    };
  };

  fileSystems = {
    "/Users" = {
      device = "/Users";
      fsType = "vboxsf";
      options = [
        "uid=1000"
        "gid=999"
        "nofail"
      ];
    };

    "/Volumes" = {
      device = "/Volumes";
      fsType = "vboxsf";
      options = [
        "uid=1000"
        "gid=999"
        "nofail"
      ];
    };

    "/private" = {
      device = "/private";
      fsType = "vboxsf";
      options = [
        "uid=1000"
        "gid=999"
        "nofail"
      ];
    };
  };
}
