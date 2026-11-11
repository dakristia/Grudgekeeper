-- Grudgekeeper - writing a kill order: who, the bounty, a line about why. A small sheet of the same
-- parchment; "Seal it" sends it to the guild. No gold changes hands now: whoever fulfils the order is
-- paid by you, by mail (Mail.lua fills the letter in). Its parts - the head, the ruled lines, the wax
-- seal - are the sheets' own (Letters.lua), the same as the note's.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local FADED = { 0.35, 0.25, 0.15 }
local W, H = 310, 340

local frame
local target            -- { key, guid, c, r, l }

local function Ink(fs, colour, font, size)
    GK.SetFont(fs, font, size)                   -- a family: names in Cyrillic too (Core.lua)
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

local plan            -- GK.PostPlan of the target: pot is set when the sheet adds to someone else's open order

--- Sealing the sheet (for any look): adds to the plan's pot, or posts the order. plan: the one the sheet
--- was opened with (default: worked out now). False, and a line in chat, when the order couldn't be posted.
function GK.PostSubmit(t, copper, note, plan)
    plan = plan or GK.PostPlan(t)
    if plan.pot then
        GK.Contribute(plan.pot, copper)
    else
        local o, why = GK.PostOrder(t, copper, note)
        if not o then
            print(GK.TAG .. ": " .. (why or "the order couldn't be posted."))
            return false
        end
    end
    GK.Sound("IG_QUEST_LIST_OPEN")
    return true
end

local function Seal()
    local gold = tonumber(frame.gold:GetText()) or 0
    local silver = tonumber(frame.silver:GetText()) or 0
    local copper = gold * 10000 + silver * 100
    if not GK.PostSubmit(target, copper, frame.note:GetText(), plan) then return end
    frame:Hide()
    GK.OpenWindow(1)
end

local function Build()
    frame = GK.MakeSheet("GrudgekeeperPost", W, H)
    frame.head = GK.SheetHead(frame, W)
    frame.title, frame.name, frame.info = frame.head.caption, frame.head.name, frame.head.info

    frame.bounty = GK.SheetSection(frame, "Bounty", 100)
    frame.gold = GK.SheetLine(frame, 50, 4, nil, true)
    frame.gold:SetPoint("TOPLEFT", 30, -116)
    local g = frame:CreateTexture(nil, "ARTWORK")
    g:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    g:SetSize(13, 13)
    g:SetPoint("LEFT", frame.gold, "RIGHT", 3, 0)
    frame.silver = GK.SheetLine(frame, 30, 2, nil, true)
    frame.silver:SetPoint("LEFT", g, "RIGHT", 14, 0)
    local s = frame:CreateTexture(nil, "ARTWORK")
    s:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")
    s:SetSize(13, 13)
    s:SetPoint("LEFT", frame.silver, "RIGHT", 3, 0)

    frame.why = GK.SheetSection(frame, "Why", 156)
    frame.note = GK.SheetLine(frame, W - 60, 80, "what did they do?")
    frame.note:SetPoint("TOPLEFT", 30, -172)

    frame.small = frame:CreateFontString(nil, "ARTWORK")
    Ink(frame.small, FADED, TEXT_FONT, 11)
    frame.small:SetWidth(W - 68)
    frame.small:SetSpacing(2)

    frame.seal = GK.SheetSeal(frame, Seal)
    GK.SheetCancel(frame)
end

--- The orders on a target that decide what the sheet does: yours, and the first guildie's.
local function Orders(t)
    local me = LIB.Me()
    local mine, theirs
    for _, o in ipairs(GK.OrdersOn(t.key, t.guid)) do
        if o.by == me then mine = o elseif not theirs then theirs = o end
    end
    return mine, theirs, me
end

--- What GK.OpenPost(t) will do, said as the line in the right-click menu: decided by the same Orders, so the
--- line can't promise a new order and open someone else's pot.
function GK.PostLabel(t)
    local mine, theirs = Orders(t)
    if mine then return "Change your kill order" end
    if theirs then return "Add to the pot" end
    return "Post a kill order"
end

--- Which of the sheet's three ways it goes for a target { key, guid, c, r, l }, and what it says:
---   you have an open order on them   "change": it is filled in, and sealing changes it
---   a guildie has one                "pot": the sheet adds your share to THEIR pot - one order, one pot,
---                                    rather than two orders racing for the same kill
---   nobody has                       "new": a new order
--- Returns { case, pot (the order whose pot it is, for "pot"), mine, title, bounty (the label), small (the
--- explanation), button, amount (copper, to start with), note (to start with), asksWhy (it takes a note) }.
function GK.PostPlan(t)
    local mine, theirs, me = Orders(t)
    local pot = (not mine) and theirs or nil
    local p = { pot = pot, mine = mine }
    if pot then
        local total, backers = GK.Pot(pot)
        p.case = "pot"
        p.title, p.bounty = "ADD TO THE POT", "Your share"
        p.small = ("%s already has an order on them: %s%s. Your share goes on top, and you pay it "
            .. "to whoever fulfils it."):format(GK.Show(pot.by), GK.MoneyText(total),
            backers > 0 and (" from %d backer%s and them"):format(backers, backers == 1 and "" or "s") or "")
        p.button = "Add it"
        p.amount = pot.pot and pot.pot[me] or 0
    else
        p.case = mine and "change" or "new"
        p.title, p.bounty = "KILL ORDER", "Bounty"
        p.small = "No gold is taken now. Whoever fulfils the order is owed the bounty, and you pay them "
            .. "by mail. The order runs for a week."
        p.button = mine and "Change it" or "Seal it"
        p.amount = mine and mine.reward or 0
    end
    p.asksWhy = not pot
    p.note = mine and mine.note or ""
    return p
end

--- Open the sheet for a target: { key, guid, c, r, l }. Three ways it can go (see GK.PostPlan).
function GK.OpenPost(t)
    if not (t and t.key) then return end
    if not frame then Build() end
    target = t
    plan = GK.PostPlan(t)
    frame.head:Set(plan.title, t, true)
    frame.bounty:Label(plan.bounty)
    frame.small:SetText(plan.small)
    frame.small:ClearAllPoints()
    frame.small:SetPoint("TOP", 0, plan.asksWhy and -210 or -154)     -- into the Why's room when it has none
    frame.seal:Set(plan.button)
    local amount = plan.amount
    frame.why:ShowAll(plan.asksWhy)
    frame.note:SetShown(plan.asksWhy)
    frame.gold:SetText(amount >= 10000 and tostring(math.floor(amount / 10000)) or "")
    frame.silver:SetText(amount % 10000 >= 100 and tostring(math.floor(amount / 100) % 100) or "")
    frame.note:SetText(plan.note)
    GK.PlaceSheet(frame)
    frame:Show()
    frame:Raise()
end

--- /grudge post: an order on your target, if that is an enemy player - else the who-picker (Pick.lua),
--- rather than a chat line nobody reads.
function GK.PostOnTarget()
    local u = GK.ReadUnit("target")
    if u then
        GK.OpenPost(u)
        return
    end
    GK.OpenPicker("order")
end
