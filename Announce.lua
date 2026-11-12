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
-- Held announcements are capped: after a long raid in a fight-only setting, a backlog would otherwise all
-- replay at once, long after it mattered. The oldest goes.
local MAX_HELD = 30

-- The sound of each kind until one is picked (GK.db.spreeSounds): the Grudgekeeper calling out each tier.
local DEFAULT_SOUNDS = {
    bloodied = "file:voice_bloodied",
    merciless = "file:voice_merciless",
    butcher = "file:voice_butcher",
    reaper = "file:voice_reaper",
    grudgebound = "file:voice_grudgebound",
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
    -- IsInInstance() itself, not GK.InWorld(): that one is cached and cleared by Core when the area changes,
    -- and this must not depend on whether Core's handler ran before ours
    return GK.AnnounceAllowed(when, not leftCombat and InCombat(), (IsInInstance()) and true or false)
end

-- ---------------------------------------------------------------------------
-- The splash
-- ---------------------------------------------------------------------------
local splash
local splashBusyUntil = 0
local SEAL = 170                  -- the splash seal's size; the ribbon is twice as wide, half as high

-- The fire behind a spree's seal, growing with the tier: the flames' size (times the seal's) and strength,
-- and how many embers rise. Spree ended and tormentor splashes don't burn.
local FIRE = {
    bloodied = { size = 1.83, alpha = 0.55, embers = 4 },
    merciless = { size = 1.98, alpha = 0.7, embers = 7 },
    butcher = { size = 2.15, alpha = 0.85, embers = 10 },
    reaper = { size = 2.32, alpha = 1, embers = 14 },
    grudgebound = { size = 2.54, alpha = 1, embers = 22 },
}
local MAX_EMBERS = 0
for _, fire in pairs(FIRE) do MAX_EMBERS = math.max(MAX_EMBERS, fire.embers) end
-- spree_flames.tga is a 4x4 sheet of a 16-frame loop, played at 12 frames a second
local FLAME_FRAMES, FLAME_COLS, FLAME_ROWS, FLAME_FPS = 16, 4, 4, 12
local SHINE_START, SHINE_TIME, SHINE_WIDTH = 0.35, 0.6, 60

--- A dark outline on a line of text, so it reads over snow and sunlit sand as well as at night.
local function Outline(fs)
    local file, size = fs:GetFont()
    if file then fs:SetFont(file, size, "OUTLINE") end
end

local function BuildSplash()
    splash = CreateFrame("Frame", "GrudgekeeperSplash", UIParent)
    splash:SetFrameStrata("HIGH")
    splash:EnableMouse(false)
    -- Two thirds of the first try, which took too much of the screen (the owner, 2026-11-12).
    splash:SetSize(2 * SEAL, SEAL + SEAL / 2 + 40)
    splash:SetPoint("TOP", UIParent, "CENTER", 0, 260)
    -- A soft ember glow of its own: the letter icon's glow.tga is a ring, and grown this big it read as a
    -- white halo around the seal.
    splash.glow = splash:CreateTexture(nil, "BACKGROUND")
    splash.glow:SetTexture(MEDIA .. "spree_glow")
    splash.glow:SetBlendMode("ADD")
    splash.glow:SetSize(SEAL * 1.8, SEAL * 1.8)
    splash.glow:SetPoint("CENTER", splash, "TOP", 0, -SEAL / 2)
    -- Flames lick up from behind the seal: their middle sits a little above the seal's, as the tops are taller.
    splash.flames = splash:CreateTexture(nil, "BACKGROUND", nil, 1)
    splash.flames:SetTexture(MEDIA .. "spree_flames")
    splash.flames:SetPoint("CENTER", splash, "TOP", 0, -SEAL / 2 + SEAL * 0.04)
    splash.seal = splash:CreateTexture(nil, "ARTWORK")
    splash.seal:SetSize(SEAL, SEAL)
    splash.seal:SetPoint("CENTER", splash, "TOP", 0, -SEAL / 2)
    splash.ribbon = splash:CreateTexture(nil, "ARTWORK")
    splash.ribbon:SetSize(2 * SEAL, SEAL / 2)
    splash.ribbon:SetPoint("TOP", splash, "TOP", 0, -SEAL + 4)
    -- A light sweeps across the ribbon as it lands, kept to the ribbon's shape by a mask of the ribbon itself.
    splash.shine = splash:CreateTexture(nil, "OVERLAY")
    splash.shine:SetTexture(MEDIA .. "spree_shine")
    splash.shine:SetBlendMode("ADD")
    splash.shine:SetSize(SHINE_WIDTH, SEAL / 2)
    splash.shineMask = splash:CreateMaskTexture()
    splash.shineMask:SetAllPoints(splash.ribbon)
    splash.shine:AddMaskTexture(splash.shineMask)
    splash.embers = {}
    for i = 1, MAX_EMBERS do
        local e = splash:CreateTexture(nil, "OVERLAY")
        e:SetTexture(MEDIA .. "spree_spark")
        e:SetBlendMode("ADD")
        splash.embers[i] = e
    end
    splash.line = splash:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    Outline(splash.line)
    splash.line:SetPoint("TOP", splash, "TOP", 0, -SEAL - SEAL / 2 + 4)
    splash.age = 0
    -- The punch (the seal scales in), the glow's pulse, the flames, embers and shine, and the fade, by hand:
    -- one frame's OnUpdate.
    splash:SetScript("OnUpdate", function(self, dt)
        local age = self.age + dt
        self.age = age
        local s = 1
        if age < SPLASH_POP then s = 1.6 - 0.6 * (age / SPLASH_POP) end
        self.seal:SetSize(SEAL * s, SEAL * s)
        self.glow:SetAlpha(0.45 + 0.2 * math.sin(age * 6))
        local fire = self.fire
        if fire then
            local i = math.floor(age * FLAME_FPS) % FLAME_FRAMES
            local col, row = i % FLAME_COLS, math.floor(i / FLAME_COLS)
            self.flames:SetTexCoord(col / FLAME_COLS, (col + 1) / FLAME_COLS, row / FLAME_ROWS, (row + 1) / FLAME_ROWS)
            self.flames:SetAlpha(fire.alpha * math.min(1, age / SPLASH_POP))
            local catching = math.min(1, age / 0.3)
            for n = 1, fire.embers do
                local e, m = self.embers[n], self.motes[n]
                local t = (age - m.born) % m.life
                local f = t / m.life
                e:SetPoint("CENTER", self.seal, "CENTER", m.x + m.vx * t, m.y + m.rise * t)
                e:SetAlpha((1 - f) * math.min(1, f * 5) * catching)
            end
        end
        local p = (age - SHINE_START) / SHINE_TIME
        if self.ribbon:IsShown() and p >= 0 and p <= 1 then
            self.shine:SetPoint("CENTER", self.ribbon, "LEFT", -SHINE_WIDTH + p * (2 * SEAL + 2 * SHINE_WIDTH), 0)
            self.shine:Show()
        else
            self.shine:Hide()
        end
        if age >= SPLASH_HOLD + SPLASH_FADE then
            self:Hide()
        elseif age > SPLASH_HOLD then
            self:SetAlpha(1 - (age - SPLASH_HOLD) / SPLASH_FADE)
        end
    end)
    splash:Hide()
end

--- Light the splash's fire for a tier (nil: no fire), with fresh embers each time.
local function Kindle(key)
    local fire = key and FIRE[key]
    splash.fire = fire
    splash.flames:SetShown(fire ~= nil)
    splash.motes = {}
    for n, e in ipairs(splash.embers) do
        e:ClearAllPoints()
        e:SetShown(fire ~= nil and n <= fire.embers)
        if fire and n <= fire.embers then
            local size = 10 + math.random() * 8
            e:SetSize(size, size)
            e:SetAlpha(0)
            -- each mote loops on its own clock: it rises from about the seal's upper half, drifting sideways
            splash.motes[n] = { x = math.random(-60, 60), y = SEAL * 0.3 - math.random(-10, 40),
                vx = math.random(-12, 12), rise = 35 + math.random() * 35,
                life = 0.9 + math.random() * 0.9, born = math.random() * 1.8 }
        end
    end
    if fire then
        splash.flames:SetSize(SEAL * fire.size, SEAL * fire.size)
        splash.flames:SetAlpha(0)
    end
end

local function ShowSplash(item)
    if not splash then BuildSplash() end
    splash.seal:SetTexture(item.seal)
    splash.ribbon:SetTexture(item.ribbon)
    splash.ribbon:SetShown(item.ribbon ~= nil)
    if item.ribbon then
        splash.shineMask:SetTexture(item.ribbon, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    splash.shine:Hide()
    Kindle(item.fire)
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
    local notice = GK.NoticeFrame()
    for i, t in ipairs(active) do
        t:ClearAllPoints()
        if i == 1 then
            if notice then
                t:SetPoint("TOPRIGHT", notice, "BOTTOMRIGHT", 0, -26)
            else
                -- the letter is not built until one comes: where it will be
                local rel, x, y = GK.NoticeCorner()
                t:SetPoint("TOPRIGHT", UIParent, rel, x, y - 26)
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
    t:SetSize(324, 84)
    t.seal = t:CreateTexture(nil, "ARTWORK")
    t.seal:SetSize(64, 64)
    t.seal:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    t.ribbon = t:CreateTexture(nil, "ARTWORK")
    t.ribbon:SetSize(256, 64)
    t.ribbon:SetPoint("TOPLEFT", t.seal, "TOPRIGHT", 4, 0)
    -- a size up from the first try, which was hard to read by the letter icon (the owner, 2026-11-12)
    t.line = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    Outline(t.line)
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
        t.line:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -68)
        t.line:SetWidth(324)
    else
        t.line:SetPoint("LEFT", t.seal, "RIGHT", 4, 0)
        t.line:SetWidth(256)
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

--- Show what is ready: the toasts at once, the splashes in their own order, each when the one before it has
--- had its time. A toast never waits for a splash.
local function Drain()
    local waiting = {}
    for _, item in ipairs(ready) do
        local wait = splashBusyUntil - GetTime()
        if item.style == "splash" and (wait > 0 or #waiting > 0) then
            waiting[#waiting + 1] = item
        else
            Show(item)
        end
    end
    ready = waiting
    local wait = splashBusyUntil - GetTime()
    if waiting[1] and wait > 0 and not drainTimer then
        drainTimer = true
        C_Timer.After(wait + 0.05, function()
            drainTimer = false
            Drain()
        end)
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
        ready[#ready + 1] = item
        Drain()
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
--- A name as it may be printed: a question mark when the game hides it.
local function Hide(name)
    if GK.Secret(name) then return "?" end
    return name
end

local function Name(key) return Hide(GK.Show(key)) end

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

LIB.Listen("GK_SPREE", function(who, spree, tierName, mine, key)
    if not key then return end
    local line = ("%d kills in a row"):format(spree)
    if not mine then line = Name(who) .. ": " .. line end
    Add(mine and "spreeMine" or "spreeGuild", mine, { seal = MEDIA .. "spree_" .. key,
        ribbon = MEDIA .. "spree_" .. key .. "_name", line = line, sound = key, fire = key })
end)

LIB.Listen("GK_SPREE_ENDED", function(who, spree, killerName, mine)
    local line
    if mine then
        line = ("Your %d-kill spree ended (%s)"):format(spree, Hide(killerName))
    else
        line = ("%s's %d-kill spree ended (%s)"):format(Name(who), spree, Hide(killerName))
    end
    Add("spreeEnded", mine, { seal = MEDIA .. "seal_broken", line = line, sound = "ended" })
end)

LIB.Listen("GK_TORMENTOR", function(who, enemyName, count, mine)
    local line = ("%s put an end to %s, who had killed %d of us"):format(mine and "You" or Name(who), Hide(enemyName), count)
    Add("spreeTormentor", mine, { seal = MEDIA .. "seal_black", line = line, sound = "tormentor" })
end)

--- /grudge spree: a sample splash and a sample toast, whatever the settings and the when-rules say.
function GK.AnnounceSample()
    Show({ style = "splash", seal = MEDIA .. "spree_butcher", ribbon = MEDIA .. "spree_butcher_name",
        line = "7 kills in a row", sound = "butcher", fire = "butcher" })
    Show({ style = "toast", seal = MEDIA .. "spree_butcher", ribbon = MEDIA .. "spree_butcher_name",
        line = "Glue Enjoyer: 7 kills in a row", silent = true })
end
