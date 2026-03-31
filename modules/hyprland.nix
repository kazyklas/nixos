{ config, pkgs, ... }:

{
  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      env = [
        "XCURSOR_SIZE,25"
        "HYPRCURSOR_SIZE,24"
        "WALLPAPERS_PATH,/home/tklas/Pictures/Wallpapers"
        "SCRIPTS_PATH,/home/tklas/.config/hypr/scripts"
        "HYPRCURSOR_THEME,"
      ];

      monitor = [
        "eDP-1,2880x1800@120.00Hz,auto,1.5"
        "DP-1,3440x1440@99.98Hz,2880x0,1"
      ];

      exec-once = [
        "noctalia-shell"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
        "foot --server"
        "swaync"
      ];

      source = [
        "$HOME/.config/hypr/colors.conf"
        "$HOME/.config/hypr/noctalia/noctalia-colors.conf"
      ];

      "$terminal" = "footclient";
      "$fileManager" = "nautilus";
      "$menu" = "rofi -show drun";
      "$mainMod" = "SUPER";
      "$ipc" = "noctalia-shell ipc call";
      "$scriptsPath" = "/home/tklas/.config/hypr/scripts";

      general = {
        gaps_in = 8;
        gaps_out = 8;
        border_size = 1;
        "col.active_border" = "rgba(595959aa)";
        "col.inactive_border" = "$background";
        resize_on_border = true;
        allow_tearing = false;
        layout = "dwindle";
      };

      decoration = {
        rounding = 14;
        rounding_power = 2;
        active_opacity = 1;
        inactive_opacity = 0.60;
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
        blur = {
          enabled = true;
          size = 10;
          passes = 3;
          contrast = 2;
          brightness = 1.5;
          vibrancy = 0.1696;
        };
      };

      animations = {
        enabled = true;
        bezier = [
          "easeOutQuint,0.23,1,0.32,1"
          "easeInOutCubic,0.65,0.05,0.36,1"
          "linear,0,0,1,1"
          "almostLinear,0.5,0.5,0.75,1"
          "quick,0.15,0,0.1,1"
        ];
        animation = [
          "global,1,10,default"
          "border,1,5.39,easeOutQuint"
          "windows,1,4.79,easeOutQuint"
          "windowsIn,1,4.1,easeOutQuint,popin 87%"
          "windowsOut,1,1.49,linear,popin 87%"
          "fadeIn,1,1.73,almostLinear"
          "fadeOut,1,1.46,almostLinear"
          "fade,1,3.03,quick"
          "layers,1,3.81,easeOutQuint"
          "layersIn,1,4,easeOutQuint,fade"
          "layersOut,1,1.5,linear,fade"
          "fadeLayersIn,1,1.79,almostLinear"
          "fadeLayersOut,1,1.39,almostLinear"
          "workspaces,1,1.94,almostLinear,fade"
          "workspacesIn,1,0.40,almostLinear,fade"
          "workspacesOut,1,0.40,almostLinear,fade"
          "zoomFactor,1,7,quick"
        ];
      };

      workspace = [
        "w[tv1],gapsout:0,gapsin:0"
        "f[1],gapsout:0,gapsin:0"
      ];

      windowrule = [
        "match:class ^(google-chrome)$, workspace 2"
        "match:class ^(1password|org.keepassxc.KeePassXC)$, workspace 3"
        "match:class ^(dev.zed.Zed)$, workspace 4"
        "match:class ^(Lens)$, workspace 5"
        "match:class ^(1password|org.keepassxc.KeePassXC)$, no_screen_share on"
        "match:class ^(google-chrome)$, opacity 1.0 override 1.0 override 1.0 override"
        "match:workspace w[tv1], rounding 0, border_size 0"
        "match:workspace f[1], rounding 0, border_size 0"
        "match:class .*, suppress_event maximize"
      ];

      group = {
        "col.border_active" = "rgba(595959aa)";
        "col.border_inactive" = "rgba(1c1c21ee)";
        "col.border_locked_active" = "rgba(fd4663aa)";
        "col.border_locked_inactive" = "rgba(1c1c21ee)";
        groupbar = {
          "col.active" = "rgba(8d8da5aa)";
          "col.inactive" = "rgba(1c1c21ee)";
          "col.locked_active" = "rgba(fd4663aa)";
          "col.locked_inactive" = "rgba(1c1c21ee)";
        };
      };

      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = false;
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      input = {
        kb_layout = "us";
        kb_variant = "";
        kb_model = "";
        kb_options = "";
        kb_rules = "";
        follow_mouse = 1;
        sensitivity = 0;
        repeat_rate = 60;
        repeat_delay = 400;
        touchpad = {
          natural_scroll = false;
        };
      };

      gesture = [
        "3,horizontal,workspace"
        "3,up,mod:,scale:1,fullscreen"
      ];

      device = {
        name = "epic-mouse-v1";
        sensitivity = -0.5;
      };

      bind = [
        "$mainMod,Return,exec,$terminal"
        "$mainMod,Q,killactive,"
        "$mainMod,M,exec,hyprctl dispatch exit"
        "$mainMod,E,exec,$fileManager"
        "$mainMod,T,togglefloating,"
        "$mainMod,space,exec,noctalia-shell ipc call launcher toggle"
        "$mainMod,P,pseudo,"
        "$mainMod CTRL,L,exec,noctalia-shell ipc call lockScreen lock"
        "$mainMod,W,exec,noctalia-shell ipc call wallpaper toggle"
        ",PRINT,exec,hyprshot -m region"
        "$mainMod,PRINT,exec,hyprshot -m output"
        "$mainMod CTRL,R,exec,hyprctl reload"

        "$mainMod,h,movefocus,l"
        "$mainMod,l,movefocus,r"
        "$mainMod,k,movefocus,u"
        "$mainMod,j,movefocus,d"

        "$mainMod SHIFT,h,swapwindow,l"
        "$mainMod SHIFT,l,swapwindow,r"
        "$mainMod SHIFT,k,swapwindow,u"
        "$mainMod SHIFT,j,swapwindow,d"

        "$mainMod,f,fullscreen,0"

        "$mainMod,1,workspace,1"
        "$mainMod,2,workspace,2"
        "$mainMod,3,workspace,3"
        "$mainMod,4,workspace,4"
        "$mainMod,5,workspace,5"
        "$mainMod,6,workspace,6"
        "$mainMod,7,workspace,7"
        "$mainMod,8,workspace,8"
        "$mainMod,9,workspace,9"
        "$mainMod,0,workspace,10"

        "$mainMod SHIFT,1,movetoworkspace,1"
        "$mainMod SHIFT,2,movetoworkspace,2"
        "$mainMod SHIFT,3,movetoworkspace,3"
        "$mainMod SHIFT,4,movetoworkspace,4"
        "$mainMod SHIFT,5,movetoworkspace,5"
        "$mainMod SHIFT,6,movetoworkspace,6"
        "$mainMod SHIFT,7,movetoworkspace,7"
        "$mainMod SHIFT,8,movetoworkspace,8"
        "$mainMod SHIFT,9,movetoworkspace,9"
        "$mainMod SHIFT,0,movetoworkspace,10"

        "$mainMod SHIFT,left,movecurrentworkspacetomonitor,+1"
        "$mainMod SHIFT,right,movecurrentworkspacetomonitor,-1"

        "$mainMod,S,togglespecialworkspace,magic"
        "$mainMod SHIFT,S,movetoworkspace,special:magic"

        "$mainMod,mouse_down,workspace,e+1"
        "$mainMod,mouse_up,workspace,e-1"

        "$mainMod,mouse:272,movewindow"
        "$mainMod,mouse:273,resizeactive"

        ",XF86AudioRaiseVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume,exec,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute,exec,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute,exec,wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"

        ",XF86MonBrightnessDown,exec,${pkgs.brightnessctl}/bin/brightnessctl set 5%-"
        ",XF86MonBrightnessUp,exec,${pkgs.brightnessctl}/bin/brightnessctl set +5%"
      ];

      bindd = [
        "SUPER,C,Universal copy,sendshortcut,CTRL,Insert,"
        "SUPER,V,Universal paste,sendshortcut,SHIFT,Insert,"
        "SUPER,X,Universal cut,sendshortcut,CTRL,X,"
      ];
    };

    xwayland = {
      enable = true;
    };
  };
}
