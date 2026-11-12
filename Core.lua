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

-- The release, from the TOC. Its own name: GK.version is the count of changes (GK.Changed), and was
-- this until 1.4.0 - the settings page and the help said "v" and that count.
GK.addonVersion = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
GK.TAG = "|cffc8281eGrudgekeeper|r"
local TAG = GK.TAG

-- Account settings; the settings page (Options.lua) says what each one does.
local defaults = {
    anyLetters = true,       -- letters at all; off, nothing arrives as one (Letters.lua: Add)
    letters = true,          -- kill orders your guildies post arrive as letters
    myLetters = true,        -- a letter for a kill that earns a title, and a death that posts an order
    keepLetters = false,     -- an unread letter waits by the icon until read; off, it fades after a while (Letters.lua)
    alertNear = true,        -- warn when the target of any open kill order is near, or a guildie sees them
    plateMarks = true,       -- a skull over anyone with an open order on them
    -- a screenshot when you fulfil an order: off to begin with, "ikke la screenshots være på ved default"
    -- (the owner, 2026-11-08). Defaults are written into the saved table, so an account that had it on
    -- keeps it on until the box is unticked.
    shotFulfil = false,
    shotEveryKill = false,   -- a screenshot at every kill
    share = true,            -- tell the guild your kills, deaths and score, and where targets are seen
    autoOrders = true,       -- your death to someone on a rampage or camping you posts a kill order (Guild.lua)
    sound = true,
    oldPortraits = true,     -- race faces from the old character-creation screen, not today's race icons (GK.SetPortrait);
                             -- on by default, whichever skin (the owner, 2026-11-11)
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
    shameSound = "auto",     -- and the sound it plays (GK.SoundChoices; "off" for none; "auto" until one is picked: GK.ShameSoundKey)
    nearSound = "kit:PVP_THROUGH_QUEUE", -- the sound of a target near, a Marked player or the watched guild (GK.NearSound)
    kudosGroup = false,      -- one friendly chat line when a Kudos player joins your group (chat: off, the owner doesn't read it)
    plateNotes = true,       -- a small dim mark on the nameplate of a player you have notes on
    guilds = {},             -- [guild key] = { board, orders, wanted, slain, feed, nextId } (Guild.lua)
    spreeMine = "splash",    -- your spree milestone: "off", "toast" or "splash" (Announce.lua)
    spreeGuild = "toast",    -- a guildie's spree milestone
    spreeEnded = "toast",    -- a spree of ours or a guildie's that an enemy ended
    spreeTormentor = "toast", -- one of the guild put an end to a tormentor
    announceWhenMine = "always",       -- when yours may come: "always", "noCombat", "noCombatInInstance" or "noInstance"
    announceWhenGuild = "noCombat",    -- the same for a guildie's; one held back waits, then comes in order
    spreeSounds = {},        -- [tier key, "ended" or "tormentor"] = a sound (GK.SoundChoices); none picked: Announce.lua's own
    looks = {},              -- [player key] = race file and sex, "Scourge3": their race's face on cards (Sightings.lua)
}
-- This character's own record.
local charDefaults = {
    points = 0, kills = 0, deaths = 0, assists = 0,
    streak = 0, bestStreak = 0,  -- kills since you last died to an enemy player, and the most ever
    spree = 0,               -- the same, counting only the kills worth points (GK.SpreeTier)
    done = 0, won = 0,           -- kill orders you fulfilled, and the bounties on them (copper)
    -- week = { id, p, k, d, a }: this week's score, made by GK.Week and started over at the weekly reset
    log = {},                -- newest first: { k = "K", "A" or "D", t, n, c, r, l, z, p, o, w (an assist's killer) }
    foes = {},               -- [key] = { n, c, r, l, k, d, a, last, lastKill, lastAssist, lastDeath, hits = { time, ... } }
    tracked = {},            -- [key] = { t, c, r, l }: enemies you track, yours alone (Sightings.lua, GK.Track)
    letters = {},            -- oldest first (Letters.lua)
    letterId = 0,
    -- pc, u, parts: this PC's mark on the record, whether it held a score before marks existed, and the
    -- other PCs' parts of the score (GK.ClaimPC, and Guild.lua's "One character, more than one PC")
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
GK.AVENGE_BONUS = 1      -- they killed a guildie in the last AVENGE_FOR seconds, before this fight began
GK.AVENGE_FOR = 15 * 60
GK.REPEATS = 2           -- the same player is worth points this many times a day, then nothing
GK.ASSIST_LESS = 1       -- an assist is worth this much less than the kill, and still at least 1
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

--- Points for one assist: the kill's, with no order bonus (the killer fulfils it), a little less. A
--- kill worth nothing (grey, or farmed) is an assist worth nothing.
function GK.AssistPoints(mine, theirs, killedToday, revenge, avenged)
    local p = GK.Points(mine, theirs, killedToday, false, revenge, avenged)
    if p > 0 then p = math.max(p - GK.ASSIST_LESS, 1) end
    return p
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
        w = { id = id, p = 0, k = 0, d = 0, a = 0 }
        GK.char.week = w
    end
    return w
end

--- This PC's mark on the character's record, made the first time it is loaded here. The record lives in
--- this PC's saved file only, so a second PC has a record - and a mark - of its own, and the guild adds
--- the two up (Guild.lua). u: the record held a score already when it got its mark, the score from before
--- marks existed - which an older client may have told the guild as a row of its own.
local MARK = "0123456789abcdefghijklmnopqrstuvwxyz"
function GK.ClaimPC(c)
    if type(c.parts) ~= "table" then c.parts = {} end
    if type(c.pc) == "string" and c.pc:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$") then return end
    local id = {}
    for i = 1, 6 do
        local n = math.random(#MARK)
        id[i] = MARK:sub(n, n)
    end
    c.pc = table.concat(id)
    c.u = ((c.points or 0) + (c.kills or 0) + (c.deaths or 0) + (c.assists or 0) > 0) or nil
    c.parts = {}
end

-- ---------------------------------------------------------------------------
-- Names, places, money
-- ---------------------------------------------------------------------------
--- For display: no realm of ours, and the surname only when the player shows surnames.
function GK.Show(key)
    if not key then return "?" end
    -- the screenshot mode (Shots.lua) puts a made-up name where yours would be
    local stand = GK.shotNames and GK.shotNames[key]
    if stand then return stand end
    -- First name and surname, never a realm: on Forever a realm is one of a server's internal ones
    -- ("CAMWOWEU5Realm2PvP"), which means nothing to anyone reading it ("nemesis viser spiller med
    -- realmnavn bak. det trengs ikke. bare fornavn etternavn", the owner, 2026-11-07). LIB.ShortName drops
    -- only our own realm; a guildie on another wrote the name with theirs. No name has a "-" in it.
    return LIB.ShortName(key:match("^(.-)%-[^%-]*$") or key)
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
    -- the first word up to a plain space: %S follows the locale, and under Latin-1 it ends a Cyrillic
    -- name at the 0xA0 inside "Р" (GK.Lower's note)
    local fa, fb = a:match("^[^ ]+"), b:match("^[^ ]+")
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

--- Is this, after a name's dash, a realm? The live servers' internal realms ("CAMWOWEU4Realm4PvP") and the
--- beta's ("ClassicBetaPvP2") carry digits or PvP/PvE; a surname is a plain word. Our own realm is one,
--- whatever it looks like.
local function LooksLikeRealm(s)
    return s == LIB.Realm() or s:find("%d") ~= nil or s:find("PvP", 1, true) ~= nil or s:find("PvE", 1, true) ~= nil
end

--- Any player's key in the one spelling Grudgekeeper keeps: name and surname, and our realm. Every
--- Forever character has a surname (DECISIONS.md, 2026-10-03), and a name is unique across the region,
--- so the realm part of a key tells nobody apart - but on the live servers it varied, and so the same
--- player had several keys:
---   - LibForever reads the surname of a player on another of the server's internal realms as the realm:
---     "Unc-Shark" for Unc Shark. Every Unc then lost their surname wherever a realm was cut off, and
---     a death to Unc Allayra went to Unc Shark (the owner, 2026-11-06). A dash followed by a plain
---     word is put back as the surname.
---   - a guildie on another realm writes everyone with THEIR realm ("Unc Shark-CAMWOWEU4Realm8PvP"), so
---     their kill orders never met the same enemy on our nameplates. The realm becomes ours.
--- A key whose name has no surname and a realm after it stays as it is: "Unc-<realm>" is a name we were
--- given without one (a death recap, an old record), and guessing which Unc it is would be worse.
function GK.PlayerKey(key)
    if type(key) ~= "string" then return key end
    local name, after = key:match("^(.-)%-([^%-]+)$")
    if not name or name == "" then return LIB.FullName(key) end
    if not name:find(" ", 1, true) and not LooksLikeRealm(after) then
        name = name .. " " .. after                    -- the surname, read as a realm
    end
    return name .. "-" .. LIB.Realm()
end

-- What was kept before GK.PlayerKey (0.1.0-beta2 and the live servers' first days) moves to its spelling
-- once: GK.db.keys and GK.char.keys say it has. A record that meets one already under the new key is
-- added into it where we know how (the counts of a foe, the tallies of the guild); anything else keeps
-- its old key rather than lose either.
local KEYS_VERSION = 1

local function MaxInto(into, from)
    for who, n in pairs(from or {}) do
        if type(n) == "number" and (into[who] or 0) < n then into[who] = n end
    end
end

local MERGE = {
    foes = function(a, b)
        a.k, a.d = (a.k or 0) + (b.k or 0), (a.d or 0) + (b.d or 0)
        a.last = math.max(a.last or 0, b.last or 0)
        if b.lastDeath and (a.lastDeath or 0) < b.lastDeath then a.lastDeath = b.lastDeath end
    end,
    wanted = function(a, b)
        a.victims = a.victims or {}
        MaxInto(a.victims, b.victims)
        a.last = math.max(a.last or 0, b.last or 0)
    end,
    slain = function(a, b)
        a.by = a.by or {}
        MaxInto(a.by, b.by)
        a.last = math.max(a.last or 0, b.last or 0)
    end,
}

--- Move a table keyed by players to the one spelling; merge(new, old) when both are there, else keep both.
local function Rekey(t, merge)
    if type(t) ~= "table" then return end
    local moves = {}
    for k in pairs(t) do
        local nk = type(k) == "string" and GK.PlayerKey(k) or k
        if nk ~= k then moves[#moves + 1] = { k, nk } end
    end
    for _, m in ipairs(moves) do
        local old, new = m[1], m[2]
        local v = t[old]
        if t[new] == nil then
            t[old], t[new] = nil, v
        elseif merge then
            merge(t[new], v)
            t[old] = nil
        end
    end
end

local function RekeyList(list, field)
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" and type(e[field]) == "string" then e[field] = GK.PlayerKey(e[field]) end
    end
end

--- Once, at login: every name Grudgekeeper keeps for another player, in GK.PlayerKey's spelling.
function GK.RekeyStores()
    if (GK.char.keys or 0) < KEYS_VERSION then
        Rekey(GK.char.foes, MERGE.foes)
        for key, f in pairs(GK.char.foes) do f.n = GK.Show(key) end
        RekeyList(GK.char.log, "n")
        RekeyList(GK.char.letters, "n")
        GK.char.keys = KEYS_VERSION
    end
    if (GK.db.keys or 0) < KEYS_VERSION then
        for _, g in pairs(GK.db.guilds) do
            Rekey(g.wanted, MERGE.wanted)
            Rekey(g.slain, MERGE.slain)
            Rekey(g.people)
            for key, p in pairs(g.people or {}) do
                if type(p) == "table" then p.n = key end
            end
            for _, o in pairs(g.orders or {}) do
                if type(o.n) == "string" then o.n = GK.PlayerKey(o.n) end
            end
            RekeyList(g.feed, "n")
        end
        GK.db.keys = KEYS_VERSION
    end
end

--- A unit's player in that spelling (LIB.UnitKey, made GK.PlayerKey's), or nil.
function GK.UnitKey(unit)
    local key = LIB.UnitKey(unit)
    return key and GK.PlayerKey(key) or nil
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

-- Spree tiers: the kill that makes a spree one of these numbers is a milestone. Grudgebound comes again at
-- every 5 after the last number. The key is the tier's art file name (Media/spree_<key>.tga).
GK.SPREE_TIERS = {
    { n = 3, key = "bloodied", name = "Bloodied" },
    { n = 5, key = "merciless", name = "Merciless" },
    { n = 7, key = "butcher", name = "Butcher" },
    { n = 10, key = "reaper", name = "Reaper" },
    { n = 15, key = "grudgebound", name = "Grudgebound" },
}

GK.SPREE_MIN = GK.SPREE_TIERS[1].n       -- the shortest spree that is one: below it nothing is told

--- The tier a spree of n is in (nil below the first), and whether n is the number that begins that tier.
local function TierFor(n)
    if type(n) ~= "number" then return nil end
    local tier
    for _, t in ipairs(GK.SPREE_TIERS) do
        if n >= t.n then tier = t end
    end
    if not tier then return nil end
    local last = GK.SPREE_TIERS[#GK.SPREE_TIERS]
    return tier, n == tier.n or (tier == last and n % 5 == 0)
end

--- The tier a spree of n is in now: its name and key, nil below the first tier.
function GK.SpreeTierOf(n)
    local tier = TierFor(n)
    if tier then return tier.name, tier.key end
end

--- The tier a spree of n begins, when n is a milestone: its name and key. nil for any other number.
function GK.SpreeTier(n)
    local tier, begins = TierFor(n)
    if tier and begins then return tier.name, tier.key end
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

-- GetCoinTextureString is not a global in Forever: it lives in C_CurrencyInfo. Called through pcall, plain
-- text when it isn't there. Looked up at each call - two table reads - so nothing is kept from before it was.
function GK.Coins(copper)
    local coinString = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
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

-- A sound you pick for a warning (a Shame player joining your group, 2026-11-08: "spille denne ... eller
-- andre lyder man kan velge i settings"). Keys: "off", "file:<ours>" for a file in Media, "kit:<name>" for
-- one of the game's own by its SOUNDKIT name (one this client lacks is left out), and "lsm:<name>" for a
-- sound another addon registered with LibSharedMedia - we embed no library, so those are there only when
-- something else has loaded it.
-- A file can be for one guild only, and then it is neither listed nor played anywhere else: "Måkke ta med
-- han" is a Norwegian clip, for the guild it was made for (the owner, 2026-11-09: "det burde nok ikke være
-- standard lyden med mindre du er medlem i yippyapp.. siden det er norskt", then "kankje bare yippyapp ahr
-- det som et valg i det hele tatt").
-- The war horn made for a target near and two God of War clips were taken out before 1.2.0 (the owner,
-- 2026-11-10: "ta de to ut. fjern warhorn"): a soundtrack's music has no place in a public package, and
-- the game's own sounds below say "warning" well enough.
local SOUND_FILES = {
    { "makke", "Måkke ta med han", "Interface\\AddOns\\Grudgekeeper\\Media\\makke.mp3", guild = "YippYapp" },
    -- the Grudgekeeper calling out each spree tier (ElevenLabs, 2026-11-12)
    { "voice_bloodied", "Voice: Bloodied", "Interface\\AddOns\\Grudgekeeper\\Media\\voice_bloodied.mp3" },
    { "voice_merciless", "Voice: Merciless", "Interface\\AddOns\\Grudgekeeper\\Media\\voice_merciless.mp3" },
    { "voice_butcher", "Voice: Butcher", "Interface\\AddOns\\Grudgekeeper\\Media\\voice_butcher.mp3" },
    { "voice_reaper", "Voice: Reaper", "Interface\\AddOns\\Grudgekeeper\\Media\\voice_reaper.mp3" },
    { "voice_grudgebound", "Voice: Grudgebound", "Interface\\AddOns\\Grudgekeeper\\Media\\voice_grudgebound.mp3" },
}
local CHIME = "kit:UI_RAID_BOSS_WHISPER_WARNING"

--- Whether one of our files is ours to offer: one for a guild only while we are in it (in any case), and
--- not while the client can't say which guild that is.
local function Offered(s)
    if not s.guild then return true end
    local mine = GetGuildInfo and GetGuildInfo("player")
    return type(mine) == "string" and not Secret(mine) and GK.SameGuild(mine, s.guild)
end
-- The game's own, named for where the game plays them. More of them, as LibSharedMedia brings no sounds
-- of its own ("legg til flere lyder fra libsharedmedia", the owner, 2026-11-10: its only one is None, and
-- the rest are other addons' files). Each has a file in Forever's live build 70790 (soundkitentry, by
-- the SoundKitConstants id); one this client lacks in SOUNDKIT is left out.
local SOUND_KITS = {
    { "PVP_THROUGH_QUEUE", "Battleground horn" },
    { "UI_GARRISON_TOAST_INVASION_ALERT", "Invasion alert" },
    { "RAID_WARNING", "Raid warning" },
    { "RAID_BOSS_EMOTE_WARNING", "Boss emote" },
    { "UI_RAID_BOSS_WHISPER_WARNING", "The chime" },
    { "IG_PVP_UPDATE", "PvP update" },
    { "IG_CREATURE_AGGRO_SELECT", "Hostile target" },
    { "GM_CHAT_WARNING", "GM warning" },
    { "MAP_PING", "Map ping" },
    { "READY_CHECK", "Ready check" },
    { "UI_BATTLEGROUND_COUNTDOWN_FINISHED", "Countdown" },
    { "ALARM_CLOCK_WARNING_1", "Alarm 1" },
    { "ALARM_CLOCK_WARNING_2", "Alarm 2" },
    { "ALARM_CLOCK_WARNING_3", "Alarm 3" },
    { "UI_RAID_BOSS_DEFEATED", "Boss defeated" },
    { "UI_PVP_HONOR_PRESTIGE_RANK_UP", "Rank up" },
    { "IG_PLAYER_INVITE", "Group invite" },
}

--- Whether a pick is one of ours that left the package: a file (the war horn, the God of War clips) or a
--- kit taken off the list (HARDCORE_DUEL, which plays nothing on Forever). Only our own: another addon's
--- sound may simply not be loaded yet at login.
local function Gone(pick)
    if type(pick) ~= "string" then return false end
    local kind, name = pick:match("^(%a+):(.+)$")
    local list = (kind == "file" and SOUND_FILES) or (kind == "kit" and SOUND_KITS)
    if not list then return false end
    for _, s in ipairs(list) do
        if s[1] == name then return false end
    end
    return true
end

--- A gone pick goes back to the default: it would play the chime, or nothing, under a dropdown showing
--- nothing picked.
function GK.ForgetGoneSounds(db)
    for field, default in pairs({ nearSound = defaults.nearSound, shameSound = defaults.shameSound }) do
        if Gone(db[field]) then db[field] = default end
    end
    for key, pick in pairs(type(db.spreeSounds) == "table" and db.spreeSounds or {}) do
        if Gone(pick) then db.spreeSounds[key] = nil end
    end
end

local function SharedMedia()
    if type(LibStub) ~= "table" then return nil end
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    return ok and type(lib) == "table" and type(lib.HashTable) == "function" and lib or nil
end

local function SharedSounds()
    local lsm = PlaySoundFile and SharedMedia()
    if not lsm then return nil end
    local ok, sounds = pcall(lsm.HashTable, lsm, "sound")
    return ok and type(sounds) == "table" and sounds or nil
end

--- Every sound there is to pick, { { key, label } }: none, ours, the game's, then other addons' by name.
function GK.SoundChoices()
    local list = { { "off", "None" } }
    for _, s in ipairs(SOUND_FILES) do
        if Offered(s) then list[#list + 1] = { "file:" .. s[1], s[2] } end
    end
    for _, s in ipairs(SOUND_KITS) do
        if SOUNDKIT and SOUNDKIT[s[1]] then list[#list + 1] = { "kit:" .. s[1], s[2] } end
    end
    local shared = SharedSounds()
    if shared then
        local names = {}
        for name in pairs(shared) do
            if type(name) == "string" and name ~= "None" then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do list[#list + 1] = { "lsm:" .. name, name } end
    end
    return list
end

--- Play a picked sound, whatever the Sounds setting says (the caller asks it). Returns true when the game
--- took it, false for none picked or one that can't be played - a file gone, a sound pack uninstalled.
function GK.PlayChoice(key)
    if type(key) ~= "string" then return false end
    local kind, name = key:match("^(%a+):(.+)$")
    local file
    if kind == "kit" then
        local id = SOUNDKIT and SOUNDKIT[name]
        if not id then return false end
        local ok, played = pcall(PlaySound, id, "Master")
        return ok and played ~= false
    elseif kind == "file" then
        for _, s in ipairs(SOUND_FILES) do
            if s[1] == name and Offered(s) then file = s[3] end
        end
    elseif kind == "lsm" then
        local shared = SharedSounds()
        file = shared and shared[name]
    end
    if not (file and PlaySoundFile) then return false end
    local ok, played = pcall(PlaySoundFile, file, "Master")
    return ok and played and true or false
end

--- The sound of a target near (and a Marked player, and the watched guild): the one picked, the chime when it
--- can't be played - a warning never goes silent because a file went missing - and nothing for None or with
--- Sounds off.
function GK.NearSound()
    if not (GK.db and GK.db.sound) then return end
    local key = GK.db.nearSound or defaults.nearSound
    if key == "off" then return end
    if not GK.PlayChoice(key) then GK.Sound("UI_RAID_BOSS_WHISPER_WARNING") end
end

--- The sound a Shame player joining plays: the one picked in the settings, and until one is ("auto") the
--- clip of a guild we are in, or the chime.
function GK.ShameSoundKey()
    local key = GK.db and GK.db.shameSound
    if type(key) == "string" and key ~= "auto" then return key end
    for _, s in ipairs(SOUND_FILES) do
        if s.guild and Offered(s) then return "file:" .. s[1] end
    end
    return CHIME
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
        g = { board = {}, orders = {}, wanted = {}, slain = {}, tormentors = {}, feed = {}, people = {}, nextId = 1 }
        GK.db.guilds[key] = g
    end
    if not g.slain then g.slain = {} end      -- a store from before the guild kept its tally
    if not g.tormentors then g.tormentors = {} end   -- and from before it counted who kills us
    -- the notes (Notes.lua), here from the start: made by the first read instead, an empty one turned up
    -- after the test panel had put the store back (smoke_grudgekeeper, 2026-11-05)
    if not g.people then g.people = {} end
    return g
end

-- Tormentors: an enemy who has killed 3 or more of the guild since any of us last killed them. Each client
-- counts from what it hears (our deaths, a guildie's D) and clears the count at any kill of theirs (ours, or
-- a guildie's K), so two clients that were offline at different times differ a little. That is fine.
local MAX_TORMENTORS = 200
local TORMENTOR_AT = 3

--- One more of the guild killed by this enemy. Their count after it. At most MAX_TORMENTORS enemies are
--- kept: when a new one comes to a full table, the one with the smallest count goes.
function GK.TormentorGrew(key)
    local t = GK.Store().tormentors
    if not t[key] then
        local n, least, leastKey = 0, nil, nil
        for k, v in pairs(t) do
            n = n + 1
            if not least or v < least then least, leastKey = v, k end
        end
        if n >= MAX_TORMENTORS and leastKey then t[leastKey] = nil end
    end
    t[key] = (t[key] or 0) + 1
    return t[key]
end

--- The count of guildies this enemy killed, when it was 3 or more, so the kill that ends it can be told; nil
--- otherwise. The count starts over either way (a count of 0 is no entry, which keeps the table small).
function GK.TormentorEnded(key)
    local t = GK.Store().tormentors
    local n = t[key]
    t[key] = nil
    return n and n >= TORMENTOR_AT and n or nil
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

--- The guild's leaderboard with you in it, best first: { { who, p, k, d, a, l, c, total, me } }. a is
--- nil for a guildie whose client sends no assists (the released one).
--- weekly: this week's score; a guildie whose last word was from another week has none this week,
--- and one with nothing this week isn't listed. total is all-time points either way (for the title).
-- Guildies under this level are left off the board: alts parked in a starting zone filled it with rows of
-- nothing ("leaderboard kan kanskje filtrere ut folk under lvl 10 elns?", the owner, 2026-11-07). Their
-- score is kept, and they are back on it at 10. A row that never said its level stays; you always do.
local BOARD_MIN_LEVEL = 10

function GK.Board(weekly)
    local list, me, week = {}, LIB.Me(), GK.WeekId()
    for who, r in pairs(GK.Store().board) do
        if who ~= me and (r.l or BOARD_MIN_LEVEL) >= BOARD_MIN_LEVEL then
            local p, k, d, a = r.p or 0, r.k or 0, r.d or 0, r.a
            if weekly then
                if r.wid == week then p, k, d, a = r.wp or 0, r.wk or 0, r.wd or 0, r.wa
                else p, k, d, a = 0, 0, 0, r.a and 0 end
            end
            if not weekly or p > 0 or k > 0 or d > 0 or (a or 0) > 0 then
                list[#list + 1] = { who = who, p = p, k = k, d = d, a = a, l = r.l, c = r.c, total = r.p or 0,
                    rf = r.rf, sx = r.sx }
            end
        end
    end
    local _, class = UnitClass("player")
    local _, raceFile = UnitRace("player")
    local c, w = GK.char, GK.Week()
    list[#list + 1] = { who = me or "?", p = weekly and w.p or c.points, k = weekly and w.k or c.kills,
        d = weekly and w.d or c.deaths, a = weekly and (w.a or 0) or (c.assists or 0), l = UnitLevel("player"), c = class, total = c.points, me = true,
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
    add(("%d points - %d kills, %d assists, %d deaths"):format(GK.char.points, GK.char.kills, GK.char.assists or 0,
        GK.char.deaths), 1, 1, 1)
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
    print(TAG .. " v" .. GK.addonVersion .. " commands:")
    print("  /grudge  - open the window: kill orders, the guild's leaderboard, your grudges")
    print("  /grudge post  - write a kill order on your target (no enemy targeted: it asks who)")
    print("  /grudge letters  - read your letters")
    print("  /grudge test  - four sample letters, to see what they look like")
    print("  /grudge notice  - show the letter icon to drag it where you want it (notice reset: back to start)")
    print("  /grudge spree  - show a sample spree splash and toast")
    print("  /grudge options  - open the settings")
    print("  /grudge guild  - officers: put an enemy guild on watch by its name")
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
    elseif cmd == "spree" then
        GK.AnnounceSample()           -- a sample splash and toast (Announce.lua)
    elseif cmd == "options" or cmd == "settings" then
        GK.OpenOptions()
    elseif cmd == "guild" then
        -- the guild on watch, typed in (Pick.lua): for an officer or the guild master, as on the ledger.
        -- Not "watch": that is the Shame list's word (NotesUI.lua)
        if GK.CanWatchGuild() then GK.OpenPicker("guild")
        else print(TAG .. ": only an officer or the guild master can put a guild on watch.") end
    elseif cmd == "debug meter" then
        GK.MeterProbe()               -- the game's damage meter after a fight (Kills.lua)
    elseif cmd == "debug" then
        if GK.OpenDebug then GK.OpenDebug() else GK.Debug() end
    elseif cmd == "shots" and GK.OpenShots then
        GK.OpenShots()                -- pictures for the store page, with a made-up guild (Shots.lua)
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
    if GK.LastAssistDebug then print("  last assist: " .. GK.LastAssistDebug()) end
    -- each PC's part of the score, this one's first by its mark (Guild.lua's "One character, more than one PC")
    if GK.MyPartsText then print(("  this PC %s; parts: %s"):format(tostring(GK.char.pc), GK.MyPartsText() or "none")) end
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

-- ---------------------------------------------------------------------------
-- Every alphabet a name is written in
-- ---------------------------------------------------------------------------
-- Friz Quadrata and Morpheus hold the Latin letters only, so a character named in Cyrillic was drawn as
-- nothing in our windows ("vi må ha support for russiske bokstaver ... fordi noen characters har slike
-- navn", the owner, 2026-11-07). The game's own fonts are families with one file per alphabet
-- (Blizzard_Fonts_Shared/GameFonts.xml), and ours are too: CreateFontFamily (FontDocumentation.lua) makes
-- one per face, size and flags, the first time it is asked for. Without it, the face alone.
local OTHER_ALPHABETS = {
    { "russian", { ["Fonts\\MORPHEUS.ttf"] = "Fonts\\MORPHEUS_CYR.ttf" }, "Fonts\\FRIZQT___CYR.TTF" },
    { "korean", {}, "Fonts\\2002.TTF" },
    { "simplifiedchinese", {}, "Fonts\\ARKai_T.ttf" },
    { "traditionalchinese", {}, "Fonts\\blei00d.TTF" },
}
local families, familyCount = {}, 0

local function Family(file, size, flags)
    if not CreateFontFamily then return nil end
    local id = file .. "|" .. size .. "|" .. flags
    local family = families[id]
    if family == nil then
        local members = { { alphabet = "roman", file = file, height = size, flags = flags } }
        for _, a in ipairs(OTHER_ALPHABETS) do
            members[#members + 1] = { alphabet = a[1], file = a[2][file] or a[3], height = size, flags = flags }
        end
        familyCount = familyCount + 1
        local ok, made = pcall(CreateFontFamily, "GrudgekeeperFont" .. familyCount, members)
        family = ok and made or false
        families[id] = family
    end
    return family or nil
end

--- A text's face and size, in a family that also writes Cyrillic, Korean and Chinese names; the face
--- alone on a client without font families.
function GK.SetFont(fs, file, size, flags)
    flags = flags or ""
    local family = Family(file, size, flags)
    if family then fs:SetFontObject(family) else fs:SetFont(file, size, flags) end
end

--- Lower case for the letters names are written in: a to z, the Latin-1 letters (Ø to ø) and Cyrillic (Ж
--- to ж). string.lower knows a to z only, so "ПЕТЯ" never found "Петя" - and under a Latin-1 locale it
--- lowers the lead byte of a UTF-8 letter too (0xD0 to 0xF0: the smoke test's Lua did), breaking it. So A
--- to Z by their bytes, never by the locale.
function GK.Lower(s)
    s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
    s = s:gsub("\195([\128-\158])", function(b) if b ~= "\151" then return "\195" .. string.char(b:byte() + 32) end end)
    s = s:gsub("\208([\144-\159])", function(b) return "\208" .. string.char(b:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(b) return "\209" .. string.char(b:byte() - 32) end)
    s = s:gsub("\208([\128-\143])", function(b) return "\209" .. string.char(b:byte() + 16) end)
    return s
end

--- A word with its first letter a capital, as the game writes a name: a to z, Latin-1 and Cyrillic.
function GK.UpperFirst(w)
    local a, b = w:byte(1, 2)
    if not a then return w end
    if a < 128 then return (w:gsub("^%l", string.upper)) end
    if a == 195 and b and b >= 160 and b <= 190 and b ~= 183 then return string.char(195, b - 32) .. w:sub(3) end
    if a == 208 and b and b >= 176 and b <= 191 then return string.char(208, b - 32) .. w:sub(3) end
    if a == 209 and b and b >= 128 and b <= 143 then return string.char(208, b + 32) .. w:sub(3) end
    if a == 209 and b and b >= 144 and b <= 159 then return string.char(208, b - 16) .. w:sub(3) end
    return w
end

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
    GK.SetFont(fs, font, size)
    fs:SetTextColor(colour[1], colour[2], colour[3])
    if look.shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

--- A flat colour from the skin: "stripe", "rule", or "blood" (GK.BLOOD), at alpha a or the skin's own.
function GK.Paint(tex, role, a)
    painted[tex] = { role, a }
    if role == "blood" then
        tex:SetColorTexture(GK.BLOOD[1], GK.BLOOD[2], GK.BLOOD[3], a or 1)
    else
        local c = GK.LOOK[role]
        tex:SetColorTexture(c[1], c[2], c[3], a or c[4])
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
    local fresh = GrudgekeeperDB == nil             -- a first install: no "what's new" (GK.DeliverNews)
    GK.db = LIB.PrepareDB(GrudgekeeperDB, defaults, nil, 1)
    GrudgekeeperDB = GK.db
    GK.UseLook(GK.db.look)
    GK.char = LIB.PrepareDB(GrudgekeeperCharDB, charDefaults, nil, 1)
    GrudgekeeperCharDB = GK.char
    -- Retired 2026-11-07, when taking an order went: the orders you took, and the warning for every
    -- order beside the one for yours (every order warns now). Gone from the saved files too.
    GK.char.accepted, GK.db.alertAll = nil, nil
    GK.ClaimPC(GK.char)
    GK.ForgetGoneSounds(GK.db)
    GK.RekeyStores()
    RegisterMinimap()
    GK.StartGuild()
    GK.StartSightings()
    GK.StartKills()
    GK.StartLetters(fresh)
    GK.StartMail()
    GK.StartSocial()
    GK.StartProfiles()
    GK.StartInspect()
    GK.StartMapPins()
    GK.RegisterOptions()
end)
