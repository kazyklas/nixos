{
  description = "NixOS configuration with Noctalia";

  # Flake inputs use the git+https:// fetcher rather than github: on purpose:
  # github: resolves refs via the GitHub REST API (api.github.com), which
  # Claude Code's cloud sandbox only authenticates for repos explicitly
  # attached to the session, so `nix flake update` 403s there for any
  # third-party repo. git+https:// resolves refs via plain `git ls-remote`
  # instead, which the sandbox's anonymous git proxy serves fine. Functionally
  # equivalent for public repos, just without GitHub's tarball shortcut.
  inputs = {
    # Flake inputs use git+https:// rather than the github: fetcher: the
    # latter resolves refs via the GitHub REST API, which Claude Code's cloud
    # sandbox only authenticates for repos explicitly attached to the
    # session, so it 403s on these third-party upstreams. git+https:// talks
    # plain git protocol instead, which the sandbox proxies for any public
    # repo. `shallow=1` keeps the clone to the pinned revision instead of
    # pulling each repo's full history (nixpkgs' alone is multiple GB).
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
      # caelestia-cli moved to hatch-vcs dynamic versioning upstream, which
      # can't determine a version from a tarball/non-git checkout and fails
      # to build (SETUPTOOLS_SCM_PRETEND_VERSION doesn't rescue it under
      # structuredAttrs). Pin to the last rev that still built successfully
      # until upstream fixes this.
      inputs.caelestia-cli.url = "git+https://github.com/caelestia-dots/cli?rev=6b84ee5090ec50f36aa1a53990d57ab0013925a0";
    };

    bookokrat = {
      url = "git+https://github.com/bugzmanov/bookokrat?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pins its own nixpkgs on purpose: spicetify-cli must match the Spotify
    # version it patches, so don't make this follow ours.
    spicetify-nix.url = "git+https://github.com/Gerg-L/spicetify-nix?shallow=1";

    # Hermes Agent (https://hermes-agent.nousresearch.com/), issue #12. Ships
    # its own Home Manager module (modules/hermes-agent.nix wires it up); Nix
    # support is upstream-labelled Tier 2 / best-effort, so pin it like the
    # other third-party flakes and bump deliberately via `nix flake update`.
    hermes-agent = {
      url = "git+https://github.com/NousResearch/hermes-agent?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      # hermes-agent's own flake.nix pins these five via the github: fetcher,
      # which -- per the comment at the top of this file -- 403s in Claude
      # Code's cloud sandbox for a repo not explicitly attached to the
      # session. Override each to git+https too, so a `nix flake update` run
      # from a cloud session (this repo's lockfile bumps come from one) does
      # not need every one of hermes-agent's own dependencies attached.
      #
      # Pinned to the exact revisions hermes-agent's own flake.lock already
      # resolved (rather than left floating) -- these are uv2nix/pyproject-nix
      # forks that must stay in lock-step with each other and with
      # hermes-agent's pyproject.toml; floating them independently risks a
      # version mismatch the upstream flake.lock was written to avoid. Bump
      # these revisions by hand (from hermes-agent's own flake.lock) when
      # `nix flake update hermes-agent` pulls a newer hermes-agent revision.
      inputs.flake-parts.url = "git+https://github.com/hercules-ci/flake-parts?rev=17c9d6cdfc60c64f4ee8d306f9bc0b4ccb51481e";
      inputs.pyproject-nix.url = "git+https://github.com/pyproject-nix/pyproject.nix?rev=e3b599ca2e7fcf93d4edf65d7f19bbf6491724f3";
      inputs.uv2nix.url = "git+https://github.com/pyproject-nix/uv2nix?rev=7aba73a3d85454f1118f8cf9de97979b4d26bcac";
      inputs.pyproject-build-systems.url = "git+https://github.com/pyproject-nix/build-system-pkgs?rev=62c0d86027edb1c4f39a5facc09876348144f7c9";
      inputs.npm-lockfile-fix.url = "git+https://github.com/jeslie0/npm-lockfile-fix?rev=c6093acb0c0548e0f9b8b3d82918823721930fe8";
      # Only used by hermes-agent's own checks (evaluating its Home Manager
      # module against the real module system); follow ours instead of
      # fetching a second copy.
      inputs.home-manager.follows = "home-manager";
    };

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
                inputs.hermes-agent.homeManagerModules.default
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
