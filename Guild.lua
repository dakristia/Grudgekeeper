-- Grudgekeeper - the guild: leaderboard, kill orders, who is wanted, the feed.
-- Everyone sends only their OWN things: their score, their kills and deaths, the orders they posted,
-- the orders they took or fulfilled. Nobody can change another player's score or order. An order's
-- poster has the last word on it, and a guildie who was offline hears the poster's version next time.
-- Messages, fields separated by ';' (every text field goes through GK.Clean on the way in). A field
-- added later goes on the END, so an older client reads what it knows and ignores the rest:
--   B;1;points;kills;deaths;level;class;weekPoints;weekKills;weekDeaths;weekId;streak;bestStreak;
--       ordersDone;bountyWon;nemesis;nemesisTimes              my score, and my profile's numbers
--   Q;1                                                        tell me everything (at login)
--   K;1;name;class;race;level;zone;points;avenged;times        I killed someone (avenging a guildie;
--                                                              times: how often I have, in all)
--   D;1;name;class;race;level;zone;times                       someone killed me (times in all)
--   C;1;id;name;class;race;level;guid;reward;created;expires;state;doneBy;note;auto
--                                                              an order of mine, as it stands (auto:
--                                                              r or c when my death posted it, below)
--   A;1;poster;id;on                                           I took (1) or dropped (0) an order
--   F;1;poster;id;zone                                         I fulfilled an order
--   S;1;poster;id;zone;level;map;x;y                           I saw an order's target, standing here
--                                                              (x and y in thousandths of the map)
--   T;1;poster;id;copper                                       my share of an order's pot is this
--   Y;1;poster;id                                              I paid my share of a fulfilled order
-- Order states: o open, d fulfilled (a bounty may be owed), p paid, x withdrawn, e expired.
-- The pot: the poster's own reward, plus what anyone else puts in (T). Each backer owns their share,
-- owes it to whoever fulfils the order, and says when they paid it (Y); the poster's own part is
-- paid with the order's state (p), as before the pot existed.
-- Worst case a guild can make us keep: 150 orders (10 open per poster), 500 board rows, 200 wanted,
-- 200 slain (enemies the guild has killed, 20 killers each), 40 feed lines, 50 hunters and 20
-- backers per order. Every sender is also held to LibForever's 30 messages / 10 s.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local PREFIX = "Grudgekeeper"
GK.PREFIX = PREFIX
local PROTO = 1
local MAX_OPEN_PER_POSTER = 10
local MAX_ORDERS = 150
local MAX_BOARD = 500
local MAX_WANTED = 200
local MAX_SLAIN = 200
local MAX_SLAYERS = 20
local MAX_FEED = 40
local MAX_HUNTERS = 50
local MAX_BACKERS = 20
local MAX_REWARD = 1000 * 10000          -- 1000 gold, in copper
local ORDER_DAYS = 7
-- Orders that post themselves (the user, 2026-11-04: on by default). When an enemy has killed three
-- of us in two hours - a rampage - or one of us three times in half an hour - camping a corpse - the
-- death that makes it three posts a kill order from the victim's own client, in their name: no gold,
-- for three days, and only when nobody has an order on them and they had no automatic one today.
-- The victim's client, because every client hears the deaths and only one must act on them.
local AUTO_DAYS = 3
local RAMPAGE_FOR, RAMPAGE_VICTIMS = 2 * 3600, 3
local CAMP_FOR, CAMP_DEATHS = 30 * 60, 3
local RECENT_PAIRS = 10                  -- deaths kept per enemy for the rules above, at most
local KEEP_CLOSED = 14 * GK.DAY          -- withdrawn, expired and paid orders, then gone
local KEEP_OWED = 30 * GK.DAY            -- a fulfilled order still owed stays this long
local BOARD_STALE = 60 * GK.DAY          -- a guildie not heard from in this long leaves the board
local STATES = { o = 0, d = 1, p = 2, x = 2, e = 2 }   -- an order only ever moves forward

-- ---------------------------------------------------------------------------
-- The wire
-- ---------------------------------------------------------------------------
-- One table for the fields of every message, refilled each time: a login brings hundreds of messages
-- and no handler keeps the table, only the values it copies out. Fields a longer message left behind
-- are cleared, so a short message can never read another's tail.
local fields, fieldCount = {}, 0
local function Split(text)
    local n, start = 0, 1
    while n < 24 do
        local i = text:find(";", start, true)
        n = n + 1
        if not i then
            fields[n] = text:sub(start)
            break
        end
        fields[n] = text:sub(start, i - 1)
        start = i + 1
    end
    for j = n + 1, fieldCount do fields[j] = nil end
    fieldCount = n
    return fields
end

