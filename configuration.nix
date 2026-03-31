{ config, pkgs, inputs, ... }:

{
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
  networking.hostName = "nixos"; # Define your hostname.

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
  ];

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
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
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.printing.enable = true;
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "suspend";
    HandleLidSwitchDocked = "ignore";
  };
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

  # services.tlp = {
  #   enable = true;
  #   settings = {
  #     # Battery charging threshold (e.g., 40-80%)
  #     START_CHARGE_THRESH_BAT0 = 40; 
  #     STOP_CHARGE_THRESH_BAT0 = 80;
  #   };
  # };

  system.stateVersion = "25.11";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

}
