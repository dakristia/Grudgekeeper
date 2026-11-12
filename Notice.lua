-- Grudgekeeper - the notice: a small sealed letter that says something came, the way the game's own
-- envelope says you have mail - but on its own, wherever you put it, not on the minimap. It fades in
-- and blinks when a letter lands, then rests with a faint glow until you read it. Click it to read,
-- right-click for the hitlist, drag it anywhere; /grudge notice shows it to place it without waiting
-- for mail. When the target of a kill order is near it glows red, with its sound, one short line under
-- it and a bubble over it that a click targets them from; when a guildie sees them, the line alone says who
-- saw them where. That is the only warning Grudgekeeper gives: nothing opens in the middle of the screen.
local ADDON, GK = ...

local SIZE = 46
local WARN_FOR = 12              -- seconds the red glow and the line stay
local NEAR_SOUND_GAP = 600       -- the near sound plays for one player (or guild) at most this often
local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local btn
local warnUntil = 0
local placing = false            -- shown to be dragged into place, letters or not
local Replace                    -- the click-to-target button laid over its bubble again (below)

local function SavePosition(self)
    local point, _, relPoint, x, y = self:GetPoint(1)
    GK.db.notice = { point = point, relPoint = relPoint, x = x, y = y }
end

--- Where the letter icon goes: its own point, the point of UIParent it hangs from, and the offsets. The one
--- the player saved, else the default.
local function Position()
    local p = GK.db.notice
    if p and p.point then
        return p.point, p.relPoint or p.point, p.x or 0, p.y or 0
    end
    -- By default at the top, left of where the quest tracker sits in a plain UI (the user's pick,
    -- 2026-11-03): the spot it leaves empty. A fixed place on the screen, NOT tied to the tracker -
    -- the user asked for that, so it stays put whatever the tracker or another addon does. A little
    -- below the tracker's top, where Headstart's quest-group eye sits.
    return "TOPRIGHT", "TOPRIGHT", -300, -250
end

local function Place()
    btn:ClearAllPoints()
    local point, relPoint, x, y = Position()
    btn:SetPoint(point, UIParent, relPoint, x, y)
end

--- Where the icon's bottom right corner is, as a point of UIParent and offsets from it, for what hangs under
--- the icon before it has been built (Announce.lua's toasts).
function GK.NoticeCorner()
    local point, relPoint, x, y = Position()
    local dx = point:find("RIGHT") and 0 or (point:find("LEFT") and SIZE or SIZE / 2)
    local dy = point:find("BOTTOM") and 0 or (point:find("TOP") and -SIZE or -SIZE / 2)
    return relPoint, x + dx, y + dy
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
    GameTooltip:AddLine("Click: read  -  Shift-click: read all  -  Right-click: hitlist  -  Drag: move", 0.7, 0.7, 0.7)
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
    -- Leaving: unread letters that waited their while fade from the icon (Letters.lua, FadeDue), and the
    -- letter goes the way it came rather than at once
    local vanish = btn:CreateAnimationGroup()
    local out = vanish:CreateAnimation("Alpha")
    out:SetFromAlpha(1)
    out:SetToAlpha(0)
    out:SetDuration(1.5)
    out:SetSmoothing("IN")
    vanish:SetToFinalAlpha(true)
    vanish:SetScript("OnFinished", function()
        btn:Hide()
        btn:SetAlpha(1)
    end)
    btn.vanish = vanish

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
        if button == "RightButton" then
            GK.OpenWindow(1)
        elseif IsShiftKeyDown() then
            GK.ReadAllLetters()                -- the whole pile at once (Letters.lua)
        else
            GK.OpenLetters()
        end
    end)
    btn:SetScript("OnDragStart", function(self)
        self.dragged = true
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
        Replace()
    end)
    btn:SetScript("OnEnter", Tooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
end

--- The letter icon's frame, for what sits under it (Announce.lua's toasts). nil until it has been built.
function GK.NoticeFrame() return btn end

--- One line about a letter, for the tooltip.
function GK.LetterLine(L)
    local who = GK.Show(L.n)
    if L.kind == "order" then return "Kill order: " .. who end
    if L.kind == "complete" then return "Order complete: " .. who end
    if L.kind == "paid" then return "Bounty paid: " .. who end
    if L.kind == "expired" then return "Order expired: " .. who end
    if L.kind == "kill" then return L.title and ("A new title: " .. L.title) or ("You killed " .. who) end
    if L.kind == "slain" then return "Slain by " .. who end
    if L.kind == "news" then return "News from the Grudgekeeper" end
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
--- sound for it (news of something you did yourself); fading: the last unread ones faded (Letters.lua), so
--- the letter fades out rather than going at once.
function GK.NoticeUpdate(landed, silent, fading)
    if not GK.char then return end
    if not btn then Build() end
    local unread, first = GK.Unread()
    local warning = GetTime() < warnUntil
    if unread == 0 and not warning and not placing then
        btn.breathe:Stop()
        if fading and btn:IsShown() then
            if not btn.vanish:IsPlaying() then btn.vanish:Play() end
        else
            btn.vanish:Stop()
            btn:Hide()
        end
        return
    end
    btn.vanish:Stop()                               -- something came while it faded: it stays
    btn:SetAlpha(1)
    -- the badge of the newest unread letter; a warning keeps the sealed scroll and glows red
    local icon = MEDIA .. "notice"
    for i = #GK.char.letters, first or 1, -1 do
        local L = GK.char.letters[i]
        if not L.read and not L.faded and not GK.Held(L) then
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

