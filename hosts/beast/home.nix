# Home Manager bits that are true of beast alone. The shared user config is
# ../../home.nix -- packages, zsh, git, nixvim, Hyprland, Claude Code and the
# rest all come from there, so this file stays small on purpose.
{ ... }:

{
  # No layouts declared yet, which means ../../modules/hyprland.nix emits no
  # `monitor` entries and Hyprland auto-configures whatever it finds (preferred
  # mode, auto position). Fill this in after the first boot, when the real
  # output names are known:
  #
  #   hyprctl monitors | grep -E '^Monitor|availableModes' | head
  #
  # then uncomment the shape below. `monitor-profile list` and the rofi picker
  # (SUPER + SHIFT + M) pick these up automatically; `quickProfiles` is what
  # gets SUPER + ALT + 1..n, and `defaultProfile` is the layout compiled into
  # the config for a fresh install.
  my.hyprland = {
    monitorProfiles = { };

    # defaultProfile = "desk";
    # quickProfiles = [ "desk" "solo" ];
    # monitorProfiles = {
    #   desk = {
    #     description = "Both screens";
    #     monitors = [
    #       { output = "DP-1"; mode = "preferred"; position = "0x0"; scale = 1; }
    #       { output = "HDMI-A-1"; mode = "preferred"; position = "auto"; scale = 1; }
    #     ];
    #   };
    #
    #   solo = {
    #     description = "Main screen only";
    #     monitors = [
    #       { output = "DP-1"; mode = "preferred"; position = "0x0"; scale = 1; }
    #     ];
    #   };
    # };
  };
}
