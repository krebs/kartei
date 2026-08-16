# kartei

Krebs host database and retiolum VPN modules.

Hosts, users and their key material live as plain files, one value
per file (see the schema comment in `default.nix`).  Each top-level
directory is a user namespace.

The `retiolum` NixOS/Darwin modules consume the host database
directly and drive [tincr](https://github.com/Mic92/tincr).

## Joining retiolum

Joining takes two steps: publish your host's public key here in
kartei, and point your NixOS configuration at the private key.

### 1. Add your host to kartei

Fork this repository and run

```console
$ nix run .#add-host
```

The wizard asks for your namespace and hostname, generates a tinc
keypair, picks an IPv6 address and writes all files where they
belong.  Follow its instructions to install the private key on your
host, then commit and open a PR:

```console
$ nix flake check
$ git commit -m 'alice: add toaster'
```

<details>
<summary>Manual steps, if you prefer to skip the wizard</summary>

Generate a keypair and install the private half on your host:

```console
$ nix shell --refresh 'github:Mic92/tincr'
$ # pre-AVX2 x86_64: nix shell --refresh 'github:Mic92/tincr#tincd-compat'
$ sptps_keypair ed25519_key.priv ed25519_key.pub
$ sudo install -Dm600 ed25519_key.priv /var/src/secrets/tinc.retiolum.ed25519_key.priv
$ rm ed25519_key.priv
```

Publish the public half in your namespace (copy `template/` if you
don't have one yet):

```console
$ cp -r template alice
$ mv alice/hosts/DUMMYHOST alice/hosts/toaster
$ cd alice/hosts/toaster/retiolum
$ echo toaster.alice.r > aliases
$ grep -v '^-' /path/to/ed25519_key.pub > ed25519.key
$ rm rsa.key            # tincr is SPTPS-only, no RSA needed
$ rm ip4                # optional, see below
$ nix eval --raw --impure --expr \
    '((import ./lib { }).krebs.genipv6 "retiolum" "alice" { hostName = "toaster"; }).address' \
    > ip6
$ # optional; ask in #krebs for a free 10.243.x.y
$ # echo 10.243.42.1 > ip4
```

</details>

### 2. Enable the NixOS module

Import the retiolum module as shown under [NixOS](#nixos) or
[NixOS without flakes](#nixos-without-flakes).  Everything else is
looked up in kartei: the node name defaults to
`networking.hostName` and the addresses come from the entry you
just added.  All that's left to configure is the private key path:

```nix
networking.retiolum.ed25519PrivateKeyFile =
  "/var/src/secrets/tinc.retiolum.ed25519_key.priv";
```

After `nixos-rebuild switch`, `tincr-retiolum.service` comes up and
`ping hotdog.r` should answer.

## Leaving retiolum

`nix run .#remove-host` picks the host, deletes its records and
cleans up the namespace if nothing else is left.

## NixOS

```nix
{
  inputs.kartei.url = "github:krebs/kartei";

  outputs = { kartei, nixpkgs, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        kartei.nixosModules.retiolum
        kartei.nixosModules.ca      # optional: trust the .r/.w ACME CA
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

`.r` names resolve via tincr's DNS stub through systemd-resolved.
A static `/etc/hosts` copy is installed by default
(`networking.retiolum.extraHosts`) so the mesh stays resolvable
while tincd is restarting.

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

## Data

The raw records are exposed as flake outputs `hosts` and `users`,
or without flakes via `import <kartei> { inherit lib; }`.

Plain-file artefacts:

```
nix build .#retiolum-hosts     # /etc/tinc/retiolum/hosts directory
nix build .#etc-hosts          # /etc/hosts fragment (v4+v6)
nix build .#etc-hosts-v6only
nix build .#r-zone .#w-zone .#i-zone
nix build .#wiregrill-json
```
