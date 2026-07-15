{ config, lib, ... }: let
  slib = import ../lib { inherit lib; };
in {
  users.DUMMYUSER = {
    mail = "DUMMYUSER@example.ork";
  };
  hosts.DUMMYHOST = {
    owner = config.krebs.users.DUMMYUSER;
    nets.retiolum = {
      aliases = [ "DUMMYHOST.DUMMYUSER.r" ];
      ip6.addr = (slib.krebs.genipv6 "retiolum" "DUMMYUSER" { hostName = "DUMMYHOST"; }).address;
      tinc.pubkey_ed25519 = "DUMMYTINCPUBKEYED25519";
    };
  };
}
