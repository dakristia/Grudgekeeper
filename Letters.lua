-- Grudgekeeper - letters: news that waits until you open it.
-- Nothing pops up. A letter goes into your pile, the notice scroll (Notice.lua) shows that something
-- came, and clicking it opens the letter. Two sizes:
--   the SCROLL, unrolled between two rolls, for the orders themselves:
--     order     KILL ORDER       a guildie put a price on someone       red seal
--     complete  ORDER COMPLETE   an order was fulfilled                 red seal, FULFILLED stamp
--   the NOTE, a small landscape letter with a portrait, written by "the Grudgekeeper":
--     kill      Blood drawn      you killed someone: points, your rank   red seal
--     slain     Slain            someone killed you                     black seal, blood
--     paid      Bounty paid      the poster paid you                    red seal
--     expired   Order expired    your order ran out                     black seal
-- The paper, rolls, seals and blood are drawn by art/make_grudgekeeper_art.py (or imported from
-- generated art by art/import_grudgekeeper.py); the stamps by art/make_grudgekeeper_stamps.py.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MAX_LETTERS = 30
local KEEP_READ = 3 * GK.DAY
local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local INK = { 0.22, 0.13, 0.05 }
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
local function Prune()
    local list, now = GK.char.letters, time()
    for i = #list, 1, -1 do
        if list[i].read and now - (list[i].t or 0) > KEEP_READ then table.remove(list, i) end
    end
    while #list > MAX_LETTERS do table.remove(list, 1) end
end

