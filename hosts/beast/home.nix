# Home Manager bits that are true of beast alone. The shared user config is
# ../../home.nix -- packages, zsh, git, nixvim, Hyprland, Claude Code and the
# rest all come from there, so this file stays small on purpose.
{ ... }:

{
  # Xiaomi Mi Monitor (2560x1440, DP-3) on the left, Dell P2725HE (1920x1080,
  # DP-2) on the right, both at their highest available refresh rate. Found
  # via:
  #
  #   hyprctl monitors | grep -E '^Monitor|availableModes' | head
  my.hyprland = {
    defaultProfile = "desk";
    quickProfiles = [ "desk" ];

    monitorProfiles = {
      desk = {
        description = "Xiaomi (left) + Dell (right)";
        monitors = [
          { output = "DP-3"; mode = "2560x1440@165.00Hz"; position = "0x0"; scale = 1; }
          { output = "DP-2"; mode = "1920x1080@100.00Hz"; position = "2560x0"; scale = 1; }
        ];
      };
    };
  };
}
