{
  config,
  lib,
  pkgs,
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
      openFirewall = true;
      ed25519PrivateKeyFile = cfg.ed25519PrivateKeyFile;
      hosts = retiolumHostData.tincHosts;
      connectTo = [
        "eve"
        "eva"
        "ni"
        "prism"
      ];
      # See retiolum incident 2d2ab95f0: MST broadcast loops during
      # edge churn amplified SSDP/IGMP into a mesh-wide packet storm.
      extraConfig = ''
        LocalDiscovery = yes
        Broadcast = no
      '';
      addresses = lib.optional (cfg.ipv4 != null) "${cfg.ipv4}/12" ++ [ "${cfg.ipv6}/16" ];
      interfaceName = "tinc.retiolum";
      dns = {
        enable = true;
        suffix = "r";
        address4 = "10.243.0.53";
        address6 = "42::53";
      };
    };

    # Measured with `ping -6 -s 1378` across the mesh; pin it so
    # PMTU blackholes over double-NAT relays don't stall TCP.
    systemd.network.networks."40-tincr-retiolum".linkConfig.MTUBytes = "1377";

    networking.extraHosts = lib.mkIf cfg.extraHosts (
      if cfg.ipv4 == null then retiolumHostData.extraHosts.v6only else retiolumHostData.extraHosts.v4v6
    );

    environment.systemPackages = [
      config.services.tincr.networks.retiolum.package
    ];

    # Replace real directories left behind by the old services.tinc module
    # (setup-etc won't) and relink hosts to the current generation.
    # "+" runs as root since /etc/tinc is root-owned and tincd is not.
    systemd.services.tincr-retiolum.serviceConfig.ExecStartPre = lib.mkBefore [
      "+${pkgs.writeShellScript "tincr-retiolum-migrate" ''
        for name in hosts invitations; do
          d=/etc/tinc/retiolum/$name
          if [ -d "$d" ] && [ ! -L "$d" ]; then
            rm -rf "$d"
          fi
        done
        ln -sfn ${config.environment.etc."tinc/retiolum/hosts".source} /etc/tinc/retiolum/hosts
      ''}"
    ];
  };
}
