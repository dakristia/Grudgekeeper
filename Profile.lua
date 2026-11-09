-- Grudgekeeper - profiles: what the guild knows about one player, on a card in the same iron frame as
-- the small letters. Two kinds:
--   a guildie's RECORD   title and points, kills and deaths this week and all time, place on the board,
--                        kill streak, kill orders fulfilled and the bounties on them, nemesis, and the
--                        latest the news has on them
--   a WANTED poster      an enemy player: how often they killed us and whom, how often we got them,
--                        your own score with them, where they were last seen, the order and its pot
-- It opens from the game's right-click menu on a player (the target frame, party and raid frames, a
-- name in chat, the guild roster), from a name in the window and from a pin on the world map. Like
-- every window here, it never opens by itself.
-- Everything on a card is what this client has heard: a guildie who never runs Grudgekeeper has no
-- record, and kills made while you were offline count once the killer's next kill tells their total.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local INK = { 0.22, 0.13, 0.05 }
local FADED = { 0.42, 0.33, 0.22 }
local BLOOD = { 0.47, 0.06, 0.04 }
local LABEL = "Grudgekeeper profile"
local NAMES = 3                  -- names on a line before "and 2 more"
local QUIET_FOR = 7 * GK.DAY     -- a guildie not heard from in this long: the card says when they were

local function Plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

local function Who(key)
    if LIB.IsMyStoredName(key) then return "you" end
    return GK.Show(key)
end

--- The record in t under this player's name: the exact key, else the same name written another way
--- (GK.SameName - another realm spelling, a surname one side left off). Only ever asked from a click,
--- so a walk over a few hundred names is fine; nothing that runs per event comes through here.
local function Find(t, key)
    if not (t and type(key) == "string") then return nil end
    if t[key] then return t[key], key end
    for k, v in pairs(t) do
        if GK.SameName(k, key) then return v, k end
    end
    return nil
end

--- "once", "twice", "3 times".
local function Times(n) return n == 1 and "once" or n == 2 and "twice" or (n .. " times") end

--- A count beside a name: "once", "twice", "3x" (with the times sign).
local function Count(n) return n == 1 and "once" or n == 2 and "twice" or (n .. "\195\151") end

