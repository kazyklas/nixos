{ config, pkgs, inputs, ... }:

{

  imports = [
    ./modules/nixvim.nix
    ./modules/hyprland.nix
  ];

  home.username = "tklas";
  home.homeDirectory = "/home/tklas";

  home.stateVersion = "25.11";

  # Move your user packages here 👇
  home.packages = with pkgs; [
    # terminals
    kitty
    foot
    zsh-autosuggestions
    zsh-syntax-highlighting

    # hyprland ecosystem
    awww
    waybar
    hyprlock
    hyprshot
    rofi
    libnotify
    swaynotificationcenter
    hyprcursor

    # tools
    shell-gpt
    unrar
    git
    tree
    jq
    yq
    zip
    unzip
    brightnessctl
    btop
    htop
    evtest
    bluetuith
    wiremix
    usbutils
    pciutils
    yazi
    geeqie
    git-lfs
    uv
    azure-cli
    awscli2
    saml2aws
    gh
    ripgrep
    kubernetes-helm
    k9s
    ffmpeg
    bat
    jiratui
    jira-cli-go
    eza
    g-ls
    kubeseal
    openssl
    bc

    # dev
    lens
    kubectl
    argocd
    opentofu
    zed-editor
    vscode
    databricks-cli
    pre-commit
    terraform-docs
    tflint
    jdk17
    (maven.override { jdk_headless = jdk17_headless; })
    checkov


    # apps
    _1password-gui
    google-chrome
    keepassxc
    # spotify: installed by programs.spicetify below (patched build)
    obs-studio
    whatsapp-electron
    moonlight-qt
    # nixpkgs' source build of opencode 1.18.30 is broken (every prompt fails with
    # "Failed to send prompt"); use the upstream prebuilt binary instead.
    (pkgs.callPackage ./pkgs/opencode-bin.nix { })
    opencode-desktop
    obsidian
    vlc
    inputs.bookokrat.packages.${pkgs.stdenv.hostPlatform.system}.default
    claude-code
    gemini-cli
    ani-cli
    openvpn
    transmission_4
    teams-for-linux
    beekeeper-studio
    gimp2
  ];

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Tomas Klas";
        email = "tomas.klas@datamole.cz";
      };
    };
  };

  # Example shell (optional)
  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
      ];
      theme = "robbyrussell";
    };
    history.size = 100000;
    history.ignoreAllDups = true;
    history.path = "$HOME/.zsh_history";

    shellAliases = {
      bat = "bat --color=auto --decorations=auto";
      g = "g";
      ll = "g --tb-style=unicode --all --color always --header --git-repo-status";
      ls = "g --tb-style=unicode";
    };

    initContent = ''
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    '';
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
    ];
  };

  programs.kitty.enable = true;

  # Spicetify-patched Spotify. The "text" theme is a port of the spotify-tui
  # look; its knobs are CSS variables in user.css, which additionalCss appends
  # to (so a later :root block wins the cascade without !important).
  programs.spicetify =
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      enable = true;
      theme = spicePkgs.themes.text // {
        additionalCss = ''
          :root {
            /* The nerd-fonts variant registers under its own family name, so
               ask for it first and keep the upstream name as a fallback. */
            --font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;
            --border-radius: 0px;
            --display-coverart-image: none;
            --display-music-banner-ascii: block;
          }
        '';
      };
      colorScheme = "TokyoNight";

      enabledExtensions = with spicePkgs.extensions; [
        adblockify
        hidePodcasts
        shuffle
        fullAppDisplayMod
        volumePercentage
      ];

      enabledCustomApps = with spicePkgs.apps; [
        marketplace
        lyricsPlus
      ];
    };

  programs.caelestia = {
    enable = true;
    systemd.enable = false;
    cli.enable = true;
    settings = {
      paths.wallpaperDir = "~/Pictures/Wallpaper";
      bar = {
        persistent = false;
      };
    };
  };
}
