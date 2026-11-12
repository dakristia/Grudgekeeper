-- Grudgekeeper - the guild: leaderboard, kill orders, who is wanted, the feed.
-- Everyone sends only their OWN things: their score, their kills and deaths, the orders they posted,
-- the orders they fulfilled. Nobody can change another player's score or order. An order's
-- poster has the last word on it, and a guildie who was offline hears the poster's version next time.
-- Messages, fields separated by ';' (every text field goes through GK.Clean on the way in). A field
-- added later goes on the END, so an older client reads what it knows and ignores the rest:
--   B;1;points;kills;deaths;level;class;weekPoints;weekKills;weekDeaths;weekId;streak;bestStreak;
--       ordersDone;bountyWon;nemesis;nemesisTimes;race;sex;assists;weekAssists;parts
--                                                              my score, my profile's numbers, and
--                                                              my race (file token) and sex (2 or 3),
--                                                              for my portrait in the ledger; parts:
--                                                              what each of my PCs made of the score
--                                                              ("One character, more than one PC")
--   Q;1                                                        tell me everything (at login)
--   K;1;name;class;race;level;zone;points;avenged;times;raceFile;sex;spree
--                                                              I killed someone (avenging a guildie;
--                                                              times: how often I have, in all; raceFile
--                                                              and sex: the target's, for their race's face;
--                                                              spree: my kills worth points in a row, with
--                                                              this one, so a guildie sees a milestone)
--   D;1;name;class;race;level;zone;times;raceFile;sex          someone killed me (times in all; raceFile
--                                                              and sex: the killer's, for their race's face)
--   H;1;name;class;race;level;zone;points                      I helped a groupmate kill someone
--                                                              (the news only: the kill is theirs)
--   C;1;id;name;class;race;level;guid;reward;created;expires;state;doneBy;note;auto;raceFile;sex
--                                                              an order of mine, as it stands (auto:
--                                                              r or c when my death posted it, below;
--                                                              raceFile and sex: the target's, for their
--                                                              race's face)
--   (A;1;poster;id;on, I took or dropped an order: retired 2026-11-07. Nobody takes an order any more -
--   "hey, we put out an order, kill this one" is the whole of it, the owner. What older clients send is
--   ignored.)
--   F;1;poster;id;zone                                         I fulfilled an order
--   O;1;poster;<C's fields from id on>                         a guildie's order, passed on while
--                                                              they are away (answering a Q)
--   P;1;poster;id;backer;copper                                a guildie's share of an open order's
--                                                              pot, passed on likewise
--   R;1;guildie;<B's fields from points on to sex>;heard;assists;weekAssists;parts
--                                                              a guildie's board row, passed on
--                                                              likewise, and when I last heard them
--                                                              (B's later fields go after heard); the
--                                                              row of whoever asked goes back to them
--   S;1;poster;id;zone;level;map;x;y                           I saw an order's target, standing here
--                                                              (x and y in thousandths of the map)
--   T;1;poster;id;copper                                       my share of an order's pot is this
--   U;1;name                                                   forget my kills, deaths and news about
--                                                              this player (a grudge that was wrong)
--   Y;1;poster;id                                              I paid my share of a fulfilled order
-- Order states: o open, d fulfilled (a bounty may be owed), p paid, x withdrawn, e expired.
-- The pot: the poster's own reward, plus what anyone else puts in (T). Each backer owns their share,
-- owes it to whoever fulfils the order, and says when they paid it (Y); the poster's own part is
-- paid with the order's state (p), as before the pot existed.
-- Worst case a guild can make us keep: 150 orders (10 open per poster), 500 board rows (6 parts each), 200 wanted,
-- 200 wanted (50 guildies each), 200 slain (enemies the guild has killed, 20 killers each), 200 tormentors
-- (enemies and their count of us killed, Core.lua), 500 guildies' last sprees (in memory only), 40 feed
-- lines and 20 backers per order (a share passed on, P, counts against the same 20). Every sender is
-- also held to LibForever's 30 messages / 10 s.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local PREFIX = "Grudgekeeper"
GK.PREFIX = PREFIX
local PROTO = 1
local MAX_OPEN_PER_POSTER = 10
local MAX_ORDERS = 150
local MAX_BOARD = 500
local MAX_SPREES = 500
local MAX_WANTED = 200
local MAX_SLAIN = 200
local MAX_SLAYERS = 20
local MAX_FEED = 40
local MAX_VICTIMS = 50
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

-- The race file token and sex to send for a player, so a client that never saw them can still draw
-- their face. LookOf takes the ones the caller already has when both are set, because they are fresher.
local function LookOf(key, rf, sx)
    if rf and sx then return rf, sx end
    local face = GK.FaceOf(key)
    return face.rf, face.sx
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
-- One character, more than one PC
-- ---------------------------------------------------------------------------
-- A character's record lives in the saved file of the PC it was played on, and nothing moves it to
-- another. A guildie who logged in on a second PC started there from 0, and that PC's first B wrote 0
-- over their row on every board; back on the first PC, its B wrote the old score back, and what the
-- second PC made was gone (Happy Idiot, 2026-11-11). So each PC keeps its own part of the score under a
-- mark of its own (GK.ClaimPC), and a B names every part its sender knows of:
--   mark:u:points:kills:deaths:assists:weekId:weekPoints:weekKills:weekDeaths:weekAssists, joined by ','
-- u is 1 for a part that holds the score from before marks existed. A part only grows, so two copies of
-- one join by taking the larger of each number, and a row is the sum of its parts - on a guildie's board,
-- and in the player's own record when the guild passes their row back after they log in. Whichever PC
-- spoke last, the sum is the same.
-- A row from before marks has no parts. When a B with parts comes over one, the old row is kept as the
-- part "?" - it may be another PC's whole score - until the parts that held a score from before marks (u)
-- add up to as much, and then it goes, as counted in them. A brand-new PC's part (no u) never covers it:
-- that PC began at 0, so whatever "?" holds, it did not make.
local MAX_PARTS = 6                     -- the old row "?" included; a seventh PC is not heard of
local PART_NUMS = { "p", "k", "d", "a" }
local WEEK_NUMS = { "wp", "wk", "wd", "wa" }

--- The parts a B or an R names, by mark; nil when it names none (an older client, or a row without).
local function ReadParts(text)
    if type(text) ~= "string" or text == "" or #text > 500 then return nil end
    local out, n = {}, 0
    for token in text:gmatch("[^,]+") do
        local id, u, p, k, d, a, w, wp, wk, wd, wa = token:match(
            "^([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)$")
        local mark = id == "?" or (id and id:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$"))
        if mark and not out[id] then
            local part = { u = (u == "1" and id ~= "?") or nil, p = Int(p, 0, 1e7), k = Int(k, 0, 1e6),
                d = Int(d, 0, 1e6), a = Int(a, 0, 1e6) or 0, w = Int(w, 0, 2 ^ 31) }
            if part.p and part.k and part.d then
                if part.w then
                    part.wp, part.wk = Int(wp, 0, 1e7) or 0, Int(wk, 0, 1e6) or 0
                    part.wd, part.wa = Int(wd, 0, 1e6) or 0, Int(wa, 0, 1e6) or 0
                end
                out[id] = part
                n = n + 1
                if n >= MAX_PARTS then break end
            end
        end
    end
    return n > 0 and out or nil
end

local function PartsText(parts)
    if not parts then return nil end
    local ids = {}
    for id in pairs(parts) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = {}
    for i = 1, math.min(#ids, MAX_PARTS) do
        local x = parts[ids[i]]
        out[i] = table.concat({ ids[i], x.u and "1" or "", x.p or 0, x.k or 0, x.d or 0, x.a or 0, x.w or "",
            x.w and (x.wp or 0) or "", x.w and (x.wk or 0) or "", x.w and (x.wd or 0) or "",
            x.w and (x.wa or 0) or "" }, ":")
    end
    return #out > 0 and table.concat(out, ",") or nil
end

--- One part into a set of them: the larger of each number, this week's numbers from the latest week.
local function MergePart(set, id, x)
    local have = set[id]
    if not have then
        if Count(set) >= MAX_PARTS then return end
        have = {}
        set[id] = have
    end
    for _, f in ipairs(PART_NUMS) do have[f] = math.max(have[f] or 0, x[f] or 0) end
    have.u = have.u or x.u
    if x.w and (not have.w or x.w > have.w) then
        have.w = x.w
        for _, f in ipairs(WEEK_NUMS) do have[f] = x[f] or 0 end
    elseif x.w and x.w == have.w then
        for _, f in ipairs(WEEK_NUMS) do have[f] = math.max(have[f] or 0, x[f] or 0) end
    end
end

--- The old row "?" goes once the parts holding a score from before marks add up to at least as much.
--- extra: our own part, which is not in the set.
local function DropCovered(set, extra)
    local old = set["?"]
    if not old then return end
    local sum, any = { p = 0, k = 0, d = 0, a = 0 }, false
    local function Add(x)
        if not (x and x.u) then return end
        any = true
        for _, f in ipairs(PART_NUMS) do sum[f] = sum[f] + (x[f] or 0) end
    end
    for id, x in pairs(set) do
        if id ~= "?" then Add(x) end
    end
    Add(extra)
    if not any then return end
    for _, f in ipairs(PART_NUMS) do
        if sum[f] < (old[f] or 0) then return end
    end
    set["?"] = nil
end

--- The sum of a set of parts; this week's numbers only from the parts made in week `wid`.
local function SumParts(set, wid)
    local s = { p = 0, k = 0, d = 0, a = 0, wp = 0, wk = 0, wd = 0, wa = 0 }
    for _, x in pairs(set) do
        for _, f in ipairs(PART_NUMS) do s[f] = s[f] + (x[f] or 0) end
        if wid and x.w == wid then
            for _, f in ipairs(WEEK_NUMS) do s[f] = s[f] + (x[f] or 0) end
        end
    end
    return s
end

--- A row's score is the sum of its parts.
local function Total(r)
    local s = SumParts(r.parts, r.wid)
    r.p, r.k, r.d, r.a = s.p, s.k, s.d, s.a
    if r.wid then r.wp, r.wk, r.wd, r.wa = s.wp, s.wk, s.wd, s.wa end
end

--- Our own part: the record less what the other PCs made. Every number in the record only grows, and the
--- record grew by exactly what each other part brought (GK.MergeMine), so none of these goes below 0.
local function OwnPart(c, w, others)
    local s = SumParts(others, w.id)
    local function Left(have, less) return math.max(0, (have or 0) - less) end
    return { u = c.u, p = Left(c.points, s.p), k = Left(c.kills, s.k), d = Left(c.deaths, s.d),
        a = Left(c.assists, s.a), w = w.id, wp = Left(w.p, s.wp), wk = Left(w.k, s.wk), wd = Left(w.d, s.wd),
        wa = Left(w.a, s.wa) }
end

--- Every part this PC knows of, its own among them, as a B says them.
function GK.MyPartsText()
    local c, w = GK.char, GK.Week()
    GK.ClaimPC(c)
    local all = { [c.pc] = OwnPart(c, w, c.parts) }
    for id, x in pairs(c.parts) do all[id] = x end
    return PartsText(all)
end

--- Our own row, passed back by a guildie (R, after we asked at login): the parts other PCs made, and the
--- old row "?", join the record, and the record grows by what they bring. Our own part we know better
--- than anyone, so a part under our own mark is never taken. Returns whether anything changed.
function GK.MergeMine(parts)
    local c, w = GK.char, GK.Week()
    GK.ClaimPC(c)
    local set = c.parts
    local before = SumParts(set, w.id)
    local own = OwnPart(c, w, set)
    for id, x in pairs(parts) do
        if id ~= c.pc then MergePart(set, id, x) end
    end
    DropCovered(set, own)
    local after = SumParts(set, w.id)
    local changed = false
    for f, v in pairs(after) do
        if v ~= before[f] then changed = true end
    end
    if not changed then return false end
    c.points = c.points + after.p - before.p
    c.kills = c.kills + after.k - before.k
    c.deaths = c.deaths + after.d - before.d
    c.assists = (c.assists or 0) + after.a - before.a
    w.p, w.k = w.p + after.wp - before.wp, w.k + after.wk - before.wk
    w.d, w.a = w.d + after.wd - before.wd, (w.a or 0) + after.wa - before.wa
    return true
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
        plainName[key], plainFirst[key] = name, name:match("^[^ ]+") or name    -- not %S: see GK.SameName
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

-- ---------------------------------------------------------------------------
-- The bounty, shared: everyone who got the target - the killing blow and the guildies with them
-- (GroupHelpers, below) - gets an equal part of every gold piece in the pot ("samarbeider folk i samme
-- guild så fortjener de begge delt reward", the owner, 2026-11-09). Each who put gold in pays each hunter
-- their part straight, so nobody lays out for anyone; what doesn't divide goes to the killing blow. A
-- payment is kept per payer and hunter (o.paidTo), and said per hunter with Y. An older client knows only
-- the whole: a backer's o.paid, the poster's state "p" - both still mean everything is paid.
-- ---------------------------------------------------------------------------
--- Who got an order's target: the killing blow first, then who was with them. {} while it is open.
function GK.Hunters(o)
    if not o.doneBy then return {} end
    local out, have = { o.doneBy }, { [o.doneBy] = true }
    for _, k in ipairs(o.helpers or {}) do
        if not have[k] then
            have[k] = true
            out[#out + 1] = k
        end
    end
    return out
end

--- A hunter's part of an amount: an equal share, the killing blow taking what doesn't divide. 0 for anyone
--- who didn't get them.
function GK.Part(o, amount, hunter)
    local hunters = GK.Hunters(o)
    local n = #hunters
    if n == 0 or (amount or 0) <= 0 then return 0 end
    local each = math.floor(amount / n)
    for i, h in ipairs(hunters) do
        if h == hunter then return i == 1 and (amount - each * (n - 1)) or each end
    end
    return 0
end

--- What a payer put into an order: the poster their reward, a backer their share.
local function Given(o, payer)
    if payer == o.by then return o.reward or 0 end
    return o.pot and o.pot[payer] or 0
end

--- Whether a payer has paid a hunter their part: per hunter, or the whole as an older client marks it.
function GK.IsPaid(o, payer, hunter)
    if payer == o.by and o.state == "p" then return true end
    if o.paid and o.paid[payer] then return true end
    return o.paidTo ~= nil and o.paidTo[payer] ~= nil and o.paidTo[payer][hunter] == true
end

--- Whether a payer has paid every hunter but themselves.
local function AllPaid(o, payer)
    for _, h in ipairs(GK.Hunters(o)) do
        if h ~= payer and not GK.IsPaid(o, payer, h) then return false end
    end
    return true
end

local function MarkPaidTo(o, payer, hunter)
    o.paidTo = o.paidTo or {}
    o.paidTo[payer] = o.paidTo[payer] or {}
    o.paidTo[payer][hunter] = true
end

--- What a hunter has coming from an order: their part of everyone else's gold (their own stays theirs).
function GK.DueTo(o, hunter)
    local due = 0
    if o.by ~= hunter then due = due + GK.Part(o, o.reward or 0, hunter) end
    for who, copper in pairs(o.pot or {}) do
        if who ~= hunter then due = due + GK.Part(o, copper, hunter) end
    end
    return due
end

--- What I owe for orders others got: my reward on orders I posted and my share on orders I backed, a
--- part to each hunter but me. { { o = order, share = copper, to = hunter } }, the oldest first.
function GK.Owed()
    local me, list = LIB.Me(), {}
    for _, o in pairs(GK.Store().orders) do
        if o.doneBy and (o.state == "d" or o.state == "p") then
            local function Owe(amount)
                if amount <= 0 then return end
                for _, h in ipairs(GK.Hunters(o)) do
                    if h ~= me and not GK.IsPaid(o, me, h) then
                        local part = GK.Part(o, amount, h)
                        if part > 0 then list[#list + 1] = { o = o, share = part, to = h } end
                    end
                end
            end
            if o.by == me then Owe(o.reward or 0) end
            local mine = o.pot and o.pot[me]
            if mine and o.by ~= me then Owe(mine) end
        end
    end
    table.sort(list, function(a, b)
        if (a.o.doneAt or 0) ~= (b.o.doneAt or 0) then return (a.o.doneAt or 0) < (b.o.doneAt or 0) end
        return a.to < b.to
    end)
    return list
end

--- My part of a fulfilled order is paid: to one hunter (to), or to every hunter. Each said with Y; all paid,
--- the whole is marked as every client knows it - the poster's order "p", a backer's o.paid.
function GK.PayShare(o, to)
    local me = LIB.Me()
    if Given(o, me) <= 0 or not o.doneBy then return end
    for _, h in ipairs(to and { to } or GK.Hunters(o)) do
        if h ~= me and not GK.IsPaid(o, me, h) then
            MarkPaidTo(o, me, h)
            Send(Msg("Y", PROTO, o.by, o.id, h))
        end
    end
    if AllPaid(o, me) then
        if o.by == me then
            GK.MarkPaid(o)
        else
            o.paid = o.paid or {}
            o.paid[me] = true
        end
    end
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

local function OrderText(o)
    local rf, sx = LookOf(o.n)
    return Msg("C", PROTO, o.id, o.n, o.c, o.r, o.l, o.guid, o.reward, o.t, o.exp, o.state, o.doneBy, o.note, o.auto,
        rf, sx)
end

local function SendOrder(o) Send(OrderText(o)) end

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
        state = "o", auto = auto }
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

-- ---------------------------------------------------------------------------
-- Who helped: the group members near when our kill fulfilled an order. The killing blow is one player's,
-- the kill is often two or three ("jeg og kompis ... gikk sammen og drepte han. jeg fikk killing blow og det
-- stod ikke noe om at han hadde vært med", the owner, 2026-11-09). A member of our party or raid in sight
-- (UnitIsVisible: within about a hundred yards) counts - the combat log that would say who hit them is
-- closed to addons. They go with the F, so each of them hears it was theirs too.
-- ---------------------------------------------------------------------------
local MAX_HELPERS = 4

local function GroupHelpers()
    if not (IsInGroup and IsInGroup()) then return nil end
    local raid = IsInRaid and IsInRaid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local out = {}
    for i = 1, raid and n or (n - 1) do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsVisible(unit) then
            local key = GK.UnitKey(unit)
            if key and not GK.Secret(key) then out[#out + 1] = key end
            if #out >= MAX_HELPERS then break end
        end
    end
    return #out > 0 and out or nil
end

--- An order's helpers as the F carries them: keys, comma between ("" for none).
local function HelpersText(o)
    return o.helpers and table.concat(o.helpers, ",") or ""
end

--- Whether we are one of an order's helpers.
local function Helped(o)
    for _, k in ipairs(o.helpers or {}) do
        if LIB.IsMyStoredName(k) then return true end
    end
    return false
end
GK.Helped = Helped

--- Players by name, as a sentence says them: "Kari", "Kari and Lars", "Kari, Lars and Edvard".
function GK.NameList(keys)
    local names = {}
    for _, k in ipairs(keys) do names[#names + 1] = GK.Show(k) end
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

--- Who got an order's target, the killing blow first: "Vebjorn", "Vebjorn and Kari".
function GK.WhoGotThem(doneBy, helpers)
    local keys = { doneBy }
    for _, k in ipairs(helpers or {}) do keys[#keys + 1] = k end
    return GK.NameList(keys)
end

--- Our kill fulfilled this order.
function GK.Fulfil(o, zone)
    if o.state ~= "o" then return end
    local me = LIB.Me()
    o.state, o.doneBy, o.doneAt, o.doneZone = "d", me, time(), zone
    Touched()
    -- For the profile: orders fulfilled, and the bounties they carried when the kill was made. Not your
    -- own order: getting its target yourself closes it, but you fulfilled nobody's order ("hvis jeg
    -- fulfiller min egen order burde den ikke ligge som 'fulfilled' på profilen", the owner, 2026-11-09).
    local own = o.by == me
    o.helpers = GroupHelpers()
    if not own then
        GK.char.done = (GK.char.done or 0) + 1
        GK.char.won = (GK.char.won or 0) + GK.DueTo(o, me)        -- our part, the bounty shared (GK.Part)
    end
    -- Sent whatever "share" says: fulfilling an order is the one thing the order exists for.
    Send(Msg("F", PROTO, o.by, o.id, zone, HelpersText(o)))
    if own then SendOrder(o) end
    AddFeed({ t = o.doneAt, who = me, kind = "F", n = o.n, c = o.c, l = o.l, p = o.reward, z = zone,
        own = own or nil, h = o.helpers })
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

--- Whether we may tell the guild an order was fulfilled: it was, by us or with us there, and it is not told
--- yet. o: the order, L: its letter - either can be missing (a letter outlives a trimmed order, and an order
--- its read letter).
function GK.CanTellOrder(o, L)
    if (o and o.told) or (L and L.told) then return false end
    local t = o or L
    if not (t and t.doneBy) or (o and o.state == "o") then return false end
    return LIB.IsMyStoredName(t.doneBy) or Helped(t)
end

--- An order fulfilled, in one line of guild chat, for the guildies without Grudgekeeper - from the player's
--- click on its letter or on its card in the ledger, and once: told from either, neither offers it again.
--- A read letter is gone, and the card is where it can still be told ("jeg hadde lukket letter så fikk det
--- ikke opp igjen", the owner, 2026-11-09). Returns true when it went.
function GK.TellOrder(o, L)
    local t = o or L
    if not t then return false end
    local pot = o and (GK.Pot(o)) or L.pot or L.reward or 0
    local text = ("Grudgekeeper: %s is dead - %s's kill order, fulfilled by %s%s."):format(GK.Show(t.n),
        GK.Show(t.by), GK.WhoGotThem(t.doneBy, t.helpers), pot > 0 and (", bounty " .. GK.MoneyText(pot)) or "")
    if not GK.TellGuild(text) then return false end
    if o then o.told = true end
    if L then L.told = true end
    GK.Changed()
    return true
end

--- Where we saw an order's target: o.seen as Sightings.lua filled it in, our own spot included.
function GK.SendSighting(o)
    local s = o.seen
    if not s then return end
    Send(Msg("S", PROTO, o.by, o.id, s.z, s.l, s.m, s.x, s.y))
end

local function SendBoardNow()
    if not GK.db.share then return end
    local _, class = UnitClass("player")
    local w, c = GK.Week(), GK.char
    local nemesis, f = GK.Nemesis()
    local _, raceFile = UnitRace("player")
    Send(Msg("B", PROTO, c.points, c.kills, c.deaths, UnitLevel("player"), class,
        w.p, w.k, w.d, w.id, c.streak or 0, c.bestStreak or 0, c.done or 0, c.won or 0,
        nemesis, f and f.d or nil, raceFile, UnitSex("player"), c.assists or 0, w.a or 0, GK.MyPartsText()))
end

--- Our row, a moment after the last change - or at once (now), as the login's does, ahead of its Q.
function GK.SendBoard(now)
    if not GK.db.share then return end
    if now then SendBoardNow() else LIB.Debounce("GrudgekeeperBoard", 2, SendBoardNow) end
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

function GK.SendKill(v, zone, points, avenged, times, spree)
    local me = LIB.Me()
    AddFeed({ t = time(), who = me, kind = "K", n = v.key, c = v.c, l = v.l, p = points, z = zone, av = avenged })
    GK.NoteSlain(me, v.key, v.c, v.r, v.l, times)
    if not GK.db.share then return end
    local rf, sx = LookOf(v.key, v.rf, v.sx)
    Send(Msg("K", PROTO, v.key, v.c, v.r, v.l, zone, points, avenged, times, rf, sx, spree))
end

--- Our assist: the news only. The guild's tally of who killed whom stays with the killer's K.
function GK.SendAssist(v, zone, points)
    AddFeed({ t = time(), who = LIB.Me(), kind = "H", n = v.key, c = v.c, l = v.l, p = points, z = zone })
    if not GK.db.share then return end
    Send(Msg("H", PROTO, v.key, v.c, v.r, v.l, zone, points))
end

--- A guildie this player killed within the last few minutes (by the guild's feed): we'd be avenging
--- them. Their key, or nil. before: when the fight we got them in began (Kills.lua). A guildie heard
--- falling at or after it fell in that same fight, and is avenged in a later one only - one of the group
--- dying first is no point more for everyone who then kills or helps kill their killer.
function GK.Avenged(key, now, before)
    local me = LIB.Me()
    for _, e in ipairs(GK.Store().feed) do
        if now - (e.t or 0) > GK.AVENGE_FOR then break end           -- the feed is newest first
        if e.kind == "D" and e.who ~= me and (not before or (e.t or 0) < before) and GK.SameName(e.n, key) then
            return e.who
        end
    end
    return nil
end

function GK.SendDeath(v, zone, times)
    AddFeed({ t = time(), who = LIB.Me(), kind = "D", n = v.key, c = v.c, l = v.l, z = zone })
    -- Our own deaths count in the guild's wanted list too.
    GK.NoteWanted(LIB.Me(), v.key, v.c, v.r, v.l, times)
    if not GK.db.share then return end
    local rf, sx = LookOf(v.key, v.rf, v.sx)
    Send(Msg("D", PROTO, v.key, v.c, v.r, v.l, zone, times, rf, sx))
end

-- ---------------------------------------------------------------------------
-- Forgetting a grudge
-- ---------------------------------------------------------------------------
-- A grudge that should never have been: before 2026-11-06 a death recap that said "Unc" went to whichever
-- Unc we had seen, and a hunter's Arcane Shot was written down as a shaman's (Kills.lua) - and nothing could
-- take it back ("hvordan fjerner jeg", the owner, 2026-11-07). Forgetting removes MY record of a player: my
-- grudge with them and its lines in my log, and my part of what the guild keeps on them - their kills of me
-- (Most wanted), my kills of them, my news about them - and asks the guild to do the same (U). Only ever the
-- sender's own part: a peer may only change their own records. The score stays: those kills and deaths
-- happened, whoever they were to.

--- Take `who`'s part out of what the guild keeps on `key`.
local function ForgetIn(who, key)
    local s = GK.Store()
    local w = s.wanted[key]
    if w then
        w.victims[who] = nil
        if w.recent then
            local kept = {}
            for i = 1, #w.recent, 2 do
                if w.recent[i] ~= who then
                    kept[#kept + 1] = w.recent[i]
                    kept[#kept + 1] = w.recent[i + 1]
                end
            end
            w.recent = #kept > 0 and kept or nil
        end
        if next(w.victims) == nil then s.wanted[key] = nil end
    end
    local e = s.slain[key]
    if e then
        e.by[who] = nil
        if next(e.by) == nil then s.slain[key] = nil end
    end
    local feed = s.feed
    for i = #feed, 1, -1 do
        local n = feed[i]
        if n.who == who and n.n == key and (n.kind == "K" or n.kind == "D" or n.kind == "H") then table.remove(feed, i) end
    end
end

--- Forget my grudge with this player (their key, as my grudges have it), and tell the guild.
function GK.ForgetGrudge(key)
    local me = LIB.Me()
    if not (me and type(key) == "string") then return false end
    GK.char.foes[key] = nil
    local log = GK.char.log
    for i = #log, 1, -1 do
        if log[i].n == key then table.remove(log, i) end
    end
    ForgetIn(me, key)
    if GK.db.share then Send(Msg("U", PROTO, key)) end
    GK.Changed()
    return true
end

local function OnForget(sender, f)
    local key = GK.PlayerKey(GK.Clean(f[3], 64))
    if key then ForgetIn(sender, key) end
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
    if w.victims[victim] or Count(w.victims) < MAX_VICTIMS then w.victims[victim] = times end
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
-- What we heard lately, from anyone: [order key] or ["b:" .. guildie] = GetTime(). An answer to a login
-- passes on only what nobody has said since the ask (Answer, below).
local heard = {}

-- [order key] = GetTime() we last said again that our kill fulfilled it (ApplyOrder)
local resaid = {}
local RESAY_GAP = 60

--- Money owed is the one kind of news that also goes in chat: what we owe on the order, to each hunter.
local function Owing(o)
    local parts = {}
    for _, e in ipairs(GK.Owed()) do
        if e.o == o then parts[#parts + 1] = ("%s %s"):format(GK.Show(e.to), GK.MoneyText(e.share)) end
    end
    if #parts == 0 then return end
    local list = #parts == 1 and parts[1] or (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts])
    print(("%s: %s fulfilled the kill order on %s - mail or trade %s."):format(GK.TAG,
        GK.WhoGotThem(o.doneBy, o.helpers), GK.Show(o.n), list))
end

--- A guildie a relay names, in our spelling. Every guildie reaches us without a realm and is filed under
--- ours (GK.LocalKey's note), so one we have not heard of yet is filed under ours too: else the order a
--- relay brought and the one its poster sends later would be two.
local function GuildieKey(full)
    if type(full) ~= "string" then return nil end
    local k = GK.LocalKey(full)
    if k ~= full then return k end
    local name = full:match("^(.-)%-[^%-]+$") or full
    return name .. "-" .. LIB.Realm()
end

--- A race's file token (letters only, as the client's are) and a sex the game knows (2 male, 3 female),
--- each nil when it is anything else.
local function ReadLook(rf, sx)
    return (type(rf) == "string" and #rf <= 20 and rf:match("^%a+$")) and rf or nil, Int(sx, 2, 3)
end

--- Keeps what a message says a player looks like, so their face shows even if we never saw them. Only
--- when it names both, because a half is no face.
local function KeepLook(name, rf, sx)
    rf, sx = ReadLook(rf, sx)
    if rf and sx then GK.KeepLooks(name, { rf = rf, sx = sx }) end
end

--- The helpers an F names, in our spelling: at most MAX_HELPERS, each once, never the killer.
local function ReadHelpers(field, sender)
    if type(field) ~= "string" or field == "" then return nil end
    local out, have = {}, {}
    for part in field:gmatch("[^,]+") do
        local key = GuildieKey(GK.Clean(part, 64))
        if key and key ~= sender and not have[key] then
            have[key] = true
            out[#out + 1] = key
        end
        if #out >= MAX_HELPERS then break end
    end
    return #out > 0 and out or nil
end

--- A guildie's row on the board from a B (their own word, base 0) or an R (another guildie's copy of it,
--- base 1: the guildie's name comes first). Returns the row, or nil for a message that isn't one.
local function ApplyBoard(who, f, base)
    local function Field(i) return f[base + i] end
    local board = GK.Store().board
    if not board[who] and Count(board) >= MAX_BOARD then return nil end
    local p, k, d = Int(Field(3), 0, 1e7), Int(Field(4), 0, 1e6), Int(Field(5), 0, 1e6)
    if not (p and k and d) then return nil end
    -- This week's score came later: an older client sends none, and then has none this week.
    local wp, wk, wd, wid = Int(Field(8), 0, 1e7), Int(Field(9), 0, 1e6), Int(Field(10), 0, 1e6), Int(Field(11), 0, 2 ^ 31)
    -- The same guildie sends this after every kill and death: fill their row in, don't make a new one.
    local r = board[who]
    if not r then
        r = {}
        board[who] = r
    end
    r.p, r.k, r.d, r.l, r.c, r.t = p, k, d, GK.ValidLevel(Field(6)), GK.ValidClass(Field(7)), time()
    r.wp, r.wk, r.wd, r.wid = wp, wk, wd, wid
    -- The profile's numbers. A streak longer than all their kills, or a best below the streak now,
    -- is not a record anyone could have: such a field is dropped, not believed.
    local streak, best = Int(Field(12), 0, k), Int(Field(13), 0, k)
    if streak and best and best < streak then streak, best = nil, nil end
    r.st, r.bs = streak, best
    r.od, r.ow = Int(Field(14), 0, 1e6), Int(Field(15), 0, 1e12)
    r.nm = GK.Clean(Field(16), 64)
    r.nt = r.nm and Int(Field(17), 1, 1e6) or nil
    -- For their portrait. Anything ReadLook drops leaves the ledger showing their class instead.
    r.rf, r.sx = ReadLook(Field(18), Field(19))
    return r
end

--- Assists came after B's last field and R's heard: in B at 20-21, in R at 22-23. An older client
--- sends none.
local function ApplyAssists(r, a, wa)
    if not r then return end
    r.a, r.wa = Int(a, 0, 1e6), Int(wa, 0, 1e6)
end

--- A guildie's own B. With parts, they join the parts we have of their row and the row is the sum; a row we
--- had from before parts stays as the part "?" ("One character, more than one PC"). Without parts - an
--- older client - the row is what it says, as before parts.
local function OnBoard(sender, f)
    heard["b:" .. sender] = GetTime()
    local was = GK.Store().board[sender]
    local had, old = was and was.parts, nil
    -- only a row the guildie told us themselves: one an older client passed on may be a copy of a row with
    -- parts that lost them on the way, all the PCs' score in one, and kept as "?" it would count twice
    if was and not had and not was.via then
        old = { p = was.p or 0, k = was.k or 0, d = was.d or 0, a = was.a or 0, w = was.wid,
            wp = was.wp or 0, wk = was.wk or 0, wd = was.wd or 0, wa = was.wa or 0 }
    end
    local r = ApplyBoard(sender, f, 0)
    ApplyAssists(r, f[20], f[21])
    if not r then return end
    r.via = nil
    local parts = ReadParts(f[22])
    if not parts then
        r.parts = nil
        return
    end
    local set = had or {}
    if old and old.p + old.k + old.d + old.a > 0 then set["?"] = old end
    for id, x in pairs(parts) do MergePart(set, id, x) end
    DropCovered(set)
    r.parts = set
    Total(r)
end

--- A guildie's row, passed on by another while they are away (R). Only a row we have none of: never over
--- what we have, which is the guildie's own word or a copy as good. When it was last heard of its owner
--- comes with it, so a row passed round and round still leaves the board after BOARD_STALE.
--- Our own row, passed back to us after we asked: what our other PCs made joins our record (GK.MergeMine).
local function OnRelayedBoard(sender, f)
    local who = GuildieKey(GK.Clean(f[3], 64))
    if not who or who == sender then return end
    heard["r:" .. who] = GetTime()
    if LIB.IsMyStoredName(who) then
        local parts = ReadParts(f[24])
        if parts and GK.MergeMine(parts) then GK.SendBoard() end
        return
    end
    heard["b:" .. who] = GetTime()
    if GK.Store().board[who] then return end
    local r = ApplyBoard(who, f, 1)
    if not r then return end
    r.t = math.min(time(), Int(f[21], 0, 2 ^ 31) or time())
    ApplyAssists(r, f[22], f[23])
    -- field 24: the row's parts; empty for a row without, as its owner told it; "~" for one that came to
    -- the relayer by way of an older client; missing when the relayer is an older client
    r.parts = ReadParts(f[24])
    if r.parts then Total(r) else r.via = (f[24] == nil or f[24] == "~") or nil end
end

-- The spree each guildie last told us in a K, in memory only: their D ends it. Not kept in saved data, so
-- a guildie's spree from before our login is unknown to us, and its end is not announced.
local lastSpree = {}

--- A kill of the guild's, and so an end to that enemy's count of us. K carries the spree as its field 13; an
--- older client sends none, and then there is no milestone to tell. K is never passed on (no R or O for
--- it, and the answer to a Q holds none), so every K is a live one: a login's replay can't announce twice.
local function OnKill(sender, f)
    local name = GK.PlayerKey(GK.Clean(f[3], 64))
    if not name then return end
    local c, r, l = GK.ValidClass(f[4]), GK.Clean(f[5], 20), GK.ValidLevel(f[6])
    AddFeed({ t = time(), who = sender, kind = "K", n = name, c = c, l = l,
        z = GK.Clean(f[7], 40), p = Int(f[8], 0, 100), av = GK.LocalKey(GK.Clean(f[9], 64)) })
    GK.NoteSlain(sender, name, c, r, l, Int(f[10], 1, 1e6))
    KeepLook(name, f[11], f[12])
    local spree = Int(f[13], 0, 1e5)
    if spree and (lastSpree[sender] or Count(lastSpree) < MAX_SPREES) then
        local before = lastSpree[sender] or 0
        lastSpree[sender] = spree
        -- only a spree that moved: a kill worth nothing sends the same number again. A lower one started
        -- over on a death whose D we missed, and its milestones count again.
        local tier, key = GK.SpreeTier(spree)
        if tier and spree ~= before then LIB.Fire("GK_SPREE", sender, spree, tier, false, key) end
    end
    local tormented = GK.TormentorEnded(name)
    if tormented then LIB.Fire("GK_TORMENTOR", sender, GK.Show(name), tormented, false) end
end

local function OnAssist(sender, f)
    local name = GK.PlayerKey(GK.Clean(f[3], 64))
    if not name then return end
    AddFeed({ t = time(), who = sender, kind = "H", n = name, c = GK.ValidClass(f[4]), l = GK.ValidLevel(f[6]),
        z = GK.Clean(f[7], 40), p = Int(f[8], 0, 100) })
end

local function OnDeath(sender, f)
    local name = GK.PlayerKey(GK.Clean(f[3], 64))
    local times = Int(f[8], 1, 100000)
    if not (name and times) then return end
    local c, l = GK.ValidClass(f[4]), GK.ValidLevel(f[6])
    GK.NoteWanted(sender, name, c, GK.Clean(f[5], 20), l, times)
    AddFeed({ t = time(), who = sender, kind = "D", n = name, c = c, l = l, z = GK.Clean(f[7], 40) })
    KeepLook(name, f[9], f[10])
    GK.TormentorGrew(name)
    local spree = lastSpree[sender]
    if spree then
        if spree >= GK.SPREE_MIN then LIB.Fire("GK_SPREE_ENDED", sender, spree, GK.Show(name), false) end
        lastSpree[sender] = 0
    end
end

--- An order as its poster sends it (C, base 0), or as another guildie passes it on while the poster is
--- away (O, relayed, base 1: the poster's name comes first). A relay only brings an order we don't have,
--- or moves one we have forward - closed, and by whom if we didn't know. Nothing else about an order we
--- have is a relay's to say: that is the poster's.
local function ApplyOrder(by, f, base, relayed)
    local function Field(i) return f[base + i] end
    local id = Int(Field(3), 1, 2 ^ 31)
    local name = GK.PlayerKey(GK.Clean(Field(4), 64))
    local state = STATES[Field(12)] and Field(12) or nil
    if not (id and name and state) then return end
    KeepLook(name, Field(16), Field(17))
    local s, now = GK.Store(), time()
    local key = by .. "#" .. id
    heard[key] = GetTime()
    local o = s.orders[key]
    local fresh = not o
    if fresh then
        -- an open order that has run out while its poster was away brings nothing
        if relayed and state == "o" and (Int(Field(11), 0, 2 ^ 31) or 0) < now then return end
        if state == "o" then
            local open = 0
            for _, x in pairs(s.orders) do
                if x.by == by and x.state == "o" then open = open + 1 end
            end
            if open >= MAX_OPEN_PER_POSTER then return end
        end
        o = { key = key, id = id, by = by, state = state }
        s.orders[key] = o
    end
    if fresh or not relayed then
        o.n = name
        o.c, o.r, o.l = GK.ValidClass(Field(5)), GK.Clean(Field(6), 20), GK.ValidLevel(Field(7))
        local guid = Field(8)
        o.guid = (type(guid) == "string" and guid:match("^Player%-%d+%-%x+$")) and guid or o.guid
        o.reward = Int(Field(9), 0, MAX_REWARD) or 0
        o.t = math.min(Int(Field(10), 0, 2 ^ 31) or now, now)
        o.exp = math.max(math.min(Int(Field(11), 0, 2 ^ 31) or (now + ORDER_DAYS * GK.DAY), now + 14 * GK.DAY), o.t)
        o.note = GK.Clean(Field(14), 80)
        -- r or c: the poster's death posted it. Read every time, not only the first: an order its poster
        -- has since edited by hand arrives without it, and is an ordinary order from then on.
        o.auto = (Field(15) == "r" or Field(15) == "c") and Field(15) or nil
    end
    local was = o.state
    -- Never backwards: an "open" from a poster who hasn't heard of the kill yet doesn't reopen it.
    if STATES[state] >= STATES[was] then o.state = state end
    -- the poster says who was first, in their spelling of them (GK.LocalKey makes it ours); a relay
    -- only when we had nobody
    local doneBy = GK.LocalKey(GK.Clean(Field(13), 64))
    if doneBy and o.state ~= "o" and (not relayed or not o.doneBy) then o.doneBy = doneBy end
    if o.state ~= "o" and not o.doneAt then o.doneAt = now end
    Touched()
    Trim(s)
    -- The poster still calls it open, and our kill fulfilled it: they were away when it happened, and
    -- nobody else may tell them (OnRelayedOrder takes no order of theirs from a third). So we say it
    -- again, at most once a minute - every answer to a login carries their orders.
    if not relayed and state == "o" and o.state == "d" and o.doneBy == LIB.Me() and o.by ~= o.doneBy then
        local last = resaid[o.key]
        if not last or GetTime() - last > RESAY_GAP then
            resaid[o.key] = GetTime()
            Send(Msg("F", PROTO, o.by, o.id, o.doneZone, HelpersText(o)))
        end
    end
    if fresh and o.state == "o" then
        -- the news is what happened while you were here: an order passed on to you is a letter, not news
        if not relayed then
            AddFeed({ t = now, who = by, kind = "C", n = o.n, c = o.c, l = o.l, p = o.reward, au = o.auto and true or nil })
        end
        if GK.db.letters then GK.OrderLetter(o) end
    elseif not relayed and was ~= o.state and o.state == "p" and o.doneBy == LIB.Me() and (o.reward or 0) > 0
        and not (o.paidTo and o.paidTo[o.by] and o.paidTo[o.by][o.doneBy]) then
        -- the poster's whole, from a client that pays it so (a newer one said our part with Y already)
        GK.PaidLetter(o, nil, GK.Part(o, o.reward, o.doneBy))
    elseif was == "o" and (o.state == "d" or o.state == "p") and o.doneBy and o.doneBy ~= LIB.Me()
        and o.pot and (o.pot[LIB.Me()] or 0) > 0 then
        -- a share of ours in an order fulfilled while we were away: the letter its F would have brought
        GK.CompleteLetter(o)
        Owing(o)
    end
end

local function OnOrder(sender, f) ApplyOrder(sender, f, 0, false) end

--- An order passed on by a guildie while its poster is away (O). Never one of ours - we know our own,
--- and a relay must not make us adopt one - and never the sender's own, which they send as a C.
local function OnRelayedOrder(sender, f)
    local poster = GuildieKey(GK.Clean(f[3], 64))
    if not poster or poster == sender or LIB.IsMyStoredName(poster) then return end
    ApplyOrder(poster, f, 1, true)
end

--- The order a message names by its poster and id. The sender writes the poster as THEY know them, with
--- their own realm on the live servers (GK.LocalKey); an order is only ever filed under its poster as we
--- know them, so the one already filed under that name is the one meant.
local function OrderNamed(poster, id)
    if not (poster and id) then return nil end
    local orders = GK.Store().orders
    local o = orders[poster .. "#" .. id]
    if o then return o end
    local ours = GK.LocalKey(poster, function(k) return orders[k .. "#" .. id] ~= nil end)
    return orders[ours .. "#" .. id]
end

local function OnFulfil(sender, f)
    local o = OrderNamed(GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31))
    if not o or o.state ~= "o" then return end      -- the first one we hear of wins
    o.state, o.doneBy, o.doneAt, o.doneZone = "d", sender, time(), GK.Clean(f[5], 40)
    o.helpers = ReadHelpers(f[6], sender)
    Touched()
    AddFeed({ t = o.doneAt, who = sender, kind = "F", n = o.n, c = o.c, l = o.l, p = o.reward, z = o.doneZone,
        own = o.by == sender or nil, h = o.helpers })
    local me = LIB.Me()
    local share = (o.by == me and (o.reward or 0)) or (o.pot and o.pot[me]) or 0
    if o.by == me then SendOrder(o) end               -- the poster's word settles who was first
    -- got with you there: yours too, on your profile as on the killer's (not your own order: GK.Fulfil)
    if Helped(o) and o.by ~= me then
        GK.char.done = (GK.char.done or 0) + 1
        GK.char.won = (GK.char.won or 0) + GK.DueTo(o, me)
        GK.SendBoard()
    end
    -- yours, backed by you, or got with you there
    if o.by == me or share > 0 or Helped(o) then GK.CompleteLetter(o) end
    if share > 0 then Owing(o) end
end

local function OnPot(sender, f)
    local copper = Int(f[5], 0, MAX_REWARD)
    local o = OrderNamed(GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31))
    if not (o and copper) or sender == o.by then return end
    -- A share stays as it was promised once the order has closed: the kill was made for that pot.
    if o.state ~= "o" and o.pot and o.pot[sender] then return end
    o.pot = o.pot or {}
    if not o.pot[sender] and Count(o.pot) >= MAX_BACKERS then return end
    heard["t:" .. o.key .. ":" .. sender] = GetTime()
    local was = o.pot[sender]
    o.pot[sender] = copper > 0 and copper or nil
    if copper > 0 and not was then
        AddFeed({ t = time(), who = sender, kind = "T", n = o.n, c = o.c, l = o.l, p = copper })
    end
end

--- A guildie's share of an open order's pot, passed on by another while that backer is away (P). The
--- poster's own answer brings the order but not what others put in it, so a bounty read 50s that was 70s
--- once the backer of the other 20s had logged out. Only a share we have none of, on an open order we
--- have: never over what we have - the backer's own word or a copy as good - and never ours, the
--- poster's or the sender's own, which come as the order and as a T. Not news: it was before our time.
local function OnRelayedPot(sender, f)
    local o = OrderNamed(GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31))
    local backer = GuildieKey(GK.Clean(f[5], 64))
    local copper = Int(f[6], 1, MAX_REWARD)
    if not (o and backer and copper) or o.state ~= "o" then return end
    if backer == sender or backer == o.by or LIB.IsMyStoredName(backer) then return end
    heard["t:" .. o.key .. ":" .. backer] = GetTime()
    o.pot = o.pot or {}
    if o.pot[backer] or Count(o.pot) >= MAX_BACKERS then return end
    o.pot[backer] = copper
end

--- Y: the sender paid a hunter their part (the hunter named), or - from an older client - a backer paid it
--- all. Only the payer's own payments, and only to someone who got the target.
local function OnSharePaid(sender, f)
    local o = OrderNamed(GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31))
    if not (o and o.doneBy) then return end
    local given = Given(o, sender)
    if given <= 0 then return end
    local named = f[5] ~= nil and f[5] ~= ""
    if named then
        local hunter = GuildieKey(GK.Clean(f[5], 64))
        local part = hunter and GK.Part(o, given, hunter) or 0
        if part <= 0 or GK.IsPaid(o, sender, hunter) then return end
        MarkPaidTo(o, sender, hunter)
        if sender ~= o.by and AllPaid(o, sender) then
            o.paid = o.paid or {}
            o.paid[sender] = true
        end
        if LIB.IsMyStoredName(hunter) then GK.PaidLetter(o, sender, part) end
    else
        if sender == o.by or (o.paid and o.paid[sender]) then return end
        o.paid = o.paid or {}
        o.paid[sender] = true
        if o.doneBy == LIB.Me() then GK.PaidLetter(o, sender, given) end
    end
    GK.Changed()
end

local function OnSighting(sender, f)
    local o = OrderNamed(GK.Clean(f[3], 64), Int(f[4], 1, 2 ^ 31))
    if not o or o.state ~= "o" then return end
    local zone = GK.Clean(f[5], 40)
    -- Where they stood: a map and a spot on it, all three or none. A map id is any positive number the
    -- client knows; nothing outside the map's own square is a place.
    local m, x, y = Int(f[7], 1, 1e6), Int(f[8], 0, 1000), Int(f[9], 0, 1000)
    if not (m and x and y) then m, x, y = nil, nil, nil end
    o.seen = { by = sender, z = zone, t = time(), l = GK.ValidLevel(f[6]), m = m, x = x, y = y }
    -- Everyone hears where: nobody takes an order, every guildie is the hunter (the owner, 2026-11-07).
    if GK.db.alertNear then
        GK.Warn(("%s saw %s%s"):format(GK.Show(sender), GK.Show(o.n), zone and (" in " .. zone) or ""), false)
    end
end

-- ---------------------------------------------------------------------------
-- The answer to a login
-- ---------------------------------------------------------------------------
-- A guildie who logs in asks (Q), and everyone answers with what is theirs: their score, their orders,
-- what they put in others' pots. That alone lost what belonged to someone who was away: an order whose
-- poster had logged out never reached a guildie who logged in after it was posted, and neither did the
-- poster's score ("påse at ... informasjon ikke blir borte om en person logger ut", the owner,
-- 2026-11-07). So an answer also passes on the open orders, the shares in their pots and the board's
-- rows it knows of others, as O, P and R: only what nobody has said since the ask, checked again as each
-- one goes, so the guild's answers don't all say the same thing.
--
-- And it is paced. LibForever drops a sender's messages past 30 in 10 seconds (WithinBudget), and one
-- answer could run past that before - its tail was lost. Two a second is twenty in ten, with room left
-- for a kill or a death, which still go out at once.
local PACE = 0.5               -- seconds between two messages of an answer
local MAX_PACED = 120
local RELAY_ORDERS, RELAY_SHARES, RELAY_ROWS = 30, 30, 25
local RELAY_CLOSED = 2 * GK.DAY  -- a closed order is passed on this long, so an open copy elsewhere closes
local REPLY_GAP = 30           -- one answer per this long, however many log in

local paced, pacing = {}, false
local function Drain()
    while #paced > 0 do
        local text = table.remove(paced, 1)()
        if text then
            Send(text)
            C_Timer.After(PACE, Drain)
            return
        end
    end
    pacing = false
end

--- Send what make() returns, in turn, PACE apart; make() returns nil for what is no longer worth it.
local function Paced(make)
    if #paced >= MAX_PACED then return end
    paced[#paced + 1] = make
    if not pacing then
        pacing = true
        C_Timer.After(0, Drain)
    end
end

local function Shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local askedAt, replyAfter, replyDue = 0, 0, false
local askers = {}               -- who asked since the last answer: each gets their own row back, first

local function RowText(who, r)
    return Msg("R", PROTO, who, r.p, r.k, r.d, r.l, r.c, r.wp, r.wk, r.wd, r.wid, r.st, r.bs, r.od, r.ow,
        r.nm, r.nt, r.rf, r.sx, r.t, r.a, r.wa, PartsText(r.parts) or (r.via and "~" or ""))
end

local function Answer()
    local me, now, s, since = LIB.Me(), time(), GK.Store(), askedAt
    GK.SendBoard()
    -- whoever asked, their own row with its parts: what their other PCs made, which this PC of theirs may
    -- never have heard ("One character, more than one PC"). Once, by whoever answers first.
    local asking = askers
    askers = {}
    for who in pairs(asking) do
        local r = s.board[who]
        if r and r.parts and who ~= me then
            Paced(function()
                local passed = heard["r:" .. who]
                if (passed and passed >= since) or GK.Store().board[who] ~= r then return nil end
                return RowText(who, r)
            end)
        end
    end
    -- ours: the orders we posted, and what we put in others' pots and whether we've paid it
    for _, o in pairs(s.orders) do
        local recent = o.state == "o" or now - (o.doneAt or o.t or 0) < ORDER_DAYS * GK.DAY
        if recent then
            if o.by == me then Paced(function() return OrderText(o) end) end
            -- an order of someone else's that our kill fulfilled, said again while it is unpaid: its poster
            -- or a backer may have been away when it happened, and only we may say it (ApplyOrder)
            if o.doneBy == me and o.by ~= me and o.state == "d" then
                Paced(function() return o.state == "d" and Msg("F", PROTO, o.by, o.id, o.doneZone, HelpersText(o)) or nil end)
            end
            local mine = o.pot and o.pot[me]
            if mine then
                Paced(function() return Msg("T", PROTO, o.by, o.id, mine) end)
                if o.paid and o.paid[me] then Paced(function() return Msg("Y", PROTO, o.by, o.id) end) end
            end
            -- what we have paid each hunter, while not all of it is: the whole goes as T's Y above, or
            -- as the poster's state
            if (mine or o.by == me) and not (o.paid and o.paid[me]) and not (o.by == me and o.state == "p") then
                for h in pairs(o.paidTo and o.paidTo[me] or {}) do
                    Paced(function() return Msg("Y", PROTO, o.by, o.id, h) end)
                end
            end
        end
    end
    -- others' orders, open or lately closed, for whoever asked: in a shuffled order, so two of us
    -- answering at once rarely say the same one at the same moment
    local orders = {}
    for _, o in pairs(s.orders) do
        if o.by ~= me and (o.state == "o" or now - (o.doneAt or o.t or 0) < RELAY_CLOSED) then
            orders[#orders + 1] = o
        end
    end
    Shuffle(orders)
    for i = 1, math.min(#orders, RELAY_ORDERS) do
        local o = orders[i]
        Paced(function()
            if (heard[o.key] or 0) >= since or GK.Store().orders[o.key] ~= o then return nil end
            local rf, sx = LookOf(o.n)
            return Msg("O", PROTO, o.by, o.id, o.n, o.c, o.r, o.l, o.guid, o.reward, o.t, o.exp, o.state,
                o.doneBy, o.note, o.auto, rf, sx)
        end)
    end
    -- what others put in the open orders' pots, ours too: after the orders, so whoever asked has the order
    -- a share is on by the time it comes (they drop a share on an order they don't know). Only what its
    -- backer hasn't said since the ask, and never our own, which went as a T above.
    local shares = {}
    for _, o in pairs(s.orders) do
        if o.state == "o" and o.pot then
            for who in pairs(o.pot) do
                if who ~= me then shares[#shares + 1] = { o = o, who = who } end
            end
        end
    end
    Shuffle(shares)
    for i = 1, math.min(#shares, RELAY_SHARES) do
        local o, who = shares[i].o, shares[i].who
        Paced(function()
            local copper = o.pot and o.pot[who]
            if not copper or o.state ~= "o" or GK.Store().orders[o.key] ~= o
                or (heard["t:" .. o.key .. ":" .. who] or 0) >= since then
                return nil
            end
            return Msg("P", PROTO, o.by, o.id, who, copper)
        end)
    end
    -- others' rows on the board: this week's scorers first, then the best of all time - what a page shows
    local week, rows = GK.WeekId(), {}
    for who, r in pairs(s.board) do
        if who ~= me and not asking[who] and now - (r.t or 0) < BOARD_STALE then rows[#rows + 1] = { who = who, r = r } end
    end
    local function ThisWeek(r) return r.wid == week and (r.wp or 0) or -1 end
    table.sort(rows, function(a, b)
        if ThisWeek(a.r) ~= ThisWeek(b.r) then return ThisWeek(a.r) > ThisWeek(b.r) end
        if (a.r.p or 0) ~= (b.r.p or 0) then return (a.r.p or 0) > (b.r.p or 0) end
        return a.who < b.who
    end)
    for i = 1, math.min(#rows, RELAY_ROWS) do
        local who, r = rows[i].who, rows[i].r
        Paced(function()
            if (heard["b:" .. who] or 0) >= since or GK.Store().board[who] ~= r then return nil end
            return RowText(who, r)
        end)
    end
end

local function OnAsk(sender)
    -- Everyone logging in at once asks at once: one answer, a few seconds later. An ask inside the gap
    -- after an answer waits for the gap to end; it used to get no answer at all, so a guildie who logged
    -- in half a minute after another heard nothing.
    askedAt = GetTime()
    if Count(askers) < 50 then askers[sender] = true end
    if replyDue then return end
    replyDue = true
    C_Timer.After(math.max(0, replyAfter - GetTime()) + 2 + math.random() * 4, function()
        replyDue = false
        replyAfter = GetTime() + REPLY_GAP
        Answer()
    end)
end

local HANDLERS = { B = OnBoard, Q = OnAsk, K = OnKill, H = OnAssist, D = OnDeath, C = OnOrder, F = OnFulfil,
    S = OnSighting, T = OnPot, Y = OnSharePaid, O = OnRelayedOrder, P = OnRelayedPot, R = OnRelayedBoard,
    U = OnForget }

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
            if o.by == me then
                SendOrder(o)
                GK.ExpiredLetter(o)
            end
        elseif o.state ~= "o" then
            local age = now - (o.paidAt or o.doneAt or o.exp or o.t or now)
            if age > (o.state == "d" and KEEP_OWED or KEEP_CLOSED) then
                s.orders[key] = nil
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

-- Ask the guild for what we missed, once a session, as soon as we are in one. The client can say we are
-- in no guild for a while after login; the ask used to go only at eight seconds, and then never.
local asked = false
local function Ask()
    if asked or not IsInGuild() then return end
    asked = true
    -- our row first, then the ask: a guildie who answers has our parts by then, joined to the ones they
    -- had, and passes the whole back to us
    GK.SendBoard(true)
    Send(Msg("Q", PROTO))
end

function GK.StartGuild()
    -- While the test panel or the screenshots stand in for the guild (GK.testMode), the real guild's
    -- messages wait outside: they landed in the made-up store, and the store page's pictures showed four
    -- real guildies on the made-up leaderboard and "#4 of 19, 22, 24" a few seconds apart (2026-11-10).
    -- Taken in, it went out with the made-up store when the panel closed anyway; a guildie's score and
    -- orders come again with their next send, or the answer to our next login.
    LIB.RegisterComm(PREFIX, function(...)
        if not GK.testMode then OnMessage(...) end
    end)
    C_Timer.After(8, function()
        GK.Sweep()
        Ask()
    end)
    LIB.On("PLAYER_GUILD_UPDATE", function()
        if not asked then C_Timer.After(5, Ask) end
    end)
    C_Timer.NewTicker(600, GK.Sweep)
end
