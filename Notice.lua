-- Grudgekeeper - the notice: a small sealed letter that says something came, the way the game's own
-- envelope says you have mail - but on its own, wherever you put it, not on the minimap. It fades in
-- and blinks when a letter lands, then rests with a faint glow until you read it. Click it to read,
-- right-click for the hitlist, drag it anywhere; /grudge notice shows it to place it without waiting
-- for mail. When the target of an order you took is near it glows red, with a soft chime and one
-- short line under it. That is the only warning Grudgekeeper gives: nothing opens in the middle of
-- the screen.
local ADDON, GK = ...

local SIZE = 46
local WARN_FOR = 12              -- seconds the red glow and the line stay
local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local btn
local warnUntil = 0
local placing = false            -- shown to be dragged into place, letters or not

local function SavePosition(self)
    local point, _, relPoint, x, y = self:GetPoint(1)
    GK.db.notice = { point = point, relPoint = relPoint, x = x, y = y }
end

local function Place()
    btn:ClearAllPoints()
    local p = GK.db.notice
    if p and p.point then
        btn:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        -- By default at the top, left of where the quest tracker sits in a plain UI (the user's pick,
        -- 2026-11-03): the spot it leaves empty. A fixed place on the screen, NOT tied to the tracker -
        -- the user asked for that, so it stays put whatever the tracker or another addon does. A little
        -- below the tracker's top, where Headstart's quest-group eye sits.
        btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -250)
    end
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(GK.TAG)
    if placing then
        GameTooltip:AddLine("Drag me where letters should land, then click.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local unread = GK.Unread()
    if unread > 0 then
        GameTooltip:AddLine(("%d unread letter%s"):format(unread, unread == 1 and "" or "s"), 1, 1, 1)
        local shown = 0
        for i = #GK.char.letters, 1, -1 do
            local L = GK.char.letters[i]
            if not L.read and shown < 5 then
                shown = shown + 1
                GameTooltip:AddLine("  " .. GK.LetterLine(L), 0.9, 0.8, 0.6)
            end
        end
    end
    if GetTime() < warnUntil and btn.warnText then
        GameTooltip:AddLine(btn.warnText, 1, 0.3, 0.25)
    end
    GameTooltip:AddLine("Click: read  -  Right-click: hitlist  -  Drag: move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function Build()
    btn = CreateFrame("Button", "GrudgekeeperNotice", UIParent)
    btn:SetSize(SIZE, SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Our badges bring their own ring (Media/notice, notice_death), so the icon is the whole button.
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()

    -- The count, on a small wax-red dot.
    btn.dot = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    btn.dot:SetSize(17, 17)
    btn.dot:SetPoint("TOPRIGHT", 3, 3)
    btn.dot:SetColorTexture(0.62, 0.07, 0.05)
    local dotMask = btn:CreateMaskTexture()
    dotMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    dotMask:SetAllPoints(btn.dot)
    btn.dot:AddMaskTexture(dotMask)
    btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.count:SetPoint("CENTER", btn.dot, "CENTER", 0, 0)

    -- A glow that breathes: gold for new letters, red for a target nearby.
    btn.glow = btn:CreateTexture(nil, "BACKGROUND")
    btn.glow:SetTexture(MEDIA .. "glow")
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetSize(SIZE * 1.6, SIZE * 1.6)
    btn.glow:SetPoint("CENTER")
    btn.glow:SetAlpha(0)
    local breathe = btn.glow:CreateAnimationGroup()
    breathe:SetLooping("BOUNCE")
    local a = breathe:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15)
    a:SetToAlpha(0.9)
    a:SetDuration(0.7)
    btn.breathe = breathe

    -- Arriving: the letter fades in where there was nothing...
    local appear = btn:CreateAnimationGroup()
    local fade = appear:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.6)
    fade:SetSmoothing("OUT")
    btn.appear = appear
    -- ...and blinks three times, then holds still.
    local blink = btn.icon:CreateAnimationGroup()
    for i = 1, 6 do
        local step = blink:CreateAnimation("Alpha")
        step:SetFromAlpha(i % 2 == 1 and 1 or 0.3)
        step:SetToAlpha(i % 2 == 1 and 0.3 or 1)
        step:SetDuration(0.22)
        step:SetOrder(i)
    end
    btn.blink = blink
    appear:SetScript("OnFinished", function()
        if btn.blinkNext then
            btn.blinkNext = false
            blink:Play()
        end
    end)

    -- The one line under the letter: a target nearby, or how to place it.
    btn.line = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.line:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    btn.line:SetTextColor(1, 0.3, 0.22)

    btn:SetScript("OnClick", function(self, button)
        if self.dragged then
            self.dragged = nil
            return
        end
        if placing then
            placing = false
            btn.line:Hide()
            GK.NoticeUpdate(false)
            return
        end
        if button == "RightButton" then GK.OpenWindow(1) else GK.OpenLetters() end
    end)
    btn:SetScript("OnDragStart", function(self)
        self.dragged = true
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    btn:SetScript("OnEnter", Tooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
end

--- One line about a letter, for the tooltip.
function GK.LetterLine(L)
    local who = GK.Show(L.n)
    if L.kind == "order" then return "Kill order: " .. who end
    if L.kind == "complete" then return "Order complete: " .. who end
    if L.kind == "paid" then return "Bounty paid: " .. who end
    if L.kind == "expired" then return "Order expired: " .. who end
    if L.kind == "kill" then return ("You killed %s (+%d)"):format(who, L.p or 0) end
    if L.kind == "slain" then return "Slain by " .. who end
    return who
end

-- After a letter lands the glow breathes for this long, then stays as a faint steady ring until the
-- letter is read: noticed once, not nagged about.
local BREATHE_FOR, RESTING_GLOW = 4, 0.3
-- Letters landing together - a login's worth of orders - sound once: a letter sounds only when none
-- has landed for this long. Measured from the last LANDING, not the last sound, so a steady trickle
-- of replies is one burst and not a page turning every few seconds.
local SOUND_GAP = 3
local settleAt, settlePending, lastLanding = 0, false, -math.huge

-- One timer for however many letters land: it waits out the last one, then lets the glow rest.
local function Settle()
    if GetTime() < settleAt then
        C_Timer.After(settleAt - GetTime() + 0.1, Settle)
        return
    end
    settlePending = false
    GK.NoticeUpdate(false)
end

--- Show, hide and dress the letter for what is waiting. landed: a new letter just came; silent: no
--- sound for it (news of something you did yourself).
function GK.NoticeUpdate(landed, silent)
    if not GK.char then return end
    if not btn then Build() end
    local unread, first = GK.Unread()
    local warning = GetTime() < warnUntil
    if unread == 0 and not warning and not placing then
        btn.breathe:Stop()
        btn:Hide()
        return
    end
    -- the badge of the newest unread letter; a warning keeps the sealed scroll and glows red
    local icon = MEDIA .. "notice"
    for i = #GK.char.letters, first or 1, -1 do
        local L = GK.char.letters[i]
        if not L.read then
            icon = GK.LETTER_ICON[L.kind] or icon
            break
        end
    end
    btn.icon:SetTexture(icon)
    btn.dot:SetShown(unread > 0)
    btn.count:SetText(unread > 0 and unread or "")
    if warning then btn.glow:SetVertexColor(1, 0.15, 0.1) else btn.glow:SetVertexColor(1, 0.8, 0.35) end
    local wasShown = btn:IsShown()
    btn:Show()
    if landed then
        settleAt = GetTime() + BREATHE_FOR
        if not settlePending then
            settlePending = true
            C_Timer.After(BREATHE_FOR + 0.1, Settle)
        end
        if wasShown then
            if not btn.blink:IsPlaying() then btn.blink:Play() end
        else
            btn.blinkNext = true
            btn.appear:Play()
        end
        if not silent and GetTime() - lastLanding > SOUND_GAP then GK.Sound("IG_ABILITY_PAGE_TURN") end
        lastLanding = GetTime()
    elseif not wasShown then
        btn.appear:Play()
    end
    if warning or GetTime() < settleAt then
        if not btn.breathe:IsPlaying() then btn.breathe:Play() end
    else
        btn.breathe:Stop()
        btn.glow:SetAlpha(unread > 0 and RESTING_GLOW or 0)
    end
end

--- Show the letter to be dragged into place, letters or not (/grudge notice, the settings page).
--- reset: back to where it starts.
function GK.PlaceNotice(reset)
    if not btn then Build() end
    if reset then
        GK.db.notice = nil
        Place()
    end
    placing = true
    btn.line:SetText("Drag me - click when done")
    btn.line:SetTextColor(1, 0.82, 0.35)
    btn.line:Show()
    GK.NoticeUpdate(false)
end

--- A target nearby (urgent: red, a sound) or news of one elsewhere (quiet): a line under the letter.
function GK.Warn(text, urgent)
    if not btn then Build() end
    btn.warnText = text
    btn.line:SetText(text)
    if urgent then btn.line:SetTextColor(1, 0.3, 0.22) else btn.line:SetTextColor(1, 0.82, 0.35) end
    btn.line:Show()
    if urgent then
        warnUntil = GetTime() + WARN_FOR
        -- the boss-whisper chime: enough to look up, nothing like a raid warning's horn
        GK.Sound("UI_RAID_BOSS_WHISPER_WARNING")
    end
    GK.NoticeUpdate(false)
    if not urgent then btn.line:SetShown(btn:IsShown()) end
    C_Timer.After(WARN_FOR, function()
        if btn.warnText ~= text then return end
        btn.line:Hide()
        GK.NoticeUpdate(false)
    end)
end
