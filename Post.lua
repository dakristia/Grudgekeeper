-- Grudgekeeper - writing a kill order: who, the bounty, a line about why. A small sheet of the same
-- parchment; "Seal it" sends it to the guild. No gold changes hands now: whoever fulfils the order is
-- paid by you, by mail (Mail.lua fills the letter in).
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local INK = { 0.22, 0.13, 0.05 }
local BLOOD = { 0.47, 0.06, 0.04 }
local W, H = 300, 300

local frame
local target            -- { key, guid, c, r, l }

local function Ink(fs, colour, font, size)
    fs:SetFont(font, size, "")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

local function Box(parent, width, digits)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    if digits then
        e:SetNumeric(true)
        e:SetMaxLetters(digits)
    end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

local pot             -- set when the sheet adds to someone else's open order instead of writing a new one

local function Seal()
    local gold = tonumber(frame.gold:GetText()) or 0
    local silver = tonumber(frame.silver:GetText()) or 0
    local copper = gold * 10000 + silver * 100
    if pot then
        GK.Contribute(pot, copper)
    else
        local o, why = GK.PostOrder(target, copper, frame.note:GetText())
        if not o then
            print(GK.TAG .. ": " .. (why or "the order couldn't be posted."))
            return
        end
    end
    GK.Sound("IG_QUEST_LIST_OPEN")
    frame:Hide()
    GK.OpenWindow(1)
end

local function Build()
    frame = CreateFrame("Frame", "GrudgekeeperPost", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    local paper = frame:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(MEDIA .. "sheet")
    local top = GK.MakeRoll(frame, 30)
    top:SetWidth(W + 16)
    top:SetPoint("BOTTOM", frame, "TOP", 0, -15)
    local bottom = GK.MakeRoll(frame, 30, true)
    bottom:SetWidth(W + 16)
    bottom:SetPoint("TOP", frame, "BOTTOM", 0, 15)

    local title = frame:CreateFontString(nil, "ARTWORK")
    Ink(title, BLOOD, TITLE_FONT, 24)
    title:SetPoint("TOP", 0, -22)
    frame.title = title
    frame.name = frame:CreateFontString(nil, "ARTWORK")
    Ink(frame.name, INK, TITLE_FONT, 18)
    frame.name:SetPoint("TOP", title, "BOTTOM", 0, -10)
    frame.info = frame:CreateFontString(nil, "ARTWORK")
    Ink(frame.info, INK, TEXT_FONT, 12)
    frame.info:SetPoint("TOP", frame.name, "BOTTOM", 0, -4)

    local bounty = frame:CreateFontString(nil, "ARTWORK")
    Ink(bounty, INK, TEXT_FONT, 13)
    bounty:SetPoint("TOPLEFT", 40, -118)
    frame.bounty = bounty
    frame.gold = Box(frame, 46, 4)
    frame.gold:SetPoint("LEFT", bounty, "RIGHT", 16, 0)
    local g = frame:CreateTexture(nil, "ARTWORK")
    g:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    g:SetSize(13, 13)
    g:SetPoint("LEFT", frame.gold, "RIGHT", 2, 0)
    frame.silver = Box(frame, 30, 2)
    frame.silver:SetPoint("LEFT", g, "RIGHT", 12, 0)
    local s = frame:CreateTexture(nil, "ARTWORK")
    s:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")
    s:SetSize(13, 13)
    s:SetPoint("LEFT", frame.silver, "RIGHT", 2, 0)

    local why = frame:CreateFontString(nil, "ARTWORK")
    Ink(why, INK, TEXT_FONT, 13)
    why:SetPoint("TOPLEFT", bounty, "BOTTOMLEFT", 0, -22)
    why:SetText("Why")
    frame.why = why
    frame.note = Box(frame, 186, nil)
    frame.note:SetMaxLetters(80)
    frame.note:SetPoint("LEFT", why, "RIGHT", 30, 0)

    frame.small = frame:CreateFontString(nil, "ARTWORK")
    Ink(frame.small, INK, TEXT_FONT, 11)
    frame.small:SetPoint("TOP", 0, -196)
    frame.small:SetWidth(W - 60)
    frame.small:SetSpacing(2)

    local seal = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    seal:SetSize(110, 22)
    seal:SetPoint("BOTTOMLEFT", 34, 26)
    seal:SetScript("OnClick", Seal)
    frame.seal = seal
    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("LEFT", seal, "RIGHT", 8, 0)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() frame:Hide() end)
    local wax = frame:CreateTexture(nil, "OVERLAY")
    wax:SetTexture(MEDIA .. "seal_red")
    wax:SetSize(56, 56)
    wax:SetPoint("BOTTOMRIGHT", -20, 12)

    frame:Hide()
    if LIB.RegisterPopup then LIB.RegisterPopup(frame) else tinsert(UISpecialFrames, "GrudgekeeperPost") end
end

--- Open the sheet for a target: { key, guid, c, r, l }. Three ways it can go:
---   you have an open order on them   it is filled in, and sealing changes it
---   a guildie has one                the sheet adds your share to THEIR pot - one order, one pot,
---                                    rather than two orders racing for the same kill
---   nobody has                       a new order
function GK.OpenPost(t)
    if not (t and t.key) then return end
    if not frame then Build() end
    target = t
    local me = LIB.Me()
    local mine, theirs
    for _, o in ipairs(GK.OrdersOn(t.key, t.guid)) do
        if o.by == me then mine = o elseif not theirs then theirs = o end
    end
    pot = (not mine) and theirs or nil
    frame.name:SetText(GK.Show(t.key))
    frame.info:SetText(GK.Describe(t.l, t.c, t.r))
    local amount
    if pot then
        local total, backers = GK.Pot(pot)
        frame.title:SetText("ADD TO THE POT")
        frame.bounty:SetText("Your share")
        frame.small:SetText(("%s already has an order on them: %s%s. Your share goes on top, and you pay it "
            .. "to whoever fulfils it."):format(GK.Show(pot.by), GK.MoneyText(total),
            backers > 0 and (" from %d backer%s and them"):format(backers, backers == 1 and "" or "s") or ""))
        frame.seal:SetText("Add it")
        amount = pot.pot and pot.pot[me] or 0
    else
        frame.title:SetText("KILL ORDER")
        frame.bounty:SetText("Bounty")
        frame.small:SetText("No gold is taken now. Whoever fulfils the order is owed the bounty, and you pay them "
            .. "by mail. The order runs for a week.")
        frame.seal:SetText(mine and "Change it" or "Seal it")
        amount = mine and mine.reward or 0
    end
    frame.why:SetShown(not pot)
    frame.note:SetShown(not pot)
    frame.gold:SetText(amount >= 10000 and tostring(math.floor(amount / 10000)) or "")
    frame.silver:SetText(amount % 10000 >= 100 and tostring(math.floor(amount / 100) % 100) or "")
    frame.note:SetText(mine and mine.note or "")
    frame:Show()
    frame:Raise()
end

--- The window's Post button and /grudge post: an order on your target, if that is an enemy player.
function GK.PostOnTarget()
    local u = GK.ReadUnit("target")
    if u then
        GK.OpenPost(u)
        return
    end
    print(GK.TAG .. ": target an enemy player first - or post one on someone who killed you, from the Grudges page.")
end
