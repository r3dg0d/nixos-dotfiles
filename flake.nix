{
    description = "NixOS from Scratch";
    inputs = {
        nixpkgs.url = "nixpkgs/nixos-26.05";
        home-manager = {
            url = "github:nix-community/home-manager/release-26.05";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        # Animated 3D fetch tool — https://github.com/areofyl/fetch
        # Its overlay exposes pkgs.areofyl-fetch (used in configuration.nix).
        fetch = {
            url = "github:areofyl/fetch";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        # TUI-only web browser, developed locally in ~/Projects/tuiweb.
        # Its overlay exposes pkgs.tuiweb (used in configuration.nix).
        # This tracks the repo's committed HEAD; after committing changes there,
        # run `nix flake update tuiweb` before rebuilding to pick them up.
        # If the directory ever moves, update this URL or the rebuild will fail.
        tuiweb = {
            url = "git+file:///home/r3dg0d/Projects/tuiweb";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = { self, nixpkgs, home-manager, fetch, tuiweb, ... }: {
        nixosConfigurations.nixos-btw = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
                ./configuration.nix
                { nixpkgs.overlays = [ fetch.overlays.default tuiweb.overlays.default ]; }
                home-manager.nixosModules.home-manager
                {
                    home-manager = {
                        useGlobalPkgs = true;
                        useUserPackages = true;
                        users.r3dg0d = import ./home.nix;
                        backupFileExtension = "backup";
                    };
                }
            ];
        };
    };
}
