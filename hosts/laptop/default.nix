# The laptop: Intel, encrypted root, battery and a lid.
#
# Shared with every other host through ../../configuration.nix; only what is
# true of *this* machine lives here.
{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/laptop.nix # battery, lid, suspend, power profiles
  ];

  # Deliberately not "laptop": this machine is known as `nixos` to Tailscale,
  # SSH known_hosts and everything else on the network. The *flake attribute*
  # is what is named `laptop` (`nixos-rebuild switch --flake ~/nixos#laptop`);
  # the hostname is a separate string, and this is the only line that sets it.
  networking.hostName = "nixos";

  # Per-install fact: the NixOS release this machine was first installed with.
  # Never bump it to "upgrade" -- it only tells modules which backwards
  # compatibility to keep.
  system.stateVersion = "25.11";
}
