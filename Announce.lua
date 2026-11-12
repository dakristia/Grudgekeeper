-- Grudgekeeper - the announcements: a spree milestone, a spree that ended, a tormentor put down. Each is
-- told as a splash (big, in the middle of the screen, click-through) or a toast (small, stacked under the
-- letter icon), or not at all - the kind's setting says which. Two more settings say when it may come:
-- always, or not in a fight, not in a fight in an instance, not in an instance. One that may not come yet
-- is held, and plays in order when the setting allows (the fight ends, the area changes), one splash
-- after another. Plain frames only: nothing here is secure, protected or a CVar, so it all works in combat.
-- What is told comes from Kills.lua and Guild.lua as GK_SPREE, GK_SPREE_ENDED and GK_TORMENTOR.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local SPLASH_GAP = 3.5           -- a held splash waits this long after the one before it
local SPLASH_HOLD, SPLASH_FADE, SPLASH_POP = 2.5, 0.6, 0.25
local TOAST_HOLD, TOAST_FADE, MAX_TOASTS = 5, 0.6, 4
local MAX_HELD = 30              -- a long raid can't build a backlog without end: the oldest goes

-- The sound of each kind until one is picked (GK.db.spreeSounds), rising with the tier.
local DEFAULT_SOUNDS = {
    bloodied = "kit:IG_PVP_UPDATE",
    merciless = "kit:RAID_WARNING",
    butcher = "kit:PVP_THROUGH_QUEUE",
    reaper = "kit:HARDCORE_DUEL",
    grudgebound = "kit:UI_PVP_HONOR_PRESTIGE_RANK_UP",
    ended = "kit:UI_RAID_BOSS_DEFEATED",
    tormentor = "kit:UI_GARRISON_TOAST_INVASION_ALERT",
}
GK.SPREE_DEFAULT_SOUNDS = DEFAULT_SOUNDS     -- for the settings page, which shows these until one is picked

--- Whether an announcement may come now, by its when-setting and where we are.
function GK.AnnounceAllowed(when, inCombat, inInstance)
    if when == "noCombat" then return not inCombat end
    if when == "noCombatInInstance" then return not (inCombat and inInstance) end
    if when == "noInstance" then return not inInstance end
    return true
end

local function InCombat()
    return (InCombatLockdown() or UnitAffectingCombat("player")) and true or false
end

--- Whether an item may come now. leftCombat: the fight just ended, whatever the game still says.
local function Allowed(item, leftCombat)
    local when = item.mine and GK.db.announceWhenMine or GK.db.announceWhenGuild
    return GK.AnnounceAllowed(when, not leftCombat and InCombat(), not GK.InWorld())
end

-- ---------------------------------------------------------------------------
-- The splash
-- ---------------------------------------------------------------------------
local splash
local splashBusyUntil = 0

local function BuildSplash()
    splash = CreateFrame("Frame", "GrudgekeeperSplash", UIParent)
    splash:SetFrameStrata("HIGH")
    splash:EnableMouse(false)
    splash:SetSize(512, 424)
    splash:SetPoint("TOP", UIParent, "CENTER", 0, 300)
    splash.glow = splash:CreateTexture(nil, "BACKGROUND")
    splash.glow:SetTexture(MEDIA .. "glow")
    splash.glow:SetBlendMode("ADD")
    splash.glow:SetSize(512, 512)
    splash.glow:SetPoint("CENTER", splash, "TOP", 0, -128)
    splash.seal = splash:CreateTexture(nil, "ARTWORK")
    splash.seal:SetSize(256, 256)
    splash.seal:SetPoint("CENTER", splash, "TOP", 0, -128)
    splash.ribbon = splash:CreateTexture(nil, "ARTWORK")
    splash.ribbon:SetSize(512, 128)
    splash.ribbon:SetPoint("TOP", splash, "TOP", 0, -252)
    splash.line = splash:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    splash.line:SetPoint("TOP", splash, "TOP", 0, -384)
    splash.age = 0
    -- The punch (the seal scales in), the glow's pulse and the fade, by hand: one frame's OnUpdate.
    splash:SetScript("OnUpdate", function(self, dt)
        local age = self.age + dt
        self.age = age
        local s = 1
        if age < SPLASH_POP then s = 1.6 - 0.6 * (age / SPLASH_POP) end
        self.seal:SetSize(256 * s, 256 * s)
        self.glow:SetAlpha(0.55 + 0.35 * math.sin(age * 6))
        if age >= SPLASH_HOLD + SPLASH_FADE then
            self:Hide()
        elseif age > SPLASH_HOLD then
            self:SetAlpha(1 - (age - SPLASH_HOLD) / SPLASH_FADE)
        end
    end)
    splash:Hide()
