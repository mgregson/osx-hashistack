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
  ...
}@attrs:
let
  mergeInputs = name: lib.concatLists (lib.catAttrs name
    ([attrs] ++ inputsFrom));

  rest = builtins.removeAttrs attrs [
    "inputsFrom"
    "buildInputs"
    "nativeBuildInputs"
    "propagatedBuildInputs"
    "propagatedNativeBuildInputs"
    "shellHook"
    "VAULT_ADDR"
    "DOCKER_HOST"
  ];

  sharedHooks = {
    shellHook = ''
      vagrant plugin install vagrant-nixos-plugin
      if [[ ! -e Vagrantfile ]]
      then
        ln -s ${./Vagrantfile} Vagrantfile
      fi
      if [[ ! -e configuration.nix ]]
      then
        ln -s ${./configuration.nix} configuration.nix
      fi
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
        echo "$VAULT_TOKEN" > .vault.token
        echo "$VAULT_KEY" > .vault.key
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
} // rest)
