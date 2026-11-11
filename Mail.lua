-- Grudgekeeper - paying a bounty. The game doesn't let an addon send mail or money by itself (SendMail
-- and a trade's money are restricted), so it does the two things it can:
--   at a mailbox, a card beside it lists what you owe, each with a button that fills the letter in - to
--   whom, what for, how much - and you press Send;
--   money you give someone you owe, by mail or in a trade, pays it, however the letter or the trade was
--   made: oldest first, and what falls short of a whole share counts toward it.
-- ("hvis du har en 'outstanding payment' burde det poppe opp noe når du åpner mailbox ... og så kan vi
-- registrere om det blir sendt penger til personen via mail eller trade", the owner, 2026-11-09.)
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local W, ROW_H, ROWS_TOP, MAX_ROWS = 320, 44, 34, 5
local SEND_WINDOW = 60      -- seconds from Send to the game's word that the letter went
local TRADE_WINDOW = 10     -- seconds after a trade closes that our money may still change for it

local card
local sending       -- { to, copper, at }: a letter with money in it, sent, until the game says it went
local trade         -- { who, before, give, get, closedAt }: the trade open now, or the one just closed
local hooked

local function Ink(fs, colour, size) GK.Ink(fs, colour, GK.TEXT_FONT, size) end

-- The same player, written as a mail's To field or a trade has them and as we keep them: any case, with
-- or without a realm, a first name for a first name and surname (GK.SameName).
local function Same(a, b)
    return type(a) == "string" and type(b) == "string" and GK.SameName(GK.Lower(a), GK.Lower(b))
end

--- Money we gave a player, by mail or in a trade: it pays what we owe them, oldest first. What falls
--- short of the next whole share is kept toward it (GK.char.credit), so two trades of half pay it. Any
--- money to someone we owe counts: a gift and a bounty look the same, and owing them, it is the bounty.
function GK.GaveMoney(to, copper)
    copper = math.floor(tonumber(copper) or 0)
    if type(to) ~= "string" or to == "" or copper <= 0 then return end
    local debts = {}
    for _, e in ipairs(GK.Owed()) do
        if Same(e.to, to) then debts[#debts + 1] = e end
    end
    if #debts == 0 then return end
    local key = debts[1].to
    GK.char.credit = GK.char.credit or {}
    local have = (GK.char.credit[key] or 0) + copper
    local i = 1
    while debts[i] and have >= debts[i].share do
        local e = debts[i]
        have = have - e.share
        GK.PayShare(e.o, e.to)
        -- Money handled for you: the one kind of news that goes in chat.
        print(("%s: bounty paid - %s to %s for %s."):format(GK.TAG, GK.MoneyText(e.share), GK.Show(key),
            GK.Show(e.o.n)))
        i = i + 1
    end
    if debts[i] and have > 0 then
        GK.char.credit[key] = have
        print(("%s: %s to %s counted - %s still owed for %s."):format(GK.TAG, GK.MoneyText(have), GK.Show(key),
            GK.MoneyText(debts[i].share - have), GK.Show(debts[i].o.n)))
    else
        GK.char.credit[key] = nil
    end
    GK.Changed()
end

-- ---------------------------------------------------------------------------
-- The card at the mailbox
-- ---------------------------------------------------------------------------
-- entry = { o = order, share = copper, to = hunter }: what I owe one hunter on it (GK.Owed).
local function Fill(entry)
    local o = entry.o
    if MailFrameTab2 then MailFrameTab2:Click() end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(LIB.WhisperName(entry.to)) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(("Bounty: %s"):format(GK.Show(o.n))) end
    -- money, not C.O.D.: Blizzard's own radio, as a click on it would set it
    if SendMailRadioButton_OnClick then SendMailRadioButton_OnClick(1) end
    local credit = GK.char.credit and GK.char.credit[entry.to] or 0
    local copper = math.max(0, entry.share - credit)
    if MoneyInputFrame_SetCopper and SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, copper) end
end

local function Row(i)
    local f = card
    local b = CreateFrame("Frame", nil, f)
    b:SetSize(W - 32, ROW_H)
    b:SetPoint("TOPLEFT", 16, -(ROWS_TOP + (i - 1) * ROW_H))
    b.face = GK.MakePortrait(b, 30)
    b.face.tex:SetPoint("CENTER", b, "LEFT", 18, 0)
    local text = W - 32 - 40 - 128
    b.name = b:CreateFontString(nil, "ARTWORK")
    Ink(b.name, GK.INK, 12)
    b.name:SetPoint("TOPLEFT", 40, -8)
    b.name:SetWidth(text)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.what = b:CreateFontString(nil, "ARTWORK")
    Ink(b.what, GK.FADED, 10)
    b.what:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.what:SetWidth(text)
    b.what:SetJustifyH("LEFT")
    b.what:SetWordWrap(false)
    b.paid = GK.FrameButton(b, "Paid", 54, function() if b.entry then GK.PayShare(b.entry.o, b.entry.to) end end)
    b.paid:SetPoint("RIGHT", 0, 0)
    b.paid:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Paid another way")
        GameTooltip:AddLine("Mark it paid. Money you mail or trade them is marked by itself.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b.paid:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b.fill = GK.FrameButton(b, "Fill in", 70, function() if b.entry then Fill(b.entry) end end)
    b.fill:SetPoint("RIGHT", b.paid, "LEFT", -4, 0)
    f.rows[i] = b
    return b
end

local function Build()
    card = GK.MakeFrameSheet("GrudgekeeperOwed", W, 120, "Bounties you owe")
    card.rows = {}
    card.more = card:CreateFontString(nil, "ARTWORK")
    Ink(card.more, GK.FADED, 10)
    card.more:SetJustifyH("LEFT")
    card.note = card:CreateFontString(nil, "ARTWORK")
    Ink(card.note, GK.FADED, 10)
    card.note:SetWidth(W - 40)
    card.note:SetJustifyH("LEFT")
    card.note:SetSpacing(2)
    card.note:SetText("Mail or trade them the money and it is marked paid by itself.")
    -- closed by hand: not again until the next visit to a mailbox
    card:HookScript("OnHide", function()
        if MailFrame and MailFrame:IsShown() and not card.updating then card.dismissed = true end
    end)
end

local function Update()
    local open = MailFrame and MailFrame:IsShown()
    local owed = open and GK.Owed() or {}
    if #owed == 0 then
        if card then
            card.updating = true
            card:Hide()
            card.updating = nil
        end
        return
    end
    if not card then Build() end
    if card.dismissed then return end
    local n = math.min(#owed, MAX_ROWS)
    local first = {}            -- money already given toward a hunter counts on their oldest share only
    for i = 1, n do
        local b = card.rows[i] or Row(i)
        local e = owed[i]
        b.entry = e
        local r = GK.Store().board[e.to] or {}
        b.face:Set({ key = e.to, c = r.c, rf = r.rf, sx = r.sx })
        b.name:SetText(GK.Show(e.to))
        local credit = not first[e.to] and GK.char.credit and GK.char.credit[e.to] or 0
        first[e.to] = true
        local left = credit > 0 and (" (%s still)"):format(GK.MoneyText(e.share - credit)) or ""
        b.what:SetText(("%s%s for %s"):format(GK.MoneyText(e.share), left, GK.Show(e.o.n)))
        b:Show()
    end
    for i = n + 1, #card.rows do card.rows[i]:Hide() end
    local y = ROWS_TOP + n * ROW_H + 4
    card.more:SetShown(#owed > n)
    card.more:SetText(("and %d more"):format(#owed - n))
    card.more:SetPoint("TOPLEFT", 56, -y)
    if #owed > n then y = y + 16 end
    card.note:SetPoint("TOPLEFT", 20, -(y + 4))
    card:SetHeight(y + 40)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
    card:Show()
end

-- ---------------------------------------------------------------------------
-- Money given: by mail, and in a trade
-- ---------------------------------------------------------------------------
-- After Blizzard's own Send: to whom, and how much money went with it - only with "Send Money" picked,
-- never C.O.D., and nothing when the radio can't be read (a payment is never guessed).
local function OnSend()
    local to = SendMailNameEditBox and SendMailNameEditBox:GetText()
    local copper = 0
    if SendMailSendMoneyButton and SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper
        and SendMailMoney then
        copper = tonumber(MoneyInputFrame_GetCopper(SendMailMoney)) or 0
    end
    sending = (type(to) == "string" and to ~= "" and copper > 0) and { to = to, copper = copper, at = GetTime() }
        or nil
end

-- What each side has put in the trade, while it is open: read at every change, kept after it closes.
local function TradeSeen()
    if not trade or trade.closedAt then return end
    local give = GetPlayerTradeMoney and GetPlayerTradeMoney()
    local get = GetTargetTradeMoney and GetTargetTradeMoney()
    if type(give) == "number" then trade.give = give end
    if type(get) == "number" then trade.get = get end
end

-- A trade that closed counts only when our money moved by exactly what it said - the money we put in,
-- less what they did. Cancelled, it never moves; so nothing is read from the game's chat text.
local function TradeDone()
    local t = trade
    if not (t and t.closedAt) then return end
    if GetTime() - t.closedAt > TRADE_WINDOW then
        trade = nil
        return
    end
    if t.give > 0 and GetMoney() == t.before - t.give + t.get then
        trade = nil
        GK.GaveMoney(t.who, t.give)
    end
end

function GK.StartMail()
    LIB.On("MAIL_SHOW", function()
        if not MailFrame then return end
        -- A post-hook only: Blizzard's send runs as it always does.
        if not hooked and SendMailFrame_SendMail then
            hooksecurefunc("SendMailFrame_SendMail", OnSend)
            hooked = true
        end
        if card then card.dismissed = nil end
        Update()
    end)
    LIB.On("MAIL_CLOSED", function()
        if not card then return end
        card.updating = true
        card:Hide()
        card.updating = nil
    end)
    LIB.On("MAIL_SEND_SUCCESS", function()
        local s = sending
        sending = nil
        if s and GetTime() - s.at <= SEND_WINDOW then GK.GaveMoney(s.to, s.copper) end
    end)
    LIB.On("MAIL_FAILED", function() sending = nil end)
    LIB.On("SECURE_TRANSFER_CANCEL", function() sending = nil end)

    LIB.On("TRADE_SHOW", function()
        local who = GK.UnitKey("NPC")
        trade = (who and not GK.Secret(who) and GetMoney) and { who = who, before = GetMoney(), give = 0, get = 0 }
            or nil
        TradeSeen()
    end)
    for _, event in ipairs({ "TRADE_MONEY_CHANGED", "PLAYER_TRADE_MONEY", "TRADE_ACCEPT_UPDATE", "TRADE_UPDATE" }) do
        LIB.On(event, TradeSeen)
    end
    LIB.On("TRADE_CLOSED", function()
        local t = trade
        if not t or t.closedAt then return end          -- the game can say it twice
        t.closedAt = GetTime()
        TradeDone()
        C_Timer.After(TRADE_WINDOW + 0.1, function() if trade == t then trade = nil end end)
    end)
    LIB.On("PLAYER_MONEY", TradeDone)
    -- Once per burst of changes (GK.Changed gathers them); Update does nothing while the mail is shut.
    LIB.Listen("GRUDGEKEEPER_CHANGED", Update)
end
