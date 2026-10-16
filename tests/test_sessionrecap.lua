-- The game's side: one character, and the game's own wording for loot.
ME = { money = 10000, xp = 100, xpMax = 1000, level = 5 }
GetMoney = function() return ME.money end
UnitXP = function() return ME.xp end
UnitXPMax = function() return ME.xpMax end
UnitLevel = function() return ME.level end
GetXPExhaustion = function() return ME.rested end
-- Items: every item has the same made-up icon and is "uncommon" (green).
C_Item = {
    GetItemInfoInstant = function(link) return 123, "Trade Goods", "Metal", "", "icon-123" end,
    GetItemInfo = function(link) return "Copper Ore", link, 2 end,
    GetItemQualityColor = function(quality) return 0.12, 1, 0 end,
}
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
C_Spell = { GetSpellName = function(id)
    return ({ [1] = "Mining", [2] = "Herb Gathering", [3] = "Skinning", [4] = "Fireball" })[id]
end }
-- The fake clock the addon reads; tests move it forward.
local clock = 1800000000
time = function() return clock end
local function link(name) return "|cffffffff|Hitem:123::::::::5:::::|h[" .. name .. "]|h|r" end

local ns = LoadAddon(ADDON_DIR, "SessionRecap")
local function check(cond, what) if not cond then error("CHECK FAILED: " .. what, 2) end; io.write("pass  ", what, "\n") end

check(ns.Money(12345) == "1g 23s 45c" and ns.Duration(3725) == "1 h 2 min" and ns.Duration(45) == "45 s" and ns.Number(1234567) == "1,234,567", "money, time and numbers are written plainly")

Fire("PLAYER_LOGIN")
check(SessionRecapCharDB == nil, "before its settings load, nothing is tallied")
Fire("ADDON_LOADED", "SessionRecap"); Fire("PLAYER_LOGIN")
local s = ns.char.current
check(s and s.start == clock and s.earned == 0 and #ns.char.history == 0 and ns.db.greet, "logging in starts a session")

-- money
ME.money = 12500; Fire("PLAYER_MONEY")
ME.money = 12000; Fire("PLAYER_MONEY")
check(s.earned == 2500 and s.spent == 500, "money in and money out are tallied separately")

-- experience, including across a level
ME.xp = 400; Fire("PLAYER_XP_UPDATE")
check(s.xp == 300 and s.levels == 0, "experience gained is tallied")
ME.level, ME.xp, ME.xpMax = 6, 50, 1200; Fire("PLAYER_XP_UPDATE")
check(s.xp == 300 + 600 + 50 and s.levels == 1, "gaining a level counts the rest of the old level and the start of the new")
Fire("PLAYER_LEVEL_UP", 6)
check(s.levels == 1 and s.xp == 950, "and the level-up notice does not count it twice")

-- quests, deaths, gathering
Fire("QUEST_TURNED_IN", 100, 250, 0); Fire("QUEST_TURNED_IN", 101, 250, 0)
Fire("PLAYER_DEAD")
for _, id in ipairs({ 1, 1, 2, 3, 3, 3, 4 }) do Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", id) end
Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "cast", 1)
check(s.quests == 2 and s.deaths == 1, "quests handed in and deaths are counted")
check(s.gathers.ore == 2 and s.gathers.herbs == 1 and s.gathers.skins == 3 and ns.GatherText(s) == "2 ore, 1 herbs, 3 skins", "gathering casts are counted by kind, and only the player's own")

