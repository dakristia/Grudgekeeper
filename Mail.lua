-- Grudgekeeper - paying a bounty. The game doesn't let an addon send mail by itself (SendMail is
-- restricted), so at a mailbox a button fills the letter in - to whom, what for, how much - and you
-- press Send. When that mail goes through, the order is marked paid and the hunter is told.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local button
local pending       -- { o, to, copper }: filled in, not sent yet
local sending       -- the same, once Send was pressed with it still in place
local hooked

-- "Name" for our own realm, "Name-Realm" otherwise: what the To field accepts.
local function MailName(key)
    return LIB.WhisperName(key)
end

-- entry = { o = order, share = copper }: what I owe on it, as the poster or as a backer (GK.Owed).
local function Fill(entry)
    local o = entry.o
    if MailFrameTab2 then MailFrameTab2:Click() end
    local to = MailName(o.doneBy)
    if SendMailNameEditBox then SendMailNameEditBox:SetText(to) end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(("Bounty: %s"):format(GK.Show(o.n))) end
    if MoneyInputFrame_SetCopper and SendMailMoney then MoneyInputFrame_SetCopper(SendMailMoney, entry.share) end
    pending = { o = o, to = to, copper = entry.share }
end

local function Update()
    if not button then return end
    -- Nothing to work out while the mailbox is shut: the button is hidden with it.
    if not (MailFrame and MailFrame:IsShown()) then
        button:Hide()
        return
    end
    local owed = GK.Owed()
    button:SetShown(#owed > 0)
    button:SetText(("Pay bounty (%d)"):format(#owed))
end

local function Build()
    button = CreateFrame("Button", nil, MailFrame, "UIPanelButtonTemplate")
    button:SetSize(140, 24)
    button:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -32)
    button:SetScript("OnClick", function()
        local owed = GK.Owed()
        if owed[1] then Fill(owed[1]) end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Bounties you owe")
        for _, e in ipairs(GK.Owed()) do
            GameTooltip:AddDoubleLine(("%s, for %s"):format(GK.Show(e.o.doneBy), GK.Show(e.o.n)), GK.MoneyText(e.share),
                1, 1, 1, 1, 0.82, 0)
        end
        GameTooltip:AddLine("Click to fill in a letter for the first one. You press Send.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- After Blizzard's own Send: was it our letter, unchanged enough to count as the payment?
local function OnSend()
    if not pending then return end
    local to = SendMailNameEditBox and SendMailNameEditBox:GetText()
    local copper = (MoneyInputFrame_GetCopper and SendMailMoney) and MoneyInputFrame_GetCopper(SendMailMoney) or 0
    if to and GK.SameName(to, pending.to) and copper >= pending.copper then sending = pending end
end

function GK.StartMail()
    LIB.On("MAIL_SHOW", function()
        if not MailFrame then return end
        if not button then Build() end
        -- A post-hook only: Blizzard's send runs as it always does.
        if not hooked and SendMailFrame_SendMail then
            hooksecurefunc("SendMailFrame_SendMail", OnSend)
            hooked = true
        end
        Update()
    end)
    LIB.On("MAIL_CLOSED", function()
        pending = nil
        if button then button:Hide() end
    end)
    LIB.On("MAIL_SEND_SUCCESS", function()
        local s = sending
        sending, pending = nil, nil
        if not s then return end
        GK.PayShare(s.o)
        -- Money handled for you: the one kind of news that goes in chat.
        print(("%s: bounty paid - %s to %s for %s."):format(GK.TAG, GK.MoneyText(s.copper), GK.Show(s.o.doneBy),
            GK.Show(s.o.n)))
        Update()
    end)
    LIB.On("MAIL_FAILED", function() sending = nil end)
    -- Once per burst of changes (GK.Changed gathers them); Update does nothing while the mail is shut.
    LIB.Listen("GRUDGEKEEPER_CHANGED", Update)
end
