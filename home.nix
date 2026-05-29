{ config, pkgs, ... }:

{

  imports = [
    ./modules/nixvim.nix
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
    swww
    waybar
    hyprlock
    hyprshot
    rofi
    libnotify
    swaynotificationcenter
    hyprcursor

    # tools
    unrar
    git
    tree
    jq
    yq
    zip
    unzip
    brightnessctl
    btop
    evtest
    bluetuith
    wiremix
    usbutils
    pciutils
    yazi
    geeqie
    uv
    azure-cli
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
    opentofu
    zed-editor
    databricks-cli

    # apps
    _1password-gui
    google-chrome
    keepassxc
    spotify
    obs-studio
    whatsapp-electron
    moonlight-qt
    opencode
    obsidian
    vlc
    claude-code
    ani-cli
    openvpn
    transmission_4
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
