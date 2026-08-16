{
  config,
  lib,
  retiolumHostData,
  ...
}:
let
  cfg = config.networking.retiolum;
in
{
  imports = [ ./common.nix ];

  config = {
    services.tincr.networks.retiolum = {
      nodeName = cfg.nodename;
      listenPort = cfg.port;
      ed25519PrivateKeyFile = cfg.ed25519PrivateKeyFile;
      hosts = retiolumHostData.tincHosts;
      connectTo = [
        "eve"
        "eva"
        "ni"
        "prism"
      ];
      extraConfig = ''
        LocalDiscovery = yes
        Broadcast = no
      '';
      addresses = lib.optional (cfg.ipv4 != null) "${cfg.ipv4}/12" ++ [ "${cfg.ipv6}/16" ];
    };

    # No resolved on Darwin, so the tincr DNS stub cannot be routed
    # per-suffix; fall back to a static hosts block managed with
    # BEGIN/END markers so darwin-rebuild can update it in place.
    system.activationScripts.postActivation.text = lib.mkIf cfg.extraHosts (
      let
        hostsFile =
          if cfg.ipv4 == null then retiolumHostData.extraHosts.v6only else retiolumHostData.extraHosts.v4v6;
      in
      lib.mkAfter ''
        tmp=$(mktemp /private/etc/hosts.XXXXXX)
        chmod 644 "$tmp"
        awk '
          /^# BEGIN RETIOLUM HOSTS$/ { skip=1; next }
          /^# END RETIOLUM HOSTS$/   { skip=0; next }
          !skip { print }
        ' /private/etc/hosts > "$tmp"
        {
          echo "# BEGIN RETIOLUM HOSTS"
          cat ${builtins.toFile "retiolum-hosts" hostsFile}
          echo "# END RETIOLUM HOSTS"
        } >> "$tmp"
        mv "$tmp" /private/etc/hosts
      ''
    );
  };
}
