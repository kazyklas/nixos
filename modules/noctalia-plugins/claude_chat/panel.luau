-- Claude Chat -- a chat panel for Noctalia.
--
-- Each turn writes the prompt to a file and streams
--   cat prompt | claude -p --output-format stream-json --include-partial-messages
-- through noctalia.runStream, appending text deltas to the open assistant
-- bubble. The session id from the CLI is reused with --resume, so the
-- conversation continues across turns (and across shell restarts, since the
-- transcript and session id are persisted in the plugin data dir).

local MAX_KEPT = 60 -- transcript entries kept in memory and on disk
local RENDER_INTERVAL_MS = 60 -- floor between re-renders while streaming
local STALL_MS = 180000 -- no output at all for this long = give up

local messages = {} -- { id, role = "user"|"assistant", text, failed, streaming }
local nextId = 1
local sessionId = nil
local current = nil -- the assistant entry being streamed into
local busy = false
local runSeq = 0
local activeRun = 0
local status = nil -- one short line above the composer
local draft = ""
local composerRev = 1
local scrollRev = 0
local lastRenderMs = 0
local lastActivityMs = 0
local renderPending = false
local loaded = false
local dataDir = nil

local render -- forward declaration; defined below

--==========================================================================
-- Config and small helpers
--==========================================================================

local function conf(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

-- Single-quote a value for /bin/sh. runStream only takes a command string,
-- so every dynamic value (paths, model names, the system prompt) goes
-- through this instead of being pasted in raw.
local function sq(value)
  return "'" .. string.gsub(tostring(value), "'", "'\\''") .. "'"
end

local function stateDir()
  if dataDir == nil then
    dataDir = noctalia.pluginDataDir()
  end
  return dataDir
end

local function publishBusy()
  noctalia.state.set("busy", busy)
end

--==========================================================================
-- Persistence
--==========================================================================

local function historyPath()
  local dir = stateDir()
  if dir == nil then
    return nil
  end
  return dir .. "/history.json"
end

local function saveHistory()
  local path = historyPath()
  if path == nil then
    return
  end

  local plain = {}
  for _, message in ipairs(messages) do
    table.insert(plain, { role = message.role, text = message.text, failed = message.failed == true })
  end

  local encoded = noctalia.json.encode({ session = sessionId, messages = plain })
  if encoded ~= nil then
    noctalia.writeFile(path, encoded)
  end
end

local function loadHistory()
  local path = historyPath()
  if path == nil or not noctalia.fileExists(path) then
    return
  end

  local raw = noctalia.readFile(path)
  if raw == nil then
    return
  end

  local data = noctalia.json.decode(raw)
  if type(data) ~= "table" then
    return
  end

  if type(data.session) == "string" and data.session ~= "" then
    sessionId = data.session
  end

  messages = {}
  if type(data.messages) == "table" then
    for _, message in ipairs(data.messages) do
      if type(message) == "table" and type(message.text) == "string"
          and (message.role == "user" or message.role == "assistant") then
        table.insert(messages, {
          id = nextId,
          role = message.role,
          text = message.text,
          failed = message.failed == true,
        })
        nextId = nextId + 1
      end
    end
  end
end

local function pushMessage(entry)
  entry.id = nextId
  nextId = nextId + 1
  table.insert(messages, entry)
  while #messages > MAX_KEPT do
    table.remove(messages, 1)
  end
  return entry
end

--==========================================================================
-- Rendering
--==========================================================================

local function scheduleRender()
  if noctalia.nowMs() - lastRenderMs >= RENDER_INTERVAL_MS then
    render()
  else
    renderPending = true
  end
end

local function copyMessage(message)
  if message.text == "" then
    return
  end
  if noctalia.copyToClipboard(message.text, "text/plain") then
    noctalia.notify("Claude Chat", "Message copied")
  end
end

local function turnNode(message)
  local isUser = message.role == "user"
  local accent = isUser and "on_surface_variant" or "primary"

  local body
  if message.failed then
    body = ui.label({ text = message.text, color = "error" })
  elseif message.streaming and message.text == "" then
    body = ui.label({ text = "...", color = "on_surface_variant" })
  elseif isUser or message.streaming then
    -- Plain text while streaming: re-parsing markdown on every delta is
    -- wasted work, and the finished message is re-rendered as markdown.
    body = ui.label({ text = message.text })
  else
    body = ui.markdown({ text = message.text })
  end

  local wrapped
  if isUser then
    wrapped = ui.column({ fill = "surface_variant/0.55", radius = 10, padding = 10 }, { body })
  else
    wrapped = ui.column({ paddingH = 2 }, { body })
  end

  return ui.column({ key = "turn-" .. tostring(message.id), gap = 4 }, {
    ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = isUser and "user" or "sparkles", size = 12, color = accent }),
      ui.label({ text = isUser and "You" or "Claude", fontSize = 11, fontWeight = "bold", color = accent }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({
        glyph = "copy",
        glyphSize = 11,
        variant = "ghost",
        controlSize = "sm",
        tooltip = "Copy",
        visible = message.text ~= "" and not message.streaming,
        onClick = function()
          copyMessage(message)
        end,
      }),
    }),
    wrapped,
  })