--- "Vebjørn 5, Kari 4 and 3 more" from { [who] = count }, the most first; the sum of the counts (yours
--- too); and how many names it has. count: how a count is written after the name (Count), else as a
--- plain number. notMe: leave yourself out of the names, where a line of your own already says yours.
local function Names(map, count, notMe)
    local list, total = {}, 0
    for who, n in pairs(map) do
        if not (notMe and LIB.IsMyStoredName(who)) then list[#list + 1] = { who = who, n = n } end
        total = total + n
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.who < b.who
    end)
    local parts = {}
    for i = 1, math.min(NAMES, #list) do
        parts[i] = ("%s %s"):format(Who(list[i].who), count and count(list[i].n) or tostring(list[i].n))
    end
    local text = table.concat(parts, ", ")
    if #list > NAMES then text = text .. (" and %d more"):format(#list - NAMES) end
    return text, total, #list
end

--- How long ago, short, for a number on the card: "now", "12 min", "5 h", "3 d".
local function Since(t)
    local s = time() - (t or 0)
    if s < 90 then return "now" end
    if s < 3600 then return math.floor(s / 60) .. " min" end
    if s < 2 * GK.DAY then return math.floor(s / 3600) .. " h" end
    return math.floor(s / GK.DAY) .. " d"
end

--- The same, as the line under a number: "just now", "12 min ago", "3 d ago".
local function SinceAgo(t)
    local s = Since(t)
    return s == "now" and "just now" or (s .. " ago")
end

--- How long until: "in 5 days", "in 3 h", "within the hour".
local function Until(t)
    local s = (t or 0) - time()
    if s < 3600 then return "within the hour" end
    if s < 2 * GK.DAY then return ("in %d h"):format(math.floor(s / 3600)) end
    return ("in %d days"):format(math.floor(s / GK.DAY))
end

--- "Kari, Lars and you": a list of names, the last joined with "and", at most NAMES and "2 more".
local function AndList(names)
    local shown = {}
    for i = 1, math.min(NAMES, #names) do shown[i] = names[i] end
    if #names > NAMES then shown[#shown + 1] = ("%d more"):format(#names - NAMES) end
    if #shown < 2 then return shown[1] or "" end
    return table.concat(shown, ", ", 1, #shown - 1) .. " and " .. shown[#shown]
end

local function Upper(s) return GK.UpperFirst(s) end      -- a name's first letter in any alphabet (Core.lua)

--- What a tile counts, said for one or for more: "1 DEATH", "3 DEATHS".
local function Counted(n, word) return n == 1 and word or (word .. "s") end

--- Our guild's name, for the line under an enemy's kills and deaths; "us" without one, or while the
--- client can't say.
local function OurGuild()
    if GK.shotGuild then return GK.shotGuild end        -- the screenshot mode's made-up guild (Shots.lua)
    local name = GetGuildInfo and GetGuildInfo("player")
    if type(name) == "string" and name ~= "" and not GK.Secret(name) then return name end
    return "us"
end

--- Where and when an enemy was last seen, from the best we have: a guildie's sighting of an order's
--- target, our own look in the last 15 minutes, or the guild's news of a kill on either side (which
--- says where). { t = time(), z } or nil.
local function LastSeen(key, o, live)
    local best
    local function Take(t, z)
        if t and (not best or t > best.t) then best = { t = t, z = z } end
    end
    if o and o.seen and o.seen.t then Take(o.seen.t, o.seen.z) end
    if live and live.t and GetTime then Take(time() - math.floor(GetTime() - live.t), live.z) end
    for _, e in ipairs(GK.Store().feed) do
        if (e.kind == "K" or e.kind == "D") and e.n and (e.n == key or GK.SameName(e.n, key)) then
            Take(e.t, e.z)
            break                                   -- the feed is newest first
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- What a card says. Plain data, so the smoke test can read it without a frame:
-- { title, name, info, lines, big, caption, seal, blood, buttons = { { text, fn } }, c, unit, key, rich }
-- title, name, info, lines, big and caption are the card as the small profile card and the Inspect tab
-- draw it: a line that starts "Label: " is a label and its value there, in two columns.
-- rich is the same card for a page with room for it, the ledger's (Window.lua, FillRich), as previewed
-- with the owner (2026-11-06): every number in a tile with a name and a line that says something, then
-- sections of facts.
--   { kicker, head, sub, info, seal, sealNum, tiles = { { value, label, under, under2 } },
--     bar = { frac, left, right }, sections = { { head, kind, rows } } }
--   kicker: the small red line over the name ("WANTED", "#1 THIS WEEK"); head: the name; sub: under it.
--   kind "facts": rows { label, value, more } (no label: a paragraph; more: a grey word after the
--   value); "events": { c, text, under, right }, each with their class's crest.
-- ---------------------------------------------------------------------------

-- Who put what in a pot. The bounty tile said "from 2 guildies" and no more ("se hvem som har lagt til i
-- potten", the owner, 2026-11-07): the card says it in a section of its own rather than behind a button,
-- since a card has the room and nobody has to know to click.
local MAX_POT_ROWS = 4

--- An order's pot as rows for a card's facts, the most first: { amount, who, a grey word }. The poster's
--- reward is theirs and says so; on a fulfilled order each share says whether it is paid. More givers
--- than MAX_POT_ROWS end on one row for the rest. nil when nobody but the poster put gold in: the bounty
--- tile and Posted by say all there is then.
function GK.PotRows(o)
    if not (o and o.pot and next(o.pot)) then return nil end
    local givers = {}
    if (o.reward or 0) > 0 then givers[1] = { who = o.by, copper = o.reward, poster = true } end
    for who, copper in pairs(o.pot) do givers[#givers + 1] = { who = who, copper = copper } end
    table.sort(givers, function(a, b)
        if a.copper ~= b.copper then return a.copper > b.copper end
        return a.who < b.who
    end)
    local owed = o.state == "d" or o.state == "p"
    local rows = {}
    local shown = #givers <= MAX_POT_ROWS and #givers or MAX_POT_ROWS - 1
    for i = 1, shown do
        local g = givers[i]
        local note = g.poster and "posted it" or nil
        if owed then
            local paid = g.poster and o.state == "p" or (not g.poster and o.paid and o.paid[g.who])
            note = paid and "paid" or "not paid yet"
        end
        rows[#rows + 1] = { GK.Coins(g.copper), Upper(Who(g.who)), note }
    end
    if shown < #givers then
        local rest = 0
        for i = shown + 1, #givers do rest = rest + givers[i].copper end
        rows[#rows + 1] = { GK.Coins(rest), Plural(#givers - shown, "other") }
    end
    return rows
end

-- Forget grudge, readied by a first click: whose, and until when (GetTime()).
local FORGET_ARMED_FOR = 5
local forgetArmed, forgetUntil = nil, 0

--- An enemy player. t = { key, guid, c, r, l, unit }: whatever the caller knows. inLedger: drawn on
--- the ledger's own page (Window.lua), where your own order's button withdraws it rather than
--- opening the hitlist you are already looking at.
function GK.PosterCard(t, inLedger)
    local key, guid = t.key, t.guid
    local s = GK.Store()
    local w = Find(s.wanted, key)
    local e = Find(s.slain, key)
    local f, fkey = Find(GK.char.foes, key)
    local o = GK.OrderOn(key, guid)
    local live = GK.Seen(key, guid)
    local function Pick(field)
        return t[field] or (live and live[field]) or (o and o[field]) or (f and f[field]) or (e and e[field])
            or (w and w[field])
    end
    local c, r, l = Pick("c"), Pick("r"), Pick("l")
    -- Their race's face, from race and sex seen or kept (GK.FaceOf), under whichever spelling we have
    -- them by - the card may be asked for a name alone.
    local function Known(k) return k and GK.FaceOf(k).rf and k or nil end
    local faceKey = Known(key) or Known(fkey) or Known(o and o.n) or key
    local look = GK.FaceOf(faceKey, c)
    local d = { key = key, unit = t.unit, c = c, name = GK.Show(key), info = GK.Describe(l, c, r), lines = {},
        buttons = {}, rf = look.rf, sx = look.sx, faceKey = faceKey }
    local rich = { head = d.name, info = d.info, tiles = {}, sections = {} }
    d.rich = rich
    local lines = d.lines
    local killedUs, weKilled = 0, 0
    local history = {}             -- the rich card's History: you, then whom they killed, then who got them
    local nemesis = f ~= nil and fkey ~= nil and GK.Nemesis() == fkey
    if f and (f.k or 0) + (f.d or 0) > 0 then
        local said = {}
        if (f.k or 0) > 0 then said[#said + 1] = "killed them " .. Times(f.k) end
        if (f.d or 0) > 0 then said[#said + 1] = "died to them " .. Times(f.d) end
        history[1] = { "You", table.concat(said, ", ") }
    end
    -- With a You row, the guild's lists name only the others: "You: killed them once" over "Killed by:
    -- you once" said the same thing twice (the owner, 2026-11-06). A list left empty goes.
    local youSaid = history[1] ~= nil
    if w and next(w.victims) then
        local names, total = Names(w.victims)
        killedUs = total
        lines[#lines + 1] = ("Killed us: %s - %s."):format(Plural(total, "time"), names)
        local others, _, n = Names(w.victims, Count, youSaid)
        if n > 0 then history[#history + 1] = { "They killed", others } end
    end
    if e and next(e.by) then
        local names, total = Names(e.by)
        weKilled = total
        lines[#lines + 1] = ("We killed them: %s - %s."):format(Plural(total, "time"), names)
        local others, _, n = Names(e.by, Count, youSaid)
        if n > 0 then history[#history + 1] = { "Killed by", others } end
    end
    if f and (f.k or 0) + (f.d or 0) > 0 then
        lines[#lines + 1] = ("You: %s, %s%s"):format(Plural(f.k or 0, "kill"), Plural(f.d or 0, "death"),
            nemesis and " - your nemesis." or ".")
    end
    -- The rich card's numbers are THEIR score against the guild, read as a scoreboard: "7 KILLS on
    -- YippYapp", "3 DEATHS by YippYapp", and under it when the last was. Named from our side - "7 KILLED
    -- US", "3 WE KILLED" - the number read as the start of a sentence; "to us" became the guild's name
    -- (the owner, 2026-11-06). The guild on a line of its own, so a long name is cut, never the time.
    rich.sub = nemesis and "Your nemesis" or nil
    local guild = OurGuild()
    local kills = { tostring(killedUs), Counted(killedUs, "Kill"), "on " .. guild }
    if killedUs > 0 and w.last then kills[4] = SinceAgo(w.last) end
    local deaths = { tostring(weKilled), Counted(weKilled, "Death"), "by " .. guild }
    if weKilled > 0 and e.last then deaths[4] = SinceAgo(e.last) end
    local spotted = LastSeen(key, o, live)
    local seenTile = spotted and { Since(spotted.t), "Last seen", spotted.z or "" } or { "-", "Last seen", "not lately" }
    -- Last seen: anyone in the guild, through the order; else our own look in the last 15 minutes.
    local seen = o and o.seen
    if seen and seen.t then
        lines[#lines + 1] = ("Last seen: %s, %s, by %s."):format(seen.z or "the world", GK.Ago(seen.t), Who(seen.by))
    elseif live then
        lines[#lines + 1] = ("Last seen: by you, lately, in %s."):format(live.z or "the world")
    end
    local me = LIB.Me()
    if o then
        local pot, backers = GK.Pot(o)
        local extra = {}
        if backers > 0 then extra[#extra + 1] = Plural(backers, "backer") end
        local tail = #extra > 0 and (" - " .. table.concat(extra, ", ")) or ""
        -- An order their own killing posted (GK.AutoOrder) says why, in the Grudgekeeper's words, and
        -- was posted by a death rather than by a guildie's hand. One a guildie posted says the why they
        -- wrote, if they wrote one.
        local by = Who(o.by)
        if o.auto then
            by = (by == "you" and "your" or (by .. "'s")) .. " death"
            -- A to Z only: %u follows the locale, and under Latin-1 it takes the lead byte of a Cyrillic letter
            local why = o.note and (o.note:gsub("^[A-Z]", string.lower)) or nil
            lines[#lines + 1] = why and ("The guild wants them dead: %s"):format(why) or "The guild wants them dead."
        elseif o.note and o.note ~= "" then
            lines[#lines + 1] = ("Why: %s"):format(o.note)
        end
        if pot > 0 then
            lines[#lines + 1] = ("Posted by: %s - a bounty of %s%s."):format(by, GK.MoneyText(pot), tail)
            d.big = pot >= 10000 and (math.floor(pot / 10000) .. "g") or GK.MoneyText(pot)
            d.caption = "bounty"
        else
            lines[#lines + 1] = ("Posted by: %s - for the guild's honour%s."):format(by, tail)
        end
        -- The rich card: the bounty and how many put gold in it, then the order itself - who posted it and
        -- when, why, when it runs out. Nobody takes an order, so nobody is listed as hunting them: any
        -- guildie's kill fulfils it, and "Hunting: nobody yet" read as a sign-up it was waiting for ("jeg
        -- vil ikke at noen skal ta ordre", the owner, 2026-11-07).
        local givers = backers + ((o.reward or 0) > 0 and 1 or 0)
        rich.tiles[1] = { pot > 0 and GK.Coins(pot) or "honour", "Bounty",
            givers > 0 and ("from %d guildie%s"):format(givers, givers == 1 and "" or "s") or "no gold on it" }
        local order = { { "Posted by", ("%s, %s"):format(Upper(by), GK.Ago(o.t)) } }
        if o.note and o.note ~= "" then order[#order + 1] = { "Why", o.note } end
        if o.exp then order[#order + 1] = { "Runs out", Until(o.exp) } end
        rich.sections[1] = { head = "The order", kind = "facts", rows = order }
        local potRows = GK.PotRows(o)
        if potRows then rich.sections[2] = { head = "The pot", kind = "facts", rows = potRows } end
        if o.by ~= me then
            d.buttons[1] = { (o.pot and me and o.pot[me]) and "Your share" or "Add to the pot", function()
                GK.OpenPost({ key = o.n, guid = o.guid, c = o.c, r = o.r, l = o.l })
            end }
        elseif inLedger then
            d.buttons[1] = { "Withdraw", function() GK.Withdraw(o) end }
        else
            d.buttons[1] = { "Hitlist", function() GK.OpenWindow(1) end }
        end
    else
        d.buttons[1] = { "Post a kill order", function()
            GK.OpenPost({ key = key, guid = guid, c = c, r = r, l = l })
        end }
    end
    -- A grudge of yours can be forgotten (GK.ForgetGrudge, Guild.lua): a wrong one stayed for good before.
    -- It asks twice - the first click readies it for a few seconds and the button says so.
    if f and fkey and (f.k or 0) + (f.d or 0) > 0 then
        local armed = forgetArmed == fkey and GetTime() < forgetUntil
        d.buttons[#d.buttons + 1] = { armed and "Really forget?" or "Forget grudge", function()
            if forgetArmed == fkey and GetTime() < forgetUntil then
                forgetArmed = nil
                GK.ForgetGrudge(fkey)
                return
            end
            forgetArmed, forgetUntil = fkey, GetTime() + FORGET_ARMED_FOR
            C_Timer.After(FORGET_ARMED_FOR + 0.1, GK.Changed)        -- back to Forget grudge
            GK.Changed()
        end }
    end
    if not d.big and killedUs > 0 then d.big, d.caption = tostring(killedUs), "killed us" end
    if o then
        d.title, d.seal = "WANTED", "mark"
    elseif #history > 0 then
        d.title, d.seal = "A GRUDGE", "seal_black"
    else
        d.title = "NO RECORD"
        lines[#lines + 1] = "Nobody in the guild has killed them or died to them - not that the Grudgekeeper heard of."
        history[1] = { nil, lines[#lines] }
    end
    rich.kicker, rich.seal = d.title, d.seal
    rich.tiles[#rich.tiles + 1] = kills
    rich.tiles[#rich.tiles + 1] = deaths
    rich.tiles[#rich.tiles + 1] = seenTile
    rich.sections[#rich.sections + 1] = { head = "History", kind = "facts", rows = history }
    d.blood = f ~= nil and (f.d or 0) > 0       -- they have killed you
    return d
end

-- What a guildie did, as the rich card's Lately says it; the right-hand column is what it was worth.
local DID = { K = "Killed %s", D = "Fell to %s", F = "Fulfilled the kill order on %s", C = "Put a price on %s",
    T = "Added to the pot on %s" }

--- The last few things the news says a guildie did, newest first: { c, text, under, right }.
local function Lately(key, me, most)
    local out = {}
    for _, e in ipairs(GK.Store().feed) do
        if #out >= most then break end
        if DID[e.kind] and (e.who == key or (me and LIB.IsMyStoredName(e.who))) then
            local right
            if e.kind == "K" then
                right = (e.p or 0) > 0 and ("+%d"):format(e.p) or nil
            elseif e.kind == "C" then
                right = (e.p or 0) > 0 and GK.Coins(e.p) or "honour"
            elseif e.kind == "T" then
                right = (e.p or 0) > 0 and GK.Coins(e.p) or nil
            end
            out[#out + 1] = { c = e.c, text = DID[e.kind]:format(GK.Show(e.n)),
                under = (e.z and (e.z .. " \194\183 ") or "") .. GK.Ago(e.t), right = right }
        end
    end
    return out
end

--- How far a score is on its way to the next title: { frac, left = this title, right = what is left }.
local function Progress(p)
    local at = 1
    for i, row in ipairs(GK.TITLES) do
        if p >= row[1] then at = i end
    end
    local now, after = GK.TITLES[at], GK.TITLES[at + 1]
    if not after then return { frac = 1, left = now[2], right = "the highest title" } end
    return { frac = (p - now[1]) / (after[1] - now[1]), left = now[2],
        right = ("%s to %s"):format(Plural(after[1] - p, "point"), after[2]) }
end

--- The latest the news says about a guildie: one line, or nil.
local function Latest(key, me)
    for _, e in ipairs(GK.Store().feed) do
        if e.who == key or (me and LIB.IsMyStoredName(e.who)) then
            local target = GK.Show(e.n)
            local when = GK.Ago(e.t)
            if e.kind == "K" then
                return ("Lately: killed %s%s, %s."):format(target, (e.p or 0) > 0 and (" (+%d)"):format(e.p) or "", when)
            elseif e.kind == "D" then
                return ("Lately: fell to %s, %s."):format(target, when)
            elseif e.kind == "F" then
                return ("Lately: fulfilled the kill order on %s, %s."):format(target, when)
            elseif e.kind == "C" then
                return ("Lately: put a price on %s, %s."):format(target, when)
            end
        end
    end
    return nil
end

--- A guildie, or you: their record as they last sent it (B). nil when we have none.
function GK.RecordCard(key, unit)
    local me = LIB.IsMyStoredName(key)
    local r
    if me then
        local c, w = GK.char, GK.Week()
        local nemesis, nf = GK.Nemesis()
        local _, class = UnitClass("player")
        local _, raceFile = UnitRace("player")
        r = { p = c.points, k = c.kills, d = c.deaths, wp = w.p, wk = w.k, wd = w.d, wid = w.id,
            st = c.streak, bs = c.bestStreak, od = c.done, ow = c.won, nm = nemesis, nt = nf and nf.d,
            c = class, l = UnitLevel("player"), t = time(), rf = raceFile, sx = UnitSex("player") }
        key = LIB.Me() or key
    else
        r, key = Find(GK.Store().board, key)
        if not r then return nil end
    end
    local p = r.p or 0
    local d = { key = key, unit = unit, c = r.c, rf = r.rf, sx = r.sx, title = GK.Show(key),
        name = GK.Title(p), lines = {}, buttons = {},   -- the points are the big number, not said twice
        big = tostring(p), caption = p == 1 and "point" or "points" }
    -- place on the board: all time, and this week if they are on this week's
    local function Place(weekly)
        local list = GK.Board(weekly)
        for i, e in ipairs(list) do
            if (me and e.me) or (not me and e.who == key) then return i, #list end
        end
        return nil
    end
    -- Both counts say what they count: all time is everyone whose score reached us, this week only who
    -- has a kill, death or point this week - the leaderboard's default list. "#1 of 4 in the guild, #1
    -- this week" read as four on a list that showed one (the owner, 2026-11-06).
    local rank, of = Place(false)
    local weekRank, weekOf = Place(true)
    local where = GK.Describe(r.l, r.c)
    if rank and of > 1 then
        where = ("#%d of %d all time%s"):format(rank, of,
            weekRank and (", #%d of %d this week"):format(weekRank, weekOf) or "")
    end
    d.info = where
    local lines = d.lines
    lines[#lines + 1] = ("All time: %s, %s."):format(Plural(r.k or 0, "kill"), Plural(r.d or 0, "death"))
    local thisWeek = r.wid == GK.WeekId()
    if thisWeek and ((r.wk or 0) + (r.wd or 0) + (r.wp or 0)) > 0 then
        lines[#lines + 1] = ("This week: %s, %s, %s."):format(Plural(r.wk or 0, "kill"), Plural(r.wd or 0, "death"),
            Plural(r.wp or 0, "point"))
    else
        lines[#lines + 1] = "Nothing yet this week."
    end
    -- The rich card (the ledger): the all-time numbers in tiles, this week's under each; the place on
    -- the board with what it counts; the way to the next title; the highlights; and the news of them.
    -- The kicker is this week's place, the list the leaderboard opens on.
    local function Week(n) return thisWeek and (n or 0) > 0 and ("%d this week"):format(n) or "none this week" end
    local wp = thisWeek and (r.wp or 0) or 0
    local info = GK.Describe(r.l, r.c)
    if not me and r.t and time() - r.t > QUIET_FOR then info = info .. " \194\183 last heard " .. GK.Ago(r.t) end
    local streak, best = r.st or 0, math.max(r.bs or 0, r.st or 0)
    local rich = { head = d.title, sub = d.name, info = info,
        kicker = (weekRank and ("#%d this week"):format(weekRank)) or (rank and ("#%d all time"):format(rank)) or nil,
        seal = weekRank and weekRank <= 3 and wp > 0 and ("rank_" .. weekRank) or nil,
        tiles = {
            { tostring(p), Counted(p, "Point"), Week(r.wp) },
            { tostring(r.k or 0), Counted(r.k or 0, "Kill"), Week(r.wk) },
            { tostring(r.d or 0), Counted(r.d or 0, "Death"), Week(r.wd) },
            { rank and ("#" .. rank) or "-", "Place", rank and ("of %d all time"):format(of) or "" } },
        bar = Progress(p), sections = {} }
    rich.sealNum = rich.seal and tostring(weekRank) or nil
    -- Only the highlights there are: four rows of "none yet" and "nobody yet" were most of the card for a
    -- new player, and made the rest hard to find (the owner, 2026-11-06). The bounties go with the orders
    -- they were won on.
    local highlights = {}
    if best > 0 then
        highlights[#highlights + 1] = { "Kill streak", tostring(streak),
            best > streak and ("best ever %d"):format(best) or (me and "your best yet" or "their best yet") }
    end
    if r.nm then
        highlights[#highlights + 1] = { "Nemesis", GK.Show(r.nm),
            r.nt and ("has killed %s %s"):format(me and "you" or "them", Times(r.nt)) or nil }
    end
    if (r.od or 0) > 0 then
        highlights[#highlights + 1] = { "Orders fulfilled", tostring(r.od),
            (r.ow or 0) > 0 and (GK.Coins(r.ow) .. " in bounties") or nil }
    end
    if #highlights > 0 then rich.sections[1] = { head = "Highlights", kind = "facts", rows = highlights } end
    local news = Lately(key, me, 3)
    if #news > 0 then rich.sections[#rich.sections + 1] = { head = "Lately", kind = "events", rows = news } end
    d.rich = rich
    if (r.bs or 0) > 0 then
        lines[#lines + 1] = ("Kill streak: %d now, best %d."):format(r.st or 0, r.bs)
    end
    if (r.od or 0) > 0 then
        lines[#lines + 1] = ("Kill orders fulfilled: %d%s."):format(r.od,
            (r.ow or 0) > 0 and (", for %s in bounties"):format(GK.MoneyText(r.ow)) or "")
    end
    if r.nm then
        lines[#lines + 1] = r.nt and ("Nemesis: %s, who has killed %s %s."):format(GK.Show(r.nm), me and "you" or "them",
            Plural(r.nt, "time")) or ("Nemesis: %s."):format(GK.Show(r.nm))
    end
    local latest = Latest(key, me)
    if latest then lines[#lines + 1] = latest end
    if not me and r.t and time() - r.t > QUIET_FOR then
        lines[#lines + 1] = ("Last heard from %s."):format(GK.Ago(r.t))
    end
    d.buttons[1] = { "Leaderboard", function() GK.OpenWindow(2) end }
    return d
end

--- Is there a record to show for this friendly player: you, or a guildie on the board.
function GK.HasRecord(key)
    if type(key) ~= "string" then return false end
    return LIB.IsMyStoredName(key) or Find(GK.Store().board, key) ~= nil
end

-- ---------------------------------------------------------------------------
-- The card
-- ---------------------------------------------------------------------------
local card            -- the frame, made on first use
local showing         -- { poster = t } or { record = key, unit = unit } or { make = fn }

local function Ink(fs, colour, font, size)
    GK.SetFont(fs, font, size)                   -- a family: names in Cyrillic too (Core.lua)
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

local function Build()
    local f = GK.MakeNoteFrame("GrudgekeeperProfile")
    f.title = f:CreateFontString(nil, "ARTWORK")
    Ink(f.title, BLOOD, TITLE_FONT, 22)
    f.title:SetPoint("TOPLEFT", 172, -60)
    f.name = f:CreateFontString(nil, "ARTWORK")
    Ink(f.name, INK, TITLE_FONT, 17)
    f.name:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.info = f:CreateFontString(nil, "ARTWORK")
    Ink(f.info, FADED, TEXT_FONT, 11)
    f.info:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.body = f:CreateFontString(nil, "ARTWORK")
    Ink(f.body, INK, TEXT_FONT, 12)
    f.body:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -10)
    f.body:SetWidth(320)
    f.body:SetJustifyH("LEFT")
    f.body:SetSpacing(3)
    -- Under the portrait, the card's one number: points, the bounty, or how often they killed us.
    f.big = f:CreateFontString(nil, "ARTWORK")
    Ink(f.big, BLOOD, TITLE_FONT, 30)
    f.big:SetPoint("TOP", f.disc, "BOTTOM", 0, -12)
    f.caption = f:CreateFontString(nil, "ARTWORK")
    Ink(f.caption, INK, TEXT_FONT, 11)
    f.caption:SetPoint("TOP", f.big, "BOTTOM", 0, -2)
    -- WANTED wears the red seal from their nameplate, top right
    f.seal = f:CreateTexture(nil, "OVERLAY")
    f.seal:SetSize(54, 54)
    f.seal:SetPoint("TOPRIGHT", -46, -54)
    local sign = f:CreateFontString(nil, "ARTWORK")
    Ink(sign, INK, TITLE_FONT, 16)
    sign:SetPoint("BOTTOMRIGHT", -50, 54)
    sign:SetText("- the Grudgekeeper")
    f.buttons = {}
    for i = 1, 2 do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(140, 22)
        if i == 1 then b:SetPoint("BOTTOMLEFT", 46, 50) else b:SetPoint("LEFT", f.buttons[1], "RIGHT", 6, 0) end
        f.buttons[i] = b
    end
    -- The game's own X, as on the letter in the same frame; our own Hide, so closing works in combat too.
    GK.MakeGameCloseButton(f, function() f:Hide() end)
    if LIB.RegisterWindow then LIB.RegisterWindow(f, GK.db, "profile") end
    card = f
end

--- Their race's portrait when we know race and sex, with their class on its shoulder; else their class
--- crest; else the Grudgekeeper himself. Never their own face, even with them targeted: the same player
--- looked one way here and another everywhere else (GK.MakePortrait's note).
local function Portrait(f, d)
    local coords = d.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.c]
    local kind = GK.SetPortrait(f.portrait, d)
    if kind == "seal" then
        f.portrait:SetTexture(MEDIA .. "portrait")
        f.portrait:SetTexCoord(0, 1, 0, 1)
    end
    local badge = kind == "race" and coords
    f.badge:SetShown(badge and true or false)
    f.badgeRing:SetShown(badge and true or false)
    if badge then
        f.badge:SetTexture(CLASS_ICONS)
        f.badge:SetTexCoord(unpack(coords))
    end
end

local Refill

local function Fill(d)
    local f = card
    f.title:SetText(d.title or "")
    f.name:SetText(d.name or "")
    f.info:SetText(d.info or "")
    f.body:SetText(table.concat(d.lines, "\n"))
    f.big:SetText(d.big or "")
    f.caption:SetText(d.caption or "")
    f.seal:SetShown(d.seal ~= nil)
    if d.seal then f.seal:SetTexture(MEDIA .. d.seal) end
    f.blood:SetShown(d.blood == true)
    Portrait(f, d)
    for i, b in ipairs(f.buttons) do
        local spec = d.buttons[i]
        b:SetShown(spec ~= nil)
        if spec then
            b:SetText(spec[1])
            b:SetScript("OnClick", function()
                spec[2]()
                Refill()
            end)
        end
    end
end

Refill = function()
    if not (card and card:IsShown() and showing) then return end
    local d
    if showing.make then d = showing.make()
    elseif showing.poster then d = GK.PosterCard(showing.poster)
    else d = GK.RecordCard(showing.record, showing.unit) end
    if d then Fill(d) else card:Hide() end
end

local function Open(d)
    if not card then Build() end
    Fill(d)
    card:Show()
    card:Raise()
    GK.Sound("IG_ABILITY_PAGE_TURN")
end

--- The wanted poster for an enemy player. t = { key, guid, c, r, l, unit }.
function GK.ShowPoster(t)
    if not (t and t.key) then return end
    showing = { poster = t }
    Open(GK.PosterCard(t))
end

--- A guildie's record (or yours). unit: the unit it was opened from, for their face.
function GK.ShowRecord(key, unit)
    local d = GK.RecordCard(key, unit)
    if not d then return end
    showing = { record = d.key, unit = unit }
    Open(d)
end

--- Any other card, for a file that builds its own: make() returns a card table (see above) and is called
--- again whenever the card refills. Nothing opens if make() has nothing to show.
function GK.ShowCard(make)
    local d = make()
    if not d then return end
    showing = { make = make }
    Open(d)
end

-- ---------------------------------------------------------------------------
-- The game's right-click menu on a player
-- ---------------------------------------------------------------------------
-- Menu.ModifyMenu is how the game lets addons add to its menus: our part runs after Blizzard's own
-- entries are built, and adds its lines at the end. Nothing of Blizzard's is replaced or wrapped.
-- An enemy player always gets two: the poster, and the kill order on them. A friendly player gets the
-- record line only when there is a record: you, or a guildie on the board.
local FRIENDLY = { "SELF", "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "COMMUNITIES_GUILD_MEMBER", "GUILD" }

--- A name from the menu's context: a plain string the client lets us read, or nil.
local function Text(v)
    if type(v) ~= "string" or GK.Secret(v) or v == "" then return nil end
    return v
end

local function AddLine(root, fn, also, alsoFn)
    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton(LABEL, fn)
    if also then root:CreateButton(also, alsoFn) end
end

--- Who a friendly menu is about, as a key: from its unit, else the name it was opened on (a chat
--- line's full "Name-Realm" before the menu split it, then the plain name), else its GUID.
function GK.MenuKey(ctx)
    if type(ctx) ~= "table" then return nil end
    local unit = Text(ctx.unit)
    if unit then return GK.UnitKey(unit), unit end
    local name = Text(ctx.chatTarget) or Text(ctx.name)
    if name then return GK.PlayerKey(GK.KeyOf(name)), nil end
    local guid = Text(ctx.guid)
    if guid and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, gname, realm = pcall(GetPlayerInfoByGUID, guid)
        if ok then return GK.PlayerKey(GK.KeyOf(Text(gname), Text(realm))), nil end
    end
    return nil
end

local function OnEnemyMenu(_, root, ctx)
    if not (GK.db and GK.db.unitMenu and GK.char) or type(ctx) ~= "table" then return end
    local unit = Text(ctx.unit)
    local t = unit and GK.ReadUnit(unit)   -- an enemy player we can tell apart, or nil
    if not t then return end
    t.unit = unit
    -- and the kill order itself, one click from the enemy: opening the ledger to post one was too much
    -- work (the owner, 2026-11-05). The label says which of the sheet's three cases it will open.
    AddLine(root, function() GK.ShowPoster(t) end, GK.PostLabel(t), function() GK.OpenPost(t) end)
    -- Their guild on watch, or off it, for an officer (Notes.lua): the right spelling comes from the game,
    -- which typing one wouldn't. One guild at a time, so the line says which it replaces.
    local ok, guild = pcall(GetGuildInfo, unit)
    if ok and not GK.Secret(guild) and type(guild) == "string" and guild ~= "" and GK.CanWatchGuild
        and GK.CanWatchGuild() then
        local current = GK.WatchedGuild()
        local same = GK.SameGuild(current, guild)        -- the one on watch, if typed in another case
        local label = (same and ("Stop watching <%s>"):format(guild))
            or (current and ("Watch <%s> instead of <%s>"):format(guild, current))
            or ("Watch their guild <%s>"):format(guild)
        root:CreateButton(label, function() GK.WatchGuild(same and current or guild, not same) end)
    end
end

local function OnFriendlyMenu(_, root, ctx)
    if not (GK.db and GK.db.unitMenu and GK.char) then return end
    local key, unit = GK.MenuKey(ctx)
    if not (key and GK.HasRecord(key)) then return end
    AddLine(root, function() GK.ShowRecord(key, unit) end)
end

function GK.StartProfiles()
    LIB.Listen("GRUDGEKEEPER_CHANGED", Refill)
    if not (Menu and Menu.ModifyMenu) then return end
    -- pcall: a menu tag this client doesn't have must not stop the others
    pcall(Menu.ModifyMenu, "MENU_UNIT_ENEMY_PLAYER", OnEnemyMenu)
    for _, which in ipairs(FRIENDLY) do pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, OnFriendlyMenu) end
end
