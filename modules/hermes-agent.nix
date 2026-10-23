# Hermes Agent (https://hermes-agent.nousresearch.com/) -- Nous Research's
# open-source agent CLI/desktop app, requested in issue #12. The flake module
# itself comes from the `hermes-agent` input and is imported in flake.nix
# (alongside nixvim/caelestia-shell/spicetify-nix); this file only sets the
# options it exposes.
#
# Only `programs.hermes-agent` is enabled here: the `hermes` CLI on PATH, and
# the Electron desktop app. `services.hermes-agent` -- the always-on
# gateway/backend that connects to Telegram/Discord/Slack/etc and needs a
# model-provider API key -- stays off on purpose. That key must never go
# through `settings`/`environment`, since both land in the world-readable
# /nix/store; the module instead wants a runtime `environmentFiles` path
# outside the store (sops-nix/agenix, or just a hand-created file), and this
# repo has neither set up. Until that exists, run `hermes setup`
# interactively -- unmanaged here, so it writes its own config/auth under
# ~/.hermes exactly like a non-Nix install.
#
# To turn on the always-on gateway later:
#   services.hermes-agent = {
#     enable = true;
#     settings.model.default = "<provider>/<model>";
#     environmentFiles = [ "/home/tklas/.config/hermes-agent/env" ]; # create by hand, chmod 600
#   };
# and add `users.users.tklas.linger = true;` in configuration.nix, or the
# systemd user unit stops at logout (Home Manager can't enable linger itself).
{ ... }:

{
  programs.hermes-agent = {
    enable = true;
    desktop.enable = true;
  };
}
