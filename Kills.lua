-- Grudgekeeper - your kills and your deaths.
-- A kill: PARTY_KILL names the killer and the victim by GUID, for you and anyone in your group. We
-- count the ones landed by you or your pet, on a player of the other faction, in the open world. The
-- level comes from having seen them (Sightings.lua): the kill itself carries none.
-- An assist: the same event, the blow landed by someone in your group (or their pet) on an enemy you
-- were fighting. The game keeps the combat log and the damage numbers from us, so "fighting" means you
-- had them as your target or focus while in combat, within the last ASSIST_FOR seconds.
-- A death: the game's death recap names whoever landed the blow (the "You died" chat line carries its
-- id), and the damage meter is asked when the recap is empty. It counts as a PvP death only when that
-- name belongs to an enemy player we saw - a name alone can't tell a rogue from a murloc.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local Secret = GK.Secret

local recapId          -- the death recap the last "You died" line pointed at
local deathPending
local lastDeath = "none this session"
local lastAssist = "none this session"
local fought = {}       -- [guid] = GetTime(): enemy players you had as target or focus in combat
local held = {}         -- [unit] = the guid of the enemy fought there now ("target", "focus")
local ASSIST_FOR = 30

function GK.LastDeathDebug() return lastDeath end
function GK.LastAssistDebug() return lastAssist end

--- A screenshot, a moment later. Only ever from a kill you made (an event), never on a timer of its own.
function GK.Shot(delay)
    C_Timer.After(delay or 0.3, function() pcall(Screenshot) end)
end

local function Mine(guid)
    if type(guid) ~= "string" then return false end
    if guid == UnitGUID("player") then return true end
    return UnitExists("pet") and guid == UnitGUID("pet") or false
end

--- Someone else in your group, or their pet: their name to show, or nil.
local function Groupmate(guid)
    if type(guid) ~= "string" or Mine(guid) then return nil end
    local raid = IsInRaid()
    local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        if UnitGUID(unit) == guid or UnitGUID(unit .. "pet") == guid then
            local name = UnitName(unit)
            return (not Secret(name) and type(name) == "string") and name or "a groupmate"
        end
    end
    return nil
end

--- An enemy player you have as target or focus, while you're in combat, counts as fought. The one
--- you switch away from was fought until now.
local function Engage(unit)
    local now = GetTime()
    local old = held[unit]
    if old and fought[old] then fought[old] = now end
    held[unit] = nil
    if not UnitExists(unit) or not UnitAffectingCombat("player") then return end
    local guid = UnitGUID(unit)
    if Secret(guid) or type(guid) ~= "string" or not guid:find("^Player%-") then return end
    local hostile = UnitCanAttack("player", unit)
    if Secret(hostile) or not hostile then return end
    fought[guid] = now
    held[unit] = guid
end

--- Did you fight them lately? Your target or focus right now counts, as the stamp may be old.
local function Fought(guid)
    Engage("target")
    Engage("focus")
    local now = GetTime()
    for g, t in pairs(fought) do
        if now - t > ASSIST_FOR then fought[g] = nil end
    end
    return fought[guid] ~= nil
end

--- Today's hits on this enemy, kills and assists alike, with older ones dropped.
local function HitsToday(f, now)
    local today = 0
    for i = #f.hits, 1, -1 do
        if now - f.hits[i] > GK.DAY then table.remove(f.hits, i) else today = today + 1 end
    end
    return today
end

--- They killed you since you last got them, by kill or assist.
local function Revenge(f)
    return (f.lastDeath or 0) > math.max(f.lastKill or 0, f.lastAssist or 0)
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
    local today = HitsToday(f, now)
    local orders = GK.OrdersOn(v.key, v.guid)
    -- Revenge: they killed you since you last got them. Avenged: they killed a guildie a moment ago.
    local revenge = Revenge(f)
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

