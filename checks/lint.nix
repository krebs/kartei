# Cross-host duplicate detection, format checks and unknown-file
# detection that the per-record module types cannot express.
# Evaluates to a list of error strings; empty means the data is clean.
{ lib, root, hosts, users }:
let
  inherit (lib) concatLists elem filterAttrs hasPrefix mapAttrsToList optional optionals;

  # intentional oddities inherited from stockholm
  isTestHost = hasPrefix "test-"; # test fixtures share one retiolum address
  exemptUsers = [ "krebs" ]; # the krebs user's pubkey has always been "lol"

  # [ { key; desc; } ] -> errors for keys used by more than one desc
  dupErrors = what: entries:
    mapAttrsToList
      (key: es: "duplicate ${what} ${key}: ${lib.concatMapStringsSep ", " (e: e.desc) es}")
      (filterAttrs (_: es: lib.length es > 1)
        (lib.groupBy (e: e.key) (lib.filter (e: e.key != null) entries)));

  netsOf = hs: concatLists (mapAttrsToList
    (host: h: mapAttrsToList (netname: net: { inherit host netname net; }) h.nets)
    hs);
  nets = netsOf hosts;

  # duplicates within each net, over [ { netname; key; desc; } ]
  perNetDup = what: entries:
    concatLists (mapAttrsToList
      (netname: dupErrors "${netname} ${what}")
      (lib.groupBy (e: e.netname) entries));

  netKey = getKey: map (n: { inherit (n) netname; key = getKey n.net; desc = n.host; });

  duplicates =
    perNetDup "ip4"
      (netKey (net: net.ip4.addr or null)
        (netsOf (filterAttrs (host: _: !isTestHost host) hosts)))
    ++ perNetDup "ip6" (netKey (net: net.ip6.addr or null) nets)
    ++ perNetDup "alias" (concatLists (map
      (n: map (alias: { inherit (n) netname; key = alias; desc = n.host; }) n.net.aliases)
      nets))
    ++ dupErrors "tinc ed25519 key"
      (map (n: { key = n.net.tinc.pubkey_ed25519 or null; desc = "${n.host}/${n.netname}"; }) nets)
    ++ dupErrors "wireguard key"
      (map (n: { key = n.net.wireguard.pubkey or null; desc = "${n.host}/${n.netname}"; }) nets)
    ++ dupErrors "host ssh key"
      (mapAttrsToList (host: h: { key = h.ssh.pubkey; desc = host; }) hosts)
    ++ dupErrors "syncthing id"
      (mapAttrsToList (host: h: { key = h.syncthing.id; desc = host; }) hosts);

  ip4Re = "([0-9]{1,3}\\.){3}[0-9]{1,3}";
  ip6Re = "[0-9a-fA-F:]*:[0-9a-fA-F:.]*";
  sshKeyRe = "(ssh|sk-ssh|ecdsa|sk-ecdsa)-[^ ]+ [A-Za-z0-9+/=]+( [^\n]*)?";
  syncthingRe = "([A-Z0-9]{7}-){7}[A-Z0-9]{7}";
  cacheKeyRe = "[^:]+:[A-Za-z0-9+/=]+";
  wgKeyRe = "[A-Za-z0-9+/]{42,43}=";
  ed25519Re = "[A-Za-z0-9+/]+";
  hostnameRe = "[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?";
  mailRe = "[^@ ]+@[^@ ]+\\.[^@ ]+";

  checkFmt = desc: what: re: value:
    optional (value != null && lib.match re value == null)
      "${desc}: malformed ${what}: ${lib.strings.escapeNixString value}";

  checkLines = desc: what: re: value:
    concatLists (map (line: checkFmt desc what re line)
      (optionals (value != null) (lib.splitString "\n" value)));

  formats =
    concatLists
      (mapAttrsToList
        (host: h:
          checkFmt host "binary cache key" cacheKeyRe h.binary-cache.pubkey
          ++ checkFmt host "syncthing id" syncthingRe h.syncthing.id
          ++ checkLines host "ssh host key" sshKeyRe h.ssh.pubkey
          ++ concatLists (mapAttrsToList
            (netname: net:
              let desc = "${host}/${netname}"; in
              checkFmt desc "ip4" ip4Re (net.ip4.addr or null)
              ++ checkFmt desc "ip6" ip6Re (net.ip6.addr or null)
              ++ checkFmt desc "tinc ed25519 key" ed25519Re (net.tinc.pubkey_ed25519 or null)
              ++ checkFmt desc "wireguard key" wgKeyRe (net.wireguard.pubkey or null)
              ++ concatLists (map (a: checkFmt desc "alias" hostnameRe a) net.aliases)
              ++ optional (net.via != null && !(h.nets ? ${net.via}))
                "${desc}: via points to unknown net ${net.via}")
            h.nets))
        hosts)
    ++ concatLists (mapAttrsToList
      (user: u:
        checkFmt user "mail address" mailRe u.mail
        ++ checkLines user "ssh key" sshKeyRe u.pubkey)
      (removeAttrs users exemptUsers));

  knownHostFiles = [ "ssh.pub" "syncthing.id" "binary-cache.pub" ];
  knownNetFiles = [
    "ip4"
    "ip6"
    "aliases"
    "addrs"
    "via"
    "ssh.port"
    "rsa.key"
    "ed25519.key"
    "tinc.port"
    "tinc.weight"
    "tinc.subnets"
    "tinc.extra"
    "wireguard.key"
    "wireguard.port"
    "wireguard.subnets"
  ];
  knownUserFiles = [ "mail" "ssh.pub" ];

  entries = dir:
    if builtins.pathExists dir then builtins.readDir dir else { };

  dirsIn = dir: filterAttrs (_: t: t == "directory") (entries dir);

  # entries of dir not accepted by allowed: name -> type -> bool
  unknownIn = desc: dir: allowed:
    mapAttrsToList (name: _: "${desc}/${name}: unknown file")
      (filterAttrs (name: type: !hasPrefix "." name && !allowed name type)
        (entries dir));

  namespaces = lib.attrNames (filterAttrs
    (name: type: type == "directory" && !hasPrefix "." name
      && (builtins.pathExists (root + "/${name}/hosts")
      || builtins.pathExists (root + "/${name}/users")))
    (builtins.readDir root));

  unknownFiles = concatLists (map
    (ns:
      let nsDir = root + "/${ns}"; in
      unknownIn ns nsDir
        (name: type: type == "directory" && elem name [ "hosts" "users" "ssh" "pgp" ])
      ++ concatLists (mapAttrsToList
        (host: _:
          let hostDir = nsDir + "/hosts/${host}"; in
          unknownIn "${ns}/hosts/${host}" hostDir
            (name: type: type == "directory" || elem name knownHostFiles)
          ++ concatLists (mapAttrsToList
            (net: _: unknownIn "${ns}/hosts/${host}/${net}" (hostDir + "/${net}")
              (name: type: type != "directory" && elem name knownNetFiles))
            (dirsIn hostDir)))
        (dirsIn (nsDir + "/hosts")))
      ++ concatLists (mapAttrsToList
        (user: _: unknownIn "${ns}/users/${user}" (nsDir + "/users/${user}")
          (name: type:
            if type == "directory" then name == "pgp" else elem name knownUserFiles))
        (dirsIn (nsDir + "/users"))))
    namespaces);
in
duplicates ++ formats ++ unknownFiles
