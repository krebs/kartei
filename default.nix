# kartei - hosts, users and their key material, stored as plain files.
#
# Top-level directories are user namespaces; a namespace holds hosts
# (under hosts/), user records (under users/, several for sub-identities
# like makefu-omo) and raw key files (ssh/, pgp/).
#
# Structure:
#
#   $ns/hosts/$host/ssh.pub                   host ssh public key
#   \$ns/hosts/$host/syncthing.id            syncthing device id
#   \$ns/hosts/$host/binary-cache.pub        nix binary cache public key
#   \$ns/hosts/$host/$net/ip4                IPv4 address
#   \$ns/hosts/$host/$net/ip6                IPv6 address
#   \$ns/hosts/$host/$net/aliases            hostnames, one per line
#   \$ns/hosts/$host/$net/addrs              override for public addresses
#   \$ns/hosts/$host/$net/ssh.port           sshd port if not 22
#   \$ns/hosts/$host/$net/rsa.key            tinc RSA public key (PEM)
#   \$ns/hosts/$host/$net/ed25519.key        tinc ed25519 public key
#   \$ns/hosts/$host/$net/tinc.port          tincd port if not 655
#   \$ns/hosts/$host/$net/tinc.weight        tinc weight; "null" for automatic
#   \$ns/hosts/$host/$net/tinc.subnets       extra tinc subnets, one per line
#   \$ns/hosts/$host/$net/tinc.extra         extra tinc host config (verbatim)
#   \$ns/hosts/$host/$net/wireguard.key      wireguard public key
#   \$ns/hosts/$host/$net/wireguard.port     wireguard port if not 51820
#   \$ns/hosts/$host/$net/wireguard.subnets  wireguard subnets, one per line
#   $ns/users/$user/mail                      mail address
#   $ns/users/$user/ssh.pub                   the user's ssh key(s);
#                                             usually a symlink into ssh/
#   $ns/users/$user/pgp/$role                 pgp key for role (default,
#                                             brain, ...); symlink into pgp/
#   $ns/ssh/*, $ns/pgp/*                      raw key files
#
# Evaluates to { hosts = { $host = ...; }; users = { $user = ...; }; },
# mirroring the legacy krebs.hosts/krebs.users structure; the flake
# re-exports it.  This is pure data; policy (via routes, prefixes, dns,
# uids) belongs to the consumer, e.g. stockholm.
let
  inherit (builtins)
    attrNames concatMap filter fromJSON head listToAttrs match pathExists
    readDir readFile;

  # strip trailing newlines
  trim = s: let m = match "(.*[^\n])\n*" s; in if m == null then "" else head m;

  # non-empty lines
  lines = s: filter (l: l != "" && builtins.isString l) (builtins.split "\n" s);

  int = s: fromJSON (trim s);

  optional = path: f: name:
    if pathExists path then [ { inherit name; value = f (readFile path); } ] else [ ];

  loadNet = dir:
    listToAttrs (concatMap (x: x) [
      (optional (dir + "/ip4") (s: { addr = trim s; }) "ip4")
      (optional (dir + "/ip6") (s: { addr = trim s; }) "ip6")
      (optional (dir + "/aliases") lines "aliases")
      (optional (dir + "/addrs") lines "addrs")
      (optional (dir + "/ssh.port") (s: { port = int s; }) "ssh")
      (if pathExists (dir + "/rsa.key") then [ {
        name = "tinc";
        value = listToAttrs (concatMap (x: x) [
          [ { name = "pubkey"; value = readFile (dir + "/rsa.key"); } ]
          (optional (dir + "/ed25519.key") trim "pubkey_ed25519")
          (optional (dir + "/tinc.port") int "port")
          (optional (dir + "/tinc.weight")
            (s: if trim s == "null" then null else int s) "weight")
          (optional (dir + "/tinc.subnets") lines "subnets")
          (optional (dir + "/tinc.extra") (s: s) "extraConfig")
        ]);
      } ] else [ ])
      (if pathExists (dir + "/wireguard.key") then [ {
        name = "wireguard";
        value = listToAttrs (concatMap (x: x) [
          [ { name = "pubkey"; value = trim (readFile (dir + "/wireguard.key")); } ]
          (optional (dir + "/wireguard.port") int "port")
          (optional (dir + "/wireguard.subnets") lines "subnets")
        ]);
      } ] else [ ])
    ]);

  loadHost = owner: dir: name: {
    inherit name;
    value = listToAttrs (concatMap (x: x) [
      [
        { name = "name"; value = name; }
        { name = "owner"; value = owner; }
        {
          name = "nets";
          value = listToAttrs (map (net: {
            name = net;
            value = loadNet (dir + "/${net}");
          }) (dirsIn dir));
        }
      ]
      (optional (dir + "/ssh.pub") (s: { pubkey = trim s; }) "ssh")
      (optional (dir + "/syncthing.id") (s: { id = trim s; }) "syncthing")
      (optional (dir + "/binary-cache.pub") (s: { pubkey = trim s; }) "binary-cache")
    ]);
  };

  dirsIn = dir:
    filter (n: (readDir dir).${n} == "directory") (attrNames (readDir dir));

  namespaces =
    filter
      (n: match "\\..*" n == null && n != "template")
      (attrNames (readDir ./.));

  hosts = listToAttrs (concatMap
    (ns:
      if pathExists (./. + "/${ns}/hosts")
      then map
        (host: loadHost ns (./. + "/${ns}/hosts/${host}") host)
        (dirsIn (./. + "/${ns}/hosts"))
      else [ ])
    namespaces);

  # entries in a directory that hold content (regular files or symlinks)
  filesIn = dir:
    filter
      (n: (readDir dir).${n} != "directory" && match "\\..*" n == null)
      (attrNames (readDir dir));

  loadUser = dir: name: {
    inherit name;
    value = listToAttrs (concatMap (x: x) [
      [ { name = "name"; value = name; } ]
      (optional (dir + "/mail") trim "mail")
      (optional (dir + "/ssh.pub") trim "pubkey")
      (if pathExists (dir + "/pgp") then [ {
        name = "pgp";
        value.pubkeys = listToAttrs (map (role: {
          name = role;
          value = readFile (dir + "/pgp/${role}");
        }) (filesIn (dir + "/pgp")));
      } ] else [ ])
    ]);
  };

  users = listToAttrs (concatMap
    (ns:
      if pathExists (./. + "/${ns}/users")
      then map
        (user: loadUser (./. + "/${ns}/users/${user}") user)
        (dirsIn (./. + "/${ns}/users"))
      else [ ])
    namespaces);
in {
  inherit hosts users;
}