--- One assist of ours: a groupmate landed the blow on an enemy we were fighting. Points a little
--- below the kill's, no order fulfilled (the killer does that), no letter: a line in chat.
--- v = { key, guid, c, r, l, with }
function GK.RecordAssist(v)
    local now = time()
    local f = GK.Foe(v.key, { n = GK.Show(v.key), c = v.c, r = v.r, l = v.l })
    GK.KeepLooks(v.key, GK.Seen(v.key, v.guid) or v)
    local today = HitsToday(f, now)
    local revenge = Revenge(f)
    local avenged = GK.Avenged(v.key, now)
    local points = GK.AssistPoints(UnitLevel("player"), v.l, today, revenge, avenged)
    local c = GK.char
    f.hits[#f.hits + 1] = now
    f.a = (f.a or 0) + 1
    f.lastAssist = now
    c.assists = (c.assists or 0) + 1
    c.points = c.points + points
    local week = GK.Week()
    week.p, week.a = week.p + points, (week.a or 0) + 1
    local zone = GK.Zone()
    GK.AddLog({ k = "A", t = now, n = v.key, c = v.c, r = v.r, l = v.l, z = zone, p = points, w = v.with,
        rv = revenge or nil, av = avenged })
    GK.SendAssist(v, zone, points)
    GK.SendBoard()
    print(("%s: assist on %s, with %s (%s)."):format(GK.TAG, GK.Show(v.key), v.with or "your group",
        points > 0 and ("+%d"):format(points) or "no points"))
    GK.Changed()
end

--- The enemy player a PARTY_KILL names, as we record them; nil when they aren't one we count.
local function Victim(target)
    local ok, _, classFile, race, raceFile, _, name, realm = pcall(GetPlayerInfoByGUID, target)
    if not ok or Secret(name) or type(name) ~= "string" then return nil end
    local s = GK.Seen(nil, target)
    local key = (s and s.key) or GK.PlayerKey(GK.KeyOf(name, realm))
    if not key then return nil end
    -- The other side only: we keep sightings of enemies alone, so having seen them settles it;
    -- otherwise their race decides, and a race that could be either side is not counted.
    if not s and GK.EnemyRace(not Secret(raceFile) and raceFile or nil) ~= true then return nil end
    local level = s and s.l
    if not level and UnitExists("target") and UnitGUID("target") == target then
        local l = UnitLevel("target")
        level = not Secret(l) and GK.ValidLevel(l) or nil
    end
    return { key = key, guid = target,
        c = (s and s.c) or (not Secret(classFile) and GK.ValidClass(classFile)) or nil,
        r = (s and s.r) or GK.Clean(race, 20), l = level }
end

--- PARTY_KILL (attacker GUID, victim GUID). A function of its own so the smoke test can call it.
--- Your blow is a kill; a groupmate's, on someone you were fighting, is your assist.
function GK.OnPartyKill(attacker, target)
    if Secret(attacker) or Secret(target) or type(target) ~= "string" then return end
    if not target:find("^Player%-") or not GK.InWorld() then return end
    if Mine(attacker) then
        local v = Victim(target)
        if v then GK.RecordKill(v) end
        return
    end
    local with = Groupmate(attacker)
    if not with then return end
    if not Fought(target) then
        lastAssist = ("%s got a kill you weren't fighting in: no assist"):format(with)
        return
    end
    local v = Victim(target)
    if not v then
        lastAssist = ("%s got a kill, but not of an enemy player we count"):format(with)
        return
    end
    v.with = with
    lastAssist = ("%s, with %s"):format(v.key, with)
    fought[target] = nil
    GK.RecordAssist(v)
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

--- /grudge debug meter: what the game's damage meter holds of the damage enemies took in the last fight,
--- and from whom. A probe, to learn whether a kill a mob or another player finished can go to whoever did
--- the work ("hvis det er mob som dreper så må vi krediteres ... også hvis ... vi har fightet lenge mot han
--- og noen andre sniper kill", the owner, 2026-11-09). The combat log is closed to addons; this meter is
--- not, out of combat. Prints only what it can read, and "(secret)" for what it can't.
--- The last fight ("Current") shows every enemy in it. The whole meter ("Overall") shows only the ones
--- with a class, the players, as the mobs drown them. For each: whether the name and the GUID are
--- readable, and who hit them when the GUID is. The first row's fields go first, to learn their names.
function GK.MeterProbe()
    local meter = C_DamageMeter
    local types, sessions = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
    if type(meter) ~= "table" or not (types and sessions and types.EnemyDamageTaken and meter.GetCombatSessionFromType) then
        print(GK.TAG .. ": this client has no damage meter for the damage enemies take.")
        return
    end
    if InCombatLockdown() then
        print(GK.TAG .. ": after the fight - the meter is secret during one.")
        return
    end
    local function S(v) if Secret(v) then return "(secret)" end return tostring(v) end
    local function Readable(v)
        if v == nil then return "missing" end
        if Secret(v) then return "secret" end
        return v == "" and "empty" or "readable"
    end
    local function Fields(t)
        local keys = {}
        for k, v in pairs(t) do keys[#keys + 1] = tostring(k) .. "=" .. (Secret(v) and "(secret)" or type(v)) end
        table.sort(keys)
        return table.concat(keys, " ")
    end
    local shownFields
    for _, kind in ipairs({ "Current", "Overall" }) do
        local ok, session = pcall(meter.GetCombatSessionFromType, sessions[kind], types.EnemyDamageTaken)
        if not ok or type(session) ~= "table" or Secret(session) or type(session.combatSources) ~= "table" then
            print(("%s meter, %s: nothing readable (%s)"):format(GK.TAG, kind, ok and S(session) or tostring(session)))
        else
            print(("%s meter, %s: %d enemies took %s"):format(GK.TAG, kind, #session.combatSources, S(session.totalAmount)))
            local skipped = 0
            for _, src in ipairs(session.combatSources) do
                local class = src.classFilename
                local player = not Secret(class) and type(class) == "string" and class ~= ""
                if kind == "Overall" and not player then
                    skipped = skipped + 1
                else
                    if not shownFields then
                        shownFields = true
                        print("  fields: " .. Fields(src))
                    end
                    local guid = src.sourceGUID
                    print(("  %s (name %s), %s %s: took %s, guid %s%s"):format(S(src.name), Readable(src.name),
                        S(src.factionGroup), S(class), S(src.totalAmount), Readable(guid),
                        (guid and not Secret(guid)) and (" " .. guid) or ""))
                    if guid and not Secret(guid) and meter.GetCombatSessionSourceFromType then
                        local ok2, d = pcall(meter.GetCombatSessionSourceFromType, sessions[kind], types.EnemyDamageTaken, guid)
                        if ok2 and type(d) == "table" and not Secret(d) and type(d.combatSpells) == "table" then
                            for j, sp in ipairs(d.combatSpells) do
                                if j > 8 then break end
                                local u = type(sp.combatSpellDetails) == "table" and sp.combatSpellDetails or {}
                                print(("    spell %s: %s from %s / %s, mob %s, pet %s, deadly %s"):format(S(sp.spellID),
                                    S(sp.totalAmount), S(sp.creatureName), S(u.unitName), S(u.isMob), S(u.isPet),
                                    S(sp.isDeadly)))
                            end
                        else
                            print(("    who hit them: nothing readable (%s)"):format(ok2 and S(d) or tostring(d)))
                        end
                    end
                end
            end
            if skipped > 0 then print(("  and %d without a class (mobs), left out"):format(skipped)) end
        end
    end
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
    LIB.On("PLAYER_TARGET_CHANGED", function() Engage("target") end)
    LIB.On("PLAYER_FOCUS_CHANGED", function() Engage("focus") end)
    LIB.On("PLAYER_REGEN_DISABLED", function()
        Engage("target")
        Engage("focus")
    end)
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
