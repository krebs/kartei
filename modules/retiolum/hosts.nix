# Derive the retiolum peer set directly from kartei.
{ lib }:
let
  krebs =
    (lib.evalModules {
      modules = [
        ../../module.nix
        { krebs.users.krebs.mail = "spam@krebsco.de"; }
      ];
    }).config.krebs;

  retiolumHosts = lib.filterAttrs (
    _: h: h.nets ? retiolum && h.nets.retiolum.tinc != null
  ) krebs.hosts;

  # tincr is SPTPS-only; drop legacy RSA-only entries so the daemon
  # does not log a refusal per connection attempt.
  sptpsHosts = lib.filterAttrs (_: h: h.nets.retiolum.tinc.pubkey_ed25519 != null) retiolumHosts;

  tincHosts = lib.mapAttrs (_: h: h.nets.retiolum.tinc.config) sptpsHosts;

  netHostsLines =
    netname: tld: hosts: withV4:
    lib.concatStrings (
      lib.mapAttrsToList (
        name: h:
        let
          net = h.nets.${netname};
          aliases = lib.concatStringsSep " " (lib.unique ([ "${name}.${tld}" ] ++ net.aliases));
        in
        lib.optionalString (withV4 && net.ip4 != null) "${net.ip4.addr} ${aliases}\n"
        + lib.optionalString (net.ip6 != null) "${net.ip6.addr} ${aliases}\n"
      ) hosts
    );

  internetHosts = lib.filterAttrs (_: h: h.nets ? internet) krebs.hosts;

  hostsLines =
    withV4:
    netHostsLines "retiolum" "r" retiolumHosts withV4
    + netHostsLines "internet" "i" internetHosts withV4;

  own = lib.mapAttrs (_: h: {
    ip4 = h.nets.retiolum.ip4.addr or null;
    ip6 = h.nets.retiolum.ip6.addr or null;
  }) retiolumHosts;
in
{
  inherit tincHosts own;
  inherit krebs;
  extraHosts = {
    v4v6 = hostsLines true;
    v6only = hostsLines false;
  };
}
