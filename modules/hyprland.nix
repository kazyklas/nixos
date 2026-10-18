{ config, pkgs, lib, ... }:

let
  inherit (lib.generators) mkLuaInline;

  mainMod = "SUPER";
  terminal = "footclient";
  fileManager = "nautilus";
  menu = "rofi -show drun";

  # hl.bind(keys, dispatcher) / hl.bind(keys, dispatcher, opts)
  bind = keys: dispatcher: { _args = [ keys (mkLuaInline dispatcher) ]; };
  bind' = keys: dispatcher: opts: { _args = [ keys (mkLuaInline dispatcher) opts ]; };

  exec = cmd: "hl.dsp.exec_cmd(${builtins.toJSON cmd})";

  directions = [
    { key = "h"; dir = "left"; }
    { key = "l"; dir = "right"; }
    { key = "k"; dir = "up"; }
    { key = "j"; dir = "down"; }
  ];

  focusBinds = lib.concatMap (d: [
    (bind "${mainMod} + ${d.key}" ''hl.dsp.focus({ direction = "${d.dir}" })'')
    (bind "${mainMod} + SHIFT + ${d.key}" ''hl.dsp.window.swap({ direction = "${d.dir}" })'')
  ]) directions;

  # SUPER + 1..9,0 focuses a workspace, + SHIFT moves the active window there.
  workspaceBinds = lib.concatMap (i:
    let key = toString (lib.mod i 10); in [
      (bind "${mainMod} + ${key}" "hl.dsp.focus({ workspace = ${toString i} })")
      (bind "${mainMod} + SHIFT + ${key}" "hl.dsp.window.move({ workspace = ${toString i} })")
    ]) (lib.range 1 10);

  # A host that declares no layouts gets no `monitor-profile` at all: the
  # generated script's `case` would have nothing but its fallback branch, which
  # shellcheck (rightly) rejects as unreachable code. Hyprland then just
  # auto-configures whatever outputs it finds, which is the sane default for a
  # machine whose screens are not described here yet.
  hasProfiles = monitorProfiles != { };

  # The user-session bits started with the compositor. `monitor-profile
  # restore` goes first so the screens are back the way they were at this desk
  # before anything else starts placing windows -- and is left out entirely on a
  # host with no profiles, where the command does not exist.
  startupCommands =
    lib.optional hasProfiles "monitor-profile restore"
    ++ [ "noctalia" "foot --server" "swaync" ];

  startHook = ''
    function()
    ${lib.concatMapStringsSep "\n"
        (c: "  hl.exec_cmd(${builtins.toJSON c})")
        startupCommands}
    end'';

  # SUPER + SHIFT + M opens the rofi picker (SUPER + M is hl.dsp.exit(), so it
  # stays clear); SUPER + ALT + 1..n jump straight to the host's
  # `quickProfiles`, in the order it lists them.
  monitorBinds = lib.optionals hasProfiles (
    [ (bind "${mainMod} + SHIFT + M" (exec "monitor-profile")) ]
    ++ lib.imap1
      (i: name: bind "${mainMod} + ALT + ${toString i}" (exec "monitor-profile ${name}"))
      cfg.quickProfiles
  );

  # Noctalia renders ~/.config/hypr/noctalia.lua and expects the compositor config
  # to load it. Home Manager owns hyprland.lua, so Noctalia's own appender cannot
  # patch us -- the literal require("noctalia") in the comment below is what its
  # apply.sh greps for to decide it has nothing to do.
  noctaliaTheme = ''
    -- Noctalia colour template hook: require("noctalia")
    local hyprConfigDir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
    package.path = hyprConfigDir .. "/?.lua;" .. hyprConfigDir .. "/?/init.lua;" .. package.path

    local ok, noctalia = pcall(require, "noctalia")
    if ok and type(noctalia) == "table" and type(noctalia.apply_theme) == "function" then
      noctalia.apply_theme()
    end
  '';

  # ---------- monitor profiles ----------
  # The layouts themselves are per-machine data, so they live in
  # hosts/<host>/home.nix under `my.hyprland.monitorProfiles` (the options are
  # declared at the bottom of this file). `monitor-profile` (generated below)
  # applies one at runtime through `hyprctl eval`, so changing desk needs no
  # rebuild; `defaultProfile` is the layout compiled into the config for the
  # first boot, and the start hook then restores whichever profile was last
  # applied.
  cfg = config.my.hyprland;
  monitorProfiles = cfg.monitorProfiles;

  # This config is Lua (`configType = "lua"`), and Hyprland's non-legacy parser
  # refuses `hyprctl keyword` outright -- the runtime equivalent of a `monitor`
  # entry is `hl.monitor(spec)`, driven through `hyprctl eval`. The spec takes
  # the very attrset the profiles above are written in, so an entry renders
  # straight to Lua. JSON and Lua literals agree on strings, numbers and bools.
  #
  # `disabled` is always spelled out: an output switched off by one profile
  # stays off when the next profile merely gives it a mode again, so leaving the
  # field implicit means a screen never comes back after a round trip.
  renderMonitor = m:
    let
      field = k: v: "${k} = ${builtins.toJSON v}";
      spec = { disabled = false; } // m;
    in "hl.monitor({ ${lib.concatStringsSep ", " (lib.mapAttrsToList field spec)} })";

  # Every output any profile mentions. Outputs not used by the profile being
  # applied are explicitly disabled, so leftovers from the previous desk do not
  # linger as phantom screens holding workspaces.
  allOutputs = lib.unique
    (lib.concatMap (p: map (m: m.output) p.monitors)
      (lib.attrValues monitorProfiles));

  profileCase = name: profile:
    let
      used = map (m: m.output) profile.monitors;
      unused = lib.subtractLists used allOutputs;
      chunk = lib.concatMapStringsSep "\n"
        (m: renderMonitor m)
        (profile.monitors ++ map (o: { output = o; disabled = true; }) unused);
    in ''
      ${name})
        chunk=${lib.escapeShellArg chunk}
        ;;
    '';

  monitorProfile = pkgs.writeShellApplication {
    name = "monitor-profile";
    runtimeInputs = with pkgs; [ hyprland rofi libnotify ];
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
      state_file="$state_dir/monitor-profile"

      usage() {
        cat <<'EOF'
      monitor-profile [PROFILE|restore|list]

        PROFILE   apply a named profile (see `list`)
        restore   re-apply the profile last applied (no-op if none)
        list      print the available profiles
        (no args) pick a profile with rofi
      EOF
      }

      apply() {
        local name=$1 chunk out
        case "$name" in
      ${lib.concatStrings (lib.mapAttrsToList profileCase monitorProfiles)}
          *)
            echo "monitor-profile: unknown profile '$name'" >&2
            usage >&2
            return 1
            ;;
        esac

        # `hyprctl eval` exits 0 even when the Lua is rejected, so the reply is
        # the only thing that says whether the layout actually changed.
        out=$(hyprctl eval "$chunk")
        if [ "$out" != "ok" ]; then
          echo "monitor-profile: $name failed: $out" >&2
          notify-send -a monitor-profile -u critical "Monitor profile" "$name failed: $out"
          return 1
        fi

        mkdir -p "$state_dir"
        printf '%s\n' "$name" > "$state_file"
        notify-send -a monitor-profile -t 2000 "Monitor profile" "$name"
      }

      case "''${1:-}" in
        -h|--help)
          usage
          ;;
        list)
          printf '%s\n' ${lib.escapeShellArgs
            (lib.mapAttrsToList (n: p: "${n}\t${p.description}") monitorProfiles)}
          ;;
        restore)
          # Called from the Hyprland start hook: silently keep the compiled-in
          # layout when nothing has been chosen yet.
          [ -r "$state_file" ] || exit 0
          apply "$(cat "$state_file")"
          ;;
        "")
          choice=$("$0" list | rofi -dmenu -i -p "Monitor profile" -no-custom) || exit 0
          [ -n "$choice" ] || exit 0
          apply "''${choice%%$'\t'*}"
          ;;
        *)
          apply "$1"
          ;;
      esac
    '';
  };
