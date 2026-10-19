-- ARGB Sync -- management panel.
--
-- Pure editor: it only reads/writes the shared state.json (same file the
-- widget's background worker uses) and flips the `argb_enabled` /
-- `argb_mode` pub-sub values the widget watches. All the actual syncing
-- happens in widget.luau's update() tick, which keeps running whether or
-- not this panel is open.

local DEVICE_SCAN_TIMEOUT_MS = 5000

local state = nil -- loaded in onOpen
local status = nil
local deviceListText = "Press Scan to list OpenRGB devices."
local scanning = false
local scanLastLineMs = 0

--==========================================================================
-- Small helpers (duplicated in widget.luau -- see the note there).
--==========================================================================

local function sq(value)
  return "'" .. string.gsub(tostring(value), "'", "'\\''") .. "'"
end

local function conf(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local function dataPath()
  return noctalia.pluginDataDir() .. "/state.json"
end

local function defaultState()
  return {
    enabled = false,
    mode = "auto",
    slots = {
      primary   = { active = true,  hex = "#a6c9fb", device = "" },
      secondary = { active = false, hex = "#bac7dd", device = "" },
      tertiary  = { active = false, hex = "#d9bde3", device = "" },
    },
    last_wallpaper = nil,
    last_theme_mode = nil,
  }
end

local function loadState()
  local path = dataPath()
  if noctalia.fileExists(path) then
    local raw = noctalia.readFile(path)
    local data = raw ~= nil and noctalia.json.decode(raw) or nil
    if type(data) == "table" and type(data.slots) == "table" then
      return data
    end
  end
  return defaultState()
end

local function saveState()
  local encoded = noctalia.json.encode(state)
  if encoded ~= nil then
    noctalia.writeFile(dataPath(), encoded)
  end
end

local SLOT_ORDER = { "primary", "secondary", "tertiary" }
local SLOT_TITLE = { primary = "Primary", secondary = "Secondary", tertiary = "Tertiary" }

--==========================================================================
-- Actions (forward-declared, defined below render)
--==========================================================================

local render
local toggleEnabled
local setMode
local toggleSlotActive
local setSlotHex
local setSlotDevice
local applyNow
local turnOff
local scanDevices

--==========================================================================
-- Rendering
--==========================================================================

local function headerNode()
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({
      name = state.enabled and "bulb" or "bulb-off",
      size = 18,
      color = state.enabled and "primary" or "on_surface_variant",
    }),
    ui.column({ gap = 0, flexGrow = 1 }, {
      ui.label({ text = "ARGB Sync", fontSize = 14, fontWeight = "bold" }),
      ui.label({
        text = state.enabled
          and (state.mode == "auto" and "Following the wallpaper palette" or "Manual colors")
          or "Off",
        fontSize = 10,
        color = "on_surface_variant",
      }),
    }),
    ui.button({
      glyph = "settings",
      variant = "ghost",
      controlSize = "sm",
      tooltip = "Plugin settings",
      onClick = function()
        noctalia.openSettings()
      end,
    }),
    ui.button({
      glyph = "x",
      variant = "ghost",
      controlSize = "sm",
      tooltip = "Close",
      onClick = function()
        panel.close()
      end,
    }),
  })
end

local function powerRowNode()
  return ui.row({ gap = 10, align = "center" }, {
    ui.label({ text = "Power", flexGrow = 1 }),
    ui.button({
      text = state.enabled and "On" or "Off",
      variant = state.enabled and "primary" or "secondary",
      controlSize = "sm",
      onClick = toggleEnabled,
    }),
  })
end

local function modeRowNode()
  return ui.row({ gap = 10, align = "center" }, {
    ui.label({ text = "Source", flexGrow = 1 }),
    ui.button({
      text = "Wallpaper",
      variant = state.mode == "auto" and "secondary" or "ghost",
      selected = state.mode == "auto",
      controlSize = "sm",
      onClick = function()
        setMode("auto")
      end,
    }),
    ui.button({
      text = "Manual",
      variant = state.mode == "manual" and "secondary" or "ghost",
      selected = state.mode == "manual",
      controlSize = "sm",
      onClick = function()
        setMode("manual")
      end,
    }),
  })
end

local function slotRowNode(key)
  local slot = state.slots[key]

  local hexField
  if state.mode == "manual" then
    hexField = ui.input({
      key = "hex-" .. key,
      value = slot.hex,
      width = 110,
      placeholder = "#rrggbb",
      onSubmit = function(value)
        setSlotHex(key, value)
      end,
    })
  else
    hexField = ui.label({ text = slot.hex, width = 110, color = "on_surface_variant" })
  end

  return ui.row({ gap = 8, align = "center" }, {
    ui.button({
      glyph = slot.active and "check" or "x",
      variant = slot.active and "primary" or "ghost",
      controlSize = "sm",
      tooltip = slot.active and "Used -- click to disable" or "Unused -- click to enable",
      onClick = function()
        toggleSlotActive(key)
      end,
    }),
    ui.column({ fill = slot.hex, width = 20, height = 20, radius = 4 }, {}),
    ui.label({ text = SLOT_TITLE[key], width = 72 }),
    hexField,
    ui.input({
      key = "device-" .. key,
      value = slot.device,
      placeholder = "All devices",
      flexGrow = 1,
      onSubmit = function(value)
        setSlotDevice(key, value)
      end,
    }),
  })
end

