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
    quickshell
    hyprcursor

    # tools
    git
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

    # dev
    lens
    kubectl
    opentofu
    zed-editor

    # apps
    _1password-gui
    google-chrome
    keepassxc
    spotify
    obs-studio
    whatsapp-electron
    ani-cli
    moonlight-qt
    opencode
    obsidian
    vlc
    claude-code
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
}
