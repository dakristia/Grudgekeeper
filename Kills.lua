-- Grudgekeeper - your kills and your deaths.
-- A kill: PARTY_KILL names the killer and the victim by GUID, for you and anyone in your group. We
-- count the ones landed by you or your pet, on a player of the other faction, in the open world. The
-- level comes from having seen them (Sightings.lua): the kill itself carries none.
-- An assist: the same event, the blow landed by someone in your group (or their pet) on an enemy player
-- you hurt in that fight. The game keeps the combat log from us, but its damage meter says who hit whom
-- once the fight is over, so the kill waits for the end of combat and the meter is asked then: any
-- damage of yours (or your pet's) on the victim makes it an assist, none and it is not one. The meter
-- holds you and your group only, never a stranger (/grudge debug meter, 2026-11-11), so a kill a mob or
-- a stranger finished has no killer in your group and is no assist. Taken, with fixes, from dakristia's
-- vBaustad/Grudgekeeper#2.
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
local pending = {}      -- [guid] = { v, at }: a groupmate's kill waiting for the meter to be readable
local PENDING_FOR = 120 -- seconds a kill may wait for a readable meter before it is dropped
local LOOK_BACK = 3     -- fights before "Current" asked too, when another one began before the meter was read
-- When the fight we are in began, at PLAYER_REGEN_DISABLED. A guildie who fell after that fell in this
-- fight, and is avenged only in a later one (GK.Avenged): one of the group dying first made every kill
-- and assist on their killer worth a point more, for the whole group - "trenger en combat reset i mellom"
-- (the owner, 2026-11-12).
local fightStart = time()

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
    -- Revenge: they killed you since you last got them. Avenged: they killed a guildie a moment ago, before
    -- this fight began.
    local revenge = Revenge(f)
    local avenged = GK.Avenged(v.key, now, v.fight or fightStart)
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
    -- The spree counts the kills worth points only: a grey kill or a farmed one is in the streak, not here.
    if points > 0 then c.spree = (c.spree or 0) + 1 end
    local week = GK.Week()
    week.p, week.k = week.p + points, week.k + 1
    local zone = GK.Zone()
    GK.AddLog({ k = "K", t = now, n = v.key, c = v.c, r = v.r, l = v.l, z = zone, p = points,
        o = orders[1] and orders[1].key or nil, rv = revenge or nil, av = avenged })
    for _, o in ipairs(orders) do GK.Fulfil(o, zone) end
    GK.SendKill(v, zone, points, avenged, f.k, c.spree)
    -- What the kill made of it, for whatever shows it (GK_SPREE, GK_TORMENTOR). Only after the send: the
    -- guild hears the kill first.
    if points > 0 then
        local tier, key = GK.SpreeTier(c.spree)
        if tier then LIB.Fire("GK_SPREE", LIB.Me(), c.spree, tier, true, key) end
    end
    local tormented = GK.TormentorEnded(v.key)
    if tormented then LIB.Fire("GK_TORMENTOR", LIB.Me(), GK.Show(v.key), tormented, true) end
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
--- below the kill's, no order fulfilled (the killer does that), and no line in chat - the owner doesn't
--- read them; the ledger's Grudges and News have it. A letter only when it earns a new title, as a kill.
--- v = { key, guid, c, r, l, with }
function GK.RecordAssist(v)
    local now = time()
    local f = GK.Foe(v.key, { n = GK.Show(v.key), c = v.c, r = v.r, l = v.l })
    GK.KeepLooks(v.key, GK.Seen(v.key, v.guid) or v)
    local today = HitsToday(f, now)
    local revenge = Revenge(f)
    local avenged = GK.Avenged(v.key, now, v.fight or fightStart)
    local points = GK.AssistPoints(UnitLevel("player"), v.l, today, revenge, avenged)
    local c = GK.char
    local titleBefore = GK.Title(c.points)
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
    -- the points of an assist can cross a title as well as a kill's
    if GK.db.myLetters then
        local title = GK.Title(c.points)
        if title ~= titleBefore then GK.KillLetter(v, zone, title) end
    end
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

--- The names the meter may give our own rows: "First Surname" as it writes us ("Critical Mango",
--- /grudge debug meter, 2026-11-11), and the first name alone. UnitName gives the two apart on Forever
--- (DECISIONS.md, 2026-09-26): matching on its first value alone, as the PR did, never found us. And our
--- pet's name, for a row the meter marks as a pet's. nil when we can't tell who we are.
local function OurNames()
    local first, surname = UnitName("player")
    if Secret(first) or type(first) ~= "string" or first == "" then return nil end
    local names = { [first] = true }
    if not Secret(surname) and type(surname) == "string" and surname ~= "" then names[first .. " " .. surname] = true end
    local pet = UnitExists("pet") and UnitName("pet") or nil
    return names, (not Secret(pet) and type(pet) == "string" and pet ~= "") and pet or nil
end

--- The rows of who hit one enemy in one fight, by the meter call given; nil when it won't say.
local function Rows(call, ...)
    local ok, src = pcall(call, ...)
    if not ok or type(src) ~= "table" or Secret(src) or type(src.combatSpells) ~= "table" then return nil end
    return src.combatSpells
end

--- What our rows add up to.
local function Ours(rows, names, pet)
    local total = 0
    for _, sp in ipairs(rows) do
        local d = type(sp) == "table" and sp.combatSpellDetails
        local who, amount = type(d) == "table" and d.unitName, type(sp) == "table" and sp.totalAmount
        if type(who) == "string" and not Secret(who) and type(amount) == "number" and not Secret(amount)
            and (names[who] or (pet and who == pet and not Secret(d.isPet) and d.isPet == true)) then
            total = total + amount
        end
    end
    return total
end

--- How much damage we did to this enemy, by the game's damage meter: a number, or nil when the meter
--- can't be read now (secret in combat), or false when this client has no such meter. The last fight
--- first; when we did nothing there, the few fights before it, newest first - a new fight begun before
--- this one was read has become "Current" and would hide ours.
local function OurDamage(guid)
    local meter = C_DamageMeter
    local types, sessions = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
    if type(meter) ~= "table" or not meter.GetCombatSessionSourceFromType
        or not (types and types.EnemyDamageTaken and sessions) then return false end
    local names, pet = OurNames()
    if not names then return nil end
    local rows = Rows(meter.GetCombatSessionSourceFromType, sessions.Current, types.EnemyDamageTaken, guid)
    local total = rows and Ours(rows, names, pet) or nil
    if (total or 0) > 0 or not (meter.GetAvailableCombatSessions and meter.GetCombatSessionSourceFromID) then
        return total
    end
    local ok, list = pcall(meter.GetAvailableCombatSessions)
    if not ok or type(list) ~= "table" or Secret(list) then return total end
    local ids = {}
    for _, s in ipairs(list) do
        local id = type(s) == "table" and s.sessionID
        if type(id) == "number" and not Secret(id) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return a > b end)
    for i = 1, math.min(#ids, LOOK_BACK) do
        local r = Rows(meter.GetCombatSessionSourceFromID, ids[i], types.EnemyDamageTaken, guid)
        if r then
            local t = Ours(r, names, pet)
            if t > 0 then return t end
            total = total or 0
        end
    end
    return total
end

--- Ask the meter about every kill waiting. Out of combat only: in a fight the meter is secret, and the
--- next end of combat tries again. A kill the meter can't be read for in two minutes is dropped.
local function Settle()
    if InCombatLockdown() then return end
    for guid, p in pairs(pending) do
        local v = p.v
        local dmg = OurDamage(guid)
        if dmg == false then
            pending[guid] = nil
            lastAssist = "no damage meter on this client: no assist"
        elseif dmg == nil then
            if GetTime() - p.at > PENDING_FOR then
                pending[guid] = nil
                lastAssist = ("%s: the meter never said"):format(v.key)
            end
        else
            pending[guid] = nil
            if dmg > 0 then
                lastAssist = ("%s, with %s (%d damage from you)"):format(v.key, v.with, dmg)
                GK.RecordAssist(v)
            else
                lastAssist = ("%s got %s, but the meter shows no damage from you"):format(v.with, v.key)
            end
        end
    end
end

--- Once a fight is over: the meter may need a moment, and a read it refused is tried again a little later.
local function SettleSoon()
    if not next(pending) then return end
    for _, delay in ipairs({ 1, 3, 6 }) do C_Timer.After(delay, Settle) end
end

--- PARTY_KILL (attacker GUID, victim GUID). A function of its own so the smoke test can call it.
--- Your blow is a kill; a groupmate's waits for the meter, and is your assist if you hurt the victim.
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
    local v = Victim(target)
    if not v then
        lastAssist = ("%s got a kill, but not of an enemy player we count"):format(with)
        return
    end
    v.with = with
    v.fight = fightStart           -- settled once the fight is over, maybe after the next began: this one counts
    pending[target] = { v = v, at = GetTime() }
    lastAssist = ("%s, with %s: waiting for the fight to end"):format(v.key, with)
    if not InCombatLockdown() then SettleSoon() end
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
    -- The first run (2026-11-11, mobs only) never asked who hit them: a mob has no sourceGUID here, so the
    -- creature ID is asked by as well, and the line says which of the two it had. Overall lumps every mob
    -- of a kind together, so only Current is taken apart, and Overall lists the players alone - the ones
    -- with a class - as the mobs drown them (the idea from vBaustad/Grudgekeeper#2).
    for _, kind in ipairs({ "Current", "Overall" }) do
        local ok, session = pcall(meter.GetCombatSessionFromType, sessions[kind], types.EnemyDamageTaken)
        if not ok or type(session) ~= "table" or Secret(session) or type(session.combatSources) ~= "table" then
            print(("%s meter, %s: nothing readable (%s)"):format(GK.TAG, kind, ok and S(session) or tostring(session)))
        else
            print(("%s meter, %s: %d enemies took %s"):format(GK.TAG, kind, #session.combatSources, S(session.totalAmount)))
            local list, mobs = {}, 0
            for _, src in ipairs(session.combatSources) do
                local class = src.classFilename
                if kind == "Current" or (not Secret(class) and type(class) == "string" and class ~= "") then
                    list[#list + 1] = src
                else
                    mobs = mobs + 1
                end
            end
            if mobs > 0 then print(("  (%d without a class - mobs - left out)"):format(mobs)) end
            for i, src in ipairs(list) do
                if i > 6 then break end
                local guid, cid = src.sourceGUID, src.sourceCreatureID
                print(("  %s, %s %s: took %s, died at %s - %s, creature %s"):format(S(src.name), S(src.factionGroup),
                    S(src.classFilename), S(src.totalAmount), S(src.deathTimeSeconds),
                    guid == nil and "no GUID" or Secret(guid) and "GUID secret" or ("GUID " .. tostring(guid):sub(1, 7)),
                    S(cid)))
                local byGuid = (guid ~= nil and not Secret(guid)) and guid or nil
                local byId = (not Secret(cid) and type(cid) == "number") and cid or nil
                if kind ~= "Current" then
                    -- the breakdown is asked for the last fight only
                elseif not (byGuid or byId) then
                    print("    who hit them: nothing to ask by")
                elseif meter.GetCombatSessionSourceFromType then
                    local ok2, d = pcall(meter.GetCombatSessionSourceFromType, sessions[kind], types.EnemyDamageTaken,
                        byGuid, byId)
                    if ok2 and type(d) == "table" and not Secret(d) and type(d.combatSpells) == "table" then
                        if #d.combatSpells == 0 then print("    who hit them: an empty list") end
                        for j, sp in ipairs(d.combatSpells) do
                            if j > 4 then break end
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
    end
end

--- One death of ours to an enemy player. v = { key, guid, c, r, l, spell }
--- Returns the spree we had before it ended, which is 0 for none.
function GK.RecordDeath(v)
    local f = GK.Foe(v.key, { n = GK.Show(v.key), c = v.c, r = v.r, l = v.l })
    GK.KeepLooks(v.key, GK.Seen(v.key, v.guid) or v)     -- a grudge now: their race's face is kept
    f.d = f.d + 1
    f.lastDeath = time()
    GK.char.deaths = GK.char.deaths + 1
    GK.char.streak = 0
    local spree = GK.char.spree or 0
    GK.char.spree = 0
    GK.TormentorGrew(v.key)
    if spree >= GK.SPREE_MIN then LIB.Fire("GK_SPREE_ENDED", LIB.Me(), spree, GK.Show(v.key), true) end
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
    return spree
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
    LIB.On("PLAYER_REGEN_ENABLED", SettleSoon)
    LIB.On("PLAYER_REGEN_DISABLED", function() fightStart = time() end)
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
