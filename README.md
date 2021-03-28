Developing for a HashiStack environment on OSX is a bit of a pain. This aims to
make things easier.

# Usage
Note that this _does not_ work on newer M1/ARM systems from Apple!

## Prerequisites
 - nix
 - VirtualBox

### What if I don't like Nix?
Nix is used as a convenience tool - it's not strictly necessary. It helps ensure
that the right software is installed and the right environment is configured. If
you don't want to use nix you can do this all yourself.

In that case, the following additional requirements exist:
 - Vagrant
 - Consul (client; if desired)
 - Vault (client; if desired)
 - Nomad (client; if desired)
 - docker (cleint; if desired)
 - docker-compose (if desired)

See the Starting the Environment Without Nix section to get a sense of how to
get going.

## With Nix
### Start the Environment
 - Run `nix-shell` in the base of this project.

That's all! It'll take a few minutes to get started (longer if you need to
download the base Vagrant box, shorter if you don't destroy the Vagrant box
between uses). You should see:

```
Bringing machine 'default' up with 'virtualbox' provider...
==> default: Importing base box 'griff/nixos-20.03-x86_64'...

==> default: Matching MAC address for NAT networking...
==> default: Checking if box 'griff/nixos-20.03-x86_64' version '2003.3325.643379977' is up to date...
==> default: Setting the name of the VM: local-nomad_default_1616313471881_24431
==> default: Clearing any previously set network interfaces...
==> default: Preparing network interfaces based on configuration...
    default: Adapter 1: nat
==> default: Forwarding ports...
    default: 4646 (guest) => 4646 (host) (adapter 1)
    default: 8500 (guest) => 8500 (host) (adapter 1)
    default: 8200 (guest) => 8200 (host) (adapter 1)
    default: 2375 (guest) => 2375 (host) (adapter 1)
    default: 22 (guest) => 2222 (host) (adapter 1)
==> default: Running 'pre-boot' VM customizations...
==> default: Booting VM...
==> default: Waiting for machine to boot. This may take a few minutes...
    default: SSH address: 127.0.0.1:2222
    default: SSH username: vagrant
    default: SSH auth method: private key
    default:
    default: Vagrant insecure key detected. Vagrant will automatically replace
    default: this with a newly generated keypair for better security.
    default:
    default: Inserting generated public key within guest...
    default: Removing insecure key from the guest if it's present...
    default: Key inserted! Disconnecting and reconnecting using new SSH key...
==> default: Machine booted and ready!
==> default: Checking for guest additions in VM...
==> default: Mounting shared folders...
    default: /Users => /Users
    default: /Volumes => /Volumes
    default: /private => /private
==> default: Running provisioner: shell...
    default: Running: inline script
    default: unpacking channels...
    default: created 2 symlinks in user environment
==> default: Running provisioner: nixos...

=======================================

Vault Root Token: XXXXXXXXXXXXXXX
```

Then you should be dropped into a shell. Check that things work:
 - Verify that `vault status` and `vault token lookup` work.
 - Verify that `nomad status` works.
 - Verify that `consul info` works.
 - Verify that docker works, however you prefer.

### Enter an Existing Environment
If your environment is already running, you can still use `nix-shell` to get
your shell configured to interact with it. Just navigate to the base of the
project and run `nix-shell` - your shell session will be configured with all
of the tools and environment variables for the project.

### Adding an Environment to your Project
To add an environment just like this to your project you can import `env.nix` as
a function and call it:
```
{ pkgs ? import <nixpkgs> {} }:
with pkgs;

let
  envkit = fetchFromGitHub {
    owner = "mgregson";
    repo = "osx-hashistack";
    rev = "release/0.2.0";
    sha256 = "1ysbcjq3dl6giha9xb600l2c2k5pa8im3j02vbhlk8sjr8cwgc88";
  };
  mkEnv = import "${envkit}/env.nix" { inherit pkgs; };
in

mkEnv {
  buildInputs = [
  ];
}
```

#### Exposing Additional Ports
You can expose additional ports in your project's environment by adding the
`extraExposedPorts` name to the attrset given to `env.nix`:
```
{ pkgs ? import <nixpkgs> {} }:
with pkgs;

let
  envkit = fetchFromGitHub {
    owner = "mgregson";
    repo = "osx-hashistack";
    rev = "release/0.2.0";
    sha256 = "1ysbcjq3dl6giha9xb600l2c2k5pa8im3j02vbhlk8sjr8cwgc88";
  };
  mkEnv = import "${envkit}/env.nix" { inherit pkgs; };
in

mkEnv {
  extraExposedPorts = [
    2001
  ];
}
```

`extraExposedPorts` should be a list of integers.

## Without Nix
Getting going without Nix is a more involved process:
 - Run `vagrant up` to start the VM.
 - Set `VAULT_ADDR` to `http://127.0.0.1:8200` in your shell.
 - Set `DOCKER_HOST` to `tcp://127.0.0.1:2375` in your shell.
 - Initialize vault using `vault operator init`.
 - Write down the unseal data and root token!
 - Unseal vault using `vault operator unseal`.
 - Set `VAULT_TOKEN` to your root token in your shell.

That should get the environment going. In order to configure a new shell to work
with the environment you'll need to manually configure the appropriate exports.

If you're interested in automating some of this the script embedded in
`default.nix` might be helpful.

# Hacking
If you're using this, let me know! Contributions welcome!

## Ideas/Improvements
 - A clean environment shutdown feature would be pretty convenient. Something
   that suspends the VM, or cleanly shuts it down for later ressurrection.
 - A way to erase the environment and start fresh. Clear out all VM data, all
   vault and consul data, free up any disk space, stop anything that's running,
   and get things into a state so that next time `nix-shell` is invoked a new
   environment is created from default settings.
 - The whole thing could probably be a lot more robust. The two-step
   provisioning process used to configure nomad to work with vault is probably
   very brittle.
 - There's probably a way to use nix more effectively in setting up the
   environment. I suspect that would be better than using a wrapped shell
   script.
 - Replace this entire thing with a customized VM image inside Docker Desktop
   for Mac, removing the dependence on vagrant and VirtualBox entirely. This is
   probably also a better path towards supporting Apple Silicon. It would likely
   also be _faster_.
 - Pull the `Vagrantfile` and `configuration.nix` templates back out into their
   own files so that they're easier to maintain.