end

local function emptyStateNode()
  return ui.column({ gap = 6, padding = 24, align = "center" }, {
    ui.glyph({ name = "sparkles", size = 30, color = "primary/0.7" }),
    ui.label({ text = "Ask Claude anything", color = "on_surface_variant" }),
    ui.label({
      text = "Enter sends - Shift+Enter for a new line",
      fontSize = 11,
      color = "on_surface_variant/0.75",
    }),
  })
end

local newChat -- defined with the actions below
local submit
local stopRun

local function headerNode()
  local model = conf("model", "default")
  local subtitle = (model == "default") and "Claude Code" or ("Claude Code - " .. model)
  if conf("tools", "chat") ~= "chat" then
    subtitle = subtitle .. " - " .. conf("tools", "chat")
  end

  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "sparkles", size = 16, color = "primary" }),
    ui.column({ gap = 0 }, {
      ui.label({ text = "Claude", fontSize = 15, fontWeight = "bold" }),
      ui.label({ text = subtitle, fontSize = 10, color = "on_surface_variant" }),
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      glyph = "plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = "New conversation",
      onClick = function()
        newChat()
      end,
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

local function composerNode()
  return ui.row({ gap = 8, align = "end" }, {
    ui.input({
      key = "composer-" .. tostring(composerRev),
      value = draft,
      placeholder = "Message Claude...",
      multiline = true,
      submitOnEnter = true,
      focus = true,
      height = 76,
      flexGrow = 1,
      onChange = function(value)
        draft = value
      end,
      onSubmit = function(value)
        submit(value)
      end,
    }),
    ui.button({
      glyph = busy and "stop" or "send",
      variant = busy and "destructive" or "primary",
      tooltip = busy and "Stop streaming" or "Send",
      onClick = function()
        if busy then
          stopRun()
        else
          submit(draft)
        end
      end,
    }),
  })
end

render = function()
  lastRenderMs = noctalia.nowMs()
  renderPending = false

  local turns = {}
  for _, message in ipairs(messages) do
    table.insert(turns, turnNode(message))
  end
  if #turns == 0 then
    table.insert(turns, emptyStateNode())
  end

  local root = {
    headerNode(),
    ui.separator({}),
    ui.scroll({
      flexGrow = 1,
      gap = 14,
      stickToBottom = true,
      scrollToBottomRev = scrollRev,
    }, turns),
  }

  if status ~= nil then
    table.insert(root, ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = busy and "dots" or "info", size = 12, color = busy and "primary" or "on_surface_variant" }),
      ui.label({ text = status, fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
    }))
  end

  table.insert(root, composerNode())

  panel.render(ui.column({ gap = 10, padding = 14, flexGrow = 1 }, root))
end

--==========================================================================
-- Talking to the CLI
--==========================================================================

local function buildCommand(promptPath)
  local bin = conf("claude_bin", "claude")
  local workdir = noctalia.expandPath(conf("workdir", "~"))
  local args = " -p --output-format stream-json --include-partial-messages --verbose"

  local model = conf("model", "default")
  if model ~= "default" then
    args = args .. " --model " .. sq(model)
  end

  local mode = conf("tools", "chat")
  if mode == "read_only" then
    args = args .. " --restricted --tools " .. sq("Read,Glob,Grep,WebSearch") .. " --permission-prompts none"
  elseif mode == "agent" then
    args = args .. " --permission-mode bypassPermissions"
  else
    -- Chat only: no tools at all, and user/project settings are ignored.
    args = args .. " --restricted --tools '' --permission-prompts none"
  end

  local systemPrompt = conf("system_prompt", "")
  if systemPrompt ~= "" then
    args = args .. " --append-system-prompt " .. sq(systemPrompt)
  end

  if sessionId ~= nil then
    args = args .. " --resume " .. sq(sessionId)
  end

  return "cd " .. sq(workdir) .. " && cat " .. sq(promptPath) .. " | " .. sq(bin) .. args
end

local function toolNameFrom(message)
  if type(message.content) ~= "table" then
    return nil
  end
  for _, block in ipairs(message.content) do
    if type(block) == "table" and block.type == "tool_use" and type(block.name) == "string" then
      return block.name
    end
  end
  return nil
end

