-- Bar widget: toggles the Claude Chat panel, and shows that a turn is in
-- flight (the panel publishes `busy` on the plugin state channel).
local PANEL = "tklas/claude_chat:chat"

local busy = false

local function paint()
  barWidget.setGlyph(busy and "dots" or "sparkles")
  barWidget.setTooltip(busy and "Claude is answering" or "Chat with Claude")
end

noctalia.state.watch("busy", function(value)
  busy = value == true
  paint()
end)

function update()
  noctalia.setUpdateInterval(60000)
  paint()
end

function onClick()
  noctalia.togglePanel(PANEL)
end
