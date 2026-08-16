# Non-flake entry point.  The flake wraps ./nixos.nix to also pull in
# tincr's services.tincr module and package; without flakes, fetch
# tincr (and its crane dep) from the pins in flake.lock so
# `imports = [ <kartei/modules/retiolum> ]` is self-contained.
{ lib, pkgs, ... }:
let
  fetchLocked =
    lock:
    builtins.fetchTarball {
      url = "https://github.com/${lock.owner}/${lock.repo}/archive/${lock.rev}.tar.gz";
      sha256 = lock.narHash;
    };
  tincr = fetchLocked (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes.tincr.locked;
  crane = fetchLocked (builtins.fromJSON (builtins.readFile "${tincr}/flake.lock")).nodes.crane.locked;
in
{
  imports = [
    ./nixos.nix
    "${tincr}/nix/module.nix"
  ];

  services.tincr.package = lib.mkDefault (pkgs.callPackage "${tincr}/nix/tincd.nix" {
    craneLib = import crane { inherit pkgs; };
  });
}
