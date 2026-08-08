{
  description = "r3dg0d's NixOS workstation — niri + COSMIC, SDDM/ascii-city, the SIVA voice stack";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Animated 3D fetch tool — https://github.com/areofyl/fetch
    # Its overlay exposes pkgs.areofyl-fetch.
    fetch = {
      url = "github:areofyl/fetch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TUI-only web browser, developed locally in ~/Projects/tuiweb.
    # Its overlay exposes pkgs.tuiweb.
    #
    # PORTABILITY: this is the one input that is not fetchable from the
    # network. `install.sh` checks for the checkout up front and tells you what
    # to do if it is missing, rather than letting nix fail deep into an eval.
    # After committing changes over there, run `nix flake update tuiweb` here
    # before rebuilding to pick them up.
    tuiweb = {
      url = "git+file:///home/r3dg0d/Projects/tuiweb";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, fetch, tuiweb, ... }:
    let
      # Every system this flake's *packages* are built for. The NixOS hosts
      # below pin their own.
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      overlays = [
        fetch.overlays.default
        tuiweb.overlays.default
        (import ./pkgs)
      ];

      pkgsFor = system: import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };

      # One entry per machine. `install.sh` reads these names to offer a host
      # choice, so adding a machine here is all it takes to make it installable.
      hosts = {
        nixos-btw = {
          system = "x86_64-linux";
          user = "r3dg0d";
        };
      };

      mkHost = name: { system, user }: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/${name}
          { nixpkgs.overlays = overlays; }
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} = import ./modules/home;
              backupFileExtension = "backup";
            };
          }
        ];
      };
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs mkHost hosts;

      # The packages this repo defines, buildable on their own:
      #   nix build .#sddm-ascii-city
      #   nix build .#siva
      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          inherit (pkgs)
            sddm-ascii-city
            siva
            siva-type
            siva-voicefetch
            siva-fetch-assets
            quickshell-mirror
            hydralauncher-wayland
            mingw32-cc;
        });

      # `nix flake check` evaluates *and builds* every host, which is the only
      # check that actually proves the configuration is sound.
      checks = forAllSystems (system:
        nixpkgs.lib.mapAttrs'
          (name: _host: {
            name = "nixos-${name}";
            value = self.nixosConfigurations.${name}.config.system.build.toplevel;
          })
          (nixpkgs.lib.filterAttrs (_: h: h.system == system) hosts));

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);

      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [ nixpkgs-fmt nil shellcheck ];
          };
        });
    };
}
