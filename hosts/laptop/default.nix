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

  # The office printers. CUPS discovers both over DNS-SD on its own, but only
  # as *temporary* queues, which Chrome's print dialog does not list -- it asks
  # CUPS for permanent destinations and gets an empty set. Declaring them makes
  # them permanent queues; `model = "everywhere"` is driverless IPP, so no
  # vendor PPD or driver package is needed. `ensure-printers.service` runs
  # `lpadmin` at activation and talks to the printer, so a rebuild performed
  # off this network leaves that one unit failed and changes nothing else.
  hardware.printers.ensurePrinters = [
    {
      name = "Brother_MFC_J3960DW";
      description = "Brother MFC-J3960DW";
      location = "Datamole Back Office";
      deviceUri = "ipp://BRN94DDF8F07879.local:631/ipp/print";
      model = "everywhere";
    }
    {
      name = "Canon_MF750C";
      description = "Canon MF750C Series";
      location = "PRG-5-L";
      deviceUri = "ipp://Canon-5-L.local:631/ipp/print";
      model = "everywhere";
    }
  ];

  # Per-install fact: the NixOS release this machine was first installed with.
  # Never bump it to "upgrade" -- it only tells modules which backwards
  # compatibility to keep.
  system.stateVersion = "25.11";
}