end

local function ShowSplash(item)
    if not splash then BuildSplash() end
    splash.seal:SetTexture(item.seal)
    splash.ribbon:SetTexture(item.ribbon)
    splash.ribbon:SetShown(item.ribbon ~= nil)
    splash.line:SetText(item.line)
    splash.age = 0
    splash:SetAlpha(1)
    splash:Show()
    splashBusyUntil = GetTime() + SPLASH_GAP
end

-- ---------------------------------------------------------------------------
-- The toasts
-- ---------------------------------------------------------------------------
local active, pool = {}, {}       -- the toasts showing, oldest first, and the frames not in use

local function Relayout()
    local notice = GK.NoticeFrame and GK.NoticeFrame()
    for i, t in ipairs(active) do
        t:ClearAllPoints()
        if i == 1 then
            if notice then
                t:SetPoint("TOPRIGHT", notice, "BOTTOMRIGHT", 0, -26)
            else
                t:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -300)
            end
        else
            t:SetPoint("TOPRIGHT", active[i - 1], "BOTTOMRIGHT", 0, -4)
        end
    end
end

local function RemoveToast(t)
    t:Hide()
    for i, a in ipairs(active) do
        if a == t then table.remove(active, i) break end
    end
    pool[#pool + 1] = t
    Relayout()
end

local function BuildToast()
    local t = CreateFrame("Frame", nil, UIParent)
    t:SetFrameStrata("HIGH")
    t:EnableMouse(false)
    t:SetSize(244, 66)
    t.seal = t:CreateTexture(nil, "ARTWORK")
    t.seal:SetSize(48, 48)
    t.seal:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    t.ribbon = t:CreateTexture(nil, "ARTWORK")
    t.ribbon:SetSize(192, 48)
    t.ribbon:SetPoint("TOPLEFT", t.seal, "TOPRIGHT", 4, 0)
    t.line = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.line:SetJustifyH("LEFT")
    t.age = 0
    t:SetScript("OnUpdate", function(self, dt)
        local age = self.age + dt
        self.age = age
        if age >= TOAST_HOLD + TOAST_FADE then
            RemoveToast(self)
        elseif age > TOAST_HOLD then
            self:SetAlpha(1 - (age - TOAST_HOLD) / TOAST_FADE)
        end
    end)
    return t
end

local function ShowToast(item)
    if #active >= MAX_TOASTS then RemoveToast(active[1]) end
    local t = table.remove(pool) or BuildToast()
    t.seal:SetTexture(item.seal)
    t.ribbon:SetTexture(item.ribbon)
    t.ribbon:SetShown(item.ribbon ~= nil)
    t.line:SetText(item.line)
    -- under its ribbon; with no ribbon, beside the seal
    t.line:ClearAllPoints()
    if item.ribbon then
        t.line:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -50)
        t.line:SetWidth(244)
    else
        t.line:SetPoint("LEFT", t.seal, "RIGHT", 4, 0)
        t.line:SetWidth(192)
    end
    t.age = 0
    t:SetAlpha(1)
    active[#active + 1] = t
    Relayout()
    t:Show()
end

-- ---------------------------------------------------------------------------
-- Showing, holding and releasing
-- ---------------------------------------------------------------------------
local held, ready = {}, {}        -- not allowed yet; allowed and waiting for their turn. Both in arrival order.
local drainTimer = false

--- What an item is shown with, and its sound: when it is shown, not when it was queued.
local function Show(item)
    if item.style == "splash" then ShowSplash(item) else ShowToast(item) end
    if GK.db.sound and not item.silent then
        GK.PlayChoice((GK.db.spreeSounds or {})[item.sound] or DEFAULT_SOUNDS[item.sound])
    end
end

--- Show what is ready, in order: a toast at once, a splash when the one before it has had its time.
local function Drain()
    while ready[1] do
        local item = ready[1]
        local wait = splashBusyUntil - GetTime()
        if item.style == "splash" and wait > 0 then
            if not drainTimer then
                drainTimer = true
                C_Timer.After(wait + 0.05, function()
                    drainTimer = false
                    Drain()
                end)
            end
            return
        end
        table.remove(ready, 1)
        Show(item)
    end
end

--- The held ones that may come now go to ready, in the order they arrived.
local function ReleaseHeld(leftCombat)
    local keep = {}
    for _, item in ipairs(held) do
        if Allowed(item, leftCombat) then ready[#ready + 1] = item else keep[#keep + 1] = item end
    end
    held = keep
    Drain()
end

local function Tell(item)
    if Allowed(item) then
        if #ready == 0 then Show(item) else ready[#ready + 1] = item Drain() end
    else
        held[#held + 1] = item
        if #held > MAX_HELD then table.remove(held, 1) end
    end
end

LIB.On("PLAYER_REGEN_ENABLED", function() if #held > 0 then ReleaseHeld(true) end end)
LIB.On("PLAYER_ENTERING_WORLD", function() if #held > 0 then ReleaseHeld(false) end end)
LIB.On("ZONE_CHANGED_NEW_AREA", function() if #held > 0 then ReleaseHeld(false) end end)

-- ---------------------------------------------------------------------------
-- What is told
-- ---------------------------------------------------------------------------
local function Name(key)
    local name = GK.Show(key)
    if GK.Secret(name) then return "?" end
    return name
end

--- setting: the kind's own (off, toast, splash). nil for anything else, which shows nothing.
local function Style(setting)
    local s = GK.db and GK.db[setting]
    if s == "toast" or s == "splash" then return s end
    return nil
end

local function Add(setting, mine, item)
    item.style = Style(setting)
    if not item.style then return end
    item.mine = mine
    Tell(item)
end

LIB.Listen("GK_SPREE", function(who, spree, tierName, mine)
    local _, key = GK.SpreeTierOf(spree)
    if not key then return end
    local line = ("%d kills in a row"):format(spree)
    if not mine then line = Name(who) .. ": " .. line end
    Add(mine and "spreeMine" or "spreeGuild", mine, { seal = MEDIA .. "spree_" .. key,
        ribbon = MEDIA .. "spree_" .. key .. "_name", line = line, sound = key })
end)

LIB.Listen("GK_SPREE_ENDED", function(who, spree, killerName, mine)
    local line
    if mine then
        line = ("Your %d-kill spree ended (%s)"):format(spree, killerName)
    else
        line = ("%s's %d-kill spree ended (%s)"):format(Name(who), spree, killerName)
    end
    Add("spreeEnded", mine, { seal = MEDIA .. "seal_broken", line = line, sound = "ended" })
end)

LIB.Listen("GK_TORMENTOR", function(who, enemyName, count, mine)
    local line = ("%s put an end to %s, who had killed %d of us"):format(mine and "You" or Name(who), enemyName, count)
    Add("tormentor", mine, { seal = MEDIA .. "seal_black", line = line, sound = "tormentor" })
end)

--- /grudge spree: a sample splash and a sample toast, whatever the settings and the when-rules say.
function GK.AnnounceSample()
    Show({ style = "splash", seal = MEDIA .. "spree_butcher", ribbon = MEDIA .. "spree_butcher_name",
        line = "7 kills in a row", sound = "butcher" })
    Show({ style = "toast", seal = MEDIA .. "spree_butcher", ribbon = MEDIA .. "spree_butcher_name",
        line = "Glue Enjoyer: 7 kills in a row", silent = true })
end
