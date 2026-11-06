-- Grudgekeeper - keep score of world PvP: who you killed, who killed you and how often, a guild
-- leaderboard, and kill orders with a bounty on them.
-- Forever closes the combat log to addons, so nothing here watches a fight. Three things the client
-- does hand us are enough:
--   PARTY_KILL         your killing blow (or your pet's), with the victim's GUID      (Kills.lua)
--   the death recap    the name of whoever landed the blow that killed you            (Kills.lua)
--   units you can see  nameplates, your target and your mouse: level, class, race    (Sightings.lua)
-- All three are open in the world and secret in instances and battlegrounds, so Grudgekeeper keeps
-- score of the open world only. The guild hears about it over the addon channel (Guild.lua), and
-- news arrives as a sealed scroll you open when you like (Letters.lua, Notice.lua) - never a popup.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

GK.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
GK.TAG = "|cffc8281eGrudgekeeper|r"
local TAG = GK.TAG

-- Account settings; the settings page (Options.lua) says what each one does.
local defaults = {
    letters = true,          -- kill orders your guildies post arrive as letters
    myLetters = true,        -- a letter for your own kills and deaths
    alertNear = true,        -- warn when the target of an order you accepted is near
    alertAll = false,        -- ...and for every open order, accepted or not
    plateMarks = true,       -- a skull over anyone with an open order on them
    shotFulfil = true,       -- a screenshot when you fulfil an order (the user asked for this one)
    shotEveryKill = false,   -- a screenshot at every kill
    share = true,            -- tell the guild your kills, deaths and score, and where targets are seen
    autoOrders = true,       -- your death to someone on a rampage or camping you posts a kill order (Guild.lua)
    sound = true,
    tooltip = true,          -- one line on an enemy player's tooltip: your history with them
    guildButton = true,      -- a small Grudgekeeper badge beside the guild window
    minimap = {},            -- LibDBIcon's own record: where the button sits, whether it is hidden
    mapPins = true,          -- where an order's target was last seen, on the world map
    unitMenu = true,         -- our lines in the game's right-click menu on a player: profile, and kill order on an enemy
    inspectTab = true,       -- a tab of ours on the game's Inspect window: a guildie's record, an enemy's poster
    sortBy = {},             -- [ledger page name] = the column heading its rows are sorted by (none: the page's own order)
    mineOnly = false,        -- whether the ledger's sortable pages list only the rows that are yours
    noteAlerts = false,      -- warn when a player on your Marked list is near
    watchNearby = false,     -- one chat line when a player on your Shame list is near
    watchGroup = true,       -- warn when a Shame list player joins your group
    kudosGroup = false,      -- one friendly chat line when a Kudos player joins your group (chat: off, the owner doesn't read it)
    plateNotes = true,       -- a small dim mark on the nameplate of a player you have notes on
    guilds = {},             -- [guild key] = { board, orders, wanted, slain, feed, nextId } (Guild.lua)
}
-- This character's own record.
local charDefaults = {
    points = 0, kills = 0, deaths = 0,
    streak = 0, bestStreak = 0,  -- kills since you last died to an enemy player, and the most ever
    done = 0, won = 0,           -- kill orders you fulfilled, and the bounties on them (copper)
    -- week = { id, p, k, d }: this week's score, made by GK.Week and started over at the weekly reset
    log = {},                -- newest first: { k = "K" or "D", t, n, c, r, l, z, p, o }
    foes = {},               -- [key] = { n, c, r, l, k, d, last, lastKill, lastDeath, hits = { time, ... } }
    accepted = {},           -- [order key] = true: orders you took
    letters = {},            -- oldest first (Letters.lua)
    letterId = 0,
}

-- ---------------------------------------------------------------------------
-- Values from the client and from other players
-- ---------------------------------------------------------------------------
--- A value the client keeps from us (identity in an instance, say). Anything that can't even be
--- asked about counts as secret.
local function Secret(v)
    if not issecretvalue then return false end
    local ok, s = pcall(issecretvalue, v)
    return (not ok) or (s and true or false)
end
GK.Secret = Secret

--- Text from another player or the client, safe to keep, show and send: no escape codes or control
--- characters (LIB.Sanitize), no ';' (our field separator), capped. nil when nothing is left.
function GK.Clean(s, n)
    if s == nil or Secret(s) then return nil end
    s = LIB.Sanitize(s, n or 48):gsub(";", ",")
    return s ~= "" and s or nil
end

function GK.ValidClass(c)
    return type(c) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c] and c or nil
end

--- 1-100, or -1 for a level the game shows as "??". nil for anything else.
function GK.ValidLevel(l)
    l = tonumber(l)
    if not l then return nil end
    if l == -1 then return -1 end
    if l < 1 or l > 100 or l ~= math.floor(l) then return nil end
    return l
end

-- Which race is on which side, by the client's file token ("Scourge" is Undead). A race on both sides
-- (Pandaren) is in neither list, and then only having SEEN the player as hostile decides.
local HORDE = { Orc = true, Scourge = true, Tauren = true, Troll = true, BloodElf = true, Goblin = true,
    Nightborne = true, HighmountainTauren = true, MagharOrc = true, ZandalariTroll = true, Vulpera = true }
local ALLIANCE = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true, Worgen = true,
    VoidElf = true, LightforgedDraenei = true, DarkIronDwarf = true, KulTiran = true, Mechagnome = true }

--- Is this race on the other side from us? nil when the race doesn't say.
function GK.EnemyRace(raceFile)
    local mine = UnitFactionGroup("player")
    local ours, theirs
    if mine == "Alliance" then ours, theirs = ALLIANCE, HORDE
    elseif mine == "Horde" then ours, theirs = HORDE, ALLIANCE
    else return nil end
    if theirs[raceFile] then return true end
    if ours[raceFile] then return false end
    return nil
end

-- ---------------------------------------------------------------------------
-- Points
-- ---------------------------------------------------------------------------
--- The level at and below which someone is grey to you: the game's own experience rule, the same
--- line classic honour drew between an honourable kill and none.
function GK.GreyLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    return level - 1 - math.floor(level / 5)
end

--- The colour the game gives their level beside yours. -1 is "??": far above you.
function GK.Con(mine, theirs)
    if not (mine and theirs) then return nil end
    if theirs == -1 then return "red" end
    local d = theirs - mine
    if d >= 5 then return "red" end
    if d >= 3 then return "orange" end
    if d >= -2 then return "yellow" end
    if theirs > GK.GreyLevel(mine) then return "green" end
    return "grey"
end

GK.POINTS = { grey = 0, green = 1, yellow = 2, orange = 3, red = 4 }
GK.UNKNOWN_POINTS = 1    -- a level we never saw: the least a real kill is worth
GK.ORDER_BONUS = 3       -- on top, for the kill that fulfils a kill order
GK.REVENGE_BONUS = 1     -- they killed you since you last killed them
GK.AVENGE_BONUS = 1      -- they killed a guildie in the last AVENGE_FOR seconds
GK.AVENGE_FOR = 15 * 60
GK.REPEATS = 2           -- the same player is worth points this many times a day, then nothing
GK.DAY = 24 * 3600

--- Points for one kill: by their level beside yours, plus revenge and avenging a guildie - nothing at
--- all once you have killed the same player REPEATS times today, so farming one player buys nothing,
--- bonuses included - and the order bonus on top. Returns the points and the colour.
function GK.Points(mine, theirs, killedToday, order, revenge, avenged)
    local con = GK.Con(mine, theirs)
    local p = con and GK.POINTS[con] or GK.UNKNOWN_POINTS
    if (killedToday or 0) >= GK.REPEATS then
        p = 0
    else
        if revenge then p = p + GK.REVENGE_BONUS end
        if avenged then p = p + GK.AVENGE_BONUS end
    end
    if order then p = p + GK.ORDER_BONUS end
    return p, con
end

-- Titles by all-time points: our own words, so nobody takes them for the game's honour ranks.
GK.TITLES = {
    { 0, "Unblooded" }, { 10, "Cutthroat" }, { 25, "Bloodhound" }, { 50, "Headhunter" },
    { 100, "Slayer" }, { 200, "Executioner" }, { 400, "Grudgebearer" }, { 800, "Dread Reaper" },
}

function GK.Title(points)
    local title = GK.TITLES[1][2]
    for _, row in ipairs(GK.TITLES) do
        if (points or 0) >= row[1] then title = row[2] end
    end
    return title
end

--- The week we're in, named by the time of the next weekly reset to the hour, so every client in
--- the guild names it the same. A client that can't say when the reset is counts weeks from 1970.
function GK.WeekId()
    local now = time()
    local get = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    local ok, secs = false, nil
    if get then ok, secs = pcall(get) end
    if ok and type(secs) == "number" and secs > 0 and not Secret(secs) then
        return math.floor((now + secs) / 3600 + 0.5)
    end
    return math.floor(now / (7 * GK.DAY))
end

--- This character's score this week, started over when the reset has passed.
function GK.Week()
    local id = GK.WeekId()
    local w = GK.char.week
    if type(w) ~= "table" or w.id ~= id then
        w = { id = id, p = 0, k = 0, d = 0 }
        GK.char.week = w
    end
    return w
end

-- ---------------------------------------------------------------------------
-- Names, places, money
-- ---------------------------------------------------------------------------
--- For display: no realm of ours, and the surname only when the player shows surnames.
function GK.Show(key)
    return key and LIB.ShortName(key) or "?"
end

--- "Name-Realm" from a name and a realm the client gave us (GetPlayerInfoByGUID).
function GK.KeyOf(name, realm)
    if type(name) ~= "string" or name == "" or Secret(name) then return nil end
    if type(realm) == "string" and realm ~= "" and not Secret(realm) then
        return name .. "-" .. LIB.NormalizeRealm(realm)
    end
    return LIB.FullName(name)
end

--- Two spellings of one character: the same, or the same first name where one of the two has no
--- surname - the death recap and GetPlayerInfoByGUID may leave a surname off that a unit's name has.
--- Only ever used to match a name to someone we SAW, never to merge two records we keep.
function GK.SameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    a = a:gsub("%-[^%-]*$", "")
    b = b:gsub("%-[^%-]*$", "")
    if a == b then return true end
    local fa, fb = a:match("^%S+"), b:match("^%S+")
    if fa ~= fb then return false end
    return a == fa or b == fb
end

--- A guildie's name as another client wrote it into a message, in OUR spelling of it. On Forever's live
--- servers one guild spans several of the server's internal realms (CAMWOWEU4Realm4PvP, ...Realm8PvP,
--- CAMWOWEU5Realm2PvP), and the client gives us every guildie WITHOUT a realm - the sender of an addon
--- message is "Edvard" - so we file them under our own realm. A name a guildie writes into a message is
--- filed the same way on THEIR side, under THEIR realm: Lars, on another realm, names Edvard's order
--- "Edvard-CAMWOWEU4Realm8PvP" and us "Vebjorn-CAMWOWEU4Realm8PvP". Guildhall found it in the game
--- (2026-11-06, GH.LocalKey). A name from the wire whose realm is not ours becomes ours - but only when
--- that spelling is someone we know (ourselves, a guildie we have heard or seen on the roster or the
--- board, or what known(spelling) says, for a record that only its owner can have made), and never when
--- the name as written is known already. The client can't tell two such names apart either: it shows
--- them without a realm.
function GK.LocalKey(full, known)
    if type(full) ~= "string" then return full end
    local me = LIB.Me()
    local function Known(k)
        return k == me or LIB.KnownGuildie(k) or GK.Store().board[k] ~= nil or (known ~= nil and known(k) == true)
    end
    if Known(full) then return full end
    local name = full:match("^(.-)%-[^%-]+$")
    if not name or name == "" then return full end
    local ours = name .. "-" .. LIB.Realm()
    if ours ~= full and Known(ours) then return ours end
    return full
