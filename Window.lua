local addonName, ns = ...

-- The session window: this session's figures on the left, what was looted
-- most on the right, and the last few sessions underneath. Drawn from plain
-- colours and lines, so it needs no texture files.

local ACCENT_R, ACCENT_G, ACCENT_B = 0.85, 0.63, 0.40
local WIDTH, HEIGHT = 560, 430
local HEADER_HEIGHT = 38
local PADDING = 14
local LINE = 20
local LOOT_ROWS, HISTORY_ROWS = 8, 5

-- The figures shown for the current session, top to bottom.
local STATS = {
    { key = "time", label = "Time played" },
    { key = "earned", label = "Money in" },
    { key = "spent", label = "Money out" },
    { key = "net", label = "Net" },
    { key = "xp", label = "Experience" },
    { key = "rate", label = "Per hour" },
    { key = "levels", label = "Levels gained" },
    { key = "quests", label = "Quests handed in" },
    { key = "gathered", label = "Gathered" },
    { key = "deaths", label = "Deaths" },
}

local window
local statValues, lootLabels, historyLabels = {}, {}, {}

local function Fill(frame, r, g, b, a)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function Outline(frame, alpha)
    local function Edge(point1, point2, isVertical)
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, alpha)
        edge:SetPoint(point1)
        edge:SetPoint(point2)
        if isVertical then edge:SetWidth(1) else edge:SetHeight(1) end
    end
    Edge("TOPLEFT", "TOPRIGHT", false)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", false)
    Edge("TOPLEFT", "BOTTOMLEFT", true)
    Edge("TOPRIGHT", "BOTTOMRIGHT", true)
end

