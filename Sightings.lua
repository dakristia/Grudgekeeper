-- Grudgekeeper - the enemy players we can see.
-- That is all an addon has on Forever: Spy read the combat log, which is closed. An enemy counts as
-- seen when their nameplate comes up (enemy nameplates have to be on), or you target or mouse over
-- them. What we saw - level, class, race, GUID - is kept for a while, because a kill or a death only
-- names someone, and the level has to come from having seen them.
-- Anyone with an open kill order on them gets a skull over their nameplate, and lights up the notice
-- scroll (Notice.lua) with a sound - never a popup. Nobody takes an order: every guildie is the hunter.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local Secret = GK.Secret

local SEEN_FOR = 15 * 60      -- what we saw of someone counts for this long
local MAX_SEEN = 300
local ALERT_GAP = 90          -- the same target warns you at most this often
local SHARE_GAP = 120         -- and is reported to the guild at most this often

local seen, byGuid, count = {}, {}, 0      -- [key] = { key, guid, c, r, rf, l, t, z }
local alerted, shared = {}, {}             -- [order key] = GetTime() of the last warning / report (and
                                           -- of the last time we noted where we stood)
local plates = {}                          -- nameplate units on screen

function GK.SeenCount() return count end

--- What we saw of someone lately, by GUID or key: { key, guid, c, r, rf, l, t, z } or nil.
function GK.Seen(key, guid)
    local s = (guid and byGuid[guid]) or (key and seen[key])
    if s and GetTime() - s.t <= SEEN_FOR then return s end
    return nil
end

--- Every enemy player we saw lately, the latest first: the records themselves ({ key, guid, c, r, rf, l,
--- t = GetTime(), z }), in a new list. For the who-picker, which asks once per keystroke at most.
function GK.SeenList()
    local out, now = {}, GetTime()
    for _, s in pairs(seen) do
        if now - s.t <= SEEN_FOR then out[#out + 1] = s end
    end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.key < b.key
    end)
    return out
end

