# Artefacts the old retiolum repo used to commit, for non-NixOS
# consumers. The NixOS module reads the same data straight from Nix.
{
  lib,
  runCommand,
  writeText,
}:
let
  data = import ./modules/retiolum/hosts.nix { inherit lib; };
  krebs = data.krebs;

  # Some hosts declare a wiregrill net without a wireguard pubkey; the
  # submodule then throws on access instead of being null.
  wiregrill = lib.filterAttrs (
    _: h:
    h.nets ? wiregrill
    && (
      let
        r = builtins.tryEval (h.nets.wiregrill.wireguard.pubkey or null);
      in
      r.success && r.value != null
    )
  ) krebs.hosts;
  # knot on eve serves .r/.w for the whole mesh; the per-node tincr
  # DNS stub does not replace that.
  zone =
    tld: netname:
    ''
      @ 3600 IN SOA ${tld}. root.${tld}. 1 7200 3600 86400 3600
      @ 3600 IN NS ns1
      ns1 IN A 10.243.29.174
      ns1 IN AAAA 42:0:3c46:70c7:8526:2adf:7451:8bbb
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        name: h:
        let
          net = h.nets.${netname};
        in
        lib.concatMapStrings (
          alias:
          let
            hn = lib.removeSuffix ".${tld}" alias;
          in
          lib.optionalString (lib.hasSuffix ".${tld}" alias) (
            lib.optionalString (net.ip4 != null) "${hn} IN A ${net.ip4.addr}\n"
            + lib.optionalString (net.ip6 != null) "${hn} IN AAAA ${net.ip6.addr}\n"
          )
        ) (lib.unique ([ "${name}.${tld}" ] ++ net.aliases))
      ) (lib.filterAttrs (_: h: h.nets ? ${netname}) krebs.hosts)
    );

  wiregrillJson = builtins.toJSON (
    lib.mapAttrs (_: h: {
      pubkey = h.nets.wiregrill.wireguard.pubkey;
      addrs = h.nets.wiregrill.addrs;
      subnets = h.nets.wiregrill.wireguard.subnets;
      endpoint = h.nets.wiregrill.via.addrs or null;
    }) wiregrill
  );
in
{
  retiolum-hosts =
    runCommand "retiolum-hosts"
      {
        passAsFile = [ "script" ];
        script = lib.concatStrings (
          lib.mapAttrsToList (name: text: ''
            cat > "$out/${name}" <<'EOF'
            ${text}
            EOF
          '') data.tincHosts
        );
      }
      ''
        mkdir -p $out
        bash "$scriptPath"
      '';

  r-zone = writeText "r.zone" (zone "r" "retiolum");
  w-zone = writeText "w.zone" (zone "w" "wiregrill");
  i-zone = writeText "i.zone" (zone "i" "internet");

  etc-hosts = writeText "etc.hosts" data.extraHosts.v4v6;
  etc-hosts-v6only = writeText "etc.hosts-v6only" data.extraHosts.v6only;
  wiregrill-json = writeText "wiregrill.json" wiregrillJson;
}
