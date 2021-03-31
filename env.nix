{ pkgs ? import <nixpkgs> {} }:
with pkgs;
# A special kind of derivation that is only meant to be consumed by the
# nix-shell.
{
  inputsFrom ? [], # a list of derivations whose inputs will be made available to the environment
  buildInputs ? [],
  nativeBuildInputs ? [],
  propagatedBuildInputs ? [],
  propagatedNativeBuildInputs ? [],
  extraExposedPorts ? [],
  vmCpus ? 1,
  vmMemory ? 2048,
  ...
}@attrs:
let
  defaultExposedPorts = [4646 8500 8200];
  exposedPorts = defaultExposedPorts ++ extraExposedPorts;
  configurationfile = writeTextFile {
    name = "configuration.nix";
    text = ''
{config, pkgs, ...}:

let
  unstable = import <unstable> { config = { allowUnfree = true; }; };
  hasVaultTokenFile = builtins.pathExists /etc/nixos/vault-token;
  vaultToken = if hasVaultTokenFile then builtins.readFile /etc/nixos/vault-token else "s.pLaCeHoLdEr";
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
        text = '''
          {
            "bip": "172.17.0.1/24",
            "dns": ["172.17.0.1"]
          }
        ''';
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
      extraConfig = '''
        api_addr = "http://172.17.0.1:8200"
        ui = true
        service_registration "consul" {
          address = "127.0.0.1:8500"
        }
      ''';
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
          enabled = hasVaultTokenFile;
          address = "http://vault.service.consul:8200";
          token = vaultToken;
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
    '';
  };

  vagrantfile = writeTextFile {
    name = "Vagrantfile";
    text = ''
      $configure_channels = <<-'SCRIPT'
      nix-channel --add https://nixos.org/channels/nixos-unstable unstable
      nix-channel --update
      SCRIPT

      $dirs = [
        "/Users",
        "/Volumes",
        "/private",
      ]

      $ports = [${(lib.strings.concatStrings (lib.strings.intersperse "," (map toString exposedPorts)))}]

      Vagrant.configure("2") do |config|
        config.vm.box = "griff/nixos-20.03-x86_64"

        config.vm.provider "virtualbox" do |v|
          v.cpus = ${toString vmCpus}
          v.memory = ${toString vmMemory}
          v.customize ["modifyvm", :id, "--acpi", "off"]
        end

        $ports.each do |p|
          config.vm.network "forwarded_port", guest: p, host: p, protocol: "tcp"
        end

        config.vm.synced_folder '.', '/vagrant', disabled: true
        $dirs.each do |d|
          config.vm.synced_folder d, d
        end

        config.vm.provision :install_channels,
                            type: :shell,
                            inline: $configure_channels

        config.vm.provision :nixos,
                            path: "${configurationfile}"

        if File.exist?(".vault.token")
          config.vm.provision :vault_token,
                              type: :file,
                              run: :never,
                              source: ".vault.token",
                              destination: "/tmp/vault-token"

          config.vm.provision :install_token,
                              type: :shell,
                              run: :never,
                              inline: "mv /tmp/vault-token /etc/nixos/vault-token"
        end
      end
    '';
  };

  mergeInputs = name: lib.concatLists (lib.catAttrs name
    ([attrs] ++ inputsFrom));

  rest = builtins.removeAttrs attrs [
    "inputsFrom"
    "buildInputs"
    "nativeBuildInputs"
    "propagatedBuildInputs"
    "propagatedNativeBuildInputs"
    "shellHook"
    "exposedPorts"
    "VAULT_ADDR"
    "DOCKER_HOST"
  ];

  sharedHooks = {
    shellHook = ''
      vagrant plugin install vagrant-nixos-plugin
      if [[ `vagrant status --machine-readable | grep "default,state," | cut -d, -f4` != "running" ]]
      then
        vagrant up --no-tty
        sleep 10
      fi
      if [[ `vault status -format=json | jq '.initialized'` == "false" ]]
      then
        VAULT_DATA=`vault operator init -format=json --key-shares=1 --key-threshold=1`
        export VAULT_KEY=`echo "$VAULT_DATA" | jq -j '.unseal_keys_b64[0]'`
        export VAULT_TOKEN=`echo "$VAULT_DATA" | jq -j '.root_token'`
        echo -n "$VAULT_TOKEN" > .vault.token
        echo -n "$VAULT_KEY" > .vault.key
        vagrant provision --provision-with vault_token
        vagrant provision --provision-with install_token
        vagrant provision --provision-with nixos
      fi
      if [[ -f .vault.token ]]
      then
        export VAULT_TOKEN=`cat .vault.token`
      fi
      if [[ -f .vault.key ]]
      then
        export VAULT_KEY=`cat .vault.key`
      fi
      if [[ -n "$VAULT_KEY" && -n "$VAULT_TOKEN" ]]
      then
        if [[ `vault status -format=json | jq '.sealed'` == "true" ]]
        then
          vault operator unseal $VAULT_KEY > /dev/null
          echo ""
          echo "======================================="
          echo ""
          echo "Vault Root Token:" $VAULT_TOKEN
        fi
      fi
    '';
  };
in

stdenv.mkDerivation ({
  name = "nix-shell";
  phases = ["nobuildPhase"];

  buildInputs = (mergeInputs "buildInputs") ++ [
    vagrant
    vault
    jq
  ];
  nativeBuildInputs = mergeInputs "nativeBuildInputs";
  propagatedBuildInputs = mergeInputs "propagatedBuildInputs";
  propagatedNativeBuildInputs = mergeInputs "propagatedNativeBuildInputs";

  shellHook = lib.concatStringsSep "\n" (lib.catAttrs "shellHook"
    (lib.reverseList inputsFrom ++ [sharedHooks attrs]));

  nobuildPhase = ''
    echo
    echo "This derivation is not meant to be built, aborting";
    echo
    exit 1
  '';

  VAULT_ADDR = "http://127.0.0.1:8200";
  DOCKER_HOST = "tcp://127.0.0.1:2375";
  VAGRANT_VAGRANTFILE = vagrantfile;
} // rest)