-- ---------------------------------------------------------------------------
-- The bubble: who is near, said by the letter in the game's own chat bubble, and a click on it that
-- targets them ("HAN ER I NÆRHETEN, KLIKK FOR TARGET!", the owner, 2026-11-09). No addon may target anyone
-- by itself; a click on the game's secure button running /targetexact can - and that button can be set up,
-- shown and hidden only out of combat. So the bubble (ours, shown whenever) and the button laid over it
-- (the game's, out of combat) are two frames, and a warning in the middle of a fight says to target them
-- by hand. A button left on screen by a fight stays until it ends, and its bubble with it, so it never
-- lies invisible where a click would target someone.
-- ---------------------------------------------------------------------------
local BUBBLE_W, BUBBLE_H = 230, 66
local bubble, clicker
local clickerName                -- whom the button targets now

--- The macro that targets a name: the whole name, else the first name alone - the character's name in the
--- game, which Forever's surname is added to. nil for anything but letters, spaces, ' and -, so a name off
--- the wire can never carry a command into it.
local function TargetMacro(name)
    if type(name) ~= "string" or #name > 48 or not name:find("^[%a\128-\255][%a\128-\255 '%-]*$") then
        return nil
    end
    local lines = { "/cleartarget", "/targetexact " .. name }
    local first = name:match("^(.-) ")
    if first and first ~= "" then lines[#lines + 1] = "/targetexact [noexists] " .. first end
    return table.concat(lines, "\n")
end

local function BuildBubble()
    bubble = CreateFrame("Frame", "GrudgekeeperNearBubble", btn, "BackdropTemplate")
    bubble:SetSize(BUBBLE_W, BUBBLE_H)
    bubble:SetPoint("BOTTOMRIGHT", btn, "TOPLEFT", 18, -2)
    bubble:SetFrameLevel(btn:GetFrameLevel() + 6)
    bubble:SetClampedToScreen(true)
    if bubble.SetBackdrop then
        bubble:SetBackdrop({ bgFile = "Interface\\Tooltips\\ChatBubble-Background",
            edgeFile = "Interface\\Tooltips\\ChatBubble-Backdrop", tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 16, right = 16, top = 16, bottom = 16 } })
    end
    bubble.tail = bubble:CreateTexture(nil, "ARTWORK")
    bubble.tail:SetTexture("Interface\\Tooltips\\ChatBubble-Tail")
    bubble.tail:SetSize(24, 24)
    bubble.tail:SetPoint("TOP", bubble, "BOTTOMRIGHT", -26, 5)
    -- red over black and white over black: read on the bubble's white and on a dark one alike
    bubble.name = bubble:CreateFontString(nil, "OVERLAY")
    GK.SetFont(bubble.name, GK.TEXT_FONT, 15, "OUTLINE")
    bubble.name:SetTextColor(1, 0.22, 0.16)
    bubble.name:SetPoint("TOP", 0, -14)
    bubble.name:SetWidth(BUBBLE_W - 24)
    bubble.name:SetWordWrap(false)
    bubble.hint = bubble:CreateFontString(nil, "OVERLAY")
    GK.SetFont(bubble.hint, GK.TEXT_FONT, 11, "OUTLINE")
    bubble.hint:SetTextColor(1, 0.92, 0.75)
    bubble.hint:SetPoint("TOP", bubble.name, "BOTTOM", 0, -6)
    bubble.hint:SetWidth(BUBBLE_W - 24)
    -- a pop as it comes
    local pop = bubble:CreateAnimationGroup()
    local grow = pop:CreateAnimation("Scale")
    grow:SetScaleFrom(0.6, 0.6)
    grow:SetScaleTo(1, 1)
    grow:SetDuration(0.18)
    grow:SetSmoothing("OUT")
    grow:SetOrigin("BOTTOMRIGHT", 0, 0)
    local fade = pop:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.18)
    bubble.pop = pop
    bubble:Hide()
end

local HideBubble

