-- Grudgekeeper - your kills and your deaths.
-- A kill: PARTY_KILL names the killer and the victim by GUID, for you and anyone in your group. We
-- count the ones landed by you or your pet, on a player of the other faction, in the open world. The
-- level comes from having seen them (Sightings.lua): the kill itself carries none.
-- A death: the game's death recap names whoever landed the blow (the "You died" chat line carries its
-- id), and the damage meter is asked when the recap is empty. It counts as a PvP death only when that
-- name belongs to an enemy player we saw - a name alone can't tell a rogue from a murloc.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local Secret = GK.Secret

local recapId          -- the death recap the last "You died" line pointed at
local deathPending
local lastDeath = "none this session"

function GK.LastDeathDebug() return lastDeath end

--- A screenshot, a moment later. Only ever from a kill you made (an event), never on a timer of its own.
function GK.Shot(delay)
    C_Timer.After(delay or 0.3, function() pcall(Screenshot) end)
end

local function Mine(guid)
    if type(guid) ~= "string" then return false end
    if guid == UnitGUID("player") then return true end
    return UnitExists("pet") and guid == UnitGUID("pet") or false
end

-- ---------------------------------------------------------------------------
-- Kills
-- ---------------------------------------------------------------------------
--- One kill of ours: points, the log, the guild, any order it fulfils, a letter when it earns a title.
--- v = { key, guid, c, r, l }
function GK.RecordKill(v)
    local now = time()
    local f = GK.Foe(v.key, { n = GK.Show(v.key), c = v.c, r = v.r, l = v.l })
    GK.KeepLooks(v.key, GK.Seen(v.key, v.guid) or v)     -- a grudge now: their race's face is kept
    local today = 0
    for i = #f.hits, 1, -1 do
        if now - f.hits[i] > GK.DAY then table.remove(f.hits, i) else today = today + 1 end
    end
    local orders = GK.OrdersOn(v.key, v.guid)
    -- Revenge: they killed you since you last killed them. Avenged: they killed a guildie a moment ago.
    local revenge = (f.lastDeath or 0) > (f.lastKill or 0)
    local avenged = GK.Avenged(v.key, now)
    local c = GK.char
    local titleBefore = GK.Title(c.points)
    local points = GK.Points(UnitLevel("player"), v.l, today, #orders > 0, revenge, avenged)
    f.hits[#f.hits + 1] = now
    f.k = f.k + 1
    f.lastKill = now
    c.kills = c.kills + 1
    c.points = c.points + points
    c.streak = (c.streak or 0) + 1
    c.bestStreak = math.max(c.bestStreak or 0, c.streak)
    local week = GK.Week()
    week.p, week.k = week.p + points, week.k + 1
    local zone = GK.Zone()
    GK.AddLog({ k = "K", t = now, n = v.key, c = v.c, r = v.r, l = v.l, z = zone, p = points,
        o = orders[1] and orders[1].key or nil, rv = revenge or nil, av = avenged })
    for _, o in ipairs(orders) do GK.Fulfil(o, zone) end
    GK.SendKill(v, zone, points, avenged, f.k)
    GK.SendBoard()
    if (#orders > 0 and GK.db.shotFulfil) or GK.db.shotEveryKill then GK.Shot(0.3) end
    -- A letter only for the kill that earns a new title. One for every kill was one after every fight ("den
    -- kan bli litt spam"), and a narrower rule - above your level, revenge, a streak - still sent too many:
    -- "kanskje for kills så kommer melding bare når man ranker opp?" (the owner, 2026-11-07). Every kill
    -- still counts, and the ledger's Grudges and News have them all.
    if #orders == 0 and GK.db.myLetters then
        local title = GK.Title(c.points)
        if title ~= titleBefore then GK.KillLetter(v, zone, title) end
    end
    GK.Changed()
end

--- PARTY_KILL (attacker GUID, victim GUID). A function of its own so the smoke test can call it.
function GK.OnPartyKill(attacker, target)
    if Secret(attacker) or Secret(target) or type(target) ~= "string" then return end
    if not target:find("^Player%-") or not Mine(attacker) or not GK.InWorld() then return end
    local ok, _, classFile, race, raceFile, _, name, realm = pcall(GetPlayerInfoByGUID, target)
    if not ok or Secret(name) or type(name) ~= "string" then return end
    local s = GK.Seen(nil, target)
    local key = (s and s.key) or GK.PlayerKey(GK.KeyOf(name, realm))
    if not key then return end
    -- The other side only: we keep sightings of enemies alone, so having seen them settles it;
    -- otherwise their race decides, and a race that could be either side is not counted.
    if not s and GK.EnemyRace(not Secret(raceFile) and raceFile or nil) ~= true then return end
    local level = s and s.l
    if not level and UnitExists("target") and UnitGUID("target") == target then
        local l = UnitLevel("target")
        level = not Secret(l) and GK.ValidLevel(l) or nil
    end
    GK.RecordKill({ key = key, guid = target,
        c = (s and s.c) or (not Secret(classFile) and GK.ValidClass(classFile)) or nil,
        r = (s and s.r) or GK.Clean(race, 20), l = level })
end

-- ---------------------------------------------------------------------------
-- Deaths
-- ---------------------------------------------------------------------------
--- Who landed the killing blow, by the game's death recap: name and spell, or nil.
local function FromRecap(id)
    if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
    local ok, events = pcall(C_DeathRecap.GetRecapEvents, id)
    if not ok or type(events) ~= "table" or Secret(events) or #events == 0 then return nil end
    -- The blow that killed is the one that overkilled; the first event when none says so.
    local blow = events[1]
    for _, e in ipairs(events) do
        if type(e) == "table" and not Secret(e.overkill) and type(e.overkill) == "number" and e.overkill > 0 then
            blow = e
            break
        end
    end
    if type(blow) ~= "table" or Secret(blow.sourceName) or type(blow.sourceName) ~= "string" then return nil end
    local spell = blow.spellName
    return blow.sourceName, (not Secret(spell) and type(spell) == "string") and spell or nil
end

--- The same from the game's damage meter: the source of the deadly hit. Readable only out of combat,
--- which being dead is.
local function FromMeter()
    local meter = C_DamageMeter
    local types, sessions = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
    if type(meter) ~= "table" or not meter.GetCombatSessionSourceFromType or not (types and sessions) then return nil end
    if InCombatLockdown() then return nil end
    local ok, src = pcall(meter.GetCombatSessionSourceFromType, sessions.Current, types.DamageTaken, UnitGUID("player"))
    if not ok or type(src) ~= "table" or Secret(src) or type(src.combatSpells) ~= "table" then return nil end
    for _, sp in ipairs(src.combatSpells) do
        if type(sp) == "table" and not Secret(sp.isDeadly) and sp.isDeadly then
            local d = sp.combatSpellDetails
            local who = sp.creatureName or (type(d) == "table" and d.unitName)
            if type(who) == "string" and not Secret(who) and who ~= "" then return who end
        end
    end
    return nil
end

--- One death of ours to an enemy player. v = { key, guid, c, r, l, spell }
function GK.RecordDeath(v)
    local f = GK.Foe(v.key, { n = GK.Show(v.key), c = v.c, r = v.r, l = v.l })
    GK.KeepLooks(v.key, GK.Seen(v.key, v.guid) or v)     -- a grudge now: their race's face is kept
    f.d = f.d + 1
    f.lastDeath = time()
    GK.char.deaths = GK.char.deaths + 1
    GK.char.streak = 0
    local week = GK.Week()
    week.d = week.d + 1
    local zone = GK.Zone()
    GK.AddLog({ k = "D", t = time(), n = v.key, c = v.c, r = v.r, l = v.l, z = zone, s = v.spell })
    GK.SendDeath(v, zone, f.d)
    GK.SendBoard()
    -- the third of us in two hours, or the third time for you in half an hour: an order goes out
    local auto = GK.AutoOrder(v)
    -- A letter only for the death that posted that order. One death to someone you will never see again
    -- is no news ("kanskje ikke så viktig å få brev om man bare blir drept en random gang", the owner,
    -- 2026-11-06); it still counts, and the ledger's Grudges and News have it.
    if GK.db.myLetters and auto then GK.SlainLetter(v, f.d, zone, true) end
    GK.Changed()
end

function GK.ResolveDeath()
    deathPending = false
    local id = recapId
    recapId = nil
    if not GK.InWorld() then
        lastDeath = "in an instance: not counted"
        return
    end
    local how = "the death recap"
    local name, spell = FromRecap(id)
    if not name and id then name, spell = FromRecap(nil) end
    if not name then
        name, how = FromMeter(), "the damage meter"
    end
    if not name then
        lastDeath = "neither the death recap nor the damage meter named anyone"
        return
    end
    local s, why = GK.SeenByName(name)
    if not s then
        lastDeath = ("%s, by %s - %s, so not counted"):format(GK.Clean(name, 40) or "?", how,
            why == "several" and "several enemy players we saw go by that name" or "not an enemy player we saw")
        return
    end
    lastDeath = ("%s, by %s"):format(s.key, how)
    GK.RecordDeath({ key = s.key, guid = s.guid, c = s.c, r = s.r, l = s.l, spell = GK.Clean(spell, 40) })
end

function GK.StartKills()
    LIB.On("PARTY_KILL", function(attacker, target) GK.OnPartyKill(attacker, target) end)
    LIB.On("CHAT_MSG_SYSTEM", function(text)
        if type(text) ~= "string" or Secret(text) then return end
        local id = text:match("|Hdeath:(%d+)|h")
        if id then recapId = tonumber(id) end
    end)
    LIB.On("PLAYER_DEAD", function()
        if deathPending then return end
        deathPending = true
        -- The recap, and the chat line that names it, land just after the death itself.
        C_Timer.After(1.5, GK.ResolveDeath)
    end)
end
