{ config, pkgs, inputs, ... }:

{

  imports = [
    ./modules/nixvim.nix
    ./modules/hyprland.nix
    ./modules/noctalia-claude-chat.nix
    ./modules/claude-code.nix
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
    # Future Cyan: the theme my.hyprland (modules/hyprland.nix) points
    # HYPRCURSOR_THEME at. Not in nixpkgs, so it's vendored (pkgs/future-cyan-hyprcursor.nix).
    (pkgs.callPackage ./pkgs/future-cyan-hyprcursor.nix { })

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

    # PDF skill runtime (modules/claude/skills/pdf). The Python libraries it
    # needs are resolved per-invocation by uv, so only the command-line tools
    # have to exist in the profile.
    poppler-utils # pdftotext, pdfimages, pdftoppm
    qpdf
    tesseract # OCR for scanned PDFs

    # aks-troubleshooting skill: host-side DNS checks (dig, nslookup). az,
    # kubectl and jq it also needs are already above.
    dnsutils

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
    # bookokrat's SVG snapshot tests are pixel-exact against font rendering;
    # a few more started failing after the nixpkgs bump (font/freetype
    # rendering drift), joining the ones upstream already skips for the same
    # flakiness reason. Skip those too rather than fail the whole build.
    (inputs.bookokrat.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      checkFlags = (old.checkFlags or [ ]) ++ [
        "--skip=test_content_view_svg"
        "--skip=test_keybinding_errors_popup_svg"
        "--skip=test_toc_back_to_books_list_svg"
      ];
    }))
    # claude-code: installed by programs.claude-code (modules/claude-code.nix)
    gemini-cli
    ani-cli
    openvpn
    transmission_4
    teams-for-linux
    beekeeper-studio
    gimp
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
