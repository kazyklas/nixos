{
  description = "NixOS configuration with Noctalia";

  # Flake inputs use the git+https:// fetcher rather than github: on purpose:
  # github: resolves refs via the GitHub REST API (api.github.com), which
  # Claude Code's cloud sandbox only authenticates for repos explicitly
  # attached to the session, so `nix flake update` 403s there for any
  # third-party repo. git+https:// resolves refs via plain `git ls-remote`
  # instead, which the sandbox's anonymous git proxy serves fine. Functionally
  # equivalent for public repos, just without GitHub's tarball shortcut.
  # `shallow=1` keeps it that way: without it, git+https:// clones each repo's
  # *entire* history (multiple GB for nixpkgs) instead of just the pinned rev.
  inputs = {
    nixpkgs.url = "git+https://github.com/nixos/nixpkgs?ref=nixos-unstable&shallow=1";

    noctalia = {
      url = "git+https://github.com/noctalia-dev/noctalia-shell?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "git+https://github.com/nix-community/home-manager?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "git+https://github.com/nix-community/nixvim?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-shell = {
      url = "git+https://github.com/caelestia-dots/shell?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bookokrat = {
      url = "git+https://github.com/bugzmanov/bookokrat?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pins its own nixpkgs on purpose: spicetify-cli must match the Spotify
    # version it patches, so don't make this follow ours.
    spicetify-nix.url = "git+https://github.com/Gerg-L/spicetify-nix?shallow=1";

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
