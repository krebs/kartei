{ lib, config, ... }:
let
  hostData = import ./hosts.nix { inherit lib; };
  slib = import ../../lib { inherit lib; };
  cfg = config.networking.retiolum;
in
{
  options.networking.retiolum = {
    nodename = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "tinc node name of this machine inside retiolum.";
    };
    ipv4 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = hostData.own.${cfg.nodename}.ip4 or null;
      defaultText = "looked up in kartei by nodename";
      description = "Own retiolum IPv4 address.";
    };
    ipv6 = lib.mkOption {
      type = lib.types.str;
      default =
        hostData.own.${cfg.nodename}.ip6 or (slib.krebs.genipv6 "retiolum" "external" {
          hostName = cfg.nodename;
        }).address;
      defaultText = "looked up in kartei by nodename, otherwise derived from it";
      description = "Own retiolum IPv6 address.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 655;
      description = "TCP/UDP port tincd listens on.";
    };
    ed25519PrivateKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "${config.krebs.secret.directory or "/var/src/secrets"}/tinc.retiolum.ed25519_key.priv";
      defaultText = "/var/src/secrets/tinc.retiolum.ed25519_key.priv";
      description = "Path to this node's Ed25519 private key.";
    };
    extraHosts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to add all retiolum peers to /etc/hosts.  The tincr
        DNS stub already answers ‹node.r› queries via resolved, but
        static entries keep name resolution working before the daemon
        is up (e.g. during nixos-rebuild over the mesh).
      '';
    };
  };

  config._module.args.retiolumHostData = hostData;
}