-- loot, read from the game's chat lines
Fire("CHAT_MSG_LOOT", "You receive loot: " .. link("Copper Ore") .. "x3.")
Fire("CHAT_MSG_LOOT", "You receive loot: " .. link("Copper Ore") .. ".")
Fire("CHAT_MSG_LOOT", "You receive item: " .. link("Light Leather") .. "x2.")
Fire("CHAT_MSG_LOOT", "Someone receives loot: " .. link("Epic Sword") .. ".")
Fire("CHAT_MSG_LOOT", "You receive loot: " .. link("Rough Stone") .. ".")
check(s.loot["Copper Ore"] == 4 and s.loot["Light Leather"] == 2 and s.loot["Rough Stone"] == 1 and s.loot["Epic Sword"] == nil, "your own loot is tallied by item, with stack sizes, and other people's is ignored")
local top = ns.TopLoot(s, 2)
check(#top == 2 and top[1][1] == "Copper Ore" and top[1][2] == 4 and top[2][1] == "Light Leather", "the most-looted list is in order and cut to length")

-- rates and the one-line summary
clock = clock + 1800
ME.money = 12100; Fire("PLAYER_MONEY")
check(ns.Seconds(s) == 1800 and ns.XPPerHour(s) == 1900, "experience per hour comes from the time played")
check(ns.OneLine(s) == "30 min, up 21s, 950 experience, 1 level, 2 quests, 2 ore, 1 herbs, 3 skins", "the one-line summary: " .. ns.OneLine(s))
SlashCmdList.SESSIONRECAP("report")
check(PRINTED[#PRINTED]:find("Deaths: 1.", 1, true) ~= nil, "/session report sums the session up in chat")

-- a value the game withholds
local SECRET = {}
issecretvalue = function(v) return v == SECRET end
local earnedBefore = s.earned
ME.money = SECRET; Fire("PLAYER_MONEY")
ME.money = 12100; Fire("PLAYER_MONEY")
check(s.earned == earnedBefore, "a value the game withholds for a moment is not counted as a change")

-- the window
SlashCmdList.SESSIONRECAP("")
check(SessionRecapWindow:IsShown(), "/session opens the window")
SessionRecapWindow.__scripts.OnUpdate(SessionRecapWindow, 1.5)
-- Money shows as coin pictures; reading them back as letters keeps the
-- checks readable: "26(silver coin)" in green reads "26s".
local function Plain(text)
    text = text:gsub("|TInterface\\MoneyFrame\\UI%-(%a)%a+Icon:0:0:2:0|t", function(c) return c:lower() end)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local texts, raw = {}, {}
for _, f in ipairs(Frames()) do
    if rawget(f, "__text") then texts[Plain(f.__text)] = f; raw[f.__text] = f end
end
check(texts["30 min"] and texts["26s"] and texts["5s"] and texts["+21s"] and texts["950"] and texts["1,900"] and texts["2 ore, 1 herbs, 3 skins"], "it shows the session's figures")
check(raw["|cff50d050+21|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t|r"] and raw["|cffff7060" .. "5|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t|r"], "money shows with coin pictures, money in green and money out red")
check(ns.CoinText(1234567) == "123|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 45|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 67|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t", "coins are written gold, silver, copper")
local ore = texts["Copper Ore"]
check(ore and texts["x4"] and texts["No earlier sessions on this character yet."], "and what was looted most")
check(ore.__color and math.abs(ore.__color[1] - 0.12) < 0.01 and ore.__color[2] == 1, "looted items are named in their quality colour")
local icons = {}
for _, f in ipairs(Frames()) do
    if rawget(f, "__texture") == "icon-123" and f.__shown ~= false then icons[#icons + 1] = f end
end
check(#icons >= 1, "and shown with their icon")
check(texts["Level 6:  50 / 1,200  (4%)"], "the level bar says how far through the level you are")
local pace = nil
for text in pairs(texts) do if text:find("^About .+ to level 7 at this pace$") then pace = text end end
check(pace ~= nil, "and how long the rest will take at this pace: " .. tostring(pace))
ME.rested = 300
SessionRecapWindow.__scripts.OnUpdate(SessionRecapWindow, 1.5)
local restedShown = false
for _, f in ipairs(Frames()) do
    if rawget(f, "__text") and Plain(f.__text) == "Level 6:  50 / 1,200  (4%)  300 rested" then restedShown = true end
end
check(restedShown, "rested experience is shown too")
ME.rested = nil

-- a quick relog carries on; a long break starts afresh
clock = clock + 300
local printedBefore = #PRINTED
Fire("PLAYER_LOGIN")
check(ns.char.current == s and #ns.char.history == 0, "logging back in within a few minutes carries on the same session")
check(#PRINTED == printedBefore + 1 and PRINTED[#PRINTED]:find("Carrying on this session, 35 min so far.", 1, true) ~= nil, "and says so in one line at login: " .. PRINTED[#PRINTED])
clock = clock + 3 * 3600
printedBefore = #PRINTED
Fire("PLAYER_LOGIN")
check(ns.char.current ~= s and #ns.char.history == 1 and ns.char.history[1] == s and ns.char.current.earned == 0, "after a long break a new session starts and the old one is kept")
check(#PRINTED == printedBefore + 1 and PRINTED[#PRINTED]:find("Last session: ", 1, true) ~= nil, "and one line about the last session is said at login")

-- starting a new one by hand; very short sessions are not kept
clock = clock + 30
SlashCmdList.SESSIONRECAP("new")
check(#ns.char.history == 1, "a session of a few seconds is not worth keeping")
clock = clock + 600; ME.money = 20000; Fire("PLAYER_MONEY")
for _, f in ipairs(Frames()) do
    local label = nil
    if f.__scripts.OnClick and f ~= SessionRecapWindow and f ~= SessionRecapMinimapButton then
        f.__scripts.OnClick(f)
    end
end
check(#ns.char.history == 2 and ns.char.history[1].earned == 7900, "the New session button files the session in progress")
SlashCmdList.SESSIONRECAP("")
check(SessionRecapWindow:IsShown(), "and the window can be opened again afterwards")
SessionRecapWindow.__scripts.OnUpdate(SessionRecapWindow, 1.5)

-- the history is capped
for i = 1, 14 do clock = clock + 600; Fire("PLAYER_MONEY"); SlashCmdList.SESSIONRECAP("new") end
check(#ns.char.history == 10, "only the last ten sessions are kept")

SlashCmdList.SESSIONRECAP("greet")
clock = clock + 600; Fire("PLAYER_MONEY"); clock = clock + 3 * 3600
printedBefore = #PRINTED
Fire("PLAYER_LOGIN")
check(#PRINTED == printedBefore and not ns.db.greet, "/session greet turns the login line off")
SessionRecap_OnAddonCompartmentClick()
SlashCmdList.SESSIONRECAP("help")

-- the minimap button
check(SessionRecapMinimapButton.__shown, "the minimap button shows by default")
local wasShown = SessionRecapWindow:IsShown()
SessionRecapMinimapButton.__scripts.OnClick(SessionRecapMinimapButton)
check(SessionRecapWindow:IsShown() ~= wasShown, "clicking it opens or closes the window")
SlashCmdList.SESSIONRECAP("button")
check(not SessionRecapMinimapButton.__shown and not ns.db.minimapButton, "/session button hides it")
SlashCmdList.SESSIONRECAP("button")
check(SessionRecapMinimapButton.__shown, "and shows it again")

-- /session debug explains what the game has sent
Fire("CHAT_MSG_LOOT", "Someone else receives loot: [Linen Cloth].")
printedBefore = #PRINTED
SlashCmdList.SESSIONRECAP("debug")
local said = table.concat(PRINTED, " | ", printedBefore + 1)
check(said:find("Money changes seen: ", 1, true) and said:find("Loot lines seen: ", 1, true) and said:find("Someone else receives loot", 1, true), "/session debug reports money and loot events, and the last loot line not counted: " .. said)

-- the game misbehaving must not leave an error on screen
UnitXP = function() error("something this client does differently") end
check(pcall(Fire, "PLAYER_XP_UPDATE"), "a surprise from the game while tallying does not raise an error")
