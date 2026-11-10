-- Grudgekeeper - letters: news that waits until you open it.
-- Nothing pops up. A letter goes into your pile, the notice scroll (Notice.lua) shows that something
-- came, and clicking it opens the letter. Two sizes:
--   the SCROLL, unrolled between two rolls, for the orders themselves:
--     order     KILL ORDER       a guildie put a price on someone       red seal
--     complete  ORDER COMPLETE   an order was fulfilled                 red seal, FULFILLED stamp
--   the NOTE, a small landscape letter with a portrait, written by "the Grudgekeeper":
--     kill      A new title      a kill earned you one: where you stand  red seal
--     slain     Slain            someone killed you                     black seal, blood
--     paid      Bounty paid      the poster paid you                    red seal
--     expired   Order expired    your order ran out                     black seal
-- The paper, rolls, seals and blood are drawn by art/make_grudgekeeper_art.py (or imported from
-- generated art by art/import_grudgekeeper.py); the stamps by art/make_grudgekeeper_stamps.py.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MAX_LETTERS = 30
local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local STAMP_ALPHA = 0.55                 -- a letter's stamp, under its writing (BuildScroll)
local INK = { 0.22, 0.13, 0.05 }
local FADED = { 0.35, 0.25, 0.15 }
local BLOOD = { 0.47, 0.06, 0.04 }
local W, BODY_H, ROLL_H = 300, 340, 32         -- the scroll
local NW, NH = 540, 360                         -- the note: the frame's own 3:2, so it isn't stretched
local UNROLL, ROLLUP = 0.45, 0.2
local NOTE = { kill = true, slain = true, paid = true, expired = true }

-- The badge the notice scroll wears for the newest unread letter: the sealed scroll, or the bloodied
-- letter when someone killed you.
GK.LETTER_ICON = {
    order = MEDIA .. "notice",
    complete = MEDIA .. "notice",
    paid = MEDIA .. "notice",
    expired = MEDIA .. "notice",
    kill = MEDIA .. "notice",
    slain = MEDIA .. "notice_death",
}

-- ---------------------------------------------------------------------------
-- The rolled ends of a scroll
-- ---------------------------------------------------------------------------
-- In three pieces, so any width keeps the curled ends round: the two ends at their own shape, the
-- middle stretched. roll.tga holds the roll across its full width in rows 16-112 of 128
-- (art/import_grudgekeeper.py puts it there). flip: the bottom roll.
local ROLL_V0, ROLL_V1, ROLL_CAP = 16 / 128, 112 / 128, 0.08
local CAP_ASPECT = 512 * ROLL_CAP / 96          -- an end's width over its height, in the texture

function GK.MakeRoll(parent, height, flip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height)
    local v0, v1 = ROLL_V0, ROLL_V1
    if flip then v0, v1 = v1, v0 end
    local function Piece(u0, u1)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetTexture(MEDIA .. "roll")
        t:SetTexCoord(u0, u1, v0, v1)
        return t
    end
    local left, middle, right = Piece(0, ROLL_CAP), Piece(ROLL_CAP, 1 - ROLL_CAP), Piece(1 - ROLL_CAP, 1)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(height * CAP_ASPECT)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(height * CAP_ASPECT)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return f
end

-- ---------------------------------------------------------------------------
-- The pile
-- ---------------------------------------------------------------------------
-- A letter is news, and once read it goes: when the letters close, every letter read goes with them. They
-- were kept three days and piled up - "10 of 10" - each saying what the ledger says anyway: "letters
-- burde kanskje ikke bare bli liggende?" (the owner, 2026-11-07). While the letters are open, the ones
-- read stay, so the arrows can go back.
local reading = false            -- the letters are open: what was read stays until they close

local function Prune()
    local list = GK.char.letters
    for i = #list, 1, -1 do
        if list[i].read and not reading then table.remove(list, i) end
    end
    while #list > MAX_LETTERS do table.remove(list, 1) end
end

