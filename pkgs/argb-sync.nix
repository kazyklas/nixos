# Thin wrapper around the OpenRGB CLI client.
#
# Takes one argument: a JSON array of { "hex": "#rrggbb", "device": "..." }
# entries (device = "" means every device OpenRGB sees). Applies each entry
# as a solid color via OpenRGB's SDK client, in order.
#
# Uses --mode Direct, not --mode static: "Direct" is the SDK-controlled mode
# present on effectively every OpenRGB device (confirmed via
# `openrgb --list-detailed` against beast's MSI Mystic Light controller,
# which only advertises `Direct`) -- "static" is a device-local effect some
# controllers expose instead, not a safe default to assume.
#
# Kept as a standalone script (rather than inline shell in the Noctalia
# plugin's Lua) so it can be run and debugged by hand, independent of
# Noctalia:
#   argb-sync '[{"hex":"#ff0000","device":""}]'
{ lib
, writeShellApplication
, openrgb
, jq
}:

writeShellApplication {
  name = "argb-sync";
  runtimeInputs = [ openrgb jq ];
  text = ''
    host="''${OPENRGB_HOST:-127.0.0.1}"
    port="''${OPENRGB_PORT:-6742}"

    if [ "$#" -ne 1 ]; then
      echo "usage: argb-sync '<json array of {hex, device}>'" >&2
      exit 1
    fi
    payload=$1

    echo "$payload" | jq -c '.[]' | while IFS= read -r entry; do
      hex=$(echo "$entry" | jq -r '.hex' | sed 's/^#//')
      device=$(echo "$entry" | jq -r '.device // ""')

      args=(--client "$host:$port" --mode Direct --color "$hex")
      if [ -n "$device" ]; then
        args+=(--device "$device")
      fi

      openrgb "''${args[@]}"
    done
  '';

  meta = {
    description = "Apply a JSON list of hex colors to OpenRGB devices, for the argb_sync Noctalia plugin";
    license = lib.licenses.mit;
    mainProgram = "argb-sync";
  };
}
