{ pkgs ? import <nixpkgs> {} }:
let
  env = import ./env.nix { inherit pkgs; };
in

with pkgs;
env {
  buildInputs = [
    consul
    nomad
    docker
    docker-compose
  ];
}