-- silent: no sound as it lands - a letter about something you just did yourself, like a kill, is no
-- news to you, so it only waits by the minimap.
local function Add(kind, data, silent)
    GK.char.letterId = (GK.char.letterId or 0) + 1
    data.id, data.kind, data.t, data.read = GK.char.letterId, kind, time(), false
    local list = GK.char.letters
    list[#list + 1] = data
    Prune()
    GK.NoticeUpdate(true, silent)
    GK.Changed()
    return data
end

--- Unread letters: how many, and the first one's place in the pile.
function GK.Unread()
    local n, first = 0, nil
    for i, l in ipairs(GK.char.letters) do
        if not l.read then
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

function GK.CompleteLetter(o)
    local me = LIB.Me()
    Add("complete", { n = o.n, c = o.c, r = o.r, l = o.l, by = o.by, reward = o.reward, o = o.key,
        doneBy = o.doneBy, z = o.doneZone, pot = (GK.Pot(o)), share = o.pot and o.pot[me] or nil },
        o.doneBy == me)
end

--- Somebody paid you for an order you fulfilled: the poster (their reward) or a backer (their share).
function GK.PaidLetter(o, payer, amount)
    Add("paid", { n = o.n, c = o.c, r = o.r, l = o.l, by = payer or o.by, reward = amount or o.reward, o = o.key })
end

function GK.ExpiredLetter(o)
    Add("expired", { n = o.n, c = o.c, r = o.r, l = o.l, guid = o.guid, reward = o.reward, o = o.key })
end

--- A kill of ours. An unread kill letter is added to rather than stacked: the newest kill leads, the
--- ones before it become "and 2 more since you last looked". extra = { revenge (how often they had
--- killed you), avenged (the guildie's key), streak, title (a new one) }. Silent: you were there.
function GK.KillLetter(v, points, con, today, zone, extra)
    extra = extra or {}
    local rank, of = GK.MyRank()
    local weekRank = GK.MyRank(true)
    local list = GK.char.letters
    local last = list[#list]
    local L
    if last and last.kind == "kill" and not last.read then
        L = last
        L.more = (L.more or 0) + 1
        L.morePoints = (L.morePoints or 0) + (L.p or 0)
        L.t = time()
    else
        L = Add("kill", {}, true)
    end
    L.n, L.c, L.r, L.l, L.p, L.con, L.today, L.z = v.key, v.c, v.r, v.l, points, con, today, zone
    L.rank, L.of, L.weekRank, L.total = rank, of, weekRank, GK.char.points
    L.revenge, L.avenged, L.streak = extra.revenge, extra.avenged, extra.streak
    L.title = extra.title or L.title                -- a new title stays news until the letter is read
    GK.NoticeUpdate(true, true)
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
    Add("kill", S({ n = "Gærd Balle", c = "HUNTER", r = horde and "Night Elf" or "Troll", l = 27, p = 2, con = "yellow",
        z = "Hillsbrad Foothills",
        rank = 4, of = 12, total = 31 }))
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
    local function Hitlist() GK.OpenWindow(1) end
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
        if o and o.state == "o" and o.by ~= me then
            local mine = GK.char.accepted[o.key]
            buttons[#buttons + 1] = { mine and "Drop it" or "Take the order", function() GK.Accept(o, not mine) end }
            buttons[#buttons + 1] = { "Add to the pot", function() GK.OpenPost({ key = o.n, guid = o.guid, c = o.c,
                r = o.r, l = o.l }) end }
        else
            buttons[#buttons + 1] = { "Hitlist", Hitlist }
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
    if L.doneBy == me then
        body[#body + 1] = "You collected the bounty" .. where .. "."
        if pot > 0 then body[#body + 1] = ("%s in all, to come by mail."):format(GK.MoneyText(pot)) end
        -- One line in guild chat for the guildies without Grudgekeeper - only ever from this click.
        if not L.told and not L.sample then
            buttons[#buttons + 1] = { "Tell the guild", function()
                if GK.TellGuild(("Grudgekeeper: %s is dead - %s's kill order fulfilled%s."):format(show(L.n),
                    show(L.by), pot > 0 and (", bounty " .. GK.MoneyText(pot)) or "")) then
                    L.told = true
                end
            end }
        end
    else
        body[#body + 1] = doneBy .. (L.by == me and " collected the bounty" or " got there first") .. where .. "."
        if owe > 0 then
            body[#body + 1] = " "
            body[#body + 1] = ("You owe them %s - at a mailbox, the Pay bounty button fills it in."):format(
                GK.MoneyText(owe))
            if o and (o.state == "d" or o.state == "p") and not (o.paid and o.paid[me]) and not (o.by == me and o.state == "p") then
                buttons[#buttons + 1] = { "Mark as paid", function() GK.PayShare(o) end }
            end
        end
    end
    buttons[#buttons + 1] = { "Hitlist", Hitlist }
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
        p[#p + 1] = ("You killed %s%s."):format(Who(L), L.z and (" in " .. L.z) or "")
        if (L.p or 0) > 0 then
            p[#p + 1] = ("Worth %d point%s."):format(L.p, L.p == 1 and "" or "s")
        elseif (L.today or 0) >= GK.REPEATS then
            p[#p + 1] = "You've had them twice today already - nothing more for them until tomorrow."
            closing = nil
        elseif L.con == "grey" then
            p[#p + 1] = "They were grey to you. No honour in that, and no points."
            closing = nil
        end
        -- what made this kill more than a kill
        if L.revenge then
            p[#p + 1] = ("Revenge: they had killed you %s."):format(L.revenge == 1 and "once" or (L.revenge .. " times"))
        end
        if L.avenged then p[#p + 1] = ("You avenged %s."):format(show(L.avenged)) end
        if (L.streak or 0) >= 3 then p[#p + 1] = ("%d kills in a row without dying."):format(L.streak) end
        if (L.more or 0) > 0 then
            p[#p + 1] = ("And %d more since you last looked, for %d more point%s."):format(L.more,
                L.morePoints or 0, (L.morePoints or 0) == 1 and "" or "s")
        end
        if (L.of or 0) > 1 then
            p[#p + 1] = ("That puts you at %d points - #%d of %d in the guild%s."):format(L.total or 0, L.rank, L.of,
                (L.weekRank and L.weekRank ~= L.rank) and (", #%d this week"):format(L.weekRank) or "")
        else
            p[#p + 1] = ("That puts you at %d points."):format(L.total or 0)
        end
        if L.title then
            p[#p + 1] = ("You are now %s %s."):format(L.title:match("^[AEIOU]") and "an" or "a", L.title)
            closing = nil
        end
        action = { "Leaderboard", function() GK.OpenWindow(2) end }
        local title = (L.p or 0) > 0 and "Blood drawn" or "A kill, for nothing"
        return title, p, closing, "seal_red", false, action
    elseif L.kind == "slain" then
        p[#p + 1] = ("%s killed you%s%s."):format(Who(L, true), L.spell and (" with " .. L.spell) or "",
            L.z and (" in " .. L.z) or "")
        if L.times then
            p[#p + 1] = L.times == 1 and "The first time. Remember the name."
                or ("That's the %s time."):format(Ordinal(L.times))
        end
        if L.autoOrder then
            -- posted in your name by this very death: say so, and where to withdraw it
            p[#p + 1] = "That was one death too many: a kill order on them went out to the guild, in your name. "
                .. "You can withdraw it on the hitlist."
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

-- ---------------------------------------------------------------------------
-- Shared bits of both views
-- ---------------------------------------------------------------------------
local scroll, note  -- the two views, made on first use
local index         -- which letter in the pile is showing

local function Ink(fs, colour, font, size)
    fs:SetFont(font, size, "")
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
local function BuildScroll()
    local f = CreateFrame("Frame", "GrudgekeeperLetter", UIParent)
    f:SetSize(W + 16, BODY_H + ROLL_H)
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
    f.stamp = c:CreateTexture(nil, "OVERLAY", nil, 2)
    f.stamp:SetSize(210, 105)
    f.stamp:SetPoint("CENTER", 0, -30)

    -- Up to two buttons, bottom left; the seal has the bottom right.
    f.buttons = {}
    for i = 1, 2 do
        local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
        b:SetSize(176, 22)
        b:SetPoint("BOTTOMLEFT", 30, 56 - (i - 1) * 26)
        f.buttons[i] = b
    end
    Pager(f, c, -40, 8)

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
    local close = CreateFrame("Button", nil, rolls, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -2, 2)
    -- Every close path calls our own Hide, so it works in combat too.
    close:SetScript("OnClick", function() GK.CloseLetters() end)

    -- The stamp comes down hard: big and faint to its size, then the sheet jolts.
    local slam = f.stamp:CreateAnimationGroup()
    local grow = slam:CreateAnimation("Scale")
    grow:SetScaleFrom(2.4, 2.4)
    grow:SetScaleTo(1, 1)
    grow:SetDuration(0.16)
    grow:SetSmoothing("IN")
    local fade = slam:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
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
    local title, name, info, body, foot, seal, stamp, buttons = ScrollContent(L)
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
    UpdatePager(f)
end

-- ---------------------------------------------------------------------------
-- The note
-- ---------------------------------------------------------------------------
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
    plaque:SetFont(TITLE_FONT, 14, "")
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
    local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    later:SetSize(90, 22)
    later:SetPoint("LEFT", f.action, "RIGHT", 6, 0)
    later:SetText("Later")
    later:SetScript("OnClick", function() GK.CloseLetters() end)
    Pager(f, f, 180, 54)

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
    note = f
end

local function FillNote(L)
    local f = note
    local title, paragraphs, closing, seal, blood, action = NoteContent(L)
    f.title:SetText(title)
    local text = table.concat(paragraphs, "\n")
    if closing then
        local lines = closing
        text = text .. "\n\n" .. lines[(L.id or 1) % #lines + 1]
    end
    f.body:SetText(text)
    f.seal:SetTexture(MEDIA .. seal)
    f.blood:SetShown(blood)
    local coords = L.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[L.c]
    f.badge:SetShown(coords ~= nil)
    f.badgeRing:SetShown(coords ~= nil)
    if coords then
        f.badge:SetTexture(CLASS_ICONS)
        f.badge:SetTexCoord(unpack(coords))
    end
    SetButton(f.action, action, L, FillNote)
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

--- Open the pile at the first unread letter (or the newest).
function GK.OpenLetters()
    local list = GK.char.letters
    if #list == 0 then
        print(GK.TAG .. ": no letters. Kill orders from your guild, and your own kills and deaths, arrive here.")
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
    -- An open letter follows changes to its order (taken, paid, closed).
    LIB.Listen("GRUDGEKEEPER_CHANGED", function()
        local L = index and GK.char.letters[index]
        if not L then return end
        if scroll and scroll:IsShown() and not scroll:GetScript("OnUpdate") and not NOTE[L.kind] then FillScroll(L) end
        if note and note:IsShown() and NOTE[L.kind] then FillNote(L) end
    end)
end
