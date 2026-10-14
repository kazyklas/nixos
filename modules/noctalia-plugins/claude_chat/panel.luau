-- Claude Chat -- a chat panel for Noctalia.
--
-- Each turn writes the prompt to a file and streams
--   cat prompt | claude -p --output-format stream-json --include-partial-messages
-- through noctalia.runStream, appending text deltas to the open assistant
-- bubble.
--
-- Conversations are first class: the panel keeps a list of them in a sidebar,
-- each with its own Claude Code session id. Switching conversations switches
-- which session the next turn resumes, so several independent threads stay
-- alive side by side. Everything is persisted to the plugin data dir, so the
-- list survives a shell restart.

local MAX_CONVERSATIONS = 40 -- oldest conversations beyond this are dropped
local MAX_KEPT = 60 -- transcript entries kept per conversation
local MAX_TITLE = 28 -- characters shown in the sidebar
local RENDER_INTERVAL_MS = 60 -- floor between re-renders while streaming
local STALL_MS = 180000 -- no output at all for this long = give up
local SIDEBAR_WIDTH = 190

-- conversation: { id, title, session, updated, messages = { { id, role, text, failed, streaming } } }
local conversations = {}
local activeId = nil
local nextConvId = 1
local nextMessageId = 1

local current = nil -- the assistant entry being streamed into
local runConvId = nil -- conversation that turn belongs to
local busy = false
local runSeq = 0
local activeRun = 0
local status = nil -- one short line above the composer

local draft = ""
local composerRev = 1
local scrollRev = 0
local sidebarOpen = true
local renamingId = nil

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

local function firstLine(text)
  local collapsed = string.gsub(text, "%s+", " ")
  return noctalia.string.trim(collapsed)
end

local function truncate(text, limit)
  if utf8.len(text) == nil then
    -- Not valid UTF-8 (should not happen) -- fall back to bytes.
    if #text <= limit then
      return text
    end
    return string.sub(text, 1, limit) .. "..."
  end
  if utf8.len(text) <= limit then
    return text
  end
  return string.sub(text, 1, utf8.offset(text, limit) - 1) .. "..."
end

local function relativeTime(timestamp)
  if type(timestamp) ~= "number" then
    return ""
  end
  local delta = os.time() - timestamp
  if delta < 60 then
    return "just now"
  elseif delta < 3600 then
    return string.format("%dm ago", math.floor(delta / 60))
  elseif delta < 86400 then
    return string.format("%dh ago", math.floor(delta / 3600))
  elseif delta < 604800 then
    return string.format("%dd ago", math.floor(delta / 86400))
  end
  return noctalia.formatTime("{:%b %d}", timestamp)
end

--==========================================================================
-- Conversations
--==========================================================================

local function conversationById(id)
  for _, conversation in ipairs(conversations) do
    if conversation.id == id then
      return conversation
    end
  end
  return nil
end

local function active()
  return conversationById(activeId)
end

local function titleOf(conversation)
  if conversation.title ~= nil and conversation.title ~= "" then
    return conversation.title
  end
  for _, message in ipairs(conversation.messages) do
    if message.role == "user" and message.text ~= "" then
      return truncate(firstLine(message.text), MAX_TITLE)
    end
  end
  return "New chat"
end

local function sortConversations()
  table.sort(conversations, function(a, b)
    return (a.updated or 0) > (b.updated or 0)
  end)
end

local function createConversation()
  local conversation = {
    id = "c" .. tostring(nextConvId),
    title = nil,
    session = nil,
    updated = os.time(),
    messages = {},
  }
  nextConvId = nextConvId + 1
  table.insert(conversations, 1, conversation)
  while #conversations > MAX_CONVERSATIONS do
    table.remove(conversations)
  end
  activeId = conversation.id
  return conversation
end

local function ensureActive()
  local conversation = active()
  if conversation == nil then
    conversation = conversations[1]
    if conversation == nil then
      conversation = createConversation()
    end
    activeId = conversation.id
  end
  return conversation
end

local function pushMessage(conversation, entry)
  entry.id = nextMessageId
  nextMessageId = nextMessageId + 1
  table.insert(conversation.messages, entry)
  while #conversation.messages > MAX_KEPT do
    table.remove(conversation.messages, 1)
  end
  conversation.updated = os.time()
  return entry