end

--- "Level 35 Orc Rogue", from whatever we know.
function GK.Describe(l, c, r)
    local parts = {}
    if l then parts[#parts + 1] = l == -1 and "Level ??" or ("Level " .. l) end
    if r then parts[#parts + 1] = r end
    local cn = c and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]
    if cn then parts[#parts + 1] = cn end
    return table.concat(parts, " ")
end

-- Where we are is asked for at every nameplate that comes up, and only changes when we change area:
-- worked out once, and again when the client says the area changed.
local zoneNow, worldNow
local function PlaceChanged() zoneNow, worldNow = nil, nil end
LIB.On("PLAYER_ENTERING_WORLD", PlaceChanged)
LIB.On("ZONE_CHANGED_NEW_AREA", PlaceChanged)

function GK.Zone()
    if zoneNow == nil then
        zoneNow = GK.Clean((GetRealZoneText and GetRealZoneText()) or GetZoneText(), 40) or false
    end
    return zoneNow or nil
end

--- The open world: not a dungeon, raid or battleground, where the client hides who is who.
function GK.InWorld()
    if worldNow == nil then
        local inside = IsInInstance()
        worldNow = not inside
    end
    return worldNow
end

--- "20s", "1g 50s" - for chat and the wire. Letters draw coins with GK.Coins.
function GK.MoneyText(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
    return table.concat(out, " ")
end

-- GetCoinTextureString is not a global in Forever: it lives in C_CurrencyInfo. Resolved once, called
-- through pcall, plain text when it isn't there.
local coinString
function GK.Coins(copper)
    if coinString == nil then
        coinString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or false
    end
    if coinString then
        local ok, s = pcall(coinString, math.floor(tonumber(copper) or 0))
        if ok and type(s) == "string" then return s end
    end
    return GK.MoneyText(copper)
end

function GK.Sound(kit)
    if not (GK.db and GK.db.sound) then return end
    local id = SOUNDKIT and SOUNDKIT[kit]
    if id then pcall(PlaySound, id, "Master") end
end

--- Something changed that a window may show. Every guild message calls this, and at login they come
--- by the hundred, so the windows, the nameplate skulls and the mailbox button hear about it ONCE per
--- burst, a moment later, rather than once per message (each of them used to start its own timer per
--- message). GK.version counts every change at once, for anything that keeps an answer until the
--- data changes (the tooltip line).
local changePending = false
GK.version = 0
local function FireChanged()
    changePending = false
    LIB.Fire("GRUDGEKEEPER_CHANGED")
end
function GK.Changed()
    GK.version = GK.version + 1
    if changePending then return end
    changePending = true
    C_Timer.After(0.2, FireChanged)
end

-- ---------------------------------------------------------------------------
-- Our own record
-- ---------------------------------------------------------------------------
local MAX_FOES, MAX_LOG = 400, 200

--- The guild's shared store: the leaderboard, its kill orders, who is wanted, the feed. Guildless,
--- it is a store of your own. While the client hasn't said which guild yet (early at login) it is the
--- last one this character was in, so nothing lands in a store of its own for a minute.
function GK.Store()
    local key = LIB.GuildKey()
    if key then GK.char.guild = key elseif IsInGuild() then key = GK.char.guild end
    key = key or "-"
    local g = GK.db.guilds[key]
    if not g then
        g = { board = {}, orders = {}, wanted = {}, slain = {}, feed = {}, people = {}, nextId = 1 }
        GK.db.guilds[key] = g
    end
    if not g.slain then g.slain = {} end      -- a store from before the guild kept its tally
    -- the notes (Notes.lua), here from the start: made by the first read instead, an empty one turned up
    -- after the test panel had put the store back (smoke_grudgekeeper, 2026-11-05)
    if not g.people then g.people = {} end
    return g
end

--- Our record of one enemy player, made when first needed. At most MAX_FOES: the one met longest ago
--- goes first.
function GK.Foe(key, info)
    local foes = GK.char.foes
    local f = foes[key]
    if not f then
        f = { k = 0, d = 0, hits = {}, last = time() }
        foes[key] = f
        local n, oldest, oldKey = 0, nil, nil
        for k2, v in pairs(foes) do
            n = n + 1
            if k2 ~= key and (not oldest or (v.last or 0) < oldest) then oldest, oldKey = v.last or 0, k2 end
        end
        if n > MAX_FOES and oldKey then foes[oldKey] = nil end
    end
    if info then
        f.n = info.n or f.n
        f.c = info.c or f.c
        f.r = info.r or f.r
        f.l = info.l or f.l
    end
    f.last = time()
    return f
end

function GK.AddLog(e)
    local log = GK.char.log
    table.insert(log, 1, e)
    for i = #log, MAX_LOG + 1, -1 do log[i] = nil end
end

--- The one who has killed you most: key and record, or nil.
function GK.Nemesis()
    local best, bestKey
    for key, f in pairs(GK.char.foes) do
        if (f.d or 0) > 0 and (not best or f.d > best.d) then best, bestKey = f, key end
    end
    return bestKey, best
end

--- The guild's leaderboard with you in it, best first: { { who, p, k, d, l, c, total, me } }.
--- weekly: this week's score; a guildie whose last word was from another week has none this week,
--- and one with nothing this week isn't listed. total is all-time points either way (for the title).
function GK.Board(weekly)
    local list, me, week = {}, LIB.Me(), GK.WeekId()
    for who, r in pairs(GK.Store().board) do
        if who ~= me then
            local p, k, d = r.p or 0, r.k or 0, r.d or 0
            if weekly then
                if r.wid == week then p, k, d = r.wp or 0, r.wk or 0, r.wd or 0 else p, k, d = 0, 0, 0 end
            end
            if not weekly or p > 0 or k > 0 or d > 0 then
                list[#list + 1] = { who = who, p = p, k = k, d = d, l = r.l, c = r.c, total = r.p or 0,
                    rf = r.rf, sx = r.sx }
            end
        end
    end
    local _, class = UnitClass("player")
    local _, raceFile = UnitRace("player")
    local c, w = GK.char, GK.Week()
    list[#list + 1] = { who = me or "?", p = weekly and w.p or c.points, k = weekly and w.k or c.kills,
        d = weekly and w.d or c.deaths, l = UnitLevel("player"), c = class, total = c.points, me = true,
        rf = raceFile, sx = UnitSex("player") }
    table.sort(list, function(a, b)
        if a.p ~= b.p then return a.p > b.p end
        if a.k ~= b.k then return a.k > b.k end
        return a.who < b.who
    end)
    return list
end

--- Your place on the guild's board (this week's, with weekly), and how many are on it.
function GK.MyRank(weekly)
    local list = GK.Board(weekly)
    for i, r in ipairs(list) do
        if r.me then return i, #list end
    end
    return #list, #list
end

-- ---------------------------------------------------------------------------
-- Minimap button, addon compartment, slash command
-- ---------------------------------------------------------------------------
local function OnIconClick(button)
    if button == "RightButton" then GK.OpenOptions() else GK.ToggleWindow() end
end

local function TooltipLines(add)
    add(TAG)
    local rank, of = GK.MyRank()
    add(("%d points - %d kills, %d deaths"):format(GK.char.points, GK.char.kills, GK.char.deaths), 1, 1, 1)
    if of > 1 then add(("#%d of %d in the guild"):format(rank, of), 1, 0.82, 0) end
    local open = GK.OpenOrders and #GK.OpenOrders() or 0
    if open > 0 then add(("%d open kill order%s"):format(open, open == 1 and "" or "s"), 1, 0.5, 0.4) end
    add("Left-click: open Grudgekeeper", 0.8, 0.8, 0.8)
    add("Right-click: settings", 0.8, 0.8, 0.8)
end

function Grudgekeeper_OnAddonCompartmentClick(_, button) OnIconClick(button) end
function Grudgekeeper_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    TooltipLines(function(...) GameTooltip:AddLine(...) end)
    GameTooltip:Show()
end
function Grudgekeeper_OnAddonCompartmentLeave() GameTooltip:Hide() end

-- A minimap button of its own, straight through LibDBIcon: Grudgekeeper is not one of the YippYapp
-- addons, so it doesn't sit behind their shared button.
local ICON = "Interface\\AddOns\\Grudgekeeper\\Media\\minimap"
local function RegisterMinimap()
    local ldb, dbicon = LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
    if not (ldb and dbicon) then return end
    local obj = ldb:GetDataObjectByName("Grudgekeeper")
        or ldb:NewDataObject("Grudgekeeper", { type = "launcher", icon = ICON, label = "Grudgekeeper" })
    if not obj then return end
    obj.OnClick = function(_, button) OnIconClick(button) end
    obj.OnTooltipShow = function(tt) TooltipLines(function(...) tt:AddLine(...) end) end
    if not dbicon:IsRegistered("Grudgekeeper") then dbicon:Register("Grudgekeeper", obj, GK.db.minimap) end
end

function GK.SetMinimapShown(on)
    GK.db.minimap.hide = not on
    local dbicon = LibStub("LibDBIcon-1.0", true)
    if not dbicon then return end
    if on then dbicon:Show("Grudgekeeper") else dbicon:Hide("Grudgekeeper") end
end

local function Help()
    print(TAG .. " v" .. GK.version .. " commands:")
    print("  /grudge  - open the window: kill orders, the guild's leaderboard, your grudges")
    print("  /grudge post  - write a kill order on your target (no enemy targeted: it asks who)")
    print("  /grudge letters  - read your letters")
    print("  /grudge test  - four sample letters, to see what they look like")
    print("  /grudge notice  - show the letter icon to drag it where you want it (notice reset: back to start)")
    print("  /grudge options  - open the settings")
end

SLASH_GRUDGEKEEPER1 = "/grudge"
SLASH_GRUDGEKEEPER2 = "/grudgekeeper"
SlashCmdList.GRUDGEKEEPER = function(msg)
    local cmd = strtrim((msg or ""):lower())
    if cmd == "" then
        GK.ToggleWindow()
    elseif cmd == "orders" or cmd == "hitlist" then
        GK.OpenWindow(1)
    elseif cmd == "board" or cmd == "leaderboard" then
        GK.OpenWindow(2)
    elseif cmd == "post" then
        GK.PostOnTarget()
    elseif cmd == "letters" or cmd == "read" then
        GK.OpenLetters()
    elseif cmd == "test" then
        GK.SampleLetters()
    elseif cmd == "notice" or cmd == "notice reset" then
        GK.PlaceNotice(cmd == "notice reset")
    elseif cmd == "options" or cmd == "settings" then
        GK.OpenOptions()
    elseif cmd == "debug" then
        if GK.OpenDebug then GK.OpenDebug() else GK.Debug() end
    else
        Help()
    end
end

--- /grudge debug: what the addon can see right now, for telling us what this client allows.
function GK.Debug()
    local inside, kind = IsInInstance()
    print(("%s debug: faction %s, guild %s, in instance %s (%s)"):format(TAG, tostring(UnitFactionGroup("player")),
        tostring(LIB.GuildKey()), tostring(inside), tostring(kind)))
    if LIB.CommStats then
        local sent, received, refused = LIB.CommStats(GK.PREFIX)
        print(("  messages: %s sent, %s received, %s refused"):format(tostring(sent), tostring(received), tostring(refused)))
    end
    if GK.SeenCount then print(("  enemy players seen this session: %d"):format(GK.SeenCount())) end
    if GK.LastDeathDebug then print("  last death: " .. GK.LastDeathDebug()) end
    local s = GK.Store()
    local n = 0
    for _ in pairs(s.board) do n = n + 1 end
    print(("  board: %d guildies; open orders: %d"):format(n, GK.OpenOrders and #GK.OpenOrders() or 0))
end

-- ---------------------------------------------------------------------------
-- The two skins (GK.db.look): the Grudgekeeper's parchment, and the game's own classic dark panels in gold
-- and white, as Guild Grudge had them ("lage en classic stil som setter bakgrunner osv til classic
-- fargene og ikke parchments" - "vi vil ha 2 skins", the owner, 2026-11-06). They dress the windows in the
-- game's frame: the ledger, the note and the who-picker. The letters, the kill order's scroll and the
-- profile cards are the Grudgekeeper's own paper in both.
-- Whatever a skin dresses is drawn in GK.INK, GK.FADED or GK.BLOOD, through GK.Ink and GK.Paint, which
-- remember what they drew: a skin writes its colours into those three tables (every file holds the same
-- tables) and GK.SetLook draws it all again, then calls what GK.OnLook registered - a window's
-- background, its layout - so the switch needs no /reload.
--   title, titleScale: the face and size titles and names are set in (Morpheus on parchment; the game's
--   own Friz Quadrata, a little smaller, in classic). shadow: classic text has the game's drop shadow.
--   wash: the chosen, hovered and own rows' tint. stripe, rule: every other row, the ruled lines.
-- ---------------------------------------------------------------------------
GK.TITLE_FONT, GK.TEXT_FONT = "Fonts\\MORPHEUS.ttf", "Fonts\\FRIZQT__.TTF"
GK.LOOKS = {
    -- faded: 0.35/0.25/0.15 read too light on the toned parchment in a list (2026-11-06)
    parchment = { ink = { 0.2, 0.12, 0.05 }, faded = { 0.29, 0.2, 0.11 }, blood = { 0.47, 0.06, 0.04 },
        title = GK.TITLE_FONT, titleScale = 1, shadow = false, wash = { 0.6, 0.12, 0.05 },
        stripe = { 0.35, 0.2, 0.05, 0.07 }, rule = { 0.42, 0.33, 0.22, 0.6 } },
    classic = { ink = { 1, 1, 1 }, faded = { 0.66, 0.66, 0.66 }, blood = { 1, 0.82, 0 },
        title = GK.TEXT_FONT, titleScale = 0.85, shadow = true, wash = { 1, 0.82, 0 },
        stripe = { 1, 1, 1, 0.035 }, rule = { 0.62, 0.52, 0.32, 0.55 } },
}
GK.LOOK = GK.LOOKS.parchment
GK.INK, GK.FADED, GK.BLOOD = { 0.2, 0.12, 0.05 }, { 0.29, 0.2, 0.11 }, { 0.47, 0.06, 0.04 }

--- Put a skin's colours in place, without drawing anything again (at login, before any window is built).
function GK.UseLook(name)
    GK.LOOK = GK.LOOKS[name] or GK.LOOKS.parchment
    for i = 1, 3 do
        GK.INK[i], GK.FADED[i], GK.BLOOD[i] = GK.LOOK.ink[i], GK.LOOK.faded[i], GK.LOOK.blood[i]
    end
end

function GK.Classic() return GK.LOOK == GK.LOOKS.classic end

-- What GK.Ink and GK.Paint drew, to draw again in the other skin (weak: a thing let go is forgotten).
local inked = setmetatable({}, { __mode = "k" })
local painted = setmetatable({}, { __mode = "k" })
local onLook = {}

--- A text in a colour (GK.INK, GK.FADED, GK.BLOOD, or one of its own), in GK.TEXT_FONT or GK.TITLE_FONT
--- - which in classic is the game's own face, a little smaller.
function GK.Ink(fs, colour, font, size)
    inked[fs] = { colour, font, size }
    local look = GK.LOOK
    if font == GK.TITLE_FONT then
        font, size = look.title, math.floor(size * look.titleScale + 0.5)
    end
    fs:SetFont(font, size, "")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    if look.shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

--- A flat colour from the skin: "stripe", "rule", or "blood" (GK.BLOOD at alpha a).
function GK.Paint(tex, role, a)
    painted[tex] = { role, a }
    if role == "blood" then
        tex:SetColorTexture(GK.BLOOD[1], GK.BLOOD[2], GK.BLOOD[3], a or 1)
    else
        local c = GK.LOOK[role]
        tex:SetColorTexture(c[1], c[2], c[3], c[4])
    end
end

--- A row's tint in the skin's wash colour: the chosen row, a hovered one, your own.
function GK.Wash(tex, a)
    local c = GK.LOOK.wash
    tex:SetColorTexture(c[1], c[2], c[3], a)
end

--- fn() runs after every switch of skin: a window's background, its layout.
function GK.OnLook(fn) onLook[#onLook + 1] = fn end

--- Switch skin ("classic", or anything else for parchment) and draw everything again in it.
function GK.SetLook(name)
    GK.db.look = (name == "classic") and "classic" or nil
    GK.UseLook(GK.db.look)
    for fs, spec in pairs(inked) do GK.Ink(fs, spec[1], spec[2], spec[3]) end
    for tex, spec in pairs(painted) do GK.Paint(tex, spec[1], spec[2]) end
    for _, fn in ipairs(onLook) do fn() end
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
LIB.On("PLAYER_LOGIN", function()
    GK.db = LIB.PrepareDB(GrudgekeeperDB, defaults, nil, 1)
    GrudgekeeperDB = GK.db
    GK.UseLook(GK.db.look)
    GK.char = LIB.PrepareDB(GrudgekeeperCharDB, charDefaults, nil, 1)
    GrudgekeeperCharDB = GK.char
    RegisterMinimap()
    GK.StartGuild()
    GK.StartSightings()
    GK.StartKills()
    GK.StartLetters()
    GK.StartMail()
    GK.StartSocial()
    GK.StartProfiles()
    GK.StartInspect()
    GK.StartMapPins()
    GK.RegisterOptions()
end)