--- Fields joined with ';'. nil travels as an empty field.
local function Msg(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[i] = v == nil and "" or tostring(v)
    end
    return table.concat(parts, ";")
end

local function Send(text)
    -- The test panel (Debug.lua) is open: what its buttons do stays on this client.
    if GK.testMode or not IsInGuild() then return false end
    return LIB.Send(PREFIX, text, "GUILD")
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

local function AddFeed(e)
    local feed = GK.Store().feed
    table.insert(feed, 1, e)
    for i = #feed, MAX_FEED + 1, -1 do feed[i] = nil end
end

-- ---------------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------------
-- Finding the open orders on a player is asked at every enemy nameplate, mouseover, target and
-- tooltip. It used to walk every order and compare names one by one - two gsubs per open order per
-- nameplate, measured at ~340 bytes of garbage per enemy nameplate with 20 orders out, growing with
-- every order. Now an index of the OPEN orders, by GUID, by name and by first name, is rebuilt only
-- when an order changes (Touched), and a lookup is a few table reads. It matches exactly what
-- GK.SameName matches - the same name, or the same first name where one of the two has no surname -
-- and smoke_grudgekeeper.py checks the two agree on a few hundred random names.
local ordersVersion, indexVersion, indexStore = 0, -1, nil
local byGuid, byName, byFirst = {}, {}, {}
local NONE = {}                     -- the usual answer, shared: callers only ever read it

--- Any order was added, closed, changed hands or went: the index is rebuilt at the next lookup.
local function Touched() ordersVersion = ordersVersion + 1 end
function GK.OrdersVersion() return ordersVersion end

-- "Pølse Hans-Realm" -> "Pølse Hans", "Pølse". Cached, because the same few names are asked about
-- over and over; dropped wholesale when it grows, which a session of world PvP rarely makes it do.
local plainName, plainFirst, plainCount = {}, {}, 0
local function Plain(key)
    local name = plainName[key]
    if not name then
        if plainCount >= 500 then
            wipe(plainName)
            wipe(plainFirst)
            plainCount = 0
        end
        name = key:gsub("%-[^%-]*$", "")
        plainName[key], plainFirst[key] = name, name:match("^%S+") or name
        plainCount = plainCount + 1
    end
    return name, plainFirst[key]
end

local function Put(t, k, o)
    local list = t[k]
    if not list then
        list = {}
        t[k] = list
    end
    list[#list + 1] = o
end

local function Reindex(store)
    wipe(byGuid)
    wipe(byName)
    wipe(byFirst)
    for _, o in pairs(store.orders) do
        if o.state == "o" then
            if o.guid then Put(byGuid, o.guid, o) end
            if type(o.n) == "string" then
                local name, first = Plain(o.n)
                Put(byName, name, o)
                if first ~= name then Put(byFirst, first, o) end
            end
        end
    end
    indexVersion, indexStore = ordersVersion, store
end

-- Open candidates into list, each once; list is made only when there is something to put in it.
local function Collect(list, candidates)
    if not candidates then return list end
    for i = 1, #candidates do
        local o = candidates[i]
        if o.state == "o" then
            if not list then
                list = { o }
            else
                local dup = false
                for j = 1, #list do
                    if list[j] == o then dup = true break end
                end
                if not dup then list[#list + 1] = o end
            end
        end
    end
    return list
end

local function BiggerPot(a, b) return GK.Pot(a) > GK.Pot(b) end

--- Every open order on this player (by GUID, else by name), the biggest bounty first. The list is
--- for reading only: with no order on them it is one shared empty table.
function GK.OrdersOn(key, guid)
    local store = GK.Store()
    if indexVersion ~= ordersVersion or indexStore ~= store then Reindex(store) end
    local list
    if guid then list = Collect(list, byGuid[guid]) end
    if type(key) == "string" then
        local name, first = Plain(key)
        list = Collect(list, byName[name])
        if first ~= name then
            list = Collect(list, byName[first])      -- an order written with the first name alone
        else
            list = Collect(list, byFirst[first])     -- a first name alone: an order with any surname
        end
    end
    if not list then return NONE end
    if #list > 1 then table.sort(list, BiggerPot) end
    return list
end

-- The biggest open order among candidates, better than best so far.
local function Best(best, candidates)
    if not candidates then return best end
    for i = 1, #candidates do
        local o = candidates[i]
        if o.state == "o" and o ~= best and (not best or GK.Pot(o) > GK.Pot(best)) then best = o end
    end
    return best
end

--- The one open order on this player with the biggest bounty, or nil - what OrdersOn()[1] would be,
--- without making a list: this is the one every nameplate, mouseover and tooltip asks.
function GK.OrderOn(key, guid)
    local store = GK.Store()
    if indexVersion ~= ordersVersion or indexStore ~= store then Reindex(store) end
    local best
    if guid then best = Best(best, byGuid[guid]) end
    if type(key) == "string" then
        local name, first = Plain(key)
        best = Best(best, byName[name])
        if first ~= name then best = Best(best, byName[first]) else best = Best(best, byFirst[first]) end
    end
    return best
end

--- The whole bounty on an order: the poster's reward and every backer's share. Also how many backers.
function GK.Pot(o)
    local total, backers = o.reward or 0, 0
    if o.pot then
        for _, copper in pairs(o.pot) do
            total, backers = total + copper, backers + 1
        end
    end
    return total, backers
end

--- Open orders, biggest bounty first. Each pot is added up once, not at every comparison of the sort.
function GK.OpenOrders()
    local list, pots = {}, {}
    for _, o in pairs(GK.Store().orders) do
        if o.state == "o" then
            list[#list + 1] = o
            pots[o] = GK.Pot(o)
        end
    end
    table.sort(list, function(a, b)
        if pots[a] ~= pots[b] then return pots[a] > pots[b] end
        return (a.t or 0) > (b.t or 0)
    end)
    return list
end

--- For the hitlist: the open ones as above, then the closed ones, latest first.
function GK.AllOrders()
    local list = GK.OpenOrders()
    local closed = {}
    for _, o in pairs(GK.Store().orders) do
        if o.state ~= "o" then closed[#closed + 1] = o end
    end
    table.sort(closed, function(a, b) return (a.doneAt or a.exp or a.t or 0) > (b.doneAt or b.exp or b.t or 0) end)
    for _, o in ipairs(closed) do list[#list + 1] = o end
    return list
end

--- What I owe for orders somebody else fulfilled: my reward on orders I posted, my share of the pot
--- on orders I backed. { { o = order, share = copper } }, the oldest first.
function GK.Owed()
    local me, list = LIB.Me(), {}
    for _, o in pairs(GK.Store().orders) do
        if o.doneBy and o.doneBy ~= me then
            if o.by == me and o.state == "d" and (o.reward or 0) > 0 then
                list[#list + 1] = { o = o, share = o.reward }
            end
            local mine = o.pot and o.pot[me]
            if mine and mine > 0 and (o.state == "d" or o.state == "p") and not (o.paid and o.paid[me]) then
                list[#list + 1] = { o = o, share = mine }
            end
        end
    end
    table.sort(list, function(a, b) return (a.o.doneAt or 0) < (b.o.doneAt or 0) end)
    return list
end

--- My part of a fulfilled order is paid: the poster's through the order's state, a backer's with Y.
function GK.PayShare(o)
    local me = LIB.Me()
    if o.by == me then return GK.MarkPaid(o) end
    if not (o.pot and o.pot[me]) then return end
    o.paid = o.paid or {}
    o.paid[me] = true
    Send(Msg("Y", PROTO, o.by, o.id))
    GK.Changed()
end

--- Put my share into an order's pot (0 takes it out again). Only while the order is open.
function GK.Contribute(o, copper)
    local me = LIB.Me()
    if not me or o.state ~= "o" or o.by == me then return end
    copper = math.max(0, math.min(math.floor(tonumber(copper) or 0), MAX_REWARD))
    o.pot = o.pot or {}
    o.pot[me] = copper > 0 and copper or nil
    Send(Msg("T", PROTO, o.by, o.id, copper))
    AddFeed({ t = time(), who = me, kind = "T", n = o.n, c = o.c, l = o.l, p = copper })
    GK.Changed()
end

local function SendOrder(o)
    Send(Msg("C", PROTO, o.id, o.n, o.c, o.r, o.l, o.guid, o.reward, o.t, o.exp, o.state, o.doneBy, o.note, o.auto))
end

-- Too many orders: drop the closed ones that closed longest ago.
local function Trim(store)
    local n = Count(store.orders)
    if n <= MAX_ORDERS then return end
    local closed = {}
    for key, o in pairs(store.orders) do
        if o.state ~= "o" then closed[#closed + 1] = { key = key, at = o.doneAt or o.exp or o.t or 0 } end
    end
    table.sort(closed, function(a, b) return a.at < b.at end)
    for i = 1, math.min(#closed, n - MAX_ORDERS) do store.orders[closed[i].key] = nil end
    Touched()
end

--- Write a kill order. t = { key, guid, c, r, l }, reward in copper. Posting again on the same target
--- changes the order you already have on them. auto: "r" or "c" for an order your death posted
--- (GK.AutoOrder) - it runs three days, not seven. Returns the order, or nil and why not.
function GK.PostOrder(t, reward, note, auto)
    local s, me, now = GK.Store(), LIB.Me(), time()
    if not me then return nil, "The game hasn't said who you are yet - try again in a moment." end
    reward = math.max(0, math.min(math.floor(tonumber(reward) or 0), MAX_REWARD))
    note = GK.Clean(note, 80)
    local open = 0
    for _, o in pairs(s.orders) do
        if o.by == me and o.state == "o" then
            if (t.guid and o.guid == t.guid) or o.n == t.key then
                o.reward, o.note, o.exp = reward, note, now + ORDER_DAYS * GK.DAY
                o.auto = nil            -- written by your hand now: no longer one a death posted
                o.guid, o.c, o.r, o.l = t.guid or o.guid, t.c or o.c, t.r or o.r, t.l or o.l
                Touched()
                SendOrder(o)
                GK.Changed()
                return o
            end
            open = open + 1
        end
    end
    if open >= MAX_OPEN_PER_POSTER then
        return nil, ("You have %d open kill orders already - withdraw one first."):format(open)
    end
    -- Seconds since 1970 make an id no reinstall can hand out twice.
    local id = math.max(now, s.nextId or 1)
    s.nextId = id + 1
    local o = { key = me .. "#" .. id, id = id, by = me, n = t.key, guid = t.guid, c = t.c, r = t.r, l = t.l,
        reward = reward, note = note, t = now, exp = now + (auto and AUTO_DAYS or ORDER_DAYS) * GK.DAY,
        state = "o", hunters = {}, auto = auto }
    s.orders[o.key] = o
    Touched()
    Trim(s)
    SendOrder(o)
    AddFeed({ t = now, who = me, kind = "C", n = t.key, c = t.c, l = t.l, p = reward, au = auto and true or nil })
    GK.Changed()
    return o
end

--- My death to v: does it make an order that posts itself (see AUTO_DAYS)? Posts it and returns the
--- order, or nil. Only with sharing on - a client that keeps your deaths to itself doesn't announce
--- them this way either.
function GK.AutoOrder(v)
    if not (GK.db.autoOrders and GK.db.share) or not (v and v.key) then return nil end
    local me, now = LIB.Me(), time()
    if not me or GK.OrderOn(v.key, v.guid) then return nil end
    -- one automatic order per enemy a day, whoever's death posted it
    for _, o in pairs(GK.Store().orders) do
        if o.auto and now - (o.t or 0) < GK.DAY and GK.SameName(o.n, v.key) then return nil end
    end
    local note, kind = GK.AutoReason(v.key, me, now)
    if not note then return nil end
    return GK.PostOrder({ key = v.key, guid = v.guid, c = v.c, r = v.r, l = v.l }, 0, note, kind)
end

function GK.Withdraw(o)
    if o.by ~= LIB.Me() or o.state ~= "o" then return end
    o.state, o.doneAt = "x", time()
    Touched()
    SendOrder(o)
    GK.Changed()
end

function GK.MarkPaid(o)
    if o.by ~= LIB.Me() or o.state ~= "d" then return end
    o.state, o.paidAt = "p", time()
    Touched()
    SendOrder(o)
    GK.Changed()
end

function GK.Accept(o, on)
    GK.char.accepted[o.key] = on and true or nil
    o.hunters = o.hunters or {}
    o.hunters[LIB.Me() or "?"] = on and true or nil
    Send(Msg("A", PROTO, o.by, o.id, on and 1 or 0))
    GK.Changed()
end

--- Our kill fulfilled this order.
function GK.Fulfil(o, zone)
    if o.state ~= "o" then return end
    local me = LIB.Me()
    o.state, o.doneBy, o.doneAt, o.doneZone = "d", me, time(), zone
    Touched()
    GK.char.accepted[o.key] = nil
    -- For the profile: orders fulfilled, and the bounties they carried when the kill was made.
    GK.char.done = (GK.char.done or 0) + 1
    GK.char.won = (GK.char.won or 0) + (GK.Pot(o))
    -- Sent whatever "share" says: fulfilling an order is the one thing the order exists for.
    Send(Msg("F", PROTO, o.by, o.id, zone))
    if o.by == me then SendOrder(o) end
    AddFeed({ t = o.doneAt, who = me, kind = "F", n = o.n, c = o.c, l = o.l, p = o.reward, z = zone })
    GK.CompleteLetter(o)
end

--- One line in guild chat, for the guildies who don't run Grudgekeeper. Chat sent as the player, so:
--- only ever from the player's own click on a letter (ORDER COMPLETE's "Tell the guild"), once per
--- letter, and not while the game holds chat back. Returns true when it went.
function GK.TellGuild(text)
    if GK.testMode then
        print(GK.TAG .. " (test): this would go to guild chat: " .. tostring(text))
        return false
    end
    if not IsInGuild() or LIB.InChatLockdown() or type(text) ~= "string" then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, LIB.Sanitize(text, 240), "GUILD"))
end

--- Where we saw an order's target: o.seen as Sightings.lua filled it in, our own spot included.
function GK.SendSighting(o)
    local s = o.seen
    if not s then return end
    Send(Msg("S", PROTO, o.by, o.id, s.z, s.l, s.m, s.x, s.y))
end

function GK.SendBoard()
    if not GK.db.share then return end
    LIB.Debounce("GrudgekeeperBoard", 2, function()
        local _, class = UnitClass("player")
        local w, c = GK.Week(), GK.char
        local nemesis, f = GK.Nemesis()
        Send(Msg("B", PROTO, c.points, c.kills, c.deaths, UnitLevel("player"), class,
            w.p, w.k, w.d, w.id, c.streak or 0, c.bestStreak or 0, c.done or 0, c.won or 0,
            nemesis, f and f.d or nil))
    end)
end

--- The guild's tally of one enemy: who of us has killed them, and how often. Each killer reports
--- their own running total (K's last field), so a missed message is made good by their next kill.
function GK.NoteSlain(killer, key, c, r, l, times)
    if not (killer and key and times) then return end
    local slain = GK.Store().slain
    local e = slain[key]
    if not e then
        if Count(slain) >= MAX_SLAIN then
            local oldest, oldKey
            for k, v in pairs(slain) do
                if not oldest or (v.last or 0) < oldest then oldest, oldKey = v.last or 0, k end
            end
            if oldKey then slain[oldKey] = nil end
        end
        e = { by = {} }
        slain[key] = e
    end
    e.c, e.r, e.l = c or e.c, r or e.r, l or e.l
    e.last = time()
    if e.by[killer] or Count(e.by) < MAX_SLAYERS then e.by[killer] = times end
end

function GK.SendKill(v, zone, points, avenged, times)
    local me = LIB.Me()
    AddFeed({ t = time(), who = me, kind = "K", n = v.key, c = v.c, l = v.l, p = points, z = zone, av = avenged })
    GK.NoteSlain(me, v.key, v.c, v.r, v.l, times)
    if not GK.db.share then return end
    Send(Msg("K", PROTO, v.key, v.c, v.r, v.l, zone, points, avenged, times))
end

--- A guildie this player killed within the last few minutes (by the guild's feed): we'd be avenging
--- them. Their key, or nil.
function GK.Avenged(key, now)
    local me = LIB.Me()
    for _, e in ipairs(GK.Store().feed) do
        if now - (e.t or 0) > GK.AVENGE_FOR then break end           -- the feed is newest first
        if e.kind == "D" and e.who ~= me and GK.SameName(e.n, key) then return e.who end
    end
    return nil
end

function GK.SendDeath(v, zone, times)
    AddFeed({ t = time(), who = LIB.Me(), kind = "D", n = v.key, c = v.c, l = v.l, z = zone })
    -- Our own deaths count in the guild's wanted list too.
    GK.NoteWanted(LIB.Me(), v.key, v.c, v.r, v.l, times)
    if not GK.db.share then return end
    Send(Msg("D", PROTO, v.key, v.c, v.r, v.l, zone, times))
end

--- The guild's most wanted: who killed us, how often, and whom.
function GK.NoteWanted(victim, key, c, r, l, times)
    if not (victim and key) then return end
    local wanted = GK.Store().wanted
    local w = wanted[key]
    if not w then
        if Count(wanted) >= MAX_WANTED then
            -- make room: the one heard of longest ago
            local oldest, oldKey
            for k, v in pairs(wanted) do
                if not oldest or (v.last or 0) < oldest then oldest, oldKey = v.last or 0, k end
            end
            if oldKey then wanted[oldKey] = nil end
        end
        w = { victims = {} }
        wanted[key] = w
    end
    w.c, w.r, w.l = c or w.c, r or w.r, l or w.l
    local now = time()
    w.last = now
    if w.victims[victim] or Count(w.victims) < MAX_HUNTERS then w.victims[victim] = times end
    -- Each death heard is one more: when, and whom. Flat pairs, victim then time, oldest first; only
    -- the last two hours are ever asked about, so nothing older is kept.
    local recent = w.recent or {}
    recent[#recent + 1] = victim
    recent[#recent + 1] = now
    w.recent = recent
    GK.PruneRecent(w, now)
end

--- Drop the deaths older than the longest rule, and the oldest beyond the cap. In place: no table made.
function GK.PruneRecent(w, now)
    local recent = w.recent
    if not recent then return end
    local n, j = #recent, 1
    local skip = math.max(0, n / 2 - RECENT_PAIRS)      -- pairs over the cap, dropped from the front
    for i = 1, n, 2 do
        local t = recent[i + 1]
        if (i + 1) / 2 > skip and type(t) == "number" and now - t <= RAMPAGE_FOR then
            recent[j], recent[j + 1] = recent[i], recent[i + 1]
            j = j + 2
        end
    end
    for i = j, n do recent[i] = nil end
    if #recent == 0 then w.recent = nil end
end

--- Has this enemy just earned an order that posts itself, by the deaths the guild has heard of, as
--- seen from `victim`'s latest death? The sentence that says why, and "r" (rampage) or "c" (camping);
--- nil when neither rule holds.
function GK.AutoReason(key, victim, now)
    local w = GK.Store().wanted[key]
    local recent = w and w.recent
    if not recent then return nil end
    local theirs, seen, names = 0, {}, {}
    for i = 1, #recent, 2 do
        local who, t = recent[i], tonumber(recent[i + 1]) or 0
        if now - t <= RAMPAGE_FOR and not seen[who] then
            seen[who] = true
            names[#names + 1] = GK.Show(who)
        end
        if who == victim and now - t <= CAMP_FOR then theirs = theirs + 1 end
    end
    if #names >= RAMPAGE_VICTIMS then
        local list
        if #names == 3 then
            list = ("%s, %s and %s"):format(names[1], names[2], names[3])
        else
            list = ("%s, %s, %s and %d more"):format(names[1], names[2], names[3], #names - 3)
        end
        return ("Killed %s in two hours."):format(list), "r"
    end
    if theirs >= CAMP_DEATHS then
        return ("Killed %s %d times in half an hour."):format(GK.Show(victim), theirs), "c"
    end
    return nil
end

--- Most wanted, the most kills on the guild first: { { key, total, w } }.
function GK.MostWanted()
    local list = {}
    for key, w in pairs(GK.Store().wanted) do
        local total = 0
        for _, n in pairs(w.victims) do total = total + n end
        list[#list + 1] = { key = key, total = total, w = w }
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    return list
end

-- ---------------------------------------------------------------------------
-- What others send
-- ---------------------------------------------------------------------------
local function OnBoard(sender, f)
    local board = GK.Store().board
    if not board[sender] and Count(board) >= MAX_BOARD then return end
    local p, k, d = Int(f[3], 0, 1e7), Int(f[4], 0, 1e6), Int(f[5], 0, 1e6)
    if not (p and k and d) then return end
    -- This week's score came later: an older client sends none, and then has none this week.
    local wp, wk, wd, wid = Int(f[8], 0, 1e7), Int(f[9], 0, 1e6), Int(f[10], 0, 1e6), Int(f[11], 0, 2 ^ 31)
    -- The same guildie sends this after every kill and death: fill their row in, don't make a new one.
    local r = board[sender]
    if not r then
        r = {}
        board[sender] = r
    end
    r.p, r.k, r.d, r.l, r.c, r.t = p, k, d, GK.ValidLevel(f[6]), GK.ValidClass(f[7]), time()
    r.wp, r.wk, r.wd, r.wid = wp, wk, wd, wid
    -- The profile's numbers. A streak longer than all their kills, or a best below the streak now,
    -- is not a record anyone could have: such a field is dropped, not believed.
    local streak, best = Int(f[12], 0, k), Int(f[13], 0, k)
    if streak and best and best < streak then streak, best = nil, nil end
    r.st, r.bs = streak, best
    r.od, r.ow = Int(f[14], 0, 1e6), Int(f[15], 0, 1e12)
    r.nm = GK.Clean(f[16], 64)
    r.nt = r.nm and Int(f[17], 1, 1e6) or nil
end

local function OnKill(sender, f)
    local name = GK.Clean(f[3], 64)
    if not name then return end
    local c, r, l = GK.ValidClass(f[4]), GK.Clean(f[5], 20), GK.ValidLevel(f[6])
    AddFeed({ t = time(), who = sender, kind = "K", n = name, c = c, l = l,
        z = GK.Clean(f[7], 40), p = Int(f[8], 0, 100), av = GK.Clean(f[9], 64) })
    GK.NoteSlain(sender, name, c, r, l, Int(f[10], 1, 1e6))
end

local function OnDeath(sender, f)
    local name = GK.Clean(f[3], 64)
    local times = Int(f[8], 1, 100000)
    if not (name and times) then return end
    local c, l = GK.ValidClass(f[4]), GK.ValidLevel(f[6])
    GK.NoteWanted(sender, name, c, GK.Clean(f[5], 20), l, times)
    AddFeed({ t = time(), who = sender, kind = "D", n = name, c = c, l = l, z = GK.Clean(f[7], 40) })
end

local function OnOrder(sender, f)
    local id = Int(f[3], 1, 2 ^ 31)
    local name = GK.Clean(f[4], 64)
    local state = STATES[f[12]] and f[12] or nil
    if not (id and name and state) then return end
    local s, now = GK.Store(), time()
    local key = sender .. "#" .. id
    local o = s.orders[key]
    local fresh = not o
    if fresh then
        if state == "o" then
            local open = 0
            for _, x in pairs(s.orders) do
                if x.by == sender and x.state == "o" then open = open + 1 end
            end
            if open >= MAX_OPEN_PER_POSTER then return end
        end
        o = { key = key, id = id, by = sender, hunters = {}, state = state }
        s.orders[key] = o
    end
    o.n = name
    o.c, o.r, o.l = GK.ValidClass(f[5]), GK.Clean(f[6], 20), GK.ValidLevel(f[7])
    local guid = f[8]
    o.guid = (type(guid) == "string" and guid:match("^Player%-%d+%-%x+$")) and guid or o.guid
    o.reward = Int(f[9], 0, MAX_REWARD) or 0
    o.t = math.min(Int(f[10], 0, 2 ^ 31) or now, now)
    o.exp = math.max(math.min(Int(f[11], 0, 2 ^ 31) or (now + ORDER_DAYS * GK.DAY), now + 14 * GK.DAY), o.t)
    o.note = GK.Clean(f[14], 80)
    -- r or c: the poster's death posted it. Read every time, not only the first: an order its poster
    -- has since edited by hand arrives without it, and is an ordinary order from then on.
    o.auto = (f[15] == "r" or f[15] == "c") and f[15] or nil
    local was = o.state
    -- Never backwards: an "open" from a poster who hasn't heard of the kill yet doesn't reopen it.
    if STATES[state] >= STATES[was] then o.state = state end
    local doneBy = GK.Clean(f[13], 64)
    if doneBy and o.state ~= "o" then o.doneBy = doneBy end       -- the poster says who was first
    if o.state ~= "o" and not o.doneAt then o.doneAt = now end
    Touched()
    Trim(s)
    if fresh and o.state == "o" then
        AddFeed({ t = now, who = sender, kind = "C", n = o.n, c = o.c, l = o.l, p = o.reward, au = o.auto and true or nil })
        if GK.db.letters then GK.OrderLetter(o) end
    elseif was ~= o.state and o.state == "p" and o.doneBy == LIB.Me() and (o.reward or 0) > 0 then
        GK.PaidLetter(o)
    end
    if o.state ~= "o" then GK.char.accepted[key] = nil end
end

local function OnAccept(sender, f)
    local poster, id = GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31)
    local o = poster and id and GK.Store().orders[poster .. "#" .. id]
    if not o then return end
    o.hunters = o.hunters or {}
    if f[5] == "1" then
        if o.hunters[sender] or Count(o.hunters) < MAX_HUNTERS then o.hunters[sender] = true end
    else
        o.hunters[sender] = nil
    end
end

local function OnFulfil(sender, f)
    local poster, id = GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31)
    local o = poster and id and GK.Store().orders[poster .. "#" .. id]
    if not o or o.state ~= "o" then return end      -- the first one we hear of wins
    o.state, o.doneBy, o.doneAt, o.doneZone = "d", sender, time(), GK.Clean(f[5], 40)
    Touched()
    AddFeed({ t = o.doneAt, who = sender, kind = "F", n = o.n, c = o.c, l = o.l, p = o.reward, z = o.doneZone })
    local me = LIB.Me()
    local share = (o.by == me and (o.reward or 0)) or (o.pot and o.pot[me]) or 0
    if o.by == me then SendOrder(o) end               -- the poster's word settles who was first
    if o.by == me or share > 0 or GK.char.accepted[o.key] then
        GK.CompleteLetter(o)                          -- yours, backed by you, or you were hunting them
    end
    if share > 0 then
        -- Money owed is the one kind of news that also goes in chat.
        print(("%s: %s fulfilled the kill order on %s - send them %s in the mail."):format(GK.TAG,
            GK.Show(sender), GK.Show(o.n), GK.MoneyText(share)))
    end
    GK.char.accepted[o.key] = nil
end

local function OnPot(sender, f)
    local poster, id = GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31)
    local copper = Int(f[5], 0, MAX_REWARD)
    local o = poster and id and GK.Store().orders[poster .. "#" .. id]
    if not (o and copper) or sender == o.by then return end
    -- A share stays as it was promised once the order has closed: the kill was made for that pot.
    if o.state ~= "o" and o.pot and o.pot[sender] then return end
    o.pot = o.pot or {}
    if not o.pot[sender] and Count(o.pot) >= MAX_BACKERS then return end
    local was = o.pot[sender]
    o.pot[sender] = copper > 0 and copper or nil
    if copper > 0 and not was then
        AddFeed({ t = time(), who = sender, kind = "T", n = o.n, c = o.c, l = o.l, p = copper })
    end
end

local function OnSharePaid(sender, f)
    local poster, id = GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31)
    local o = poster and id and GK.Store().orders[poster .. "#" .. id]
    if not (o and o.pot and o.pot[sender]) or (o.paid and o.paid[sender]) then return end
    o.paid = o.paid or {}
    o.paid[sender] = true
    if o.doneBy == LIB.Me() then GK.PaidLetter(o, sender, o.pot[sender]) end
end

local function OnSighting(sender, f)
    local poster, id = GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31)
    local o = poster and id and GK.Store().orders[poster .. "#" .. id]
    if not o or o.state ~= "o" then return end
    local zone = GK.Clean(f[5], 40)
    -- Where they stood: a map and a spot on it, all three or none. A map id is any positive number the
    -- client knows; nothing outside the map's own square is a place.
    local m, x, y = Int(f[7], 1, 1e6), Int(f[8], 0, 1000), Int(f[9], 0, 1000)
    if not (m and x and y) then m, x, y = nil, nil, nil end
    o.seen = { by = sender, z = zone, t = time(), l = GK.ValidLevel(f[6]), m = m, x = x, y = y }
    if GK.char.accepted[o.key] and GK.db.alertNear then
        GK.Warn(("%s saw %s%s"):format(GK.Show(sender), GK.Show(o.n), zone and (" in " .. zone) or ""), false)
    end
end

local replyAfter = 0
local function OnAsk()
    -- Everyone logging in at once asks at once: answer once, a few seconds later.
    if GetTime() < replyAfter then return end
    replyAfter = GetTime() + 30
    C_Timer.After(2 + math.random() * 4, function()
        GK.SendBoard()
        local me, now, sent = LIB.Me(), time(), 0
        for _, o in pairs(GK.Store().orders) do
            local recent = o.state == "o" or now - (o.doneAt or o.t or 0) < ORDER_DAYS * GK.DAY
            if recent and sent < 30 then
                if o.by == me then
                    SendOrder(o)
                    sent = sent + 1
                end
                -- what I put in someone else's pot, and whether I've paid it
                local mine = o.pot and o.pot[me]
                if mine then
                    Send(Msg("T", PROTO, o.by, o.id, mine))
                    if o.paid and o.paid[me] then Send(Msg("Y", PROTO, o.by, o.id)) end
                    sent = sent + 1
                end
            end
        end
    end)
end

local HANDLERS = { B = OnBoard, Q = OnAsk, K = OnKill, D = OnDeath, C = OnOrder, A = OnAccept, F = OnFulfil,
    S = OnSighting, T = OnPot, Y = OnSharePaid }

local function OnMessage(_, text, dist, sender)
    if dist ~= "GUILD" or type(text) ~= "string" or #text > 600 or not GK.char then return end
    local f = Split(text)
    if Int(f[2], 1, 1000) ~= PROTO then return end
    local fn = HANDLERS[f[1]]
    if not fn then return end
    fn(sender, f)
    GK.Changed()
end
-- The test panel's pretend guildies (Debug.lua): their messages go through the same reader as real ones.
GK.ReceiveForTest = OnMessage
--- The test panel put the orders back as they were: the index must not keep the ones it removed.
function GK.InvalidateOrders() Touched() end

-- ---------------------------------------------------------------------------
-- Housekeeping: orders run out, closed ones go, silent guildies leave the board
-- ---------------------------------------------------------------------------
function GK.Sweep()
    local s, now, me = GK.Store(), time(), LIB.Me()
    for key, o in pairs(s.orders) do
        if o.state == "o" and (o.exp or 0) < now then
            o.state, o.doneAt = "e", now
            GK.char.accepted[key] = nil
            if o.by == me then
                SendOrder(o)
                GK.ExpiredLetter(o)
            end
        elseif o.state ~= "o" then
            local age = now - (o.paidAt or o.doneAt or o.exp or o.t or now)
            if age > (o.state == "d" and KEEP_OWED or KEEP_CLOSED) then
                s.orders[key] = nil
                GK.char.accepted[key] = nil
            end
        end
    end
    Touched()
    for who, r in pairs(s.board) do
        if now - (r.t or 0) > BOARD_STALE then s.board[who] = nil end
    end
    -- the deaths kept for the automatic orders: two hours at most, then nothing
    for _, w in pairs(s.wanted) do GK.PruneRecent(w, now) end
    GK.PruneSeen()
    GK.Changed()
end

function GK.StartGuild()
    LIB.RegisterComm(PREFIX, OnMessage)
    C_Timer.After(8, function()
        GK.Sweep()
        Send(Msg("Q", PROTO))
        GK.SendBoard()
    end)
    C_Timer.NewTicker(600, GK.Sweep)
end