-- A letter about your own kill waits before the notice shows it: it goes into the pile at once, but
-- the notice and the unread count leave it out until a minute after the kill AND you are out of combat.
-- Right after a fight it was one more thing blinking at you (the owner, 2026-11-05: "it can be annoying
-- when it pops right after combat - wait a minute?"). Another kill in that minute joins the same letter
-- and starts the minute again. Kept here, not in the saved letter: a reload lets it land at once.
local KILL_HOLD = 60
local holding = setmetatable({}, { __mode = "k" })   -- letter -> GetTime() it may land
local releasePending = false
local Release

local function Hold(L)
    holding[L] = GetTime() + KILL_HOLD
    if not releasePending then
        releasePending = true
        C_Timer.After(KILL_HOLD + 0.1, Release)
    end
end

Release = function()
    releasePending = false
    local now, soonest, landed = GetTime(), nil, false
    for L, at in pairs(holding) do
        if at > now then
            soonest = math.min(soonest or math.huge, at - now)
        elseif not InCombatLockdown() then
            holding[L], landed = nil, true
        end
        -- its minute is up but you are fighting: PLAYER_REGEN_ENABLED calls this again
    end
    if soonest and not releasePending then
        releasePending = true
        C_Timer.After(soonest + 0.1, Release)
    end
    if landed then
        GK.NoticeUpdate(true, true)
        GK.Changed()
    end
end

--- A letter still held back after your own kill: in the pile, not yet news.
function GK.Held(L) return holding[L] ~= nil end

-- silent: no sound as it lands - a letter about something you just did yourself, like a kill, is no
-- news to you, so it only waits by the minimap. hold: it waits a minute and for the fight to end first.
local function Add(kind, data, silent, hold)
    -- letters off: nothing arrives as one ("tillat å skru av letters", the owner, 2026-11-09) - the ledger,
    -- the warnings and the mailbox's card still say what matters
    if GK.db.anyLetters == false then return data end
    GK.char.letterId = (GK.char.letterId or 0) + 1
    data.id, data.kind, data.t, data.read = GK.char.letterId, kind, time(), false
    local list = GK.char.letters
    list[#list + 1] = data
    Prune()
    if hold then Hold(data) end
    GK.NoticeUpdate(not hold, silent)
    GK.Changed()
    return data
end

--- Unread letters: how many, and the first one's place in the pile. A held letter isn't news yet, and with
--- letters off none is: the notice shows only a warning then.
function GK.Unread()
    local n, first = 0, nil
    if GK.db.anyLetters == false then return 0, nil end
    for i, l in ipairs(GK.char.letters) do
        if not l.read and not holding[l] then
            n = n + 1
            first = first or i
        end
    end
    return n, first
end

function GK.OrderLetter(o)
    local w = GK.Store().wanted[o.n]
    Add("order", { n = o.n, c = o.c, r = o.r, l = o.l, by = o.by, reward = o.reward, note = o.note, o = o.key,
        times = w and w.victims[o.by] or nil, auto = o.auto })
end

--- Your own kill that fulfilled it waits like a kill letter does.
--- So does one got with you there (GK.Helped): you were in that fight too.
function GK.CompleteLetter(o)
    local me = LIB.Me()
    local ours = o.doneBy == me or GK.Helped(o)
    Add("complete", { n = o.n, c = o.c, r = o.r, l = o.l, by = o.by, reward = o.reward, o = o.key,
        doneBy = o.doneBy, z = o.doneZone, pot = (GK.Pot(o)), share = o.pot and o.pot[me] or nil,
        helpers = o.helpers }, ours, ours)
end

--- Somebody paid you for an order you fulfilled: the poster (their reward) or a backer (their share).
function GK.PaidLetter(o, payer, amount)
    Add("paid", { n = o.n, c = o.c, r = o.r, l = o.l, by = payer or o.by, reward = amount or o.reward, o = o.key })
end

function GK.ExpiredLetter(o)
    Add("expired", { n = o.n, c = o.c, r = o.r, l = o.l, guid = o.guid, reward = o.reward, o = o.key })
end

--- A kill of ours that earned a new title: the one kind of kill with a letter (Kills.lua). An unread one
--- is written over by the next rather than stacked, so two titles before you look are one letter, the
--- newest. Silent: you were there.
function GK.KillLetter(v, zone, title)
    local rank, of = GK.MyRank()
    local list = GK.char.letters
    local last = list[#list]
    local L
    if last and last.kind == "kill" and not last.read then
        L = last
        L.t = time()
        Hold(L)                                     -- the minute starts again from this kill
    else
        L = Add("kill", {}, true, true)
    end
    L.n, L.c, L.r, L.l, L.z = v.key, v.c, v.r, v.l, zone
    L.rank, L.of, L.total, L.title = rank, of, GK.char.points, title
    GK.NoticeUpdate(false)
    GK.Changed()
end

--- autoOrder: this death posted a kill order on them (GK.AutoOrder), and the letter says so.
function GK.SlainLetter(v, times, zone, autoOrder)
    Add("slain", { n = v.key, guid = v.guid, c = v.c, r = v.r, l = v.l, times = times, z = zone, spell = v.spell,
        autoOrder = autoOrder or nil })
end

--- /grudge test: one of each, so the look can be judged without a fight. Marked as samples: their
--- buttons do nothing and they count for nothing.
function GK.SampleLetters()
    local me = LIB.Me() or "you"
    -- The enemies in the samples are from the other side, whichever side you're on.
    local horde = UnitFactionGroup("player") == "Horde"
    local ph = { n = "Pølse Hans", c = "ROGUE", r = horde and "Human" or "Orc", l = 35 }
    local function S(t)
        for k, v in pairs(ph) do if t[k] == nil then t[k] = v end end
        t.sample = true
        return t
    end
    Add("order", S({ by = "Edvard", reward = 2000, note = "Camps the flight master in Tarren Mill.", times = 24 }))
    Add("complete", S({ by = me, reward = 2000, doneBy = "Vebjørn", z = "Hillsbrad Foothills" }))
    Add("kill", S({ n = "Gærd Balle", c = "HUNTER", r = horde and "Night Elf" or "Troll", l = 27,
        z = "Hillsbrad Foothills", title = "Bloodhound", rank = 4, of = 12, total = 31 }))
    Add("slain", S({ times = 24, z = "Hillsbrad Foothills", spell = "Ambush" }))
    print(GK.TAG .. ": four sample letters are in your pile - click the scroll to read them.")
end

-- ---------------------------------------------------------------------------
-- What a letter says
-- ---------------------------------------------------------------------------
local function Ordinal(n)
    local tens = n % 100
    if tens >= 11 and tens <= 13 then return n .. "th" end
    local last = n % 10
    return n .. ((last == 1 and "st") or (last == 2 and "nd") or (last == 3 and "rd") or "th")
end

local function Ago(t)
    local s = time() - (t or 0)
    if s < 90 then return "just now" end
    if s < 3600 then return math.floor(s / 60) .. " min ago" end
    if s < 2 * GK.DAY then return math.floor(s / 3600) .. " h ago" end
    return math.floor(s / GK.DAY) .. " days ago"
end
GK.Ago = Ago

local function Order(L)
    return L.o and GK.Store().orders[L.o] or nil
end

--- "Pølse Hans, a level 35 Orc Rogue" - as much as we know. mid: the name is the subject of a
--- sentence that carries on, so the description is closed with a comma too.
local function Who(L, mid)
    local name = GK.Show(L.n)
    local d = GK.Describe(L.l, L.c, L.r)
    if d == "" then return name end
    d = d:gsub("^Level", "level")
    return name .. ", " .. (d:match("^[AEIOU]") and "an " or "a ") .. d .. (mid and "," or "")
end

-- The Grudgekeeper's last word, picked by the letter's number so a letter always says the same thing.
local CLOSING = {
    kill = { "That's how a grudge is kept.", "They'll remember your name.", "Keep them coming." },
    slain = { "Some debts are paid in blood.", "I've written it down. I always do." },
    paid = { "A debt settled. The book balances." },
    expired = { "Grudges keep. Orders don't." },
}

--- The scroll: title, name, info, body (lines), foot, seal, stamp, buttons { { text, fn } }
local function ScrollContent(L)
    local me, show = LIB.Me(), GK.Show
    local info = GK.Describe(L.l, L.c, L.r)
    local body, buttons = {}, {}
    local o = Order(L)
    -- The way to the ledger and the way out are the bar under the scroll (BuildScroll), for every scroll;
    -- the buttons here are only what this one asks of you.
    if L.kind == "order" then
        -- An order that posted itself carries the Grudgekeeper's reason, not the poster's words.
        if L.note then body[#body + 1] = L.auto and L.note or ('"' .. L.note .. '"') end
        if L.times then
            body[#body + 1] = ("Has killed %s %s."):format(show(L.by), L.times == 1 and "once" or (L.times .. " times"))
        end
        if o and o.seen then
            body[#body + 1] = ("Last seen in %s, %s."):format(o.seen.z or "the world", Ago(o.seen.t))
        end
        body[#body + 1] = " "
        -- the pot as it stands now, if we still have the order; as posted otherwise
        local pot, backers = L.reward or 0, 0
        if o then pot, backers = GK.Pot(o) end
        if pot > 0 then
            body[#body + 1] = "Reward: " .. GK.Coins(pot)
            if backers > 0 and o then
                -- who chipped in, the biggest share first: the poster's own reward leads
                local shares = {}
                if (o.reward or 0) > 0 then shares[1] = { who = o.by, copper = o.reward } end
                for who, copper in pairs(o.pot) do shares[#shares + 1] = { who = who, copper = copper } end
                table.sort(shares, function(a, b) return a.copper > b.copper end)
                local names = {}
                for i = 1, math.min(3, #shares) do
                    names[i] = ("%s %s"):format(show(shares[i].who), GK.MoneyText(shares[i].copper))
                end
                local more = #shares - #names
                body[#body + 1] = table.concat(names, ", ") .. (more > 0 and (" and %d more"):format(more) or "")
            end
        else
            body[#body + 1] = "No bounty - for the guild's honour."
        end
        if o and o.state ~= "o" then body[#body + 1] = "(This order is closed.)" end
        -- Nothing to take or accept: the order is the whole message - "hey, we put out an order, kill this
        -- one" (the owner, 2026-11-07). Any guildie's kill fulfils it.
        if o and o.state == "o" then
            body[#body + 1] = pot > 0 and "Kill on sight. Whoever gets them collects." or "Kill on sight."
        end
        if o and o.state == "o" and o.by ~= me then
            buttons[#buttons + 1] = { "Add to the pot", function() GK.OpenPost({ key = o.n, guid = o.guid, c = o.c,
                r = o.r, l = o.l }) end }
        end
        -- short: the foot shares its line with the seal on a 300-wide sheet
        local foot = L.auto and ("Posted by %s's death"):format(show(L.by)) or ("Posted by " .. show(L.by))
        return "KILL ORDER", show(L.n), info, body, foot, "seal_red", nil, buttons
    end
    -- complete
    local doneBy = L.doneBy and show(L.doneBy) or "Someone"
    local where = L.z and (" in " .. L.z) or ""
    local pot = L.pot or L.reward or 0
    local owe = (L.by == me and (L.reward or 0)) or L.share or 0     -- what I promised: reward or share
    -- who else was there: the group members near the killing blow (GroupHelpers, Guild.lua) - "det stod ikke
    -- noe om at han hadde vært med" (the owner, 2026-11-09)
    local others = {}
    for _, k in ipairs(L.helpers or {}) do
        if not LIB.IsMyStoredName(k) then others[#others + 1] = k end
    end
    local helped = L.doneBy ~= me and GK.Helped(L)
    -- "you and Kari", "you, Kari and Lars": you first, then everyone else who was there
    local function YouAnd(keys)
        local names = { "you" }
        for _, k in ipairs(keys) do names[#names + 1] = show(k) end
        return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
    end
    -- what we have coming: our part of everyone else's gold, the bounty shared among all who got them
    -- (GK.Part, Guild.lua); the letter's own pot when the order is gone
    local shared = o and #GK.Hunters(o) > 1
    local due = o and GK.DueTo(o, me) or nil
    local function Coming(copper)
        if copper <= 0 then return end
        if shared then
            body[#body + 1] = ("Your part: %s of %s, to come by mail."):format(GK.MoneyText(copper), GK.MoneyText(pot))
        else
            body[#body + 1] = ("%s in all, to come by mail."):format(GK.MoneyText(copper))
        end
    end
    if L.doneBy == me and L.by == me then
        -- your own order: nobody mails you your own reward, only its backers their shares
        if #others > 0 then
            body[#body + 1] = ("Your own order - %s got them%s."):format(YouAnd(others), where)
        else
            body[#body + 1] = "Your own order - you got them yourself" .. where .. "."
        end
        local backed = due or (pot - (L.reward or 0))
        if backed > 0 then body[#body + 1] = ("%s from its backers, to come by mail."):format(GK.MoneyText(backed)) end
    elseif L.doneBy == me then
        body[#body + 1] = "You collected the bounty" .. (#others > 0 and (" with " .. GK.NameList(others)) or "")
            .. where .. "."
        Coming(due or pot)
    elseif helped then
        -- you were there: it is yours too, and yours to tell
        local all = { L.doneBy }
        for _, k in ipairs(others) do all[#all + 1] = k end
        local together = YouAnd(all)
        body[#body + 1] = ("%s got them%s. %s had the killing blow."):format(together:sub(1, 1):upper()
            .. together:sub(2), where, doneBy)
        if L.by ~= me then Coming(due or 0) end
    end
    -- One line in guild chat for the guildies without Grudgekeeper - only ever from this click, or the
    -- order's card in the ledger (GK.TellOrder).
    if not L.sample and GK.CanTellOrder(o, L) then
        buttons[#buttons + 1] = { "Tell the guild", function() GK.TellOrder(o, L) end }
    end
    if L.doneBy ~= me and not helped then
        body[#body + 1] = (L.helpers and GK.WhoGotThem(L.doneBy, L.helpers) or doneBy)
            .. (L.by == me and " collected the bounty" or " got there first") .. where .. "."
    end
    -- what we owe on it: a part to each hunter (GK.Owed); as the letter has it when the order is gone
    local debts = {}
    if o then
        for _, e in ipairs(GK.Owed()) do
            if e.o == o then debts[#debts + 1] = ("%s %s"):format(show(e.to), GK.MoneyText(e.share)) end
        end
    end
    if #debts > 0 then
        body[#body + 1] = " "
        body[#body + 1] = ("You owe %s - mail or trade it, and it is marked paid by itself."):format(#debts == 1
            and debts[1] or (table.concat(debts, ", ", 1, #debts - 1) .. " and " .. debts[#debts]))
        buttons[#buttons + 1] = { "Mark as paid", function() GK.PayShare(o) end }
    elseif not o and L.doneBy ~= me and not helped and owe > 0 then
        body[#body + 1] = " "
        body[#body + 1] = ("You owe them %s - mail or trade it to them, and it is marked paid by itself."):format(
            GK.MoneyText(owe))
    end
    -- the order's seal, broken: it has been opened and carried out
    return "ORDER COMPLETE", show(L.n) .. " is dead", info, body, "Posted by " .. show(L.by), "seal_broken",
        "stamp_fulfilled", buttons
end

--- The note: title, paragraphs, seal, blood, the action button { text, fn } or nil
local function NoteContent(L)
    local show = GK.Show
    local p = {}
    local action
    local function PostOn() GK.OpenPost({ key = L.n, guid = L.guid, c = L.c, r = L.r, l = L.l }) end
    local closing = CLOSING[L.kind]
    if L.kind == "kill" then
        -- A kill gets a letter only for a new title (Kills.lua), and it says three things: the title, the kill
        -- that got it, where you stand. Seven lines - the kill, its points, a streak, "and 1 more", the total
        -- and the title - ran into the seal ("kanskje ikke så mye text?", the owner, 2026-11-07). A letter
        -- from before then, with no title, says the kill and where you stand.
        local where = L.z and (" in " .. L.z) or ""
        local stand = (L.of or 0) > 1 and ("%d points - #%d of %d in the guild."):format(L.total or 0, L.rank, L.of)
            or ("%d points."):format(L.total or 0)
        if L.title then
            p[1] = ("You are now %s %s."):format(L.title:match("^[AEIOU]") and "an" or "a", L.title)
            p[2] = ("%s%s was the kill that did it."):format(show(L.n), where)
        else
            p[1] = ("You killed %s%s."):format(show(L.n), where)
        end
        p[#p + 1] = stand
        action = { "Leaderboard", function() GK.OpenWindow(2) end }
        return L.title and "A new title" or "Blood drawn", p, closing, "seal_red", false, action
    elseif L.kind == "slain" then
        p[#p + 1] = ("%s killed you%s%s."):format(Who(L, true), L.spell and (" with " .. L.spell) or "",
            L.z and (" in " .. L.z) or "")
        if L.times then
            p[#p + 1] = L.times == 1 and "The first time. Remember the name."
                or ("That's the %s time."):format(Ordinal(L.times))
        end
        if L.autoOrder then
            -- posted in your name by this very death: say so, and where to withdraw it
            -- Short, and no closing line after it: this is the longest of the small letters, and at eight
            -- lines its last one met the seal and signature (the preview of 2026-11-04).
            p[#p + 1] = "A kill order on them went out to the guild, in your name. The hitlist can withdraw it."
            closing = nil
            action = { "Hitlist", function() GK.OpenWindow(1) end }
        elseif GK.OrderOn(L.n, L.guid) then
            p[#p + 1] = "There's a price on their head already."
            action = { "Hitlist", function() GK.OpenWindow(1) end }
        else
            action = { "Put a price on them", PostOn }
        end
        return "Slain", p, closing, "seal_black", true, action
    elseif L.kind == "paid" then
        p[#p + 1] = ("%s paid you %s for the head of %s. Check your mail."):format(show(L.by),
            GK.MoneyText(L.reward), show(L.n))
        action = { "Hitlist", function() GK.OpenWindow(1) end }
        return "Bounty paid", p, closing, "seal_red", false, action
    end
    -- expired
    p[#p + 1] = ("%s outlived your kill order. It ran out after a week."):format(Who(L))
    action = { "Post it again", PostOn }
    return "Order expired", p, closing, "seal_black", false, action
end

--- What a letter says, apart from how it is drawn (FillScroll and FillNote draw from it):
--- { note (a small letter, else the scroll), title, name, info, lines, foot, seal, stamp, blood, buttons =
--- { { text, fn } }, c, rf, sx, key, sample }. name, info, foot and stamp are the scroll's only.
function GK.LetterContent(L)
    local d = { c = L.c, rf = L.rf, sx = L.sx, key = L.n, sample = L.sample }
    if not NOTE[L.kind] then
        local title, name, info, body, foot, seal, stamp, buttons = ScrollContent(L)
        d.title, d.name, d.info, d.lines, d.foot, d.seal, d.stamp, d.buttons = title, name, info, body, foot, seal,
            stamp, buttons
        return d
    end
    local title, paragraphs, closing, seal, blood, action = NoteContent(L)
    local lines = {}
    for i, text in ipairs(paragraphs) do lines[i] = text end
    -- The closing line only on a short letter: a long one (a death that posted a kill order) would push it
    -- into the seal and the signature.
    if closing and #paragraphs <= 4 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = closing[(L.id or 1) % #closing + 1]
    end
    d.note, d.title, d.lines, d.seal, d.blood, d.buttons = true, title, lines, seal, blood, { action }
    return d
end

-- ---------------------------------------------------------------------------
-- Shared bits of both views
-- ---------------------------------------------------------------------------
local scroll, note  -- the two views, made on first use
local index         -- which letter in the pile is showing

--- The letters closed - by X, Close, Escape or the scroll rolling up: the read ones go. A moment later,
--- as going from a scroll to a note hides one view before it shows the other.
local function Closed()
    C_Timer.After(0, function()
        if (note and note:IsShown()) or (scroll and scroll:IsShown()) then return end
        reading, index = false, nil
        Prune()
        GK.NoticeUpdate(false)
        GK.Changed()
    end)
end

local function Ink(fs, colour, font, size)
    GK.SetFont(fs, font, size)                   -- a family: names in Cyrillic too (Core.lua)
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

--- "2 of 5" with arrows either side, under `parent`'s bottom edge at x.
local function Pager(f, parent, x, y)
    f.page = parent:CreateFontString(nil, "ARTWORK")
    Ink(f.page, INK, TEXT_FONT, 11)
    f.page:SetPoint("BOTTOM", parent, "BOTTOM", x, y)
    local function Arrow(dir, dx)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(22, 22)
        b:SetPoint("CENTER", f.page, "CENTER", dx, 0)
        local kind = dir < 0 and "Prev" or "Next"
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Disabled")
        b:SetScript("OnClick", function() GK.ShowLetter(index + dir) end)
        return b
    end
    f.prev = Arrow(-1, -40)
    f.next = Arrow(1, 40)
end

local function UpdatePager(f)
    local n = #GK.char.letters
    f.page:SetText(("%d of %d"):format(index, n))
    f.prev:SetEnabled(index > 1)
    f.next:SetEnabled(index < n)
end

local function SetButton(b, spec, L, refill)
    b:SetShown(spec ~= nil)
    if not spec then return end
    b:SetText(spec[1])
    b:SetEnabled(not L.sample)
    b:SetScript("OnClick", function()
        spec[2]()
        refill(L)
    end)
end

-- ---------------------------------------------------------------------------
-- The scroll
-- ---------------------------------------------------------------------------
local BAR_H = 30                 -- the bar of buttons under the scroll's bottom roll

local function BuildScroll()
    local f = CreateFrame("Frame", "GrudgekeeperLetter", UIParent)
    f:SetSize(W + 16, BODY_H + ROLL_H + BAR_H)          -- the bar too, so it is kept on the screen
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", 0, 60)
    f:EnableMouse(true)

    -- The sheet grows down from under the top roll as it unrolls. The paper and the writing sit on a
    -- child at full size, so the growing sheet reveals them (clipped) instead of squeezing them.
    local sheet = CreateFrame("Frame", nil, f)
    sheet:SetPoint("TOP", 0, -ROLL_H / 2)
    sheet:SetSize(W, BODY_H)
    sheet:SetClipsChildren(true)
    local c = CreateFrame("Frame", nil, sheet)
    c:SetPoint("TOP")
    c:SetSize(W, BODY_H)
    local paper = c:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(MEDIA .. "sheet")

    f.title = c:CreateFontString(nil, "ARTWORK")
    Ink(f.title, BLOOD, TITLE_FONT, 26)
    f.title:SetPoint("TOP", 0, -34)
    f.name = c:CreateFontString(nil, "ARTWORK")
    Ink(f.name, INK, TITLE_FONT, 19)
    f.name:SetPoint("TOP", f.title, "BOTTOM", 0, -12)
    f.name:SetWidth(W - 50)
    f.info = c:CreateFontString(nil, "ARTWORK")
    Ink(f.info, INK, TEXT_FONT, 12)
    f.info:SetPoint("TOP", f.name, "BOTTOM", 0, -4)
    f.body = c:CreateFontString(nil, "ARTWORK")
    Ink(f.body, INK, TEXT_FONT, 13)
    f.body:SetPoint("TOP", f.info, "BOTTOM", 0, -16)
    f.body:SetWidth(W - 64)
    f.body:SetSpacing(3)
    f.foot = c:CreateFontString(nil, "ARTWORK")
    Ink(f.foot, INK, TEXT_FONT, 11)
    f.foot:SetPoint("BOTTOMLEFT", 32, 92)

    f.seal = c:CreateTexture(nil, "OVERLAY")
    f.seal:SetSize(66, 66)
    f.seal:SetPoint("BOTTOMRIGHT", -24, 22)
    -- The stamp UNDER the writing and half faded, as ink stamped on paper: over it, at full strength, it
    -- made the letter "vanskelig å lese" (the owner, 2026-11-06).
    f.stamp = c:CreateTexture(nil, "BORDER", nil, 2)
    f.stamp:SetSize(210, 105)
    f.stamp:SetPoint("CENTER", 0, -30)
    f.stamp:SetAlpha(STAMP_ALPHA)

    -- Up to two buttons, bottom left; the seal has the bottom right.
    f.buttons = {}
    for i = 1, 2 do
        local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        b:SetSize(176, 22)
        b:SetPoint("BOTTOMLEFT", 30, 56 - (i - 1) * 26)
        f.buttons[i] = b
    end

    -- The rolls sit above the sheet; the bottom one hangs from the sheet's edge, so it travels down as
    -- the sheet unrolls.
    local rolls = CreateFrame("Frame", nil, f)
    rolls:SetAllPoints()
    rolls:SetFrameLevel(sheet:GetFrameLevel() + 6)
    local top = GK.MakeRoll(rolls, ROLL_H)
    top:SetWidth(W + 16)
    top:SetPoint("TOP")
    local bottom = GK.MakeRoll(rolls, ROLL_H, true)
    bottom:SetWidth(W + 16)
    bottom:SetPoint("TOP", sheet, "BOTTOM", 0, ROLL_H / 2)
    -- The bar under the bottom roll, travelling down with it: to the order in the ledger, or away. The iron
    -- X on the top roll's end was hard to hit, and "1 of 3" with its arrows turned one order into a pile:
    -- "X oppe i høyre funker ikke så bra ... en page kun for en order. åpner du kill order så lukkes det
    -- lille vinduet" (the owner, 2026-11-07). The next letter waits for the next click on the notice.
    -- Close rolls the scroll up, as Escape does; both are our own Hide, so they work in combat too.
    f.open = CreateFrame("Button", nil, rolls, "UIPanelButtonTemplate")
    f.open:SetSize(150, 22)
    f.open:SetPoint("TOPRIGHT", bottom, "BOTTOM", -3, -4)
    f.open:SetText("Open kill orders")
    f.close = CreateFrame("Button", nil, rolls, "UIPanelButtonTemplate")
    f.close:SetSize(110, 22)
    f.close:SetPoint("TOPLEFT", bottom, "BOTTOM", 3, -4)
    f.close:SetText("Close")
    f.close:SetScript("OnClick", function() GK.CloseLetters() end)

    -- The stamp comes down hard: big and faint to its size, then the sheet jolts.
    local slam = f.stamp:CreateAnimationGroup()
    local grow = slam:CreateAnimation("Scale")
    grow:SetScaleFrom(2.4, 2.4)
    grow:SetScaleTo(1, 1)
    grow:SetDuration(0.16)
    grow:SetSmoothing("IN")
    local fade = slam:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(STAMP_ALPHA)
    fade:SetDuration(0.08)
    local jolt = f:CreateAnimationGroup()
    for i, dx in ipairs({ 5, -9, 4 }) do
        local t = jolt:CreateAnimation("Translation")
        t:SetOffset(dx, 0)
        t:SetDuration(0.04)
        t:SetOrder(i)
    end
    slam:SetScript("OnFinished", function()
        jolt:Play()
        GK.Sound("IG_QUEST_LIST_COMPLETE")
    end)
    f.slam = slam

    f.sheet = sheet
    f:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(f, GK.db, "letter") end
    -- RegisterWindow owns OnShow/OnHide; ours only ever hooks.
    f:HookScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    f:HookScript("OnHide", Closed)
    scroll = f
end

-- Unroll (dir 1) or roll up (dir -1, then hide). Runs only while it moves.
local function Roll(dir, done)
    local f = scroll
    local t0, span = GetTime(), dir > 0 and UNROLL or ROLLUP
    f:SetScript("OnUpdate", function(self)
        if not self:IsShown() then self:SetScript("OnUpdate", nil) return end
        local p = math.min(1, (GetTime() - t0) / span)
        local e = dir > 0 and (1 - (1 - p) ^ 3) or (1 - p) ^ 2
        f.sheet:SetHeight(math.max(1, BODY_H * e))
        if p >= 1 then
            self:SetScript("OnUpdate", nil)
            if done then done() end
        end
    end)
end

local function FillScroll(L)
    local f = scroll
    local d = GK.LetterContent(L)
    local title, name, info, body, foot, seal, stamp, buttons = d.title, d.name, d.info, d.lines, d.foot, d.seal,
        d.stamp, d.buttons
    -- "ORDER COMPLETE" fills the sheet at the size "KILL ORDER" wants
    Ink(f.title, BLOOD, TITLE_FONT, #title > 11 and 22 or 26)
    f.title:SetText(title)
    f.name:SetText(name)
    f.info:SetText(info)
    f.body:SetText(table.concat(body, "\n"))
    f.foot:SetText(foot or "")
    f.seal:SetTexture(MEDIA .. seal)
    f.stamp:Hide()
    f.stampName = stamp
    if stamp then f.stamp:SetTexture(MEDIA .. stamp) end
    for i, b in ipairs(f.buttons) do SetButton(b, buttons[i], L, FillScroll) end
    -- the ledger's kill orders, on this order, and the scroll gone at once: two windows on one order is one
    -- too many
    f.open:SetScript("OnClick", function()
        f:Hide()
        GK.OpenOrder(L.o)
    end)
end

-- ---------------------------------------------------------------------------
-- The note
-- ---------------------------------------------------------------------------
--- Grudgekeeper's own close button: the iron X (Media/close), a red glow behind it under the mouse,
--- a shade darker pressed. Every close path is our own Hide, so it works in combat too. size: the
--- button's side (what a click can hit); art: the cross's own side, smaller, so it sits inside a
--- socket rather than over its rim (the preview of 2026-11-04 had it filling the hole). b.cross and
-- b.glow are kept, for a caller whose socket changes size (the ledger, open and folded).
--- The game's own close button (UIPanelCloseButton), for the note frame (letter_frame, GK.MakeNoteFrame),
--- whose iron corner our cross clashed with. It sits on the bronze rivet of the top-right iron (measured
--- from letter_frame.tga: 4.3% of the width in, 6.9% of the height down); at the frame's very corner it
--- hung half off the iron ("litt lenger inn og ned", the owner, 2026-11-06). Its click is our own
--- function: the template's HideUIPanel does nothing in combat when addon code calls it.
function GK.MakeGameCloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    b:SetScript("OnClick", onClick)
    b:SetFrameLevel(parent:GetFrameLevel() + 12)
    b:SetPoint("CENTER", parent, "TOPRIGHT", -NW * 0.043, -NH * 0.069)
    return b
end

function GK.MakeCloseButton(parent, size, onClick, art)
    art = art or size
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local glow = b:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(MEDIA .. "glow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.2, 0.1)
    glow:SetSize(art * 1.8, art * 1.8)
    glow:SetPoint("CENTER")
    glow:Hide()
    local x = b:CreateTexture(nil, "ARTWORK")
    x:SetTexture(MEDIA .. "close")
    x:SetSize(art, art)
    x:SetPoint("CENTER")
    b:SetScript("OnEnter", function() glow:Show() end)
    b:SetScript("OnLeave", function() glow:Hide() x:SetVertexColor(1, 1, 1) end)
    b:SetScript("OnMouseDown", function() x:SetVertexColor(0.7, 0.7, 0.7) end)
    b:SetScript("OnMouseUp", function() x:SetVertexColor(1, 1, 1) end)
    b:SetScript("OnClick", onClick)
    b.cross, b.glow = x, glow
    return b
end

-- The client's race portraits (raceicon128-<race>-<sex>, in Forever's atlas data) by the race's file
-- token; Undead is "Scourge" to the client and "undead" to the atlas.
local RACE_ATLAS = { Scourge = "undead" }

--- Dress a portrait texture for a player: their race's face when we know race and sex, else their
--- class crest, else the Grudgekeeper's red seal. info = { rf (race file token), sx (2 male, 3
--- female), c (class) }. Returns "race", "class" or "seal", so the caller knows whether the class
--- still needs showing (as a badge) beside a face.
function GK.SetPortrait(tex, info)
    info = info or {}
    local rf, sx = info.rf, info.sx
    if type(rf) == "string" and (sx == 2 or sx == 3) and tex.SetAtlas then
        local atlas = ("raceicon128-%s-%s"):format(RACE_ATLAS[rf] or rf:lower(), sx == 3 and "female" or "male")
        local known = not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(atlas)
        if known and pcall(tex.SetAtlas, tex, atlas) then
            tex:SetTexCoord(0, 1, 0, 1)
            return "race"
        end
    end
    local coords = info.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[info.c]
    if coords then
        tex:SetTexture(CLASS_ICONS)
        tex:SetTexCoord(unpack(coords))
        return "class"
    end
    tex:SetTexture(MEDIA .. "mark")
    tex:SetTexCoord(0, 1, 0, 1)
    return "seal"
end

-- A player's own face is not shown at all, only their race's (race and sex) with their class on its
-- shoulder. The game draws a real face only from a unit and nothing reads it back, so a real one lasted
-- only while the session did and only for those you had targeted: the same player's picture switched
-- between the two ("dropp personal ikon ... så flipper ikke bildet hele tida", the owner, 2026-11-07).

--- A round portrait in the bronze ring, for the ledger's rows and the sheets' heads alike. p:Set(face)
--- dresses it (GK.SetPortrait), with a class crest on its shoulder beside a race's face. With
--- face.key and no race and sex of its own, what we kept of that player fills them in (GK.FaceOf).
function GK.MakePortrait(parent, size)
    local p = { parent = parent }
    p.tex = parent:CreateTexture(nil, "ARTWORK")
    -- The ring's hole is 0.80 of it across and its band runs out to the edge (portrait_ring, measured
    -- 2026-11-06). At 0.82 the face's masked circle - the game's mask has a soft edge - came out smaller
    -- than the hole, and the page showed between face and ring ("glippe mellom ikonet og ramma", the
    -- owner). At 0.92 the face's edge is under the band.
    p.tex:SetSize(size * 0.92, size * 0.92)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(p.tex)
    p.tex:AddMaskTexture(mask)
    p.ring = parent:CreateTexture(nil, "OVERLAY")
    p.ring:SetTexture(MEDIA .. "portrait_ring")
    -- the bronze dulled a little: polished, it was "litt shiny" beside the page (the owner, 2026-11-06)
    p.ring:SetDesaturation(0.35)
    p.ring:SetVertexColor(0.8, 0.74, 0.68)
    p.ring:SetSize(size, size)
    p.ring:SetPoint("CENTER", p.tex, "CENTER")
    -- No dark rim behind the ring: one was tried for contrast and read as a brown halo ("ser litt rart
    -- ut", 2026-11-05).
    p.badge = parent:CreateTexture(nil, "OVERLAY", nil, 2)
    p.badge:SetSize(size * 0.42, size * 0.42)
    p.badge:SetPoint("CENTER", p.tex, "BOTTOMRIGHT", -size * 0.11, size * 0.11)   -- where it sat at 0.82
    function p:Set(face)
        face = face or {}
        local key = face.faceKey or face.key
        if key and not (face.rf and face.sx) and GK.FaceOf then face = GK.FaceOf(key, face.c) end
        self.kind = GK.SetPortrait(self.tex, face)
        self.tex:Show()
        -- the class crest on the shoulder of a race's face, never beside the crest itself
        local coords = self.kind == "race" and face.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[face.c]
        self.badge:SetShown(coords and true or false)
        if coords then
            self.badge:SetTexture(CLASS_ICONS)
            self.badge:SetTexCoord(unpack(coords))
        end
    end
    function p:SetShown(on)
        self.tex:SetShown(on)
        self.ring:SetShown(on)
        if not on then self.badge:Hide() end
    end
    return p
end

-- ---------------------------------------------------------------------------
-- The sheets: the kill order, the note and the who-picker share one look, ink on the parchment and
-- nothing of the game's own kit. A face in the bronze ring at the head, each part named in small
-- capitals over a thin rule, lines to write on, and the red wax seal as the button that sends it.
-- The game's dark input boxes and red buttons on our paper read as "en intern har lagd" (the owner,
-- 2026-11-06); the look was previewed with the addon's own art before it was built.
-- ---------------------------------------------------------------------------
local function SheetInk(fs, colour, font, size)
    GK.SetFont(fs, font, size)
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

-- Every sheet made, the scroll and the framed ones alike. One opened on the ledger lies on it
-- (f.onLedger, GK.PlaceSheet): a drag on it moves the ledger, and it closes with the ledger - "henge
-- sammen er nice. lukkes hoved lukkes begge" (the owner, 2026-11-06).
local sheets = {}

--- What a drag on a sheet moves: the ledger, through the ledger's own drag (which saves where it is),
--- when the sheet lies on it - the sheet is anchored to it and goes along. Else the sheet itself.
local function Dragged(f)
    local win = f.onLedger and _G.GrudgekeeperFrame
    if win and win:IsShown() then return win end
    return f
end
local function DragStart(f)
    local t = Dragged(f)
    local fn = t ~= f and t:GetScript("OnDragStart")
    if fn then fn(t) else t:StartMoving() end
end
local function DragStop(f)
    local t = Dragged(f)
    local fn = t ~= f and t:GetScript("OnDragStop")
    if fn then fn(t) else t:StopMovingOrSizing() end
end

--- A sheet's frame and what every sheet does: the dialog strata, kept on screen, dragged as above.
local function SheetFrame(name, w, h, template)
    local f = CreateFrame("Frame", name, UIParent, template)
    f:SetSize(w, h)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", DragStart)
    f:SetScript("OnDragStop", DragStop)
    sheets[#sheets + 1] = f
    return f
end

--- The ledger closing: the sheets lying on it close with it (Window.lua hooks its OnHide).
function GK.CloseLedgerSheets()
    for _, f in ipairs(sheets) do
        if f.onLedger then f:Hide() end
    end
end

--- A sheet of parchment between two rolls, w x h, with our cross at its top right. It can be dragged
--- anywhere, and Escape closes it before the window under it. Hidden: the caller writes on it first.
function GK.MakeSheet(name, w, h)
    local f = SheetFrame(name, w, h)
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(MEDIA .. "sheet")
    local top = GK.MakeRoll(f, 30)
    top:SetWidth(w + 16)
    top:SetPoint("BOTTOM", f, "TOP", 0, -15)
    local bottom = GK.MakeRoll(f, 30, true)
    bottom:SetWidth(w + 16)
    bottom:SetPoint("TOP", f, "BOTTOM", 0, 15)
    local close = GK.MakeCloseButton(f, 20, function() f:Hide() end, 14)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetFrameLevel(f:GetFrameLevel() + 12)
    f:Hide()
    if LIB.RegisterPopup then LIB.RegisterPopup(f) else tinsert(UISpecialFrames, name) end
    return f
end

--- The head of a sheet: whom it is about. A face in the ring, a small caption over the name, and level,
--- race and class under it. head:Set(caption, t, red) with t = { key, c, r, rf, sx, l }; red: the
--- caption in blood (a kill order), else faded ink.
function GK.SheetHead(f, w)
    local width = w - 94 - 34                     -- from the face to the cross
    local h = { face = GK.MakePortrait(f, 56) }
    h.face.tex:SetPoint("CENTER", f, "TOPLEFT", 56, -54)
    h.caption = f:CreateFontString(nil, "ARTWORK")
    SheetInk(h.caption, FADED, TEXT_FONT, 10)
    h.caption:SetPoint("TOPLEFT", 94, -31)
    h.name = f:CreateFontString(nil, "ARTWORK")
    SheetInk(h.name, INK, TITLE_FONT, 20)
    h.name:SetPoint("TOPLEFT", h.caption, "BOTTOMLEFT", 0, -3)
    h.name:SetWidth(width)
    h.name:SetJustifyH("LEFT")
    h.name:SetWordWrap(false)
    h.info = f:CreateFontString(nil, "ARTWORK")
    SheetInk(h.info, FADED, TEXT_FONT, 11)
    h.info:SetPoint("TOPLEFT", h.name, "BOTTOMLEFT", 0, -3)
    h.info:SetWidth(width)
    h.info:SetJustifyH("LEFT")
    h.info:SetWordWrap(false)
    function h:Set(caption, t, red)
        self.caption:SetText(caption)
        SheetInk(self.caption, red and BLOOD or FADED, TEXT_FONT, 10)
        -- a long name steps down a size or two before the game cuts it short
        for _, size in ipairs({ 20, 17, 15 }) do
            SheetInk(self.name, INK, TITLE_FONT, size)
            self.name:SetText(GK.Show(t.key))
            if (self.name:GetStringWidth() or 0) <= width then break end
        end
        self.info:SetText(GK.Describe(t.l, t.c, t.r))
        self.face:Set(t)
    end
    return h
end

--- A part of a sheet: its name in small capitals at y down from the top, and a thin rule from there to
--- the sheet's edge. The rule is placed from the sheet on both ends, so they can't disagree on its height.
--- fs:Label(words) renames it, and the rule moves with the words.
--- fs:Place(y) moves it down the sheet, rule and all (the note sheet's parts move with its tags).
function GK.SheetSection(f, text, y)
    local fs = f:CreateFontString(nil, "ARTWORK")
    fs.rule = f:CreateTexture(nil, "ARTWORK")
    if f.skinned then
        -- on a window in the game's frame, in the skin's colours (GK.MakeFrameSheet)
        GK.Ink(fs, GK.FADED, TEXT_FONT, 10)
        GK.Paint(fs.rule, "rule")
    else
        SheetInk(fs, FADED, TEXT_FONT, 10)
        fs.rule:SetColorTexture(FADED[1], FADED[2], FADED[3], 0.45)
    end
    fs.rule:SetHeight(1)
    function fs:Place(at)
        self.y = at
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -at)
        self.rule:ClearAllPoints()
        self.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 30 + math.ceil(self:GetStringWidth() or 30) + 8, -(at + 5))
        self.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -(at + 5))
    end
    function fs:Label(words)
        self:SetText(words:upper())
        self:Place(self.y)
    end
    fs.y = y
    fs:Label(text)
    function fs:ShowAll(on)
        self:SetShown(on)
        self.rule:SetShown(on)
    end
    return fs
end

--- A line to write on: an edit box drawn as a ruled line in ink. The hint stands on it in faded ink
--- while it is empty, and the line turns to blood while you write. e.onChange(e, byHand) runs on every
--- change of its text (OnTextChanged is the line's own: set onChange, not the script).
function GK.SheetLine(f, width, letters, hint, numeric)
    local e = CreateFrame("EditBox", nil, f)
    e:SetSize(width, 20)
    e:EnableMouse(true)
    e:SetAutoFocus(false)
    e:SetMaxLetters(letters)
    GK.SetFont(e, TEXT_FONT, 13)                 -- what is typed: a name in Cyrillic shows as it is typed
    e:SetTextColor(INK[1], INK[2], INK[3])
    e:SetShadowOffset(0, 0)
    e:SetTextInsets(2, 2, 0, 0)
    e:SetHighlightColor(BLOOD[1], BLOOD[2], BLOOD[3], 0.35)
    if numeric then
        e:SetNumeric(true)
        e:SetJustifyH("RIGHT")
    end
    e.rule = e:CreateTexture(nil, "ARTWORK")
    e.rule:SetHeight(1)
    e.rule:SetPoint("BOTTOMLEFT")
    e.rule:SetPoint("BOTTOMRIGHT")
    e.hint = e:CreateFontString(nil, "ARTWORK")
    SheetInk(e.hint, FADED, TEXT_FONT, 12)
    e.hint:SetAlpha(0.7)
    e.hint:SetPoint("LEFT", 2, 0)
    e.hint:SetText(hint or "")
    local function Look(self)
        self.hint:SetShown((self:GetText() or "") == "")
        local c = self:HasFocus() and BLOOD or FADED
        self.rule:SetColorTexture(c[1], c[2], c[3], self:HasFocus() and 0.8 or 0.55)
    end
    e:SetScript("OnTextChanged", function(self, byHand)
        Look(self)
        if self.onChange then self.onChange(self, byHand) end
    end)
    e:SetScript("OnEditFocusGained", Look)
    e:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        Look(self)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    Look(e)
    return e
end

--- The button that sends a sheet: its word in blood beside the red wax seal, at the sheet's foot on the
--- right. b:Set(word).
function GK.SheetSeal(f, onClick)
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(50)
    b:SetPoint("BOTTOMRIGHT", -20, 16)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(MEDIA .. "glow")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.25, 0.1)
    b.glow:SetAlpha(0.45)
    b.glow:SetSize(84, 84)
    b.glow:Hide()
    b.wax = b:CreateTexture(nil, "ARTWORK")
    b.wax:SetTexture(MEDIA .. "seal_red")
    b.wax:SetSize(50, 50)
    b.wax:SetPoint("RIGHT")
    b.glow:SetPoint("CENTER", b.wax, "CENTER")
    b.text = b:CreateFontString(nil, "ARTWORK")
    SheetInk(b.text, BLOOD, TITLE_FONT, 18)
    b.text:SetPoint("RIGHT", b.wax, "LEFT", -2, 0)
    function b:Set(word)
        self.text:SetText(word)
        self:SetWidth(52 + math.ceil(self.text:GetStringWidth() or 60))
    end
    b:SetScript("OnEnter", function(self) self.glow:Show() end)
    b:SetScript("OnLeave", function(self)
        self.glow:Hide()
        self.wax:SetVertexColor(1, 1, 1)
    end)
    b:SetScript("OnMouseDown", function(self) self.wax:SetVertexColor(0.72, 0.72, 0.72) end)
    b:SetScript("OnMouseUp", function(self) self.wax:SetVertexColor(1, 1, 1) end)
    b:SetScript("OnClick", onClick)
    return b
end

--- Cancel, in faded ink at the sheet's foot on the left: the quiet way out. Hides the sheet.
function GK.SheetCancel(f)
    local b = CreateFrame("Button", nil, f)
    b.text = b:CreateFontString(nil, "ARTWORK")
    SheetInk(b.text, FADED, TEXT_FONT, 12)
    b.text:SetPoint("LEFT")
    b.text:SetText(CANCEL or "Cancel")
    b:SetSize(math.ceil(b.text:GetStringWidth() or 50) + 4, 20)
    b:SetPoint("BOTTOMLEFT", 30, 31)
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(INK[1], INK[2], INK[3]) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(FADED[1], FADED[2], FADED[3]) end)
    b:SetScript("OnClick", function() f:Hide() end)
    return b
end

-- ---------------------------------------------------------------------------
-- The notes' sheets in the game's own frame: Blizzard's window (SettingsFrameTemplate, which Forever
-- draws in bronze, as our other addons' windows) on our plain parchment, with the game's own boxes,
-- radio buttons and buttons, and ink for the writing. The scroll suits a kill order; for the notes and
-- the who-picker the owner asked for "blizz bars rundt og ikke scroll ... litt mer clean", then "med
-- parchment bakgrunn" (2026-11-06).
-- ---------------------------------------------------------------------------
--- A window in the game's frame, w x h, titled; dragged as every sheet is, closed by its X (which hides
--- it directly: the template's HideUIPanel does nothing in combat) and by Escape before the window under it.
function GK.MakeFrameSheet(name, w, h, title)
    local f = SheetFrame(name, w, h, "SettingsFrameTemplate")
    -- the template's flat grey backdrop gives way to the skin's background, as on the ledger: the plain
    -- parchment (sheet_single, the page with no torn edge) in its tone, or in classic the frame's own panel
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 7, -18)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    local function Back()
        if GK.Classic() then
            bg:SetAtlas("heavybronze-frame-background")
            bg:SetDesaturation(0)
            bg:SetVertexColor(1, 1, 1)
        else
            bg:SetTexture(MEDIA .. "sheet_single")
            bg:SetTexCoord(0, 1, 0, 1)
            if GK.Tone then GK.Tone(bg) end
        end
    end
    Back()
    GK.OnLook(Back)
    f.bg = bg
    f.skinned = true                  -- what is written on it takes the skin's colours (SheetSection)
    if type(f.Bg) == "table" then f.Bg:Hide() end
    if type(f.ClosePanelButton) == "table" then f.ClosePanelButton:SetScript("OnClick", function() f:Hide() end) end
    -- the title bar's own text; a font string of ours where a template has none
    f.title = type(f.NineSlice) == "table" and f.NineSlice.Text or nil
    if not f.title then
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -5)
    end
    f.title:SetText(title or "")
    f:Hide()
    if LIB.RegisterPopup then LIB.RegisterPopup(f) else tinsert(UISpecialFrames, name) end
    return f
end

--- The head of a framed sheet: whom it is about. The face in the bronze ring, the name in the ledger's
--- ink and type, and level, race and class under it. head:Set(t), t = { key, c, r, rf, sx, l }.
function GK.FrameHead(f, w)
    local width = w - 82 - 24
    local h = { face = GK.MakePortrait(f, 48) }
    h.face.tex:SetPoint("CENTER", f, "TOPLEFT", 50, -60)
    h.name = f:CreateFontString(nil, "ARTWORK")
    GK.Ink(h.name, GK.INK, GK.TITLE_FONT, 19)              -- in the skin's colours, as the frame is skinned
    h.name:SetPoint("TOPLEFT", 82, -44)
    h.name:SetWidth(width)
    h.name:SetJustifyH("LEFT")
    h.name:SetWordWrap(false)
    h.info = f:CreateFontString(nil, "ARTWORK")
    GK.Ink(h.info, GK.FADED, GK.TEXT_FONT, 11)
    h.info:SetPoint("TOPLEFT", h.name, "BOTTOMLEFT", 0, -4)
    h.info:SetWidth(width)
    h.info:SetJustifyH("LEFT")
    h.info:SetWordWrap(false)
    function h:Set(t)
        self.name:SetText(GK.Show(t.key))
        self.info:SetText(GK.Describe(t.l, t.c, t.r))
        self.face:Set(t)
    end
    return h
end

--- The game's own text box, with a grey hint on it while it is empty (as the game's search boxes have).
--- Hook OnTextChanged to follow it, rather than setting it.
local function Hint(box) box.hint:SetShown((box:GetText() or "") == "") end
function GK.FrameBox(parent, width, letters, hint)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(letters)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e.hint = e:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    e.hint:SetPoint("LEFT", 2, 0)
    e.hint:SetText(hint or "")
    e:HookScript("OnTextChanged", Hint)
    Hint(e)
    return e
end

--- The game's own button, its words in the game's small type in every state (setting only the current
--- one loses them when the button is disabled, Guildhall found).
function GK.FrameButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 96, 22)
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

--- Where a sheet opens: on the ledger when it is open - over the middle of the book, its top well below
--- the tabs (a scroll laid right under them looked as if they were its own), anchored to the ledger so
--- the two go together (see sheets, above). Beside the book was tried and the owner wanted it on top
--- (2026-11-06). Without the ledger, high in the middle. Anchored by its top either way, so a sheet that
--- grows grows downward.
function GK.PlaceSheet(f)
    local win = _G.GrudgekeeperFrame
    f:ClearAllPoints()
    f.onLedger = (win and win:IsShown()) and true or nil
    if f.onLedger then
        f:SetPoint("TOP", win, "TOP", 0, -80)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

--- The note's paper, frame, plaque and portrait, for the letters and the profiles (Profile.lua) alike:
--- f.paper, f.blood, f.portrait (the Grudgekeeper, cut round), f.badge and f.badgeRing (a class
--- circle on his shoulder), f.disc. Hidden and not yet registered as a window: the caller adds its
--- own writing first.
function GK.MakeNoteFrame(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(NW, NH)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER", 0, 120)
    f:EnableMouse(true)
    -- Paper under the iron-and-leather frame; the frame's bands cover the paper's edges. The frame's
    -- top band is about 12% of its height and its sides about 5% of its width (measured from
    -- letter_frame.tga), which is what the insets below keep clear of.
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 14, -14)
    paper:SetPoint("BOTTOMRIGHT", -14, 14)
    paper:SetTexture(MEDIA .. "letter_paper")
    f.paper = paper
    f.blood = f:CreateTexture(nil, "BORDER")
    f.blood:SetTexture(MEDIA .. "blood")
    f.blood:SetSize(190, 190)
    f.blood:SetPoint("CENTER", 150, -40)
    f.blood:SetRotation(-0.5)
    f.blood:SetAlpha(0.5)
    local frame = CreateFrame("Frame", nil, f)
    frame:SetAllPoints()
    frame:SetFrameLevel(f:GetFrameLevel() + 8)
    local border = frame:CreateTexture(nil, "ARTWORK")
    border:SetAllPoints()
    border:SetTexture(MEDIA .. "letter_frame")
    -- Who it's from, on the plaque in the middle of the top band.
    local plaque = frame:CreateFontString(nil, "OVERLAY")
    GK.SetFont(plaque, TITLE_FONT, 14)
    plaque:SetTextColor(1, 0.82, 0.4)
    plaque:SetShadowOffset(1, -1)
    plaque:SetPoint("TOP", 0, -17)
    plaque:SetText("The Grudgekeeper")

    -- The portrait: the Grudgekeeper himself, cut round, with the class of whoever the letter is about
    -- as a small badge on his shoulder.
    local disc = f:CreateTexture(nil, "ARTWORK")
    disc:SetSize(104, 104)
    disc:SetPoint("TOPLEFT", 44, -66)
    disc:SetColorTexture(0.12, 0.06, 0.03, 0.95)
    local discMask = f:CreateMaskTexture()
    discMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    discMask:SetAllPoints(disc)
    disc:AddMaskTexture(discMask)
    local portrait = f:CreateTexture(nil, "ARTWORK", nil, 1)
    portrait:SetSize(98, 98)
    portrait:SetPoint("CENTER", disc, "CENTER")
    portrait:SetTexture(MEDIA .. "portrait")
    local portraitMask = f:CreateMaskTexture()
    portraitMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    portraitMask:SetAllPoints(portrait)
    portrait:AddMaskTexture(portraitMask)
    f.badge = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.badge:SetSize(32, 32)
    f.badge:SetPoint("CENTER", disc, "BOTTOMRIGHT", -12, 12)
    local badgeRing = f:CreateTexture(nil, "ARTWORK", nil, 2)
    badgeRing:SetSize(36, 36)
    badgeRing:SetPoint("CENTER", f.badge, "CENTER")
    badgeRing:SetColorTexture(0.12, 0.06, 0.03, 0.95)
    local ringMask = f:CreateMaskTexture()
    ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ringMask:SetAllPoints(badgeRing)
    badgeRing:AddMaskTexture(ringMask)
    f.badgeRing = badgeRing
    f.disc, f.portrait = disc, portrait
    f:Hide()
    return f
end

local function BuildNote()
    local f = GK.MakeNoteFrame("GrudgekeeperNote")
    f.title = f:CreateFontString(nil, "ARTWORK")
    Ink(f.title, BLOOD, TITLE_FONT, 22)
    f.title:SetPoint("TOPLEFT", 172, -66)
    f.body = f:CreateFontString(nil, "ARTWORK")
    Ink(f.body, INK, TEXT_FONT, 13)
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -10)
    f.body:SetWidth(NW - 172 - 48)
    f.body:SetJustifyH("LEFT")
    f.body:SetSpacing(3)

    -- The signature by the right edge, the seal pressed beside it.
    local sign = f:CreateFontString(nil, "ARTWORK")
    Ink(sign, INK, TITLE_FONT, 16)
    sign:SetPoint("BOTTOMRIGHT", -50, 96)
    sign:SetText("- the Grudgekeeper")
    f.seal = f:CreateTexture(nil, "OVERLAY")
    f.seal:SetSize(48, 48)
    f.seal:SetPoint("RIGHT", sign, "LEFT", -6, 2)

    -- Buttons on the paper just above the frame's bottom band; the pager to their right.
    f.action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.action:SetSize(160, 22)
    f.action:SetPoint("BOTTOMLEFT", 46, 50)
    -- Close, beside the letter's own button. It was Later, which kept the letter unread, so the notice
    -- came straight back with it: "trykke later gir meg bare notification igjen? burde være lukk
    -- isteden?" (the owner, 2026-11-08). These letters are news the ledger keeps anyway; read is done.
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 22)
    close:SetPoint("LEFT", f.action, "RIGHT", 6, 0)
    close:SetText("Close")
    close:SetScript("OnClick", function() GK.CloseLetters() end)
    f.closeButton = close
    Pager(f, f, 180, 54)
    -- And the game's own X in the corner: our iron cross sat on top of the frame's iron corner and
    -- didn't go with it (2026-11-06).
    GK.MakeGameCloseButton(f, function() GK.CloseLetters() end)

    -- Arrives with a small drop and a fade, nothing more.
    local arrive = f:CreateAnimationGroup()
    local drop = arrive:CreateAnimation("Translation")
    drop:SetOffset(0, -8)
    drop:SetDuration(0.18)
    drop:SetSmoothing("OUT")
    local fade = arrive:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.18)
    f.arrive = arrive

    f:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(f, GK.db, "note") end
    f:HookScript("OnHide", Closed)
    note = f
end

local function FillNote(L)
    local f = note
    local d = GK.LetterContent(L)
    f.title:SetText(d.title)
    f.body:SetText(table.concat(d.lines, "\n"))
    f.seal:SetTexture(MEDIA .. d.seal)
    f.blood:SetShown(d.blood)
    local coords = L.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[L.c]
    f.badge:SetShown(coords ~= nil)
    f.badgeRing:SetShown(coords ~= nil)
    if coords then
        f.badge:SetTexture(CLASS_ICONS)
        f.badge:SetTexCoord(unpack(coords))
    end
    SetButton(f.action, d.buttons[1], L, FillNote)
    UpdatePager(f)
end

-- ---------------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------------
--- Show letter i of the pile, in whichever view it belongs. Reading it marks it read.
function GK.ShowLetter(i)
    local list = GK.char.letters
    if #list == 0 then
        GK.CloseLetters()
        return
    end
    index = math.max(1, math.min(i or #list, #list))
    local L = list[index]
    L.read = true
    reading = true
    holding[L] = nil                                -- read before its minute was up: nothing left to land
    GK.Sound("IG_ABILITY_PAGE_TURN")
    if NOTE[L.kind] then
        if scroll then scroll:Hide() end
        if not note then BuildNote() end
        FillNote(L)
        note:Show()
        note.arrive:Play()
    else
        if note then note:Hide() end
        if not scroll then BuildScroll() end
        FillScroll(L)
        scroll:Show()
        scroll.sheet:SetHeight(1)
        Roll(1, function()
            if scroll.stampName then
                scroll.stamp:Show()
                scroll.slam:Play()
            end
        end)
    end
    GK.NoticeUpdate(false)
    GK.Changed()
end

--- Every letter read at once, and so gone - a pile of them after a while away ("med mange notifications kan
--- vi tillate noe 'mark all as read'", the owner, 2026-11-09). The ledger keeps what they said. Returns how
--- many were unread.
function GK.ReadAllLetters()
    local n = 0
    for _, L in ipairs(GK.char.letters) do
        if not L.read then n = n + 1 end
        L.read = true
        holding[L] = nil
    end
    GK.CloseLetters()
    reading = false
    Prune()
    GK.NoticeUpdate(false)
    GK.Changed()
    return n
end

--- Open the pile at the first unread letter (or the newest).
function GK.OpenLetters()
    local list = GK.char.letters
    if #list == 0 then
        print(GK.TAG .. ": no letters. Kill orders from your guild, your new titles and a death that posted a "
            .. "kill order arrive here.")
        return
    end
    local _, first = GK.Unread()
    GK.ShowLetter(first or #list)
end

function GK.CloseLetters()
    if note and note:IsShown() then note:Hide() end
    if scroll and scroll:IsShown() then Roll(-1, function() scroll:Hide() end) end
end

function GK.StartLetters()
    Prune()
    GK.NoticeUpdate(false)
    LIB.On("PLAYER_REGEN_ENABLED", function() if next(holding) then Release() end end)
    -- An open letter follows changes to its order (taken, paid, closed).
    LIB.Listen("GRUDGEKEEPER_CHANGED", function()
        local L = index and GK.char.letters[index]
        if not L then return end
        if scroll and scroll:IsShown() and not scroll:GetScript("OnUpdate") and not NOTE[L.kind] then FillScroll(L) end
        if note and note:IsShown() and NOTE[L.kind] then FillNote(L) end
    end)
end
