local addonName, ns = ...

-- Keeps a tally of one play session on a character (time, money in and
-- out, experience, quests, deaths, what was looted and gathered) and can
-- show it at any point, with the last few sessions for comparison.
--
-- A session belongs to one character. Logging back in, or reloading the
-- interface, within SESSION_GAP of the last activity carries on the same
-- session; after a longer break a new one starts.

local SESSION_GAP = 15 * 60
local HISTORY_SIZE = 10
-- Sessions shorter than this are not worth keeping in the history.
local MIN_KEPT_SECONDS = 120
local HEARTBEAT_SECONDS = 30

-- Gathering casts, by the name the game gives them, and what to call the
-- result. Confirmed names on this client: "Mining", "Skinning", and
-- "Herb Gathering" for picking herbs.
local GATHERS = {
    ["Mining"] = "ore",
    ["Herb Gathering"] = "herbs",
    ["Herbalism"] = "herbs",
    ["Skinning"] = "skins",
}
ns.GATHER_ORDER = { "ore", "herbs", "skins" }

local settingsDefaults = {
    -- Whether to say one line about the previous session at login.
    greet = true,
    minimapButton = true,
    minimapAngle = 4.4,
}

-- What the game has sent this login, for /session debug. Kept in memory
-- only: it explains a zero in the window without guessing.
local seen = { money = 0, moneyHidden = 0, loot = 0, lootHidden = 0, lootMatched = 0 }

function ns.Print(msg)
    print("|cffd9a066SessionRecap|r: " .. tostring(msg))
end

-- A value the client may withhold cannot be compared or added up.
local function Usable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end
ns.Usable = Usable

-- 12345 copper -> "1g 23s 45c"
function ns.Money(copper)
    copper = math.floor(math.abs(copper) + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

-- 3725 seconds -> "1 h 2 min"
function ns.Duration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds / 60) % 60
    if hours > 0 then
        return ("%d h %d min"):format(hours, minutes)
    elseif minutes > 0 then
        return ("%d min"):format(minutes)
    end
    return ("%d s"):format(seconds)
end

-- 1234567 -> "1,234,567"
function ns.Number(value)
    local text = tostring(math.floor(value + 0.5))
    local formatted, count = text, 0
    repeat
        formatted, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until count == 0
    return formatted
end

---------------------------------------------------------------------------
-- The session
---------------------------------------------------------------------------

local function NewSession()
    local now = time()
    return { start = now, last = now, earned = 0, spent = 0, xp = 0, levels = 0,
        quests = 0, deaths = 0, loot = {}, gathers = {} }
end

function ns.Seconds(session)
    return math.max(0, (session.last or session.start) - session.start)
end

-- Files the session that has ended in the history, if it was long enough
-- to mean anything, and begins a new one. Returns the one that ended.
function ns.StartNewSession()
    local char = ns.char
    local ended = char.current
    if ended and ns.Seconds(ended) >= MIN_KEPT_SECONDS then
        table.insert(char.history, 1, ended)
        for index = #char.history, HISTORY_SIZE + 1, -1 do
            char.history[index] = nil
        end
    else
        ended = nil
    end
    char.current = NewSession()
    return ended
end

-- What the game last reported, so each change can be measured.
local lastMoney, lastXP, lastXPMax, lastLevel

local function ReadBaselines()
    local money, xp, xpMax, level = GetMoney(), UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    lastMoney = Usable(money) and money or nil
    lastXP = Usable(xp) and xp or nil
    lastXPMax = Usable(xpMax) and xpMax or nil
    lastLevel = Usable(level) and level or nil
end

local function Touch()
    ns.char.current.last = time()
end

local handlers = {}

function handlers.PLAYER_MONEY()
    seen.money = seen.money + 1
    local money = GetMoney()
    if not Usable(money) then seen.moneyHidden = seen.moneyHidden + 1; return end
    if lastMoney then
        local change = money - lastMoney
        local session = ns.char.current
        if change > 0 then
            session.earned = session.earned + change
        else
            session.spent = session.spent - change
        end
    end
    lastMoney = money
end