end

--==========================================================================
-- Persistence
--==========================================================================

local function statePath()
  local dir = stateDir()
  if dir == nil then
    return nil
  end
  return dir .. "/conversations.json"
end

local function saveState()
  local path = statePath()
  if path == nil then
    return
  end

  local plain = {}
  for _, conversation in ipairs(conversations) do
    local messages = {}
    for _, message in ipairs(conversation.messages) do
      table.insert(messages, { role = message.role, text = message.text, failed = message.failed == true })
    end
    table.insert(plain, {
      id = conversation.id,
      title = conversation.title,
      session = conversation.session,
      updated = conversation.updated,
      messages = messages,
    })
  end

  local encoded = noctalia.json.encode({ active = activeId, next = nextConvId, conversations = plain })
  if encoded ~= nil then
    noctalia.writeFile(path, encoded)
  end
end

local function adoptConversation(raw)
  if type(raw) ~= "table" then
    return
  end

  local conversation = {
    id = "c" .. tostring(nextConvId),
    title = type(raw.title) == "string" and raw.title ~= "" and raw.title or nil,
    session = type(raw.session) == "string" and raw.session ~= "" and raw.session or nil,
    updated = type(raw.updated) == "number" and raw.updated or os.time(),
    messages = {},
  }
  if type(raw.id) == "string" and raw.id ~= "" then
    conversation.id = raw.id
  end
  nextConvId = nextConvId + 1

  if type(raw.messages) == "table" then
    for _, message in ipairs(raw.messages) do
      if type(message) == "table" and type(message.text) == "string"
          and (message.role == "user" or message.role == "assistant") then
        table.insert(conversation.messages, {
          id = nextMessageId,
          role = message.role,
          text = message.text,
          failed = message.failed == true,
        })
        nextMessageId = nextMessageId + 1
      end
    end
  end

  table.insert(conversations, conversation)
end

local function loadState()
  local dir = stateDir()
  if dir == nil then
    return
  end

  local path = dir .. "/conversations.json"
  if noctalia.fileExists(path) then
    local raw = noctalia.readFile(path)
    local data = raw ~= nil and noctalia.json.decode(raw) or nil
    if type(data) == "table" then
      if type(data.conversations) == "table" then
        for _, conversation in ipairs(data.conversations) do
          adoptConversation(conversation)
        end
      end
      if type(data.next) == "number" and data.next > nextConvId then
        nextConvId = math.floor(data.next)
      end
      if type(data.active) == "string" then
        activeId = data.active
      end
    end
  else
    -- Single-conversation layout written by v1.0 of this plugin.
    local legacy = dir .. "/history.json"
    if noctalia.fileExists(legacy) then
      local raw = noctalia.readFile(legacy)
      local data = raw ~= nil and noctalia.json.decode(raw) or nil
      if type(data) == "table" and type(data.messages) == "table" and #data.messages > 0 then
        adoptConversation({ session = data.session, messages = data.messages, updated = os.time() })
        noctalia.renameFile(legacy, legacy .. ".migrated")
      end
    end
  end

  sortConversations()
  ensureActive()
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

-- Defined with the actions further down.
local newChat
local submit
local stopRun
local switchTo
local commitRename

