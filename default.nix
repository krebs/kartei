# kartei - hosts, users and their key material, stored as plain files.
#
# Top-level directories are user namespaces; a namespace holds hosts
# (under hosts/), user records (under users/, several for sub-identities
# like makefu-omo) and raw key files (ssh/, pgp/).
#
# Structure:
#
#   $ns/hosts/$host/ssh.pub                 host ssh public key
#   $ns/hosts/$host/syncthing.id            syncthing device id
#   $ns/hosts/$host/binary-cache.pub        nix binary cache public key
#   $ns/hosts/$host/$net/ip4                IPv4 address
#   $ns/hosts/$host/$net/ip6                IPv6 address
#   $ns/hosts/$host/$net/aliases            hostnames, one per line
#   $ns/hosts/$host/$net/addrs              override for public addresses
#   $ns/hosts/$host/$net/via                net name over which daemons are
#                                           publicly reachable, e.g. internet
#   $ns/hosts/$host/$net/ssh.port           sshd port if not 22
#   $ns/hosts/$host/$net/rsa.key            tinc RSA public key (PEM)
#   $ns/hosts/$host/$net/ed25519.key        tinc ed25519 public key
#   $ns/hosts/$host/$net/tinc.port          tincd port if not 655
#   $ns/hosts/$host/$net/tinc.weight        tinc weight; "null" for automatic
#   $ns/hosts/$host/$net/tinc.subnets       extra tinc subnets, one per line
#   $ns/hosts/$host/$net/tinc.extra         extra tinc host config (verbatim)
#   $ns/hosts/$host/$net/wireguard.key      wireguard public key
#   $ns/hosts/$host/$net/wireguard.port     wireguard port if not 51820
#   $ns/hosts/$host/$net/wireguard.subnets  wireguard subnets, one per line
#   $ns/users/$user/mail                    mail address
#   $ns/users/$user/ssh.pub                 the user's ssh key(s);
#                                           usually a symlink into ssh/
#   $ns/users/$user/pgp/$role               pgp key for role (default,
#                                           brain, ...); symlink into pgp/
#   $ns/ssh/*, $ns/pgp/*                    raw key files
#
# Each namespace becomes a module that only states where its records
# live; every option reads its file in its default, so consumers can
# override single values through the module system.
#
# Evaluates to { hosts = { $host = ...; }; users = { $user = ...; }; },
# mirroring the legacy krebs.hosts/krebs.users structure.  This is pure
# data; policy (via routes, prefixes, dns, uids) belongs to the
# consumer, e.g. stockholm.
#
# Needs nixpkgs' lib: import <kartei> { inherit lib; }
# (or with NIX_PATH set, plain `import <kartei> { }`).
{ lib ? import <nixpkgs/lib> }:
let
  inherit (builtins) pathExists readDir readFile;
  inherit (lib) mkOption types;

  # ---------------------------------------------------------------------
  # file primitives

  # file content with trailing newlines stripped; null if absent
  text = path:
    if pathExists path
    then lib.removeSuffix "\n" (readFile path)
    else null;

  # non-empty lines of a file; empty list if absent
  linesOf = path:
    if pathExists path
    then lib.filter (l: l != "") (lib.splitString "\n" (readFile path))
    else [ ];

  # integer file with a fallback
  intOr = default: path:
    let s = text path; in if s == null then default else lib.toInt s;

  dirsIn = dir:
    lib.filterAttrs (_: type: type == "directory") (readDir dir);

  # regular files and symlinks, no dotfiles
  filesIn = dir:
    lib.filterAttrs
      (name: type: type != "directory" && !lib.hasPrefix "." name)
      (readDir dir);

  # ---------------------------------------------------------------------
  # shared bits of the option tree below

  dirOption = mkOption {
    type = types.path;
    internal = true;
    description = "directory this record is loaded from";
  };

  addrType = types.submodule {
    options.addr = mkOption {
      type = types.str;
      description = "IP address";
    };
  };

  # ---------------------------------------------------------------------
  # the option tree, nested like the output; every option defaults to
  # the content of its file

  optionsModule.options = {

    hosts = mkOption {
      default = { };
      description = "all machines, keyed by hostname";
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          dir = dirOption;
          name = mkOption {
            type = types.str;
            default = name;
            description = "hostname; defaults to the directory name";
          };
          owner = mkOption {
            type = types.str;
            description = "name of the user this host belongs to";
          };
          ssh.pubkey = mkOption {
            type = types.nullOr types.str;
            default = text (config.dir + "/ssh.pub");
            description = "ssh host key, as in /etc/ssh/ssh_host_*.pub";
          };
          syncthing.id = mkOption {
            type = types.nullOr types.str;
            default = text (config.dir + "/syncthing.id");
            description = "syncthing device id";
          };
          binary-cache.pubkey = mkOption {
            type = types.nullOr types.str;
            default = text (config.dir + "/binary-cache.pub");
            description = "nix binary cache signing key of this host";
          };

          nets = mkOption {
            default = { };
            description = "networks this host is part of, keyed by net name (retiolum, wiregrill, internet, ...)";
            type = types.attrsOf (types.submodule ({ name, config, ... }: {
              options = {
                dir = dirOption;
                name = mkOption {
                  type = types.str;
                  default = name;
                  description = "net name; defaults to the directory name";
                };
                ip4 = mkOption {
                  type = types.nullOr addrType;
                  default =
                    lib.mapNullable (addr: { inherit addr; }) (text (config.dir + "/ip4"));
                  description = "IPv4 address of this host inside the net";
                };
                ip6 = mkOption {
                  type = types.nullOr addrType;
                  default =
                    lib.mapNullable (addr: { inherit addr; }) (text (config.dir + "/ip6"));
                  description = "IPv6 address of this host inside the net";
                };
                via = mkOption {
                  type = types.nullOr types.str;
                  default = text (config.dir + "/via");
                  description = "name of the net over which this host's tinc/wireguard daemon is publicly reachable, e.g. internet";
                };
                aliases = mkOption {
                  type = types.listOf types.str;
                  default = linesOf (config.dir + "/aliases");
                  description = "hostnames of this host inside the net, e.g. for /etc/hosts";
                };
                addrs = mkOption {
                  type = types.listOf types.str;
                  description = "publicly reachable addresses; defaults to ip4/ip6, override for hosts reachable by DNS name";
                  default =
                    if pathExists (config.dir + "/addrs")
                    then linesOf (config.dir + "/addrs")
                    else
                      lib.optional (config.ip4 != null) config.ip4.addr
                      ++ lib.optional (config.ip6 != null) config.ip6.addr;
                };
                ssh.port = mkOption {
                  type = types.port;
                  default = intOr 22 (config.dir + "/ssh.port");
                  description = "port sshd listens on inside the net";
                };

                tinc = mkOption {
                  description = "tinc daemon parameters; null when the host does not speak tinc in the net";
                  type = types.nullOr (types.submodule ({ config, ... }: {
                    options = {
                      dir = dirOption;
                      pubkey = mkOption {
                        type = types.nullOr types.str;
                        default =
                          if pathExists (config.dir + "/rsa.key")
                          then readFile (config.dir + "/rsa.key")
                          else null;
                        description = "tinc RSA public key (PEM, verbatim); null for SPTPS-only hosts";
                      };
                      pubkey_ed25519 = mkOption {
                        type = types.nullOr types.str;
                        default = text (config.dir + "/ed25519.key");
                        description = "tinc ed25519 public key; required for SPTPS-only daemons like tincr";
                      };
                      port = mkOption {
                        type = types.port;
                        default = intOr 655 (config.dir + "/tinc.port");
                        description = "port tincd listens on";
                      };
                      weight = mkOption {
                        type = types.nullOr types.int;
                        description = "route weight; null lets tinc measure";
                        default =
                          let w = text (config.dir + "/tinc.weight");
                          in if w == null then 300 else if w == "null" then null else lib.toInt w;
                      };
                      subnets = mkOption {
                        type = types.listOf types.str;
                        default = linesOf (config.dir + "/tinc.subnets");
                        description = "extra subnets routed to this host, on top of its own addresses";
                      };
                      extraConfig = mkOption {
                        type = types.lines;
                        default =
                          if pathExists (config.dir + "/tinc.extra")
                          then readFile (config.dir + "/tinc.extra")
                          else "";
                        description = "verbatim additions to the generated tinc host file";
                      };
                    };
                  }));
                  default =
                    if pathExists (config.dir + "/rsa.key")
                       || pathExists (config.dir + "/ed25519.key")
                    then { dir = config.dir; }
                    else null;
                };

                wireguard = mkOption {
                  description = "wireguard parameters; null when the host does not speak wireguard in the net";
                  type = types.nullOr (types.submodule ({ config, ... }: {
                    options = {
                      dir = dirOption;
                      pubkey = mkOption {
                        type = types.str;
                        default = text (config.dir + "/wireguard.key");
                        description = "wireguard public key";
                      };
                      port = mkOption {
                        type = types.port;
                        default = intOr 51820 (config.dir + "/wireguard.port");
                        description = "port wireguard listens on";
                      };
                      subnets = mkOption {
                        type = types.listOf types.str;
                        default = linesOf (config.dir + "/wireguard.subnets");
                        description = "subnets routed to this host, defining AllowedIPs";
                      };
                    };
                  }));
                  default =
                    if pathExists (config.dir + "/wireguard.key")
                    then { dir = config.dir; }
                    else null;
                };
              };
            }));
          };
        };
      }));
    };

    users = mkOption {
      default = { };
      description = "people and service identities, keyed by username";
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          dir = dirOption;
          name = mkOption {
            type = types.str;
            default = name;
            description = "username; defaults to the directory name";
          };
          mail = mkOption {
            type = types.nullOr types.str;
            default = text (config.dir + "/mail");
            description = "mail address";
          };
          pubkey = mkOption {
            type = types.nullOr types.str;
            default = text (config.dir + "/ssh.pub");
            description = "the user's ssh key(s), e.g. for authorized_keys; may hold several, one per line";
          };
          pgp.pubkeys = mkOption {
            type = types.attrsOf types.str;
            default =
              if pathExists (config.dir + "/pgp")
              then
                lib.mapAttrs (role: _: readFile (config.dir + "/pgp/${role}"))
                  (filesIn (config.dir + "/pgp"))
              else { };
            description = "pgp public keys by role name (default, brain, ...)";
          };
        };
      }));
    };
  };

  # ---------------------------------------------------------------------
  # one module per namespace, mirroring the structure of the tree:
  # directory discovery happens here, file reads in the option defaults

  # apply f to every subdirectory of dir: f name path
  eachDir = dir: f:
    if pathExists dir
    then lib.mapAttrs (name: _: f name (dir + "/${name}")) (dirsIn dir)
    else { };

  namespaceModule = ns:
    let dir = ./. + "/${ns}"; in
    {
      _file = toString dir;

      hosts = eachDir (dir + "/hosts") (_host: hostDir: {
        dir = hostDir;
        owner = ns;
        nets = eachDir hostDir (_net: netDir: {
          dir = netDir;
        });
      });

      users = eachDir (dir + "/users") (_user: userDir: {
        dir = userDir;
      });
    };

  namespaces =
    lib.attrNames
      (lib.filterAttrs (name: _: !lib.hasPrefix "." name && name != "template")
        (dirsIn ./.));

  eval = lib.evalModules {
    modules = [ optionsModule ] ++ map namespaceModule namespaces;
  };

  # dir is an implementation detail; keep the output plain data
  public = record: removeAttrs record [ "dir" ];
  publicNet = net: public net // {
    tinc = lib.mapNullable public net.tinc;
    wireguard = lib.mapNullable public net.wireguard;
  };
in
{
  hosts = lib.mapAttrs
    (_: host: public host // { nets = lib.mapAttrs (_: publicNet) host.nets; })
    eval.config.hosts;
  users = lib.mapAttrs (_: public) eval.config.users;
}
