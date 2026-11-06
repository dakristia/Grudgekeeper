-- Grudgekeeper - the enemy players we can see.
-- That is all an addon has on Forever: Spy read the combat log, which is closed. An enemy counts as
-- seen when their nameplate comes up (enemy nameplates have to be on), or you target or mouse over
-- them. What we saw - level, class, race, GUID - is kept for a while, because a kill or a death only
-- names someone, and the level has to come from having seen them.
-- Anyone with an open kill order on them gets a skull over their nameplate. The target of an order
-- you took or posted also lights up the notice scroll (Notice.lua), with a sound - never a popup.
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

--- The latest enemy player we saw under this name (GK.SameName), or nil.
function GK.SeenByName(name)
    local best
    local now = GetTime()
    for key, s in pairs(seen) do
        if now - s.t <= SEEN_FOR and GK.SameName(key, name) and (not best or s.t > best.t) then best = s end
    end
    return best
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
    local key = LIB.UnitKey(unit)
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
--- Is this order yours to hunt: one you took, or one you posted (your own, or one your death posted)?
--- Your own orders can't be "taken" - their buttons offer Withdraw instead - so before this, the
--- camper whose order your death posted could walk right up to you unannounced (the user, 2026-11-04).
function GK.Hunting(order)
    return GK.char.accepted[order.key] or order.by == LIB.Me()
end

-- The target of an open order is in sight: warn (if it's yours to hunt) and tell the guild where.
local function Spotted(order, s)
    local now = GetTime()
    if (GK.Hunting(order) and GK.db.alertNear) or GK.db.alertAll then
        if not alerted[order.key] or now - alerted[order.key] > ALERT_GAP then
            alerted[order.key] = now
            GK.Warn(("%s is near!"):format(GK.Show(order.n)), true)
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
    if s.guid then byGuid[s.guid] = s end
    Forget()
    -- keep our record of a known foe up to date with what we see now
    local f = GK.char.foes[key]
    if f then f.l, f.c, f.r = s.l or f.l, s.c or f.c, s.r or f.r end
    local order = GK.OrderOn(key, s.guid)
    if plates[unit] then
        if order then Mark(unit) else Unmark(unit) end
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
end