--- The enemy player we saw lately under this name (the death recap's): the one whose name is exactly
--- it, else the one GK.SameName takes for it - a name with its surname left off on one side. nil, and
--- "several", when that is more than one player: "Unc" could be Unc Shark or Unc Allayra, and naming
--- the wrong one put a shaman's name on a hunter's Arcane Shot (2026-11-06). A death not counted is
--- better than a grudge against the wrong player.
function GK.SeenByName(name)
    local exact, loose, several
    local now = GetTime()
    for key, s in pairs(seen) do
        if now - s.t <= SEEN_FOR then
            local shown = s.shown or key
            if shown == name or key == name then
                if not exact or s.t > exact.t then exact = s end
            elseif GK.SameName(shown, name) then
                several = several or (loose ~= nil)
                if not loose or s.t > loose.t then loose = s end
            end
        end
    end
    if exact then return exact end
    if several then return nil, "several" end
    return loose
end

-- Over the cap: forget whoever we saw longest ago.
local function Forget()
    if count <= MAX_SEEN then return end
    local oldest, oldKey
    for k, v in pairs(seen) do
        if not oldest or v.t < oldest then oldest, oldKey = v.t, k end
    end
    if oldKey then
        local guid = seen[oldKey].guid
        if guid and byGuid[guid] == seen[oldKey] then byGuid[guid] = nil end
        seen[oldKey] = nil
        count = count - 1
    end
end

--- A player of the other faction. Anything the client keeps from us is "no".
local function Hostile(unit)
    if not UnitExists(unit) then return false end
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not ok or Secret(isPlayer) or not isPlayer then return false end
    local mine, theirs = UnitFactionGroup("player"), UnitFactionGroup(unit)
    if Secret(theirs) or not theirs or not mine or theirs == "Neutral" then return false end
    return theirs ~= mine
end
GK.Hostile = Hostile

local function GuidOf(unit)
    local guid = UnitGUID(unit)
    return (not Secret(guid) and type(guid) == "string") and guid or nil
end

--- Who an enemy player is, without the rest: key and GUID, or nil. For the paths that run often and
--- need nothing more (the nameplate skulls, the tooltip) - no table made per call.
function GK.UnitIdentity(unit)
    if not Hostile(unit) then return nil end
    local key = GK.UnitKey(unit)
    if not key then return nil end
    return key, GuidOf(unit)
end

--- What we know of a unit, if it is an enemy player we may know: { key, guid, c, r, rf, l }. A new
--- table each call: for the rare callers (writing a kill order), not for events.
function GK.ReadUnit(unit)
    local key, guid = GK.UnitIdentity(unit)
    if not key then return nil end
    local _, class = UnitClass(unit)
    local race, raceFile = UnitRace(unit)
    local level = UnitLevel(unit)
    return {
        key = key,
        guid = guid,
        c = not Secret(class) and GK.ValidClass(class) or nil,
        r = not Secret(race) and GK.Clean(race, 20) or nil,
        rf = not Secret(raceFile) and raceFile or nil,
        l = not Secret(level) and GK.ValidLevel(level) or nil,
    }
end

-- ---------------------------------------------------------------------------
-- What they look like
-- ---------------------------------------------------------------------------
-- Race and sex are all of a player's looks an addon can keep: their face is drawn from a unit and
-- nothing reads it back, so we show none (GK.MakePortrait's note). With those two a card shows their
-- race's face (raceicon128-*) instead of their class crest, after a reload too. Kept only for players the guild
-- has a record of, so not every nameplate in the world goes into the saved file, and written over at
-- the next look: the barber changes sex (the owner, 2026-11-07).
local MAX_LOOKS = 2000
local looksCount

--- A player the guild keeps a record of: a grudge, an order, a kill or death of the guild's, a note.
--- Exact keys only - this runs at every look.
local function Recorded(key, f, order)
    if f or order then return true end
    local s = GK.Store()
    return s.wanted[key] ~= nil or s.slain[key] ~= nil or (GK.Person and GK.Person(key, false)) ~= nil
end

--- Keep race and sex from what we saw of a player (s, a record of GK.See's). True once they are kept.
function GK.KeepLooks(key, s)
    local looks = GK.db and GK.db.looks
    if not (looks and type(key) == "string" and s and s.rf and s.sx) then return false end
    local v = s.rf .. s.sx
    if looks[key] == v then return true end
    if looks[key] == nil then
        if not looksCount then
            looksCount = 0
            for _ in pairs(looks) do looksCount = looksCount + 1 end
        end
        if looksCount >= MAX_LOOKS then
            looks[next(looks)] = nil        -- any one: the cap only stops a runaway, and a race's face is cheap to lose
        else
            looksCount = looksCount + 1
        end
    end
    looks[key] = v
    return true
end

--- What a portrait draws for a player: { key, rf, sx, c }. Race and sex from a look this session (an
--- old one still says what they look like), else a note's record, else the looks we kept. The saved
--- file is data: a value that isn't a race file and a sex is no face.
function GK.FaceOf(key, c)
    local rf, sx
    local s = type(key) == "string" and seen[key] or nil
    if s then rf, sx = s.rf, s.sx end
    if not (rf and sx) and type(key) == "string" then
        local p = GK.Person and GK.Person(key, false)
        if p and p.rf and p.sx then
            rf, sx = p.rf, p.sx
        else
            local v = GK.db and GK.db.looks and GK.db.looks[key]
            local a, b
            if type(v) == "string" then a, b = v:match("^(%a+)([23])$") end    -- not "x and match": that keeps one value
            if a and #a <= 20 then rf, sx = a, tonumber(b) end
        end
    end
    return { key = key, rf = rf, sx = sx, c = c or (s and s.c) or nil }
end

-- ---------------------------------------------------------------------------
-- Skulls on nameplates
-- ---------------------------------------------------------------------------
local marks = setmetatable({}, { __mode = "k" })   -- plate -> our skull on it (made once per plate)
local marked = {}                                  -- unit -> the plate its skull is on

local function PlateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and plate or nil
end

local function Unmark(unit)
    local plate = marked[unit]
    if plate and marks[plate] then marks[plate]:Hide() end
    marked[unit] = nil
end

local function Mark(unit)
    Unmark(unit)
    if not GK.db.plateMarks then return end
    local plate = PlateOf(unit)
    if not plate then return end
    local f = marks[plate]
    if not f then
        f = CreateFrame("Frame", nil, plate)
        f:SetSize(26, 26)
        f:EnableMouse(false)
        f:SetPoint("BOTTOM", plate, "TOP", 0, -6)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        -- The kill order's own seal, not a bare skull: the raid marker "skull" sits over nameplates too.
        f.tex:SetTexture("Interface\\AddOns\\Grudgekeeper\\Media\\mark")
        marks[plate] = f
    end
    f:SetFrameLevel((plate:GetFrameLevel() or 1) + 20)
    f:Show()
    marked[unit] = plate
end

-- Every plate on screen looked at again - but only when an order changed or the skulls were switched
-- on or off. It used to run on every change of any kind, a guildie's score included.
local marksVersion, marksSetting = -1, nil
local function RefreshMarks()
    local version, on = GK.OrdersVersion(), GK.db.plateMarks
    if version == marksVersion and on == marksSetting then return end
    marksVersion, marksSetting = version, on
    local world = GK.InWorld()
    for unit in pairs(plates) do
        local key, guid
        if world then key, guid = GK.UnitIdentity(unit) end
        if key and GK.OrderOn(key, guid) then Mark(unit) else Unmark(unit) end
    end
end

-- ---------------------------------------------------------------------------
-- Seeing someone
-- ---------------------------------------------------------------------------
-- Someone of a watched guild in sight (Notes.lua, GK.WatchGuild): one warning a minute per guild, and it
-- names everyone of theirs who came up in the moment before it - a group's nameplates come at once, and
-- five warnings for one group would be four too many.
local GUILD_GAP = 60          -- the same guild warns you at most this often
local GUILD_GATHER = 2        -- seconds to wait for the rest of a group before warning
local guildNear = {}          -- [guild] = { at = GetTime() of the last warning, due, who = { [key] = GetTime() } }

--- "A", "A and B", "A, B and C", "A, B, C and 2 more".
local function NameList(names)
    local n = #names
    if n <= 1 then return names[1] or "" end
    if n <= 3 then return table.concat(names, ", ", 1, n - 1) .. " and " .. names[n] end
    return ("%s and %d more"):format(table.concat(names, ", ", 1, 3), n - 3)
end

local function GuildNear(guild, key)
    local now = GetTime()
    local g = guildNear[guild]
    if not g then
        g = { who = {} }
        guildNear[guild] = g
    end
    g.who[key] = now
    if g.due or (g.at and now - g.at < GUILD_GAP) then return end
    g.due = true
    C_Timer.After(GUILD_GATHER, function()
        g.due, g.at = false, GetTime()
        local names = {}
        for k, t in pairs(g.who) do
            if g.at - t <= GUILD_GATHER + 1 then names[#names + 1] = GK.Show(k) end
        end
        g.who = {}
        table.sort(names)
        if #names > 0 and GK.IsGuildWatched(guild) then
            GK.Warn(("<%s> near: %s"):format(guild, NameList(names)), true, nil, nil, "<" .. guild .. ">")
        end
    end)
end

--- Who of this guild we saw lately, the latest first: { key, z, t = GetTime() } records, at most `most`.
function GK.GuildSeen(guild, most)
    local out, now = {}, GetTime()
    for _, s in pairs(seen) do
        if GK.SameGuild(s.g, guild) and now - s.t <= SEEN_FOR then out[#out + 1] = s end
    end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.key < b.key
    end)
    for i = #out, (most or #out) + 1, -1 do out[i] = nil end
    return out
end

-- ---------------------------------------------------------------------------
-- The target of an open order is in sight: warn, and tell the guild where. Every order, whoever posted
-- it: there is no taking an order any more - "hey, we put out an order, kill this one" is the whole of
-- it (the owner, 2026-11-07). Before, only orders you took or posted warned you.
local function Spotted(order, s)
    local now = GetTime()
    if GK.db.alertNear then
        if not alerted[order.key] or now - alerted[order.key] > ALERT_GAP then
            alerted[order.key] = now
            GK.Warn(("%s is near!"):format(GK.Show(order.n)), true, nil, order.n, order.key)
        end
    end
    -- the order's "last seen", filled in where it is: this runs at every look at the target
    local last = order.seen
    if not last then
        last = {}
        order.seen = last
    end
    last.by, last.z, last.t, last.l = LIB.Me(), s.z, time(), s.l
    -- Where we stand goes with it - for the pin on the world map (MapPins.lua) - read only as often as
    -- the guild is told, not at every look: one map lookup per target every two minutes. A pin up to
    -- two minutes behind is still where to look; nameplates only show within a few dozen yards.
    if not shared[order.key] or now - shared[order.key] > SHARE_GAP then
        shared[order.key] = now
        local ok, m, x, y = pcall(LIB.MyPosition)
        if ok and m and x and y then
            last.m, last.x, last.y = m, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
        else
            last.m, last.x, last.y = nil, nil, nil       -- indoors: no spot, rather than an old one
        end
        if GK.db.share then GK.SendSighting(order) end
    end
end

--- Look at a unit: remember an enemy player, mark their plate, warn about an order on them.
--- Runs at every enemy nameplate, mouseover and target, so it reads straight into the record it
--- keeps for them: no table per look, and the race is cleaned only when it isn't the one we have.
function GK.See(unit)
    if not GK.char or not GK.InWorld() then return end
    local key, guid = GK.UnitIdentity(unit)
    if not key then
        if plates[unit] then Unmark(unit) end
        return
    end
    local s = seen[key]
    if not s then
        s = { key = key }
        seen[key] = s
        count = count + 1
    end
    -- Their name as the game writes it, both words: "Unc Shark". The key can't be trusted for that on
    -- the live servers - a player on another of the server's realms comes back from LibForever as
    -- "Unc-Shark", the surname read as a realm - and then every "Unc" looked like the same player to
    -- GK.SameName (2026-11-06). Once per player we keep, not per look.
    if not s.shown then
        local name, second = (UnitNameUnmodified or UnitName)(unit)
        if type(name) == "string" and not Secret(name) and not Secret(second) then
            s.shown = (type(second) == "string" and second ~= "") and (name .. " " .. second) or name
        end
    end
    s.guid = guid or s.guid
    local _, class = UnitClass(unit)
    if not Secret(class) then s.c = GK.ValidClass(class) or s.c end
    local race, raceFile = UnitRace(unit)
    if not Secret(race) and race ~= s.rawRace then
        s.rawRace, s.r = race, GK.Clean(race, 20)
    end
    if not Secret(raceFile) then s.rf = raceFile or s.rf end
    local sex = UnitSex(unit)
    if not Secret(sex) and (sex == 2 or sex == 3) then s.sx = sex end       -- for their portrait
    local level = UnitLevel(unit)
    if not Secret(level) then s.l = GK.ValidLevel(level) or s.l end
    s.t, s.z = GetTime(), GK.Zone()
    -- Their guild, only while a guild is watched: the game names an enemy's (the owner's test, 2026-11-07).
    -- Read at every look, not kept from the first: a player can leave a guild for another. No answer is
    -- not "no guild" - a nameplate may not have it yet - so it leaves what we had.
    if GK.AnyGuildWatched and GK.AnyGuildWatched() then
        local ok, guild = pcall(GetGuildInfo, unit)
        if ok and not Secret(guild) and type(guild) == "string" and guild ~= "" then
            s.g = guild
            if GK.IsGuildWatched(guild) then
                GuildNear(guild, key)
                GK.SpellWatchedGuild(guild)          -- a name typed in, spelled as the game does
            end
        end
    end
    if s.guid then byGuid[s.guid] = s end
    Forget()
    -- keep our record of a known foe up to date with what we see now
    local f = GK.char.foes[key]
    if f then f.l, f.c, f.r = s.l or f.l, s.c or f.c, s.r or f.r end
    local order = GK.OrderOn(key, s.guid)
    if plates[unit] then
        if order then Mark(unit) else Unmark(unit) end
    end
    -- Someone the guild has a record of: keep what they look like. Kept again when it changed, so a
    -- barber's new sex is written at the next look; nothing written when it didn't.
    if s.known or Recorded(key, f, order) then
        s.known = true
        if s.rf and s.sx and (s.keptRf ~= s.rf or s.keptSx ~= s.sx) and GK.KeepLooks(key, s) then
            s.keptRf, s.keptSx = s.rf, s.sx
        end
    end
    if order then Spotted(order, s) end
end

function GK.StartSightings()
    LIB.On("NAME_PLATE_UNIT_ADDED", function(unit)
        if type(unit) ~= "string" then return end
        plates[unit] = true
        GK.See(unit)
    end)
    LIB.On("NAME_PLATE_UNIT_REMOVED", function(unit)
        if type(unit) ~= "string" then return end
        plates[unit] = nil
        Unmark(unit)
    end)
    LIB.On("PLAYER_TARGET_CHANGED", function() GK.See("target") end)
    LIB.On("UPDATE_MOUSEOVER_UNIT", function() GK.See("mouseover") end)
    -- Once per burst of changes (GK.Changed gathers them); RefreshMarks itself skips unless orders changed.
    LIB.Listen("GRUDGEKEEPER_CHANGED", RefreshMarks)
end

--- What was seen longer ago than anything reads it (SEEN_FOR) is dropped, and so are warnings and
--- reports past their gap: the housekeeping sweep calls this every ten minutes. Without it a long
--- session kept every enemy ever seen, up to the cap, for nothing.
function GK.PruneSeen()
    local now = GetTime()
    for key, s in pairs(seen) do
        if now - s.t > SEEN_FOR then
            if s.guid and byGuid[s.guid] == s then byGuid[s.guid] = nil end
            seen[key] = nil
            count = count - 1
        end
    end
    for key, t in pairs(alerted) do
        if now - t > ALERT_GAP then alerted[key] = nil end
    end
    for key, t in pairs(shared) do
        if now - t > SHARE_GAP then shared[key] = nil end
    end
    for guild, g in pairs(guildNear) do
        if not g.due and now - (g.at or 0) > GUILD_GAP then guildNear[guild] = nil end
    end
end
