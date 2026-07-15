# kartei

Krebs host database and retiolum VPN modules.

Each top-level directory that is a user name contains that user's
host and user records.  `module.nix` declares the `krebs.*` options
they populate so the set can be evaluated without stockholm.

The `retiolum` NixOS/Darwin modules consume the host database
directly and drive [tincr](https://github.com/Mic92/tincr), so no
generated `hosts/` or `etc.hosts` files need to be committed.

## Joining retiolum

Before the NixOS module can start `tincd`, the mesh needs to know
your Ed25519 public key and you need a private key on disk.

### 1. Generate a keypair

```console
$ nix shell --refresh 'github:Mic92/tincr'
$ # pre-AVX2 x86_64: nix shell --refresh 'github:Mic92/tincr#tincd-compat'
$ sptps_keypair ed25519_key.priv ed25519_key.pub
$ sudo install -Dm600 ed25519_key.priv /var/src/secrets/tinc.retiolum.ed25519_key.priv
$ rm ed25519_key.priv
$ grep -v '^-' ed25519_key.pub
ZD2Ft17KwDElzv0YPV6AeKrMYMpqlMpN9hbGt/HcveL
```

The last line is your `tinc.pubkey_ed25519`.

### 2. Add your host to kartei

Fork this repository and either edit your existing user directory or
copy `template/`:

```console
$ cp -r template alice
$ $EDITOR alice/default.nix
```

```nix
{ config, lib, ... }: let
  slib = import ../lib { inherit lib; };
in {
  users.alice = {
    mail = "alice@example.org";
  };
  hosts.toaster = {
    owner = config.krebs.users.alice;
    nets.retiolum = {
      aliases = [ "toaster.alice.r" ];
      ip6.addr = (slib.krebs.genipv6 "retiolum" "alice" { hostName = "toaster"; }).address;
      # optional; ask in #krebs for a free 10.243.x.y
      # ip4.addr = "10.243.42.1";
      tinc.pubkey_ed25519 = "ZD2Ft17KwDElzv0YPV6AeKrMYMpqlMpN9hbGt/HcveL";
    };
  };
}
```

Check it evaluates and open a PR:

```console
$ nix flake check
$ git add alice && git commit -m 'alice: add toaster'
```

### 3. Enable the NixOS module

Point your configuration at kartei as shown under [NixOS](#nixos) or
[NixOS without flakes](#nixos-without-flakes).
`networking.retiolum.nodename` defaults to `networking.hostName` and
IPv4/IPv6 are looked up from the entry you added, so the only
required setting is the private key path:

```nix
networking.retiolum.ed25519PrivateKeyFile =
  "/var/src/secrets/tinc.retiolum.ed25519_key.priv";
```

After `nixos-rebuild switch`, `tincr-retiolum.service` comes up and
`ping hotdog.r` should answer.

## NixOS

```nix
{
  inputs.kartei.url = "github:krebs/kartei";

  outputs = { kartei, nixpkgs, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        kartei.nixosModules.retiolum
        kartei.nixosModules.ca      # optional: trust the .r/.w ACME CA
        # kartei.nixosModules.default  # bare krebs.{hosts,users} data
        {
          # nodename defaults to networking.hostName; ipv4/ipv6 are
          # looked up in kartei by nodename.
          networking.retiolum.ed25519PrivateKeyFile =
            "/var/src/secrets/tinc.retiolum.ed25519_key.priv";
        }
      ];
    };
  };
}
```

Name resolution for `.r` uses tincr's built-in DNS stub via
systemd-resolved.  A static `/etc/hosts` copy is also installed by
default (`networking.retiolum.extraHosts`) so the mesh stays
resolvable while tincd is restarting.

On pre-AVX2 x86_64 hardware set
`services.tincr.package = tincr.packages.${system}.tincd-compat;`.

## NixOS without flakes

```nix
{
  imports = let
    kartei = builtins.fetchTarball "https://github.com/krebs/kartei/archive/master.tar.gz";
  in [
    "${kartei}/modules/retiolum"
    "${kartei}/modules/ca"
  ];
  networking.retiolum.ed25519PrivateKeyFile = "/var/src/secrets/tinc.retiolum.ed25519_key.priv";
}
```

The module fetches tincr from the revision pinned in `flake.lock`.

## nix-darwin

```nix
darwinConfigurations.mymac = darwin.lib.darwinSystem {
  modules = [
    kartei.darwinModules.retiolum
    kartei.darwinModules.ca
    {
      networking.retiolum.nodename = "mymac";
      networking.retiolum.ed25519PrivateKeyFile =
        "/var/src/secrets/tinc.retiolum.ed25519_key.priv";
    }
  ];
};
```

## Artefacts

For consumers that still want plain files:

```
nix build .#retiolum-hosts     # /etc/tinc/retiolum/hosts directory
nix build .#etc-hosts          # /etc/hosts fragment (v4+v6)
nix build .#etc-hosts-v6only
nix build .#wiregrill-json
```
