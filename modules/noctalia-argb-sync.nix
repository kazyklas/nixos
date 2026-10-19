{ config, ... }:

let
  # Same reasoning as modules/noctalia-claude-chat.nix: link the in-tree
  # working copy instead of a store path, so editing a .luau file here
  # hot-reloads in the running shell instead of needing a rebuild.
  pluginDir = "${config.home.homeDirectory}/nixos/modules/noctalia-plugins/argb_sync";
in
{
  # Enable once with:
  #   noctalia msg plugins enable tklas/argb_sync
  # (or Settings -> Plugins -> toggle "ARGB Sync").
  xdg.dataFile."noctalia/plugins/argb_sync".source =
    config.lib.file.mkOutOfStoreSymlink pluginDir;
}
