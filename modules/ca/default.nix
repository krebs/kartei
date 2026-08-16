{ config, lib, ... }:
let
  cfg = config.retiolum.ca;
in
{
  options.retiolum.ca = {
    rootCA = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = builtins.readFile ./root-ca.crt;
      defaultText = "root-ca.crt";
    };
    intermediateCA = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = builtins.readFile ./intermediate-ca.crt;
      defaultText = "intermediate-ca.crt";
    };
    acmeURL = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://ca.r/acme/acme/directory";
    };
    trustRoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Trust the krebs root CA system-wide.  This lets krebs mint a
        certificate for any domain, so leave it off unless you know
        why you need it.
      '';
    };
    trustIntermediate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Trust the krebs ACME intermediate.  It is name-constrained to
        .r and .w, so enabling it does not affect the public web.
      '';
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.trustRoot { security.pki.certificates = [ cfg.rootCA ]; })
    (lib.mkIf cfg.trustIntermediate { security.pki.certificates = [ cfg.intermediateCA ]; })
  ];
}