function handlers.PLAYER_XP_UPDATE()
    local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if not Usable(xp) or not Usable(xpMax) or not Usable(level) then return end
    local session = ns.char.current
    if lastXP and lastXPMax and lastLevel then
        local gained
        if level > lastLevel then
            -- The rest of the old level, plus what is already in the new one.
            gained = (lastXPMax - lastXP) + xp
            session.levels = session.levels + (level - lastLevel)
        else
            gained = xp - lastXP
        end
        if gained > 0 then
            session.xp = session.xp + gained
        end
    end
    lastXP, lastXPMax, lastLevel = xp, xpMax, level
end
handlers.PLAYER_LEVEL_UP = handlers.PLAYER_XP_UPDATE

function handlers.QUEST_TURNED_IN()
    ns.char.current.quests = ns.char.current.quests + 1
end

function handlers.PLAYER_DEAD()
    ns.char.current.deaths = ns.char.current.deaths + 1
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if unit ~= "player" or not Usable(spellID) then return end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    local what = Usable(name) and GATHERS[name]
    if what then
        local gathers = ns.char.current.gathers
        gathers[what] = (gathers[what] or 0) + 1
    end
end

-- The chat lines for the player's own loot, turned into patterns. The
-- game's wording is in its own text table, so this follows its language.
local lootPatterns

