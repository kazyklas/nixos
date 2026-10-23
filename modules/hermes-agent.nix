{ ... }:

{
  # Hermes Agent (https://github.com/NousResearch/hermes-agent), wired in via
  # its own homeManagerModules.default (imported in flake.nix next to
  # caelestia-shell and spicetify, since it's a flake output rather than
  # something importable from a plain module path).
  #
  # CLI + desktop: programs.hermes-agent installs `hermes` and HERMES_HOME,
  # and desktop.enable adds the Electron `hermes-desktop` with an XDG launcher,
  # pointed at the same nix-built runtime (no second copy, no first-run
  # download). The messaging gateway/backend (services.hermes-agent) stays
  # off until there's a reason to run it as an always-on systemd user service.
  programs.hermes-agent = {
    enable = true;
    desktop.enable = true;
  };
}
