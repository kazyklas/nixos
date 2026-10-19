-- ARGB Sync -- bar widget and background worker.
--
-- This is the only place the sync logic actually runs: its update() tick
-- fires on a fixed interval (noctalia.setUpdateInterval) independent of
-- whether the panel is open, so lighting keeps following the wallpaper in
-- the background. The panel (panel.luau) only edits the same state file and
-- flips the shared `argb_enabled` / `argb_mode` pub-sub values -- it does
-- not run any sync logic itself.
--
-- Getting the palette: `noctalia theme <wallpaper> --dark|--light -o file`
-- regenerates the exact Material-You palette Noctalia itself derives from
-- the wallpaper (confirmed by running it by hand). We detect a change by
-- re-reading the wallpaper path and theme mode straight out of Noctalia's
-- own settings.toml on every tick -- cheap, and avoids depending on some
-- unrelated template (e.g. the Hyprland one) staying enabled.

local TICK_MS = 3000
local SETTINGS_PATH = "~/.local/state/noctalia/settings.toml"

local loaded = false
local enabled = false
local mode = "auto" -- "auto" | "manual"
local busyCmd = false -- one shell command in flight at a time

--==========================================================================
-- Small helpers (duplicated in panel.luau -- each entry is its own Lua
-- environment, same as claude_chat's panel.luau/widget.luau).
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

local function saveState(state)
  local encoded = noctalia.json.encode(state)
  if encoded ~= nil then
    noctalia.writeFile(dataPath(), encoded)
  end
end

--==========================================================================
-- Reading the active wallpaper + theme mode out of Noctalia's own settings
--==========================================================================

-- Tiny line scanner, not a general TOML parser: settings.toml's layout for
-- these two keys is simple and stable ([wallpaper.last].path,
-- [theme].mode), so a full parser would be pure overhead.
local function wallpaperAndMode()
  local path = noctalia.expandPath(SETTINGS_PATH)
  if not noctalia.fileExists(path) then
    return nil, nil
  end
  local text = noctalia.readFile(path)
  if type(text) ~= "string" then
    return nil, nil
  end

  local section = nil
  local wallpaperPath = nil
  local themeMode = nil
  for line in string.gmatch(text, "[^\n]+") do
    local sect = string.match(line, "^%[([%w%._]+)%]")
    if sect ~= nil then
      section = sect
    elseif section == "wallpaper.last" then
      local p = string.match(line, '^path%s*=%s*"(.-)"')
      if p ~= nil then
        wallpaperPath = p
      end
    elseif section == "theme" then
      local m = string.match(line, '^mode%s*=%s*"(.-)"')
      if m ~= nil then
        themeMode = m
      end
    end
  end
  return wallpaperPath, themeMode
end

--==========================================================================
-- Applying colors
--==========================================================================

local function paint()
  barWidget.setGlyph(enabled and "bulb" or "bulb-off")
  barWidget.setTooltip(enabled and "ARGB sync: on (click to turn off)" or "ARGB sync: off (click to turn on)")
end

noctalia.state.watch("argb_enabled", function(value)
  enabled = value == true
  paint()
end)
noctalia.state.watch("argb_mode", function(value)
  if type(value) == "string" then
    mode = value
  end
end)

local function pushColors(state)
  if busyCmd then
    return
  end

  local entries = {}
  for _, key in ipairs({ "primary", "secondary", "tertiary" }) do
    local slot = state.slots[key]
    if slot ~= nil and slot.active == true and type(slot.hex) == "string" and slot.hex ~= "" then
      table.insert(entries, { hex = slot.hex, device = slot.device or "" })
    end
  end
  if #entries == 0 then
    return
  end

  local payload = noctalia.json.encode(entries)
  if payload == nil then
    return
  end

  local bin = conf("argb_bin", "argb-sync")
  local host = conf("openrgb_host", "127.0.0.1")
  local port = conf("openrgb_port", "6742")

  local cmd = "OPENRGB_HOST=" .. sq(host) .. " OPENRGB_PORT=" .. sq(port)
    .. " " .. sq(bin) .. " " .. sq(payload)
    .. " >/dev/null 2>&1 && echo ok || echo fail"

  busyCmd = true
  noctalia.runStream(cmd, function(line)
    if line == "fail" then
      noctalia.notify("ARGB Sync", "Failed to apply colors -- is the OpenRGB server running?")
    end
    busyCmd = false
  end)
end

-- Turning the plugin off also turns the lights off, so the toggle has an
-- obvious physical effect instead of silently stopping a background
-- refresh while the hardware stays lit on a stale color.
local function pushOff()
  local bin = conf("argb_bin", "argb-sync")
  local host = conf("openrgb_host", "127.0.0.1")
  local port = conf("openrgb_port", "6742")
  local payload = noctalia.json.encode({ { hex = "#000000", device = "" } })

  local cmd = "OPENRGB_HOST=" .. sq(host) .. " OPENRGB_PORT=" .. sq(port)
    .. " " .. sq(bin) .. " " .. sq(payload)
    .. " >/dev/null 2>&1"
  noctalia.runStream(cmd, function() end)
end

local function refreshFromWallpaper(state)
  if busyCmd then
    return
  end

  local path, themeMode = wallpaperAndMode()
  if path == nil then
    return
  end
  if path == state.last_wallpaper and themeMode == state.last_theme_mode then
    return
  end

  local outFile = noctalia.pluginDataDir() .. "/palette.json"
  local darkFlag = (themeMode == "light") and "--light" or "--dark"
  local cmd = "noctalia theme " .. sq(path) .. " " .. darkFlag .. " -o " .. sq(outFile)
    .. " >/dev/null 2>&1 && echo ok || echo fail"

  busyCmd = true
  noctalia.runStream(cmd, function(line)
    busyCmd = false
    if line ~= "ok" then
      noctalia.notify("ARGB Sync", "Could not regenerate the palette from the wallpaper.")
      return
    end

    local raw = noctalia.readFile(outFile)
    local palette = raw ~= nil and noctalia.json.decode(raw) or nil
    if type(palette) ~= "table" then
      return
    end

    local fresh = loadState() -- re-load: the panel may have edited it since we started
    for _, key in ipairs({ "primary", "secondary", "tertiary" }) do
      if type(palette[key]) == "string" and fresh.slots[key] ~= nil then
        fresh.slots[key].hex = palette[key]
      end
    end
    fresh.last_wallpaper = path
    fresh.last_theme_mode = themeMode
    saveState(fresh)
    pushColors(fresh)
  end)
end

--==========================================================================
-- Lifecycle
--==========================================================================

function update()
  noctalia.setUpdateInterval(TICK_MS)

  if not loaded then
    local state = loadState()
    enabled = state.enabled == true
    mode = state.mode or "auto"
    noctalia.state.set("argb_enabled", enabled)
    noctalia.state.set("argb_mode", mode)
    loaded = true
    paint()
  end

  if not enabled then
    return
  end

  if mode == "auto" then
    refreshFromWallpaper(loadState())
  end
end

function onClick()
  enabled = not enabled
  local state = loadState()
  state.enabled = enabled
  saveState(state)
  noctalia.state.set("argb_enabled", enabled)
  paint()

  if enabled then
    if mode == "auto" then
      -- Force a re-check even if the wallpaper hasn't changed since we were
      -- last on, so turning sync back on always re-applies immediately.
      state.last_wallpaper = nil
      saveState(state)
      refreshFromWallpaper(state)
    else
      pushColors(state)
    end
  else
    pushOff()
  end
end