local function BuildLootPatterns()
    lootPatterns = {}
    for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
        local text = _G[key]
        if type(text) == "string" then
            local pattern = text:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
            -- The game's "%s" and "%d" placeholders become captures.
            pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
            lootPatterns[#lootPatterns + 1] = "^" .. pattern .. "$"
        end
    end
end

function handlers.CHAT_MSG_LOOT(message)
    seen.loot = seen.loot + 1
    if not Usable(message) then seen.lootHidden = seen.lootHidden + 1; return end
    if not lootPatterns then BuildLootPatterns() end
    for _, pattern in ipairs(lootPatterns) do
        local item, count = message:match(pattern)
        if item then
            seen.lootMatched = seen.lootMatched + 1
            -- The item arrives as a link; its name is the part in brackets.
            local name = item:match("%[(.-)%]") or item
            local loot = ns.char.current.loot
            loot[name] = (loot[name] or 0) + (tonumber(count) or 1)
            return
        end
    end
    -- Not the player's own loot, or worded in a way the patterns miss.
    seen.lastUnmatched = message
end

-- Says what the game has sent this login, to explain an empty count.
local function PrintDebug()
    if not lootPatterns then BuildLootPatterns() end
    ns.Print(("Money changes seen: %d (%d hidden by the game). Money now: %s."):format(
        seen.money, seen.moneyHidden, Usable(GetMoney()) and ns.Money(GetMoney()) or "hidden"))
    ns.Print(("Loot lines seen: %d (%d hidden, %d counted). Loot patterns: %d."):format(
        seen.loot, seen.lootHidden, seen.lootMatched, #lootPatterns))
    if seen.lastUnmatched then
        ns.Print("Last loot line not counted: " .. seen.lastUnmatched)
    end
end

---------------------------------------------------------------------------
-- Reading a session back
---------------------------------------------------------------------------

-- The items looted most, as { name, count } pairs, most first.
function ns.TopLoot(session, limit)
    local list = {}
    for name, count in pairs(session.loot or {}) do
        list[#list + 1] = { name, count }
    end
    table.sort(list, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    for index = #list, (limit or #list) + 1, -1 do
        list[index] = nil
    end
    return list
end

-- "12 ore, 8 herbs", or nil if nothing was gathered.
function ns.GatherText(session)
    local parts = {}
    for _, what in ipairs(ns.GATHER_ORDER) do
        local count = session.gathers and session.gathers[what]
        if count and count > 0 then
            parts[#parts + 1] = count .. " " .. what
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- Experience per hour over the session, or nil when too little time has
-- passed for the figure to mean anything.
function ns.XPPerHour(session)
    local seconds = ns.Seconds(session)
    if seconds < 60 or session.xp <= 0 then return end
    return session.xp / seconds * 3600
end

-- One line summing a session up.
function ns.OneLine(session)
    local parts = { ns.Duration(ns.Seconds(session)) }
    local net = session.earned - session.spent
    if session.earned > 0 or session.spent > 0 then
        parts[#parts + 1] = (net >= 0 and "up " or "down ") .. ns.Money(net)
    end
    if session.xp > 0 then
        parts[#parts + 1] = ns.Number(session.xp) .. " experience"
    end
    if session.levels > 0 then
        parts[#parts + 1] = session.levels .. (session.levels == 1 and " level" or " levels")
    end
    if session.quests > 0 then
        parts[#parts + 1] = session.quests .. (session.quests == 1 and " quest" or " quests")
    end
    local gathered = ns.GatherText(session)
    if gathered then parts[#parts + 1] = gathered end
    return table.concat(parts, ", ")
end

local function PrintReport()
    local session = ns.char.current
    ns.Print("This session: " .. ns.OneLine(session) .. ".")
    if session.earned > 0 or session.spent > 0 then
        ns.Print(("Money: %s in, %s out."):format(ns.Money(session.earned), ns.Money(session.spent)))
    end
    local rate = ns.XPPerHour(session)
    if rate then
        ns.Print(("Experience: %s an hour."):format(ns.Number(rate)))
    end
    local top = ns.TopLoot(session, 5)
    if #top > 0 then
        local items = {}
        for _, entry in ipairs(top) do
            items[#items + 1] = entry[1] .. " x" .. entry[2]
        end
        ns.Print("Most looted: " .. table.concat(items, ", ") .. ".")
    end
    if session.deaths > 0 then
        ns.Print(("Deaths: %d."):format(session.deaths))
    end
end

SLASH_SESSIONRECAP1 = "/session"
SLASH_SESSIONRECAP2 = "/recap"
SlashCmdList.SESSIONRECAP = function(msg)
    local command = (msg or ""):lower():match("^%s*(%S*)")
    if command == "" then
        ns.ToggleWindow()
    elseif command == "report" then
        Touch()
        PrintReport()
    elseif command == "new" then
        ns.StartNewSession()
        ReadBaselines()
        ns.Print("Started a new session.")
        ns.RefreshWindow()
    elseif command == "button" then
        ns.db.minimapButton = not ns.db.minimapButton
        ns.UpdateMinimapButton()
        ns.Print("Minimap button " .. (ns.db.minimapButton and "shown." or "hidden."))
    elseif command == "debug" then
        PrintDebug()
    elseif command == "greet" then
        ns.db.greet = not ns.db.greet
        ns.Print("The line about your last session at login is " .. (ns.db.greet and "on." or "off."))
    else
        ns.Print("/session - open the session window")
        ns.Print("/session report - sum up this session in chat")
        ns.Print("/session new - start a new session now")
        ns.Print("/session greet - a line about your session when you log in, on or off")
        ns.Print("/session button - show or hide the minimap button")
        ns.Print("/session debug - what the game has reported this login")
    end
end

-- Entry in the minimap's addon list.
function SessionRecap_OnAddonCompartmentClick()
    ns.ToggleWindow()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        SessionRecapDB = SessionRecapDB or {}
        for key, value in pairs(settingsDefaults) do
            if SessionRecapDB[key] == nil then
                SessionRecapDB[key] = value
            end
        end
        ns.db = SessionRecapDB
        SessionRecapCharDB = SessionRecapCharDB or {}
        SessionRecapCharDB.history = SessionRecapCharDB.history or {}
        ns.char = SessionRecapCharDB
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not ns.char then return end

    if event == "PLAYER_LOGIN" then
        local current = ns.char.current
        local line
        if not current or time() - (current.last or current.start) > SESSION_GAP then
            local ended = ns.StartNewSession()
            if ended then
                line = "Last session: " .. ns.OneLine(ended) .. ". Starting a new one."
            else
                line = "Counting this session."
            end
        else
            -- Back within a few minutes: the same session carries on.
            Touch()
            line = "Carrying on this session, " .. ns.Duration(ns.Seconds(current)) .. " so far."
        end
        if ns.db.greet then
            ns.Print(line .. " Type /session to see it.")
        end
        ns.UpdateMinimapButton()
        ReadBaselines()
        -- Registering an event this client does not have throws.
        for name in pairs(handlers) do
            pcall(self.RegisterEvent, self, name)
        end
        -- Keeps the session's end time fresh even when nothing happens.
        C_Timer.NewTicker(HEARTBEAT_SECONDS, Touch)
        return
    end

    -- Keeping count must never put an error on screen.
    if pcall(handlers[event], ...) then
        Touch()
        ns.RefreshWindow()
    end
end)
