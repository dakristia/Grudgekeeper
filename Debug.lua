-- Grudgekeeper - a TEMPORARY test panel: /grudge debug. Buttons that make things happen, so every part
-- can be tried in game before there are real kills to try it on (the user, 2026-11-04: "lag bare et
-- lite panel som vi fjerner senere"). To remove it: delete this file and its line in the TOC, the
-- OpenDebug line in Core.lua's /grudge, and GK.testMode, GK.ReceiveForTest and GK.InvalidateOrders in
-- Guild.lua.
--
-- While the panel is open nothing leaves this client: no addon message to the guild, no line in guild
-- chat. When it closes - or the game logs out or reloads with it open - your own record and the guild's
-- store are put back exactly as they were when it opened, so nothing the buttons did is kept.
-- The pretend guildies are Kari and Edvard; the pretend enemies are Pølse Hans and Gærd Balle, of
-- whichever side is not yours. With an enemy player targeted, "your target" is them instead.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local panel
local saved            -- { char, store, storeTable } while testing

local function Say(text) print(GK.TAG .. " (test): " .. text) end

-- ---------------------------------------------------------------------------
-- Test mode: nothing sent, everything put back
-- ---------------------------------------------------------------------------
local function Begin()
    if GK.testMode or not GK.char then return end
    local store = GK.Store()
    saved = { char = CopyTable(GK.char), store = CopyTable(store), storeTable = store }
    GK.testMode = true
end

local function PutBack(into, from)
    wipe(into)
    for k, v in pairs(from) do into[k] = v end
end

local function Restore()
    if not GK.testMode then return end
    GK.testMode = false
    if saved then
        PutBack(GK.char, saved.char)
        PutBack(saved.storeTable, saved.store)
        saved = nil
    end
    GK.InvalidateOrders()
    GK.CloseLetters()
    local card = _G.GrudgekeeperProfile
    if card and card:IsShown() then card:Hide() end
    GK.NoticeUpdate(false)
    GK.Changed()
    Say("your record and the guild's are back as they were before the test panel.")
end

-- ---------------------------------------------------------------------------
-- Pretend players
-- ---------------------------------------------------------------------------
local function Enemy(name, class)
    local horde = UnitFactionGroup("player") == "Horde"
    return { key = GK.KeyOf(name), c = class, r = horde and "Human" or "Orc",
        l = math.min(60, (UnitLevel("player") or 1) + 1) }
end

--- Your target when it is an enemy player, else Pølse Hans.
local function TheEnemy()
    local t = GK.ReadUnit("target")
    if t then
        t.unit = "target"
        return t
    end
    return Enemy("Pølse Hans", "ROGUE")
end

local function Guildie(name) return GK.KeyOf(name) end

--- A message from a pretend guildie, through the same reader as a real one.
local function Hear(who, ...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[i] = v == nil and "" or tostring(v)
    end
    GK.ReceiveForTest(nil, table.concat(parts, ";"), "GUILD", Guildie(who))
end

local KARI_ORDER = 901

-- { label } is a heading; { label, fn } a button.
local ACTIONS = {
    { "Letters and the notice" },
    { "Sample letters", function() GK.SampleLetters() end },
    { "Your target is near", function() GK.Warn(GK.Show(TheEnemy().key) .. " is near!", true) end },
    { "Place the letter icon", function() GK.PlaceNotice() end },
    { "Open the window", function() GK.OpenWindow(1) end },

    { "You" },
    { "Kill your target", function() GK.RecordKill(TheEnemy()) end },
    { "Die to your target", function()
        local v = TheEnemy()
        v.spell = "Ambush"
        GK.RecordDeath(v)
    end },
    { "A rampage: 3 of us dead", function()
        -- Gærd Balle kills Kari and Edvard, then you: the third death posts an order by itself
        local v = Enemy("Gærd Balle", "HUNTER")
        Hear("Kari", "D", 1, v.key, v.c, v.r, v.l, GK.Zone(), 1)
        Hear("Edvard", "D", 1, v.key, v.c, v.r, v.l, GK.Zone(), 1)
        v.spell = "Aimed Shot"
        GK.RecordDeath(v)
    end },
    { "You owe a bounty", function()
        -- your own order, fulfilled by Edvard: the Pay bounty button shows at a mailbox
        local o = GK.PostOrder(Enemy("Gærd Balle", "HUNTER"), 50000, "Test: you owe Edvard 5g")
        if o then Hear("Edvard", "F", 1, LIB.Me(), o.id, GK.Zone()) end
    end },

    { "The guild" },
    { "Kari posts an order", function()
        local v, now = TheEnemy(), time()
        Hear("Kari", "C", 1, KARI_ORDER, v.key, v.c, v.r, v.l, v.guid, 200000, now, now + 7 * GK.DAY, "o", nil,
            "Camps the flight master.")
    end },
    { "Edvard adds 5g to it", function() Hear("Edvard", "T", 1, Guildie("Kari"), KARI_ORDER, 50000) end },
    { "Edvard saw them here", function()
        -- A sighting lands only on an open order: without Kari's, nothing is placed, and the line below
        -- used to send you to the map anyway.
        local o = GK.Store().orders[Guildie("Kari") .. "#" .. KARI_ORDER]
        if not (o and o.state == "o") then
            Say("there is no open order to see them for - press Kari posts an order first.")
            return
        end
        local ok, m, x, y = pcall(LIB.MyPosition)
        if not (ok and m) then
            Say("the game gives no map position here (indoors, or an instance).")
            return
        end
        Hear("Edvard", "S", 1, Guildie("Kari"), KARI_ORDER, GK.Zone(), TheEnemy().l, m,
            math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5))
        if not (o.seen and o.seen.m) then
            Say("the sighting didn't land on Kari's order.")
            return
        end
        -- the panel's own Restore takes the order away again, and its seal with it
        Say(("open the map (M): the seal is where you stand (map %d, %.1f, %.1f), for 15 minutes "
            .. "- while this panel stays open."):format(m, x * 100, y * 100))
    end },
    { "Edvard fulfils it", function() Hear("Edvard", "F", 1, Guildie("Kari"), KARI_ORDER, GK.Zone()) end },
    { "Kari and Edvard's scores", function()
        local week = GK.WeekId()
        Hear("Kari", "B", 1, 47, 31, 12, 40, "MAGE", 14, 9, 2, week, 4, 11, 4, 850000,
            Enemy("Pølse Hans").key, 6)
        Hear("Edvard", "B", 1, 23, 15, 20, 38, "WARRIOR", 5, 3, 4, week, 0, 6, 1, 20000,
            Enemy("Gærd Balle").key, 3)
    end },
    { "Mark your target", function()
        local t = GK.ReadUnit("target")
        if not t then
            Say("target an enemy player first; the seal shows over their nameplate (enemy nameplates on: V).")
            return
        end
        GK.PostOrder(t, 0, "Test mark")
    end },

    { "Look" },
    { "Wanted poster", function() GK.ShowPoster(TheEnemy()) end },
    { "Kari's record", function() GK.ShowRecord(Guildie("Kari")) end },
    { "Your record", function() GK.ShowRecord(LIB.Me(), "player") end },
    { "The leaderboard", function() GK.OpenWindow(2) end },

    { "What the game allows" },
    { "Screenshot in 1 second", function()
        C_Timer.After(1, function() pcall(Screenshot) end)
        Say("\"Screen captured\" in a moment means a screenshot works from a timer.")
    end },
    { "Print diagnostics", function() GK.Debug() end },
}
GK.debugActions = ACTIONS    -- for tools/smoke_grudgekeeper.py, which presses every one

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------
local W, BUTTON_W, ROW = 400, 182, 26

local function Build()
    panel = CreateFrame("Frame", "GrudgekeeperDebug", UIParent)
    panel:SetPoint("CENTER", -320, 0)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.03, 0.02, 0.94)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Grudgekeeper test panel")
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 14, -36)
    note:SetWidth(W - 28)
    note:SetJustifyH("LEFT")
    note:SetText("Nothing goes to your guild while this is open. Closing it puts your record and the guild's "
        .. "back as they were (a screenshot taken stays).")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() GK.CloseDebug() end)

    local y, col = -64, 0
    for _, a in ipairs(ACTIONS) do
        if not a[2] then
            if col == 1 then y = y - ROW end
            col = 0
            local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            h:SetPoint("TOPLEFT", 14, y - 6)
            h:SetText(a[1])
            y = y - 26
        else
            local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            b:SetSize(BUTTON_W, 22)
            b:SetPoint("TOPLEFT", 14 + col * (BUTTON_W + 8), y)
            b:SetText(a[1])
            local fn = a[2]
            b:SetScript("OnClick", function()
                local ok, err = pcall(fn)
                if not ok then Say("error: " .. tostring(err)) end
                GK.Changed()
            end)
            col = col + 1
            if col == 2 then
                col = 0
                y = y - ROW
            end
        end
    end
    if col == 1 then y = y - ROW end
    local done = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    done:SetSize(W - 28, 24)
    done:SetPoint("TOPLEFT", 14, y - 10)
    done:SetText("Close and put everything back")
    done:SetScript("OnClick", function() GK.CloseDebug() end)
    panel:SetSize(W, -y + 50)
    panel:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(panel, GK.db, "debugPanel") end
    -- Closing it any way at all - the X, Escape, the big button - puts everything back.
    panel:HookScript("OnHide", Restore)
end

--- /grudge debug: open the test panel, and test mode with it.
function GK.OpenDebug()
    if not GK.char then return end
    if not panel then Build() end
    Begin()
    panel:Show()
    panel:Raise()
    Say("test mode on - nothing goes to your guild until you close the panel.")
end

--- Close the panel and put everything back. (Escape hides it without this call: OnHide restores too.)
function GK.CloseDebug()
    if panel then panel:Hide() end
    Restore()
end

-- A reload or logout with the panel open: put everything back before the game saves it.
LIB.On("PLAYER_LOGOUT", Restore)
