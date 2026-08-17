{
  description = "kartei - krebs host and user key material";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    tincr = {
      url = "github:Mic92/tincr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, tincr }:
    let
      # All loading logic lives in ./default.nix, which also works
      # without flakes: import <kartei> { inherit lib; }
      data = import ./. { inherit (nixpkgs) lib; };
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      inherit (data) hosts users;

      lib = forAllSystems (system:
        import ./lib { inherit (nixpkgs.legacyPackages.${system}) lib; });

      nixosModules = {
        retiolum = {
          imports = [
            tincr.nixosModules.tincr
            ./modules/retiolum/nixos.nix
          ];
        };
        ca = ./modules/ca;
      };

      darwinModules = {
        tincr = ./modules/tincr/darwin.nix;
        retiolum = { pkgs, ... }: {
          imports = [
            ./modules/tincr/darwin.nix
            ./modules/retiolum/darwin.nix
          ];
          services.tincr.package = nixpkgs.lib.mkDefault
            tincr.packages.${pkgs.stdenv.hostPlatform.system}.tincd;
        };
        ca = ./modules/ca;
      };

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.gum
              tincr.packages.${system}.tincd # sptps_keypair
            ];
          };
        });

      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        import ./packages.nix { inherit (pkgs) lib runCommand writeText; } // {
          # wizards: nix run .#add-host / .#remove-host
          add-host = pkgs.writeShellApplication {
            name = "add-host";
            runtimeInputs = [
              pkgs.gum
              pkgs.git
              tincr.packages.${system}.tincd # sptps_keypair
            ];
            text = builtins.readFile ./scripts/add-host;
          };
          remove-host = pkgs.writeShellApplication {
            name = "remove-host";
            runtimeInputs = [
              pkgs.gum
              pkgs.git
            ];
            text = builtins.readFile ./scripts/remove-host;
          };
        });

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lintErrors = import ./checks/lint.nix {
            inherit (nixpkgs) lib;
            root = ./.;
            inherit (data) hosts users;
          };
        in
        {
          eval = pkgs.runCommand "kartei-eval" { } ''
            ${builtins.deepSeq data "true"}
            touch $out
          '';
          lint =
            if lintErrors == [ ]
            then pkgs.runCommand "kartei-lint" { } "touch $out"
            else throw "kartei lint failed:\n${nixpkgs.lib.concatStringsSep "\n" lintErrors}";
        });

      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.retiolum
          self.nixosModules.ca
          {
            boot.loader.grub.enable = false;
            fileSystems."/" = { device = "tmpfs"; fsType = "tmpfs"; };
            networking.hostName = "example";
            networking.retiolum = {
              nodename = "hotdog";
              ed25519PrivateKeyFile = "/var/src/secrets/tinc.retiolum.ed25519_key.priv";
            };
            system.stateVersion = "24.05";
          }
        ];
      };
    };
}