in
{
  options.my.hyprland = {
    monitorProfiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Shown in the rofi picker and `monitor-profile list`.";
          };
          monitors = lib.mkOption {
            # One attrset per output, in Hyprland's own vocabulary: output,
            # mode, position, scale, or `disabled = true`. Rendered both into
            # the static config and into `hl.monitor(...)` calls, so the keys
            # have to be ones Hyprland's Lua API accepts.
            type = with lib.types; listOf (attrsOf (oneOf [ bool int float str ]));
            example = [
              { output = "eDP-1"; mode = "preferred"; position = "0x0"; scale = 1; }
            ];
            description = "The outputs this layout drives.";
          };
        };
      });
      default = { };
      description = ''
        Named monitor layouts for this host, switchable at runtime with
        `monitor-profile`. Set it in hosts/<host>/home.nix.
      '';
    };

    defaultProfile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = ''
        Which profile Hyprland's static config starts with -- it only matters
        until `monitor-profile` has been run once on the machine. `null` emits
        no `monitor` entries at all, leaving Hyprland's own default (preferred
        mode, auto position) to sort the outputs out; that is what a host whose
        output names are not known yet wants.
      '';
    };

    quickProfiles = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [ "work" "home" "solo" ];
      description = ''
        Profiles to bind to SUPER + ALT + 1..n, in order. Everything declared
        in `monitorProfiles` stays reachable through the rofi picker
        (SUPER + SHIFT + M) regardless.
      '';
    };
  };

  config = {
    # The profile names are plain strings (an `enum` type here would make the
    # option type depend on a sibling option's value, which the module system
    # resolves by recursing forever), so check them with assertions instead.
    assertions =
      let
        known = lib.attrNames monitorProfiles;
        missing = name: !(lib.elem name known);
      in
      [
        {
          assertion = cfg.defaultProfile == null || !(missing cfg.defaultProfile);
          message = "my.hyprland.defaultProfile = \"${toString cfg.defaultProfile}\" is not one of my.hyprland.monitorProfiles (${lib.concatStringsSep ", " known}).";
        }
      ] ++ map (name: {
        assertion = !(missing name);
        message = "my.hyprland.quickProfiles lists \"${name}\", which is not one of my.hyprland.monitorProfiles (${lib.concatStringsSep ", " known}).";
      }) cfg.quickProfiles;

    wayland.windowManager.hyprland = {
      enable = true;

      # Hyprland itself, its session entry and the portal come from the NixOS
      # module (programs.hyprland.enable), so Home Manager only writes config.
      package = null;
      portalPackage = null;

      configType = "lua";

      settings = {
        # ---------- env ----------
        env = [
          { _args = [ "HYPRCURSOR_SIZE" "30" ]; }
          { _args = [ "HYPRCURSOR_THEME" "Future-Cyan-Hyprcursor_Theme" ]; }
          { _args = [ "WALLPAPERS_PATH" "${config.home.homeDirectory}/Pictures/Wallpapers" ]; }
          { _args = [ "SCRIPTS_PATH" "${config.home.homeDirectory}/.config/hypr/scripts" ]; }
        ];

        # ---------- monitors ----------
        # The layout Hyprland boots with, named by `my.hyprland.defaultProfile`
        # in hosts/<host>/home.nix. `monitor-profile` switches between the
        # profiles at runtime and the start hook below restores the last one
        # chosen, so this only matters on a fresh machine. No default profile
        # means no `monitor` entries, which leaves Hyprland to auto-configure
        # whatever it finds.
        monitor =
          if cfg.defaultProfile == null then [ ]
          else monitorProfiles.${cfg.defaultProfile}.monitors;

        # ---------- look and feel ----------
        config = {
          general = {
            gaps_in = 8;
            gaps_out = 8;
            border_size = 1;
            col.active_border = "rgba(595959aa)";
            resize_on_border = true;
            allow_tearing = false;
            layout = "dwindle";
          };

          decoration = {
            rounding = 14;
            rounding_power = 2;
            active_opacity = 1.0;
            inactive_opacity = 0.80;

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
              contrast = 2.0;
              brightness = 1.5;
              vibrancy = 0.1696;
            };
          };

          animations.enabled = true;

          # Overridden at the end of the file by the Noctalia theme, kept so the
          # colours are sane if Noctalia has not rendered its template yet.
          group = {
            col = {
              border_active = "rgba(595959aa)";
              border_inactive = "rgba(1c1c21ee)";
              border_locked_active = "rgba(fd4663aa)";
              border_locked_inactive = "rgba(1c1c21ee)";
            };
            groupbar.col = {
              active = "rgba(8d8da5aa)";
              inactive = "rgba(1c1c21ee)";
              locked_active = "rgba(fd4663aa)";
              locked_inactive = "rgba(1c1c21ee)";
            };
          };

          misc = {
            force_default_wallpaper = 0;
            disable_hyprland_logo = false;
          };

          dwindle.preserve_split = true;

          input = {
            kb_layout = "us";
            follow_mouse = 1;
            sensitivity = 0;
            repeat_rate = 60;
            repeat_delay = 400;
            touchpad.natural_scroll = false;
          };
        };

        # ---------- animations ----------
        # https://github.com/HyDE-Project/HyDE/blob/master/Configs/.config/hypr/animations/end4.conf
        animation = [
          { leaf = "workspaces"; enabled = true; speed = 2; bezier = "default"; style = "slidevert"; }
          { leaf = "windowsIn"; enabled = true; speed = 3; bezier = "default"; style = "gnomed"; }
          { leaf = "windowsOut"; enabled = true; speed = 3; bezier = "default"; style = "gnomed"; }
          { leaf = "windowsMove"; enabled = true; speed = 2; bezier = "default"; style = "slide"; }
        ];

        # ---------- workspace rules ----------
        # "No gaps when only": single tiled window, or a single fullscreen one.
        workspace_rule = [
          { workspace = "w[tv1]"; gaps_out = 0; gaps_in = 0; }
          { workspace = "f[1]"; gaps_out = 0; gaps_in = 0; }
        ];

        # ---------- window rules ----------
        window_rule = [
          {
            name = "chrome-to-ws2";
            match.class = "^(google-chrome)$";
            workspace = 2;
          }
          {
            name = "password-managers-to-ws3";
            match.class = "^(1password|org.keepassxc.KeePassXC)$";
            workspace = 3;
          }
          {
            name = "zed-to-ws4";
            match.class = "^(dev.zed.Zed)$";
            workspace = 4;
          }
          {
            name = "lens-to-ws4";
            match.class = "^(Lens)$";
            workspace = 4;
          }
          {
            name = "password-managers-no-screen-share";
            match.class = "^(1password|org.keepassxc.KeePassXC)$";
            no_screen_share = true;
          }
          {
            name = "opaque-media";
            match.class = "^(google-chrome|spotify)$";
            opacity = "1.0 override 1.0 override 1.0 override";
          }
          {
            name = "no-gaps-wtv1";
            match.workspace = "w[tv1]";
            rounding = 0;
            border_size = 0;
          }
          {
            name = "no-gaps-f1";
            match.workspace = "f[1]";
            rounding = 0;
            border_size = 0;
          }
          {
            name = "suppress-maximize-events";
            match.class = ".*";
            suppress_event = "maximize";
          }
        ];

        # ---------- gestures ----------
        gesture = [
          { fingers = 3; direction = "horizontal"; action = "workspace"; }
          { fingers = 3; direction = "up"; scale = 1; action = "fullscreen"; }
        ];

        # ---------- per-device ----------
        device = {
          name = "epic-mouse-v1";
          sensitivity = -0.5;
        };

        # ---------- autostart ----------
        # Home Manager already emits its own hyprland.start hook for the systemd /
        # D-Bus environment; this one carries the user session bits.
        on = {
          _args = [
            "hyprland.start"
            (mkLuaInline startHook)
          ];
        };

        # ---------- binds ----------
        bind = [
          (bind "${mainMod} + Return" (exec terminal))
          (bind "${mainMod} + Q" "hl.dsp.window.close()")
          (bind "${mainMod} + M" "hl.dsp.exit()")
          (bind "${mainMod} + E" (exec fileManager))
          (bind "${mainMod} + T" ''hl.dsp.window.float({ action = "toggle" })'')
          (bind "${mainMod} + CTRL + V" ''hl.dsp.window.float({ action = "toggle" })'')
          (bind "${mainMod} + P" "hl.dsp.window.pseudo()")
          (bind "${mainMod} + f" "hl.dsp.window.fullscreen()")
          (bind "${mainMod} + space" (exec "noctalia msg panel-toggle launcher"))
          (bind "${mainMod} + CTRL + L" (exec "noctalia msg session lock"))
          (bind "${mainMod} + W" (exec "noctalia ipc call wallpaper toggle"))
          (bind "${mainMod} + A" (exec "noctalia msg panel-toggle tklas/claude_chat:chat"))
          (bind "${mainMod} + CTRL + R" (exec "hyprctl reload"))

          # screenshots
          (bind "PRINT" (exec "hyprshot -m region"))
          (bind "${mainMod} + PRINT" (exec "hyprshot -m output"))

          # scratchpad
          (bind "${mainMod} + S" ''hl.dsp.workspace.toggle_special("magic")'')
          (bind "${mainMod} + SHIFT + S" ''hl.dsp.window.move({ workspace = "special:magic" })'')

          # move the current workspace between monitors
          (bind "${mainMod} + SHIFT + left" ''hl.dsp.workspace.move({ monitor = "+1" })'')
          (bind "${mainMod} + SHIFT + right" ''hl.dsp.workspace.move({ monitor = "-1" })'')

          # scroll through workspaces
          (bind "${mainMod} + mouse_down" ''hl.dsp.focus({ workspace = "e+1" })'')
          (bind "${mainMod} + mouse_up" ''hl.dsp.focus({ workspace = "e-1" })'')

          # move / resize with the mouse
          (bind' "${mainMod} + mouse:272" "hl.dsp.window.drag()" { mouse = true; })
          (bind' "${mainMod} + mouse:273" "hl.dsp.window.resize()" { mouse = true; })

          # Media keys. Plain binds, as in the old config -- add
          # `{ locked = true; repeating = true; }` as a third argument if you want
          # them to work on the lock screen and on key repeat.
          (bind "XF86AudioRaiseVolume" (exec "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"))
          (bind "XF86AudioLowerVolume" (exec "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
          (bind "XF86AudioMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
          (bind "XF86AudioMicMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
          (bind "XF86MonBrightnessUp" (exec "brightnessctl set +5%"))
          (bind "XF86MonBrightnessDown" (exec "brightnessctl set 5%-"))

          # terminal-friendly copy/paste everywhere
          (bind' "${mainMod} + C" ''hl.dsp.send_shortcut({ mods = "CTRL", key = "Insert" })''
            { description = "Universal copy"; })
          (bind' "${mainMod} + V" ''hl.dsp.send_shortcut({ mods = "SHIFT", key = "Insert" })''
            { description = "Universal paste"; })
          (bind' "${mainMod} + X" ''hl.dsp.send_shortcut({ mods = "CTRL", key = "X" })''
            { description = "Universal cut"; })
        ]
        ++ focusBinds
        ++ workspaceBinds
        ++ monitorBinds;
      };

      extraConfig = noctaliaTheme;
    };

    # `monitor-profile` is referenced by the binds and the start hook above, so it
    # has to be on PATH for the Hyprland session.
    home.packages = lib.optional hasProfiles monitorProfile;

    # Hyprland is installed by the NixOS module, so the Home Manager module skips
    # the .luarc.json it would normally drop next to hyprland.lua. Point the Lua
    # language server at the stubs ourselves.
    xdg.configFile."hypr/.luarc.json".text = builtins.toJSON {
      workspace.library = [ "${pkgs.hyprland}/share/hypr/stubs" ];
      diagnostics.globals = [ "hl" ];
    };
  };
}
