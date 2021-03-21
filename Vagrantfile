# -*- mode: ruby -*-

$configure_channels = <<-'SCRIPT'
nix-channel --add https://nixos.org/channels/nixos-unstable unstable
nix-channel --update
SCRIPT

$dirs = [
  "/Users",
  "/Volumes",
  "/private",
]

$ports = [
  4646,
  8500,
  8200,
  2375,
]

Vagrant.configure("2") do |config|
  config.vm.box = "griff/nixos-20.03-x86_64"

  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--acpi", "off"]
  end

  $ports.each do |p|
    config.vm.network "forwarded_port", guest: p, host: p, protocol: "tcp"
  end

  config.vm.synced_folder '.', '/vagrant', disabled: true
  $dirs.each do |d|
    config.vm.synced_folder d, d
  end

  config.vm.provision :shell, inline: $configure_channels

  config.vm.provision :nixos, path: "configuration.nix"
end
