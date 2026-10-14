{ config, ... }:

let
  # The plugin is developed in-tree, so link the working copy rather than a
  # store copy: Noctalia hot-reloads .luau files on save, which it cannot do
  # through an immutable /nix/store path (that would need a rebuild + reload
  # for every edit).
  pluginDir = "${config.home.homeDirectory}/nixos/modules/noctalia-plugins/claude_chat";
in
{
  # ~/.local/share/noctalia/plugins is Noctalia's built-in "local" plugin
  # source and outranks every configured source, so nothing else needs
  # registering. The plugin still has to be enabled once:
  #   noctalia msg plugins enable tklas/claude_chat
  # (or Settings -> Plugins -> toggle "Claude Chat").
  xdg.dataFile."noctalia/plugins/claude_chat".source =
    config.lib.file.mkOutOfStoreSymlink pluginDir;
}
