{ pkgs ? import <nixpkgs> {} }:
with pkgs;
mkShell {
  buildInputs = [
    vagrant
    consul
    vault
    nomad
    jq
    docker
    docker-compose
  ];

  VAULT_ADDR = "http://127.0.0.1:8200";
  DOCKER_HOST = "tcp://127.0.0.1:2375";

  shellHook = ''
    if [[ ! -d .consul ]]
    then
      rm -rf .consul
      mkdir -p .consul
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
}
