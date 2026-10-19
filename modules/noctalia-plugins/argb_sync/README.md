# ARGB Sync (Noctalia plugin)

Syncs motherboard/case ARGB lighting to Noctalia's wallpaper color palette, through
[OpenRGB](https://openrgb.org). Built for `beast`, whose motherboard exposes an MSI
Mystic Light USB ARGB controller (`lsusb`: `0db0:0076`) -- one of OpenRGB's supported
devices.

```
SUPER + G                 toggle the panel (modules/hyprland.nix)
click the bar glyph       toggle sync on/off without opening the panel
```

## How it works

- **Getting colors**: `noctalia theme <wallpaper> --dark|--light -o file.json` is
  Noctalia's own CLI subcommand for regenerating the exact Material-You palette it
  derives from a wallpaper -- the same one used to theme Hyprland/GTK/terminals. The bar
  widget (`widget.luau`) re-reads the active wallpaper path and theme mode straight out
  of `~/.local/state/noctalia/settings.toml` on a 3s tick, independent of whether the
  panel is open, and only regenerates the palette when either has changed.
- **Setting the lights**: colors are pushed through `argb-sync` (`pkgs/argb-sync.nix`), a
  small wrapper around `openrgb --client ... --mode Direct --color ...`. OpenRGB itself
  (via `services.hardware.openrgb` on the `beast` host) talks to the hardware -- this
  plugin never touches USB/HID/SMBus directly.
- **Color slots**: `primary` / `secondary` / `tertiary` from the generated palette, each
  independently switchable and assignable to a device-name filter (empty = every
  OpenRGB device). Only `primary` is active by default, mapped to every device -- the
  whole rig glows in the dominant wallpaper color out of the box. Add more RGB hardware
  later and point `secondary`/`tertiary` at it from the panel.
- **Manual mode**: stops following the wallpaper and lets you type exact `#rrggbb`
  values per slot instead. Turning sync off pushes black once, so the toggle has an
  obvious effect instead of leaving stale colors lit.

Everything editable in the panel (on/off, mode, slot colors, device filters) lives in
`state.json` in the plugin data dir
(`~/.local/state/noctalia/plugins/data/tklas/argb_sync/`), not in `plugin.toml` --
it's live state, not install-time config.

## Requirements

- `services.hardware.openrgb.enable = true;` on the host (already set for `beast`,
  `hosts/beast/default.nix`) -- runs `openrgb --server` and installs the udev rules
  needed to talk to the controller without root.
- `openrgb` and `argb-sync` on `$PATH` (already added to `hosts/beast/home.nix`).

## Entries

| Entry | Id | What it is |
|-------|----|------------|
| Panel | `tklas/argb_sync:panel` | The management window. `noctalia msg panel-toggle tklas/argb_sync:panel` |
| Bar widget | `tklas/argb_sync:toggle` | Lit/unlit bulb glyph; click to toggle sync |

## Settings

Settings -> Plugins -> gear on the ARGB Sync row. Advanced only -- OpenRGB host/port and
the `argb-sync` binary path, for the rare case either isn't at its default.

## Development

Symlinked into `~/.local/share/noctalia/plugins/` from this repo
(`modules/noctalia-argb-sync.nix`), so editing a `.luau` file here hot-reloads in the
running shell -- no rebuild. Manifest changes still need:

```sh
noctalia plugins lint .
noctalia msg plugins disable tklas/argb_sync && noctalia msg plugins enable tklas/argb_sync
```

Debug the hardware side independent of Noctalia:

```sh
openrgb --list-devices
argb-sync '[{"hex":"#ff0000","device":""}]'
```

## Known limits

- One OpenRGB controller was detected on `beast` at the time this was written (the MSI
  Mystic Light motherboard header), so by default every slot's device filter resolves
  to "every device". Multi-zone setups (e.g. separate RAM/fan lighting) need their
  device names found via the panel's "Scan" button and typed into the relevant slot.
- The wallpaper-change check polls every 3s; lighting lags a wallpaper change by at most
  that long.