local function BuildClicker()
    clicker = CreateFrame("Button", "GrudgekeeperTargetButton", UIParent, "SecureActionButtonTemplate")
    clicker:SetFrameStrata("HIGH")
    -- both: the game's secure button acts on the press or the release, as the player's settings say
    clicker:RegisterForClicks("AnyUp", "AnyDown")
    clicker:SetAttribute("type", "macro")
    clicker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(("Target %s"):format(clickerName or "them"))
        GameTooltip:Show()
    end)
    clicker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- targeted: the bubble has done its job (out of combat; in a fight the button can't be hidden)
    clicker:SetScript("PostClick", function()
        if bubble then bubble.due = 0 end
        HideBubble()
    end)
    clicker:Hide()
end

--- The button over the bubble, where the bubble is: a place of its own on the screen, not anchored to the
--- bubble, so moving the letter in a fight never moves a protected frame. Out of combat only.
Replace = function()
    if not (clicker and bubble and clicker:IsShown() and bubble:IsShown()) or InCombatLockdown() then return end
    local l, b = bubble:GetLeft(), bubble:GetBottom()
    if not (l and b) then return end
    local s = bubble:GetEffectiveScale() / UIParent:GetEffectiveScale()
    clicker:ClearAllPoints()
    clicker:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
    clicker:SetSize(bubble:GetWidth() * s, bubble:GetHeight() * s)
end

--- Gone when its time is up - unless a fight keeps its button on screen; PLAYER_REGEN_ENABLED asks again.
HideBubble = function()
    if not bubble or GetTime() < (bubble.due or 0) then return end
    if clicker and clicker:IsShown() then
        if InCombatLockdown() then return end
        clicker:Hide()
    end
    bubble:Hide()
end
LibStub("LibForever-1.0").On("PLAYER_REGEN_ENABLED", function() HideBubble() end)

--- The bubble over the letter: key is whom it says is near, and a click on it targets them when it can.
local function ShowBubble(key)
    if not bubble then BuildBubble() end
    local name = GK.Show(key)
    local macro = TargetMacro(name)
    local hint = ""
    if clicker and clicker:IsShown() and InCombatLockdown() then
        -- set up before the fight: it targets whom it was set for, and says so
        hint = clickerName == name and "Click to target" or ("Click to target %s"):format(clickerName or "")
    elseif macro and not InCombatLockdown() then
        if not clicker then BuildClicker() end
        clicker:SetAttribute("macrotext", macro)
        clickerName = name
        hint = "Click to target"
    elseif macro then
        hint = "In combat - target them yourself"
    end
    bubble.name:SetText(("%s is near!"):format(name))
    bubble.hint:SetText(hint)
    bubble.due = GetTime() + WARN_FOR
    local was = bubble:IsShown()
    bubble:Show()
    if not was and bubble.pop then bubble.pop:Play() end
    -- out of combat the button is over the bubble only when it targets whom the bubble names
    if clicker and not InCombatLockdown() then
        if macro and clickerName == name then
            clicker:Show()
            Replace()
        else
            clicker:Hide()
        end
    end
    C_Timer.After(WARN_FOR + 0.1, HideBubble)
end

-- When the near sound last played for whom: a target stepping out of sight and back in is not the war all
-- over again - "bare tillat avspilling 1 gang hvert 10. min elns så den ikke spiller av bare fordi kill
-- target går litt langt unna view" (the owner, 2026-11-10). The line and the bubble still come each time,
-- so there is always something to click to target them.
local soundAt = {}
local function SoundDue(key)
    if not key then return true end
    local now = GetTime()
    for k, t in pairs(soundAt) do
        if now - t >= NEAR_SOUND_GAP then soundAt[k] = nil end
    end
    if soundAt[key] then return false end
    soundAt[key] = now
    return true
end

--- A target nearby (urgent: red, a sound) or news of one elsewhere (quiet): a line under the letter.
--- ownSound: the caller plays a sound of its own (the one picked for a Shame player), so not the near one.
--- target: the one player the warning is about (their key) - the bubble that says so and targets them.
--- soundKey: whom the sound is for (a player's key, a guild), so it plays for them once in NEAR_SOUND_GAP;
--- none, and it plays every time.
function GK.Warn(text, urgent, ownSound, target, soundKey)
    if not btn then Build() end
    btn.warnText = text
    btn.line:SetText(text)
    if urgent then btn.line:SetTextColor(1, 0.3, 0.22) else btn.line:SetTextColor(1, 0.82, 0.35) end
    btn.line:Show()
    if urgent then
        warnUntil = GetTime() + WARN_FOR
        -- the sound picked for it, the Battleground horn to begin with (it was the boss-whisper chime, and a
        -- target near deserved more: the owner, 2026-11-09; our own war horn went before 1.2.0)
        if not ownSound and SoundDue(soundKey) then GK.NearSound() end
        if target then ShowBubble(target) end
    end
    GK.NoticeUpdate(false)
    if not urgent then btn.line:SetShown(btn:IsShown()) end
    C_Timer.After(WARN_FOR, function()
        if btn.warnText ~= text then return end
        btn.line:Hide()
        GK.NoticeUpdate(false)
    end)
end
