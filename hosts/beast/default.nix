# beast: the desktop. Everything shared with the laptop comes from
# ../../configuration.nix; this file is only for what is true of this box.
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "beast";

  # Per-install fact: set this to the NixOS release you actually install beast
  # from, then leave it alone. It is not a version to keep current.
  system.stateVersion = "25.11";

  # ---------- NVIDIA ----------
  # Uncomment once beast exists. Hyprland is a Wayland compositor, so
  # modesetting is not optional -- without it the session starts on llvmpipe or
  # not at all. `open = true` is the open-kernel-module flavour, correct for
  # Turing (RTX 20xx) and newer; set it to false for anything older.
  #
  # services.xserver.videoDrivers = [ "nvidia" ];
  # hardware.nvidia = {
  #   modesetting.enable = true;
  #   open = true;
  #   nvidiaSettings = true;
  #   package = config.boot.kernelPackages.nvidiaPackages.stable;
  #   powerManagement.enable = false; # desktop: no suspend/resume VRAM dance
  # };
  #
  # The shared config already sets hardware.graphics.enable{,32Bit} (Steam) and
  # boot.kernelPackages = linuxPackages_latest. If the NVIDIA module lags the
  # latest kernel, pin one here:
  # boot.kernelPackages = pkgs.linuxPackages;

  # ---------- local LLMs ----------
  # The shared config declares services.ollama with enable = false, because the
  # laptop has nothing to run it on. beast presumably does:
  # services.ollama.enable = true;
  # services.ollama.acceleration = "cuda";
}
