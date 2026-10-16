local addonName, ns = ...

-- The session window: this session's figures on the left, what was looted
-- most on the right, progress through the level across the middle, and the
-- last few sessions underneath. Drawn from plain colours and the game's own
-- textures, so it ships no image files. The window grows with its history.

local ACCENT_R, ACCENT_G, ACCENT_B = 0.85, 0.63, 0.40
local WIDTH = 560
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

local GREY = "|cff808080"
local window
local statValues, lootLabels, historyLabels = {}, {}, {}
local xpBar, restedBar, levelText, paceText
local historyTop

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
        if session.earned == 0 then return GREY .. "0|r" end
        return "|cff50d050" .. ns.CoinText(session.earned) .. "|r"
    elseif key == "spent" then
        if session.spent == 0 then return GREY .. "0|r" end
        return "|cffff7060" .. ns.CoinText(session.spent) .. "|r"
    elseif key == "net" then
        local net = session.earned - session.spent
        if net > 0 then return "|cff50d050+" .. ns.CoinText(net) .. "|r" end
        if net < 0 then return "|cffff5050-" .. ns.CoinText(net) .. "|r" end
        return GREY .. "0|r"
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

-- An item's icon and quality colour, from the link kept when it was looted.
-- Any of this can be missing (an item the game has not loaded yet, or a
-- session from before links were kept), so each step may give up.
local function ItemLook(link)
    if not link then return end
    local ok, icon, r, g, b = pcall(function()
        local _, _, _, _, itemIcon = C_Item.GetItemInfoInstant(link)
        local quality = select(3, C_Item.GetItemInfo(link))
        local qr, qg, qb
        if quality then qr, qg, qb = C_Item.GetItemQualityColor(quality) end
        return itemIcon, qr, qg, qb
    end)
    if ok then return icon, r, g, b end
end

-- Progress through the level, and how long the rest will take at this pace.
local function RefreshLevel(session)
    local ok, xp, xpMax, level, rested = pcall(function()
        return UnitXP("player"), UnitXPMax("player"), UnitLevel("player"), GetXPExhaustion and GetXPExhaustion()
    end)
    if not ok or not ns.Usable(xp) or not ns.Usable(xpMax) or not ns.Usable(level) then
        levelText:SetText("Level progress is not available right now.")
        paceText:SetText("")
        return
    end
    if xpMax <= 0 then
        xpBar:SetMinMaxValues(0, 1); xpBar:SetValue(1)
        restedBar:SetMinMaxValues(0, 1); restedBar:SetValue(0)
        levelText:SetText(("Level %d, the highest there is."):format(level))
        paceText:SetText("")
        return
    end
    xpBar:SetMinMaxValues(0, xpMax); xpBar:SetValue(xp)
    rested = ns.Usable(rested) and rested or 0
    restedBar:SetMinMaxValues(0, xpMax); restedBar:SetValue(math.min(xpMax, xp + rested))
    local text = ("Level %d:  %s / %s  (%d%%)"):format(level, ns.Number(xp), ns.Number(xpMax), math.floor(xp / xpMax * 100))
    if rested > 0 then
        text = text .. "  |cff60a0ff" .. ns.Number(rested) .. " rested|r"
    end
    levelText:SetText(text)
    local seconds = ns.TimeToLevel(session, xp, xpMax)
    if seconds then
        paceText:SetText(("About %s to level %d at this pace"):format(ns.Duration(seconds), level + 1))
    else
        paceText:SetText(GREY .. "Pace shows once you have earned some experience|r")
    end
end

local function Refresh()
    local session = ns.char.current
    for _, stat in ipairs(STATS) do
        statValues[stat.key]:SetText(StatText(stat.key, session))
    end

    local top = ns.TopLoot(session, LOOT_ROWS)
    for index = 1, LOOT_ROWS do
        local entry, row = top[index], lootLabels[index]
        if entry then
            local icon, r, g, b = ItemLook(session.lootLinks and session.lootLinks[entry[1]])
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:Show()
            row.name:SetText(entry[1])
            row.name:SetTextColor(r or 1, g or 1, b or 1)
            row.count:SetText("x" .. entry[2])
        else
            row.icon:Hide()
            row.name:SetText(index == 1 and (GREY .. "Nothing yet|r") or "")
            row.count:SetText("")
        end
    end

    RefreshLevel(session)

    local shown = 0
    for index = 1, HISTORY_ROWS do
        local past = ns.char.history[index]
        if past then shown = index end
        historyLabels[index]:SetText(past and (date("%d %b", past.start) .. ":  " .. ns.OneLine(past))
            or (index == 1 and (GREY .. "No earlier sessions on this character yet.|r") or ""))
    end
    -- The window ends just below the last line of history.
    window:SetHeight(-historyTop + 2 + math.max(shown, 1) * LINE + 16 + PADDING)
end

local function CreateWindow()
    window = CreateFrame("Frame", addonName .. "Window", UIParent)
    window:SetWidth(WIDTH)
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
        local icon = window:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", lootLeft, y + 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = Label(window, "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", lootLeft + 22, y)
        name:SetWidth(WIDTH - lootLeft - PADDING - 72)
        local count = Label(window, "GameFontHighlightSmall", "RIGHT")
        count:SetPoint("TOPRIGHT", -PADDING, y)
        count:SetTextColor(0.72, 0.72, 0.72)
        lootLabels[index] = { icon = icon, name = name, count = count }
    end

    -- Progress through the level: experience in purple over rested in blue,
    -- as on the game's own experience bar.
    local levelTop = top - 4 - (#STATS + 1) * LINE - 10
    Heading("LEVEL PROGRESS", PADDING, levelTop)
    restedBar = CreateFrame("StatusBar", nil, window)
    restedBar:SetPoint("TOPLEFT", PADDING, levelTop - 20)
    restedBar:SetPoint("TOPRIGHT", -PADDING, levelTop - 20)
    restedBar:SetHeight(12)
    restedBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    restedBar:SetStatusBarColor(0.0, 0.39, 0.88, 0.55)
    Fill(restedBar, 1, 1, 1, 0.06)
    Outline(restedBar, 0.4)
    -- A child is drawn above its parent, so experience covers rested.
    xpBar = CreateFrame("StatusBar", nil, restedBar)
    xpBar:SetAllPoints()
    xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    xpBar:SetStatusBarColor(0.58, 0.0, 0.55, 1)
    levelText = Label(window, "GameFontHighlightSmall")
    levelText:SetPoint("TOPLEFT", PADDING, levelTop - 38)
    paceText = Label(window, "GameFontHighlightSmall", "RIGHT")
    paceText:SetPoint("TOPRIGHT", -PADDING, levelTop - 38)
    paceText:SetTextColor(1, 0.9, 0.75)

    historyTop = levelTop - 64
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
