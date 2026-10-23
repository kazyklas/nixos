{ ... }:

{
  # Hermes Agent (https://github.com/NousResearch/hermes-agent), wired in via
  # its own homeManagerModules.default (imported in flake.nix next to
  # caelestia-shell and spicetify, since it's a flake output rather than
  # something importable from a plain module path).
  #
  # Just the CLI for now: programs.hermes-agent only installs `hermes` and
  # HERMES_HOME. The messaging gateway/backend (services.hermes-agent) stays
  # off until there's a reason to run it as an always-on systemd user service.
  programs.hermes-agent = {
    enable = true;
  };
}
