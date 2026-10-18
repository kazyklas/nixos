# PLACEHOLDER -- not beast's real hardware.
#
# A NixOS configuration will not evaluate without a root filesystem, so this
# stub exists purely so `nix eval .#nixosConfigurations.beast` works before the
# machine is installed. Replace the whole file with the output of
# `nixos-generate-config --root /mnt` run on beast itself (see README).
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Printed by every build of #beast until this file is replaced.
  warnings = [
    "hosts/beast/hardware-configuration.nix is still the placeholder -- run nixos-generate-config on beast and replace it."
  ];

  boot.initrd.availableKernelModules = [ ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/PLACEHOLDER-ROOT";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/PLACEHOLDER-BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
