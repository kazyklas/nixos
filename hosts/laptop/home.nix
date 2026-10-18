# Home Manager bits that are true of the laptop alone. The shared user config
# is ../../home.nix.
{ ... }:

{
  # The desks this machine gets carried between. `monitor-profile` (see
  # ../../modules/hyprland.nix) switches between them at runtime:
  #   SUPER + SHIFT + M    rofi picker (every profile below)
  #   SUPER + ALT + 1/2/3  the three in `quickProfiles`, in order
  my.hyprland = {
    defaultProfile = "work";
    quickProfiles = [ "work" "home" "solo" ];

    monitorProfiles = {
      work = {
        description = "Laptop + Dell P3425WE ultrawide";
        monitors = [
          { output = "eDP-1"; mode = "2880x1800@120.00Hz"; position = "0x0"; scale = 1.5; }
          { output = "DP-1"; mode = "3440x1440@99.98Hz"; position = "1920x0"; scale = 1; }
        ];
      };

      home = {
        description = "Laptop + 1440p + 1080p";
        monitors = [
          { output = "DP-2"; mode = "2560x1440@59.95Hz"; position = "0x0"; scale = 1; }
          { output = "DP-1"; mode = "1920x1080@59.97Hz"; position = "2560x0"; scale = 1; }
          { output = "eDP-1"; mode = "2880x1800@120.00Hz"; position = "320x1440"; scale = 1.5; }
        ];
      };

      solo = {
        description = "Laptop screen only";
        monitors = [
          { output = "eDP-1"; mode = "2880x1800@120.00Hz"; position = "0x0"; scale = 1.5; }
        ];
      };

      docked = {
        description = "Lid closed, external displays only";
        monitors = [
          { output = "eDP-1"; disabled = true; }
          { output = "DP-1"; mode = "preferred"; position = "auto"; scale = 1; }
          { output = "DP-2"; mode = "preferred"; position = "auto"; scale = 1; }
        ];
      };
    };
  };
}