local function Label(parent, font, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

local function Heading(text, x, y)
    local label = Label(window, "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    return label
end

-- What each figure reads for a session.
local function StatText(key, session)
    if key == "time" then
        return ns.Duration(ns.Seconds(session))
    elseif key == "earned" then
        return ns.Money(session.earned)
    elseif key == "spent" then
        return ns.Money(session.spent)
    elseif key == "net" then
        local net = session.earned - session.spent
        if net > 0 then return "|cff50d050+" .. ns.Money(net) .. "|r" end
        if net < 0 then return "|cffff5050-" .. ns.Money(net) .. "|r" end
        return ns.Money(0)
    elseif key == "xp" then
        return ns.Number(session.xp)
    elseif key == "rate" then
        local rate = ns.XPPerHour(session)
        return rate and ns.Number(rate) or "-"
    elseif key == "gathered" then
        return ns.GatherText(session) or "-"
    end
    return tostring(session[key] or 0)
end

local function Refresh()
    local session = ns.char.current
    for _, stat in ipairs(STATS) do
        statValues[stat.key]:SetText(StatText(stat.key, session))
    end

    local top = ns.TopLoot(session, LOOT_ROWS)
    for index = 1, LOOT_ROWS do
        local entry = top[index]
        lootLabels[index].name:SetText(entry and entry[1] or (index == 1 and "Nothing yet" or ""))
        lootLabels[index].count:SetText(entry and ("x" .. entry[2]) or "")
    end

    for index = 1, HISTORY_ROWS do
        local past = ns.char.history[index]
        historyLabels[index]:SetText(past and (date("%d %b", past.start) .. ":  " .. ns.OneLine(past))
            or (index == 1 and "No earlier sessions on this character yet." or ""))
    end
end

local function CreateWindow()
    window = CreateFrame("Frame", addonName .. "Window", UIParent)
    window:SetSize(WIDTH, HEIGHT)
    local position = ns.char.windowPosition
    if position then
        window:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    else
        window:SetPoint("CENTER")
    end
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:Hide()
    Fill(window, 0.05, 0.05, 0.06, 0.97)
    Outline(window, 0.55)
    -- Lets Escape close the window.
    tinsert(UISpecialFrames, addonName .. "Window")

    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        local point, _, relativePoint, x, y = window:GetPoint()
        ns.char.windowPosition = { point, relativePoint, x, y }
    end)
    Fill(header, 0.16, 0.12, 0.08, 1)
    local title = Label(header, "GameFontNormalLarge")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("SessionRecap")
    title:SetTextColor(1, 0.9, 0.75)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(HEADER_HEIGHT, HEADER_HEIGHT)
    close:SetPoint("RIGHT")
    local closeHover = close:CreateTexture(nil, "HIGHLIGHT")
    closeHover:SetAllPoints()
    closeHover:SetColorTexture(0.9, 0.2, 0.2, 0.45)
    -- The cross is two drawn strokes, so it needs no font glyph or texture.
    for _, direction in ipairs({ 1, -1 }) do
        local stroke = close:CreateLine(nil, "ARTWORK")
        stroke:SetThickness(2)
        stroke:SetColorTexture(0.9, 0.9, 0.9, 1)
        stroke:SetStartPoint("CENTER", close, -6, 6 * direction)
        stroke:SetEndPoint("CENTER", close, 6, -6 * direction)
    end
    close:SetScript("OnClick", function() window:Hide() end)

    -- Starts a fresh session; the one in progress goes to the history.
    local newButton = CreateFrame("Button", nil, header)
    newButton:SetSize(104, 24)
    newButton:SetPoint("RIGHT", close, "LEFT", -4, 0)
    Fill(newButton, 1, 1, 1, 0.07)
    Outline(newButton, 0.35)
    local newHover = newButton:CreateTexture(nil, "HIGHLIGHT")
    newHover:SetAllPoints()
    newHover:SetColorTexture(1, 1, 1, 0.12)
    local newLabel = Label(newButton, "GameFontHighlightSmall", "CENTER")
    newLabel:SetPoint("CENTER")
    newLabel:SetText("New session")
    newButton:SetScript("OnClick", function() SlashCmdList.SESSIONRECAP("new") end)

    local top = -(HEADER_HEIGHT + 14)
    Heading("THIS SESSION", PADDING, top)
    for index, stat in ipairs(STATS) do
        local y = top - 4 - index * LINE
        local name = Label(window, "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", PADDING, y)
        name:SetText(stat.label)
        name:SetTextColor(0.72, 0.72, 0.72)
        local value = Label(window, "GameFontHighlight", "RIGHT")
        value:SetPoint("TOPRIGHT", window, "TOPLEFT", 270, y)
        statValues[stat.key] = value
    end

    local lootLeft = 300
    Heading("MOST LOOTED", lootLeft, top)
    for index = 1, LOOT_ROWS do
        local y = top - 4 - index * LINE
        local name = Label(window, "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", lootLeft, y)
        name:SetWidth(WIDTH - lootLeft - PADDING - 50)
        local count = Label(window, "GameFontHighlightSmall", "RIGHT")
        count:SetPoint("TOPRIGHT", -PADDING, y)
        count:SetTextColor(0.72, 0.72, 0.72)
        lootLabels[index] = { name = name, count = count }
    end

    local historyTop = top - 4 - (#STATS + 1) * LINE - 10
    Heading("EARLIER SESSIONS", PADDING, historyTop)
    for index = 1, HISTORY_ROWS do
        local line = Label(window, "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", PADDING, historyTop - 2 - index * LINE)
        line:SetWidth(WIDTH - PADDING * 2)
        line:SetTextColor(0.8, 0.8, 0.8)
        historyLabels[index] = line
    end

    -- The clock keeps running while the window is open.
    local elapsedTotal = 0
    window:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 1 then return end
        elapsedTotal = 0
        ns.char.current.last = time()
        Refresh()
    end)
end

function ns.ToggleWindow()
    if not window then CreateWindow() end
    if window:IsShown() then
        window:Hide()
    else
        ns.char.current.last = time()
        Refresh()
        window:Show()
    end
end

-- Called when the tally changes.
function ns.RefreshWindow()
    if window and window:IsShown() then
        Refresh()
    end
end