local function finishRun(assistant, event, promptPath)
  activeRun = 0
  busy = false
  status = nil
  assistant.streaming = false
  current = nil
  publishBusy()

  if event ~= nil and (event.subtype ~= "success" or event.is_error == true) then
    local detail = type(event.result) == "string" and event.result
      or ("claude ended with: " .. tostring(event.subtype))
    if assistant.text == "" then
      assistant.text = detail
      assistant.failed = true
    else
      status = detail
    end
  elseif event ~= nil and assistant.text == "" and type(event.result) == "string" then
    -- No deltas arrived (very short answers can skip them) -- use the result.
    assistant.text = event.result
  end

  scrollRev = scrollRev + 1
  render()
  saveHistory()

  if promptPath ~= nil then
    noctalia.removeFile(promptPath)
  end
end

local function handleLine(run, assistant, promptPath, line)
  if run ~= activeRun or type(line) ~= "string" or line == "" then
    return
  end

  lastActivityMs = noctalia.nowMs()

  local event = noctalia.json.decode(line)
  if type(event) ~= "table" then
    return
  end

  if type(event.session_id) == "string" and event.session_id ~= "" then
    sessionId = event.session_id
  end

  if event.type == "stream_event" and type(event.event) == "table" then
    local inner = event.event
    if inner.type == "content_block_delta" and type(inner.delta) == "table"
        and inner.delta.type == "text_delta" and type(inner.delta.text) == "string" then
      assistant.text = assistant.text .. inner.delta.text
      status = nil
      scheduleRender()
    elseif inner.type == "content_block_stop" then
      render()
    end
  elseif event.type == "assistant" and type(event.message) == "table" then
    local tool = toolNameFrom(event.message)
    if tool ~= nil then
      status = tool .. "..."
      render()
    end
  elseif event.type == "result" then
    finishRun(assistant, event, promptPath)
  end
end

--==========================================================================
-- Actions
--==========================================================================

submit = function(text)
  if busy then
    return
  end

  local body = noctalia.string.trim(text or draft or "")
  if body == "" then
    return
  end

  local dir = stateDir()
  if dir == nil then
    status = "Could not create the plugin data directory."
    render()
    return
  end

  runSeq = runSeq + 1
  local run = runSeq
  local promptPath = dir .. "/prompt-" .. tostring(run) .. ".txt"

  local written, writeError = noctalia.writeFile(promptPath, body)
  if not written then
    status = "Could not write the prompt: " .. tostring(writeError)
    render()
    return
  end

  activeRun = run
  busy = true
  status = "Claude is thinking..."
  draft = ""
  composerRev = composerRev + 1
  lastActivityMs = noctalia.nowMs()
  publishBusy()

  pushMessage({ role = "user", text = body })
  local assistant = pushMessage({ role = "assistant", text = "", streaming = true })
  current = assistant
  scrollRev = scrollRev + 1
  render()

  local started = noctalia.runStream(buildCommand(promptPath), function(line)
    handleLine(run, assistant, promptPath, line)
  end)

  if not started then
    assistant.text = "Could not start `" .. conf("claude_bin", "claude") .. "`. Is it on PATH?"
    assistant.failed = true
    finishRun(assistant, nil, promptPath)
  end
end

stopRun = function()
  if not busy then
    return
  end
  activeRun = 0
  busy = false
  publishBusy()
  if current ~= nil then
    current.streaming = false
    if current.text == "" then
      current.text = "Stopped."
      current.failed = true
    end
    current = nil
  end
  status = "Stopped. The claude process finishes on its own."
  render()
  saveHistory()
end

newChat = function()
  if busy then
    stopRun()
  end
  messages = {}
  sessionId = nil
  current = nil
  status = nil
  draft = ""
  composerRev = composerRev + 1
  scrollRev = scrollRev + 1
  render()
  saveHistory()
end

--==========================================================================
-- Lifecycle
--==========================================================================

function onOpen(context)
  if not loaded then
    loadHistory()
    loaded = true
  end

  -- A run that was still streaming when the panel closed, with nothing
  -- arriving since, is never going to finish -- clear it instead of
  -- reopening onto a dead spinner.
  if busy and noctalia.nowMs() - lastActivityMs > STALL_MS then
    if current ~= nil then
      current.streaming = false
      if current.text == "" then
        current.text = "No response from claude."
        current.failed = true
      end
      current = nil
    end
    activeRun = 0
    busy = false
    status = nil
    publishBusy()
  end

  if type(context) == "string" and context ~= "" then
    draft = context
    composerRev = composerRev + 1
  end

  panel.setWantsSecondTicks(true)
  scrollRev = scrollRev + 1
  render()
end

function update()
  if not busy then
    return
  end

  local now = noctalia.nowMs()
  if renderPending then
    render()
  end
  if now - lastActivityMs > STALL_MS then
    local assistant = current
    if assistant ~= nil then
      if assistant.text == "" then
        assistant.text = "No response from claude (timed out)."
        assistant.failed = true
      end
      finishRun(assistant, nil, nil)
    else
      busy = false
      publishBusy()
      render()
    end
  end
end

function onIpc(event, payload)
  if event == "ask" then
    submit(payload)
  elseif event == "new" then
    newChat()
  elseif event == "stop" then
    stopRun()
  end
end
