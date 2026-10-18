{
  description = "NixOS configuration with Noctalia";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bookokrat = {
      url = "github:bugzmanov/bookokrat";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pins its own nixpkgs on purpose: spicetify-cli must match the Spotify
    # version it patches, so don't make this follow ours.
    spicetify-nix.url = "github:Gerg-L/spicetify-nix";

  };

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # Every host gets the shared layers (./configuration.nix + ./home.nix) plus
  # its own hosts/<name>/ directory for hardware, hostname and whatever else is
  # true of that machine alone. Adding a machine is: create hosts/<name>/ and
  # add its name to the list in `nixosConfigurations` below.
  outputs = inputs@{ self, nixpkgs, home-manager, nixvim, caelestia-shell, ... }:
    let
      mkHost = hostName: nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs hostName; };
        modules = [
          ./configuration.nix
          ./hosts/${hostName}

          # Home Manager module
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs hostName; };
            home-manager.users.tklas = {
              imports = [
                ./home.nix
                ./hosts/${hostName}/home.nix
                nixvim.homeModules.nixvim
                caelestia-shell.homeManagerModules.default
                inputs.spicetify-nix.homeManagerModules.spicetify
              ];
            };
          }
        ];
      };
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs [ "laptop" "beast" ] mkHost // {
        # The laptop's hostname is still `nixos`, so this alias keeps the bare
        # `nixos-rebuild switch --flake ~/nixos` (which resolves the attribute
        # from the hostname) and the old `#nixos` working.
        nixos = self.nixosConfigurations.laptop;
      };
    };
}
