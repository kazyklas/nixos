# Shared system configuration: everything that is true of every machine in this
# flake. Hardware, hostname, stateVersion and the rest of the machine-specific
# facts live in hosts/<name>/ instead.
{ config, pkgs, inputs, ... }:

{
  nixpkgs.config.permittedInsecurePackages = [
    "python3.14-ecdsa-0.19.2"
    "beekeeper-studio-6.0.5"
  ];

  environment.sessionVariables = {
	  NIXOS_OZONE_WL = "1";
	  MOZ_ENABLE_WAYLAND = "1";
  	MOZ_WEBRENDER = "0";
  };

  environment.variables = {
	  EDITOR = "vim";
  };

  # noctalia features
  hardware.bluetooth.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable networking
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;

  # Set your time zone.
  time.timeZone = "Europe/Prague";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "cs_CZ.UTF-8";
    LC_IDENTIFICATION = "cs_CZ.UTF-8";
    LC_MEASUREMENT = "cs_CZ.UTF-8";
    LC_MONETARY = "cs_CZ.UTF-8";
    LC_NAME = "cs_CZ.UTF-8";
    LC_NUMERIC = "cs_CZ.UTF-8";
    LC_PAPER = "cs_CZ.UTF-8";
    LC_TELEPHONE = "cs_CZ.UTF-8";
    LC_TIME = "cs_CZ.UTF-8";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.hack

    # General-purpose coverage. Without these, scripts like Thai, Devanagari,
    # Arabic, Hebrew and Georgian resolve only to the Unifont bitmap fallback,
    # which renders as tofu/blocky glyphs -- most visibly in Steam, whose
    # bundled fontconfig is too old to parse 10-scale-bitmap-fonts.conf and so
    # cannot scale bitmap fonts at all. programs.steam.fontPackages defaults to
    # config.fonts.packages, so adding them here covers Steam too.
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    liberation_ttf
  ];

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  services.ollama = {
    enable = false;
    port = 11434;
    host = "0.0.0.0";
  };
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.hyprland = {
	  enable = true;
	  xwayland.enable = true;
  };

  programs.zsh.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.tklas = {
    isNormalUser = true;
    description = "tklas";
    extraGroups = [ "networkmanager" "wheel" "podman" ];
    shell = pkgs.zsh;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = let
    zen-browser = pkgs.appimageTools.wrapType2 rec {
      pname = "zen-browser";
      version = "1.19.5b";
      src = pkgs.fetchurl {
        url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen-x86_64.AppImage";
        sha256 = "6128deeaed009a114769148e498ea27cf521c1af6649dd1d3766953bb0dccd0e";
      };
      meta = {
        description = "Zen Browser is a Firefox-based browser focused on privacy and aesthetics";
        homepage = "https://zen-browser.app";
        license = pkgs.lib.licenses.mpl20;
        platforms = [ "x86_64-linux" ];
      };
    };
  in with pkgs; [
	  # vim
	  git
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    tailscale
    zen-browser
  ];

  programs.steam = {
    enable = true;
  };
  programs.appimage.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
 
  # enable uv to run
  programs.nix-ld.enable = true;


  environment.localBinInPath = true;

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true; # Required for containers under podman-compose to be able to talk to each other.
    };
  };

  # List services that you want to enable:
  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.tailscale.enable = true;
  services.printing.enable = true;
  # Enable the X11 windowing system.
  services.xserver.enable = true;
  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us, cz";
    variant = "";
  };

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

}