local function conversationRow(conversation)
  if renamingId == conversation.id then
    return ui.input({
      key = "rename-" .. conversation.id,
      value = titleOf(conversation),
      controlSize = "sm",
      focus = true,
      onSubmit = function(value)
        commitRename(conversation.id, value)
      end,
    })
  end

  local isActive = conversation.id == activeId
  local label = titleOf(conversation)
  if busy and runConvId == conversation.id then
    label = "* " .. label
  end

  return ui.button({
    key = "conv-" .. conversation.id,
    text = truncate(label, MAX_TITLE),
    contentAlign = "start",
    controlSize = "sm",
    variant = isActive and "secondary" or "ghost",
    selected = isActive,
    tooltip = string.format("%d messages - %s - right-click to rename or delete",
      #conversation.messages, relativeTime(conversation.updated)),
    onClick = function()
      switchTo(conversation.id)
    end,
    onRightClick = function()
      panel.openContextMenu({
        items = {
          { kind = "header", label = truncate(titleOf(conversation), MAX_TITLE) },
          { id = "rename", label = "Rename" },
          { kind = "separator" },
          { id = "delete", label = "Delete" },
        },
        onActivate = "onConversationMenu",
        context = conversation.id,
      })
    end,
  })
end

local function sidebarNode()
  local rows = {}
  for _, conversation in ipairs(conversations) do
    table.insert(rows, conversationRow(conversation))
  end

  return ui.column({ gap = 8, width = SIDEBAR_WIDTH }, {
    ui.button({
      text = "New chat",
      glyph = "plus",
      variant = "primary",
      controlSize = "sm",
      onClick = function()
        newChat()
      end,
    }),
    ui.label({
      text = string.format("%d conversation%s", #conversations, #conversations == 1 and "" or "s"),
      fontSize = 10,
      color = "on_surface_variant/0.8",
    }),
    ui.scroll({ flexGrow = 1, gap = 2 }, rows),
  })
end

local function headerNode()
  local model = conf("model", "default")
  local subtitle = (model == "default") and "Claude Code" or ("Claude Code - " .. model)
  if conf("tools", "chat") ~= "chat" then
    subtitle = subtitle .. " - " .. conf("tools", "chat")
  end

  local conversation = ensureActive()

  return ui.row({ gap = 8, align = "center" }, {
    ui.button({
      glyph = sidebarOpen and "layout-sidebar-left-collapse" or "menu-2",
      variant = "ghost",
      controlSize = "sm",
      tooltip = sidebarOpen and "Hide conversations" or "Show conversations",
      onClick = function()
        sidebarOpen = not sidebarOpen
        render()
      end,
    }),
    ui.column({ gap = 0, flexGrow = 1 }, {
      ui.label({ text = truncate(titleOf(conversation), 40), fontSize = 14, fontWeight = "bold" }),
      ui.label({ text = subtitle, fontSize = 10, color = "on_surface_variant" }),
    }),
    ui.button({
      glyph = "plus",
      variant = "ghost",
      controlSize = "sm",
      tooltip = "New conversation",
      visible = not sidebarOpen,
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

local function statusLine()
  if busy and runConvId ~= nil and runConvId ~= activeId then
    local other = conversationById(runConvId)
    local name = other ~= nil and truncate(titleOf(other), MAX_TITLE) or "another conversation"
    return "Answering in " .. name .. "..."
  end
  return status
end

local function chatColumnNode()
  local conversation = ensureActive()

  local turns = {}
  for _, message in ipairs(conversation.messages) do
    table.insert(turns, turnNode(message))
  end
  if #turns == 0 then
    table.insert(turns, emptyStateNode())
  end

  local children = {
    headerNode(),
    ui.separator({}),
    ui.scroll({
      flexGrow = 1,
      gap = 14,
      stickToBottom = true,
      scrollToBottomRev = scrollRev,
    }, turns),
  }

  local line = statusLine()
  if line ~= nil then
    table.insert(children, ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = busy and "dots" or "info", size = 12, color = busy and "primary" or "on_surface_variant" }),
      ui.label({ text = line, fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
    }))
  end

  table.insert(children, composerNode())

  return ui.column({ gap = 10, flexGrow = 1 }, children)
end

render = function()
  lastRenderMs = noctalia.nowMs()
  renderPending = false

  local root = {}
  if sidebarOpen then
    table.insert(root, sidebarNode())
    table.insert(root, ui.separator({ orientation = "vertical" }))
  end
  table.insert(root, chatColumnNode())

  panel.render(ui.row({ gap = 12, padding = 14, flexGrow = 1 }, root))
end

--==========================================================================
-- Talking to the CLI
--==========================================================================

local function buildCommand(promptPath, sessionId)
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

local function finishRun(conversation, assistant, event, promptPath)
  activeRun = 0
  busy = false
  runConvId = nil
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

  conversation.updated = os.time()
  sortConversations()
  scrollRev = scrollRev + 1
  render()
  saveState()

  if promptPath ~= nil then
    noctalia.removeFile(promptPath)
  end
end

local function handleLine(run, conversation, assistant, promptPath, line)
  if run ~= activeRun or type(line) ~= "string" or line == "" then
    return
  end

  lastActivityMs = noctalia.nowMs()

  local event = noctalia.json.decode(line)
  if type(event) ~= "table" then
    return
  end

  -- Every event carries the session id; keeping it on the conversation is
  -- what lets the next turn --resume this exact thread.
  if type(event.session_id) == "string" and event.session_id ~= "" then
    conversation.session = event.session_id
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
    finishRun(conversation, assistant, event, promptPath)
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

  local conversation = ensureActive()
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
  runConvId = conversation.id
  status = "Claude is thinking..."
  draft = ""
  composerRev = composerRev + 1
  renamingId = nil
  lastActivityMs = noctalia.nowMs()
  publishBusy()

  pushMessage(conversation, { role = "user", text = body })
  local assistant = pushMessage(conversation, { role = "assistant", text = "", streaming = true })
  current = assistant
  if conversation.title == nil then
    conversation.title = truncate(firstLine(body), MAX_TITLE)
  end
  sortConversations()
  scrollRev = scrollRev + 1
  render()

  local started = noctalia.runStream(buildCommand(promptPath, conversation.session), function(line)
    handleLine(run, conversation, assistant, promptPath, line)
  end)

  if not started then
    assistant.text = "Could not start `" .. conf("claude_bin", "claude") .. "`. Is it on PATH?"
    assistant.failed = true
    finishRun(conversation, assistant, nil, promptPath)
  end
end

stopRun = function()
  if not busy then
    return
  end
  activeRun = 0
  busy = false
  runConvId = nil
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
  saveState()
end

newChat = function()
  -- A pristine empty conversation is already a new chat; don't stack them up.
  local conversation = active()
  if conversation ~= nil and #conversation.messages == 0 and conversation.session == nil then
    renamingId = nil
    draft = ""
    composerRev = composerRev + 1
    render()
    return
  end

  createConversation()
  renamingId = nil
  status = nil
  draft = ""
  composerRev = composerRev + 1
  scrollRev = scrollRev + 1
  render()
  saveState()
end

switchTo = function(id)
  if id == activeId then
    return
  end
  if conversationById(id) == nil then
    return
  end
  activeId = id
  renamingId = nil
  status = nil
  draft = ""
  composerRev = composerRev + 1
  scrollRev = scrollRev + 1
  render()
  saveState()
end

commitRename = function(id, value)
  local conversation = conversationById(id)
  renamingId = nil
  if conversation ~= nil then
    local title = truncate(firstLine(value or ""), MAX_TITLE)
    conversation.title = title ~= "" and title or nil
    saveState()
  end
  render()
end

local function deleteConversation(id)
  local index = nil
  for position, conversation in ipairs(conversations) do
    if conversation.id == id then
      index = position
      break
    end
  end
  if index == nil then
    return
  end

  if busy and runConvId == id then
    stopRun()
  end

  table.remove(conversations, index)
  if renamingId == id then
    renamingId = nil
  end
  if activeId == id then
    activeId = nil
    draft = ""
    composerRev = composerRev + 1
  end
  ensureActive()
  scrollRev = scrollRev + 1
  render()
  saveState()
end

-- Context menus dispatch to a global callback by name.
function onConversationMenu(action, conversationId)
  if action == "rename" then
    renamingId = conversationId
    render()
  elseif action == "delete" then
    deleteConversation(conversationId)
  end
end

--==========================================================================
-- Lifecycle
--==========================================================================

function onOpen(context)
  if not loaded then
    loadState()
    loaded = true
  end
  ensureActive()

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
    runConvId = nil
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
    local conversation = runConvId ~= nil and conversationById(runConvId) or nil
    if assistant ~= nil and conversation ~= nil then
      if assistant.text == "" then
        assistant.text = "No response from claude (timed out)."
        assistant.failed = true
      end
      finishRun(conversation, assistant, nil, nil)
    else
      busy = false
      runConvId = nil
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
  elseif event == "switch" then
    switchTo(payload)
  end
end
