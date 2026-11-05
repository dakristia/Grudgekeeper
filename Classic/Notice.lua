-- Grudgekeeper - the Classic look: the letter icon. A small envelope in a standard button, the number of
-- unread letters on it, draggable anywhere (GK.db.classicNotice). It blinks when a letter lands and
-- rests with a faint glow until you read it, like the ledger's; click it to read, right-click for the
-- hitlist. A target nearby makes it glow red with a line of chat; the parchment notice stays hidden
-- while this look is on.
local ADDON, GK = ...
local C = GK.Classic

local SIZE = 40
local ENVELOPE = "Interface\\Icons\\INV_Letter_15"
local WARN_FOR = 12                  -- seconds the red glow and the line stay
local BREATHE_FOR, RESTING_GLOW = 4, 0.3
local SOUND_GAP = 3                  -- a letter sounds only when none has landed for this long

local btn
local warnUntil, settleAt, settlePending, lastLanding = 0, 0, false, -math.huge
local placing = false

local function SavePosition(self)
    local point, _, relPoint, x, y = self:GetPoint(1)
    GK.db.classicNotice = { point = point, relPoint = relPoint, x = x, y = y }
end

local function Place()
    btn:ClearAllPoints()
    local p = GK.db.classicNotice
    if p and p.point then
        btn:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -250)    -- where the ledger's starts
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
            if not L.read and not GK.Held(L) and shown < 5 then
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
    btn = CreateFrame("Button", "GrudgekeeperClassicNotice", UIParent)
    btn:SetSize(SIZE, SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:Hide()
    C.frames[#C.frames + 1] = btn

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(ENVELOPE)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- the number of unread letters, on the icon's lower right
    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.count:SetPoint("BOTTOMRIGHT", -2, 2)

    -- a glow that breathes: gold for new letters, red for a target nearby
    btn.glow = btn:CreateTexture(nil, "OVERLAY")
    btn.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    btn.glow:SetBlendMode("ADD")
    btn.glow:SetSize(SIZE * 1.9, SIZE * 1.9)
    btn.glow:SetPoint("CENTER")
    btn.glow:SetAlpha(0)
    local breathe = btn.glow:CreateAnimationGroup()
    breathe:SetLooping("BOUNCE")
    local a = breathe:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15)
    a:SetToAlpha(0.9)
    a:SetDuration(0.7)
    btn.breathe = breathe

    -- arriving: it fades in where there was nothing, and blinks three times
    local appear = btn:CreateAnimationGroup()
    local fade = appear:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.6)
    fade:SetSmoothing("OUT")
    btn.appear = appear
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

    -- the one line under the icon: how to place it
    btn.line = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.line:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    btn.line:Hide()

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

-- One timer for however many letters land: it waits out the last one, then lets the glow rest.
local function Settle()
    if GetTime() < settleAt then
        C_Timer.After(settleAt - GetTime() + 0.1, Settle)
        return
    end
    settlePending = false
    GK.NoticeUpdate(false)
end

--- Show, hide and dress the icon for what is waiting. landed: a new letter just came; silent: no sound
--- for it (news of something you did yourself).
C.Wraps.NoticeUpdate = function(_, landed, silent)
    if not GK.char then return end
    local old = _G.GrudgekeeperNotice
    if old and old:IsShown() then old:Hide() end            -- the parchment notice stays hidden
    if not btn then Build() end
    local unread, first = GK.Unread()
    local warning = GetTime() < warnUntil
    if unread == 0 and not warning and not placing then
        btn.breathe:Stop()
        btn:Hide()
        return
    end
    -- the newest unread letter tints the icon: red when someone killed you
    local tint = false
    for i = #GK.char.letters, first or 1, -1 do
        local L = GK.char.letters[i]
        if not L.read and not GK.Held(L) then
            tint = L.kind == "slain"
            break
        end
    end
    if tint then btn.icon:SetVertexColor(1, 0.55, 0.5) else btn.icon:SetVertexColor(1, 1, 1) end
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

--- Show the icon to be dragged into place, letters or not (/grudge notice, the settings page).
--- reset: back to where it starts.
C.Wraps.PlaceNotice = function(_, reset)
    if not btn then Build() end
    if reset then
        GK.db.classicNotice = nil
        Place()
    end
    placing = true
    btn.line:SetText("Drag me - click when done")
    btn.line:SetTextColor(1, 0.82, 0.35)
    btn.line:Show()
    GK.NoticeUpdate(false)
end

--- A target nearby (urgent: a red glow and a soft chime) or news of one elsewhere (quiet): one line in chat
--- either way. With the raid warning as the alert style the original chain does it.
C.Wraps.Warn = function(original, text, urgent)
    if GK.db.alertStyle == "raid" then return original(text, urgent) end
    print(GK.TAG .. ": " .. (urgent and "|cffff5040" or "|cffffd259") .. text .. "|r")
    if not urgent then return end
    if not btn then Build() end
    btn.warnText = text
    warnUntil = GetTime() + WARN_FOR
    GK.Sound("UI_RAID_BOSS_WHISPER_WARNING")
    GK.NoticeUpdate(false)
    C_Timer.After(WARN_FOR, function()
        if btn.warnText ~= text then return end
        GK.NoticeUpdate(false)
    end)
end
