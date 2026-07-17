{
  description = "kartei - krebs host and user key material";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      # All loading logic lives in ./default.nix, which also works
      # without flakes: import <kartei> { inherit lib; }
      data = import ./. { inherit (nixpkgs) lib; };
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      inherit (data) hosts users;

      checks = nixpkgs.lib.genAttrs systems (system: {
        eval = nixpkgs.legacyPackages.${system}.runCommand "kartei-eval" { } ''
          ${builtins.deepSeq data "true"}
          touch $out
        '';
      });
    };
}