local function slotsNode()
  local rows = { ui.label({ text = "Color slots", fontSize = 11, color = "on_surface_variant" }) }
  for _, key in ipairs(SLOT_ORDER) do
    table.insert(rows, slotRowNode(key))
  end
  table.insert(rows, ui.label({
    text = "Device is a name substring from the scan below (3+ characters) -- empty means every device.",
    fontSize = 10,
    color = "on_surface_variant/0.8",
  }))
  return ui.column({ gap = 6 }, rows)
end

local function devicesNode()
  return ui.column({ gap = 6 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.label({ text = "OpenRGB devices", flexGrow = 1, fontSize = 11, color = "on_surface_variant" }),
      ui.button({
        text = scanning and "Scanning..." or "Scan",
        glyph = "refresh",
        variant = "ghost",
        controlSize = "sm",
        onClick = scanDevices,
      }),
    }),
    ui.column({ fill = "surface_variant/0.4", radius = 8, padding = 8 }, {
      ui.label({ text = deviceListText, fontSize = 11, color = "on_surface_variant" }),
    }),
  })
end

render = function()
  local children = {
    headerNode(),
    ui.separator({}),
    powerRowNode(),
    modeRowNode(),
    ui.separator({}),
    slotsNode(),
    ui.separator({}),
    devicesNode(),
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        text = "Apply now",
        variant = "primary",
        onClick = applyNow,
      }),
      ui.spacer({ flexGrow = 1 }),
    }),
  }

  if status ~= nil then
    table.insert(children, ui.label({ text = status, fontSize = 11, color = "on_surface_variant" }))
  end

  panel.render(ui.column({ gap = 12, padding = 14 }, children))
end

--==========================================================================
-- Actions
--==========================================================================

local function activeEntries()
  local entries = {}
  for _, key in ipairs(SLOT_ORDER) do
    local slot = state.slots[key]
    if slot.active == true and slot.hex ~= "" then
      table.insert(entries, { hex = slot.hex, device = slot.device or "" })
    end
  end
  return entries
end

local function runArgbSync(payload, onDone)
  local bin = conf("argb_bin", "argb-sync")
  local host = conf("openrgb_host", "127.0.0.1")
  local port = conf("openrgb_port", "6742")

  local cmd = "OPENRGB_HOST=" .. sq(host) .. " OPENRGB_PORT=" .. sq(port)
    .. " " .. sq(bin) .. " " .. sq(payload)
    .. " >/dev/null 2>&1 && echo ok || echo fail"

  noctalia.runStream(cmd, function(line)
    if onDone ~= nil then
      onDone(line == "ok")
    end
  end)
end

applyNow = function()
  local entries = activeEntries()
  if #entries == 0 then
    status = "No active color slots -- enable at least one above."
    render()
    return
  end

  local payload = noctalia.json.encode(entries)
  status = "Applying..."
  render()
  runArgbSync(payload, function(ok)
    status = ok and "Applied." or "Failed -- is the OpenRGB server running?"
    render()
  end)
end

turnOff = function()
  runArgbSync(noctalia.json.encode({ { hex = "#000000", device = "" } }), nil)
end

toggleEnabled = function()
  state.enabled = not state.enabled
  saveState()
  noctalia.state.set("argb_enabled", state.enabled)

  if state.enabled then
    if state.mode == "auto" then
      -- Let the widget's own tick pick up a fresh palette (it owns the
      -- wallpaper-watching logic); force it to re-check immediately.
      state.last_wallpaper = nil
      saveState()
    end
    applyNow()
  else
    turnOff()
  end

  render()
end

setMode = function(mode)
  if state.mode == mode then
    return
  end
  state.mode = mode
  saveState()
  noctalia.state.set("argb_mode", mode)
  render()
end

toggleSlotActive = function(key)
  local slot = state.slots[key]
  slot.active = not slot.active
  saveState()
  render()
end

setSlotHex = function(key, value)
  local trimmed = noctalia.string.trim(value or "")
  if string.match(trimmed, "^#%x%x%x%x%x%x$") == nil then
    status = "'" .. trimmed .. "' is not a #rrggbb color."
    render()
    return
  end
  state.slots[key].hex = trimmed
  status = nil
  saveState()
  render()
end

setSlotDevice = function(key, value)
  state.slots[key].device = noctalia.string.trim(value or "")
  saveState()
  render()
end

local scanLines = {}

scanDevices = function()
  if scanning then
    return
  end
  scanning = true
  scanLines = {}
  scanLastLineMs = noctalia.nowMs()
  deviceListText = "Scanning..."
  render()

  noctalia.runStream("openrgb --list-devices 2>&1", function(line)
    table.insert(scanLines, line)
    scanLastLineMs = noctalia.nowMs()
    deviceListText = table.concat(scanLines, "\n")
    render()
  end)
end

--==========================================================================
-- Lifecycle
--==========================================================================

function onOpen()
  state = loadState()
  status = nil
  -- Needed so update() below can notice when a device scan goes quiet (see
  -- the stall check there); the panel is otherwise fully event-driven, same
  -- as claude_chat's panel which uses the same ticks to detect a stalled run.
  panel.setWantsSecondTicks(true)
  render()
end

function update()
  -- openrgb --list-devices has no explicit "done" marker over runStream's
  -- line callback; treat a stretch of silence as finished so "Scanning..."
  -- never gets stuck if something goes wrong. Mirrors the STALL_MS check in
  -- claude_chat/panel.luau's update().
  if scanning and noctalia.nowMs() - scanLastLineMs >= DEVICE_SCAN_TIMEOUT_MS then
    scanning = false
    if #scanLines == 0 then
      deviceListText = "No OpenRGB devices found -- is the openrgb service running?"
    end
    render()
  end
end
