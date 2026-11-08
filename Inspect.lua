-- Grudgekeeper - a tab of our own on the game's Inspect window. Inspect a guildie and a tab below
-- Blizzard's own opens their page of the ledger - title and points, their week, streak, nemesis -
-- inside the Inspect window, not in a window of ours (the owner's idea, 2026-11-05). An enemy player,
-- if the game lets you inspect one, gets their wanted poster, and the tab glows while there is an order
-- on them. Anyone else - no guildie, no enemy - gets no tab, as the game shows no Guild tab for a
-- player without a guild: the Grudgekeeper has nothing to say about them.
--
-- How it sits in Blizzard's window: the tab and the page are frames of ours, parented to the Inspect
-- frame, and nothing of Blizzard's is replaced or written to. We follow it with hooksecurefunc - one of
-- Blizzard's tabs chosen hides our page, a new unit re-lays our tab - and HookScript. The one thing we
-- do to it: while our page is up, the game's own page under it is hidden (its item slots drew over a
-- page laid on top), and shown again when ours goes - unless one of the game's tabs was chosen, which
-- shows its own. The window loads on demand (Blizzard_InspectUI), so all of this waits for it.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
-- The ledger's card laid out for the Inspect window's inside, about 332 x 395 units, at the ledger's
-- own type sizes (see DETAIL in Window.lua).
local LAYOUT = { w = 332, face = 78, faceX = 58, faceY = 64, bigY = 108, bigSize = 24, titleX = 110,
    titleY = 32, titleSize = 22, seal = 40, sealX = 18, sealY = 24, ruleY = 158, linesY = 168, padX = 20,
    valueX = 112, signY = 44, buttonY = 14 }

local tab, page

--- The unit the Inspect window is showing, read from Blizzard's frame (never written).
local function Unit()
    local f = InspectFrame
    if not f then return nil end
    local unit
    if f.GetInspectUnit then unit = f:GetInspectUnit() else unit = f.unit end
    return type(unit) == "string" and unit or nil
end

local function Plain(v)
    if v ~= nil and not GK.Secret(v) then return v end
    return nil
end

local function Guildie(unit)
    local mine = Plain((GetGuildInfo("player")))
    local theirs = Plain((GetGuildInfo(unit)))
    return mine ~= nil and theirs == mine
end

--- What our tab shows for a unit: the card, and whether there is an order on them (the tab glows); nil
--- when the Grudgekeeper has nothing to say. A guildie with no score yet still gets a page: it says so,
--- which is the one way to see that a guildie hasn't got Grudgekeeper.
function GK.InspectCard(unit)
    if type(unit) ~= "string" or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    local t = GK.ReadUnit(unit)                       -- an enemy player we can tell apart
    if t then
        t.unit = unit
        return GK.PosterCard(t), GK.OrderOn(t.key, t.guid) ~= nil
    end
    local key = GK.UnitKey(unit)
    if not key then return nil end
    local d
    if GK.HasRecord(key) then
        d = GK.RecordCard(key, unit)
    elseif Guildie(unit) then
        local _, class = UnitClass(unit)
        class = Plain(class)
        local race = Plain((UnitRace(unit)))
        local sex = Plain(UnitSex(unit))
        if sex ~= 2 and sex ~= 3 then sex = nil end
        d = { key = key, unit = unit, c = class, title = GK.Show(key), name = "No score yet",
            info = GK.Describe(Plain(UnitLevel(unit)), class, race and GK.Clean(race, 20), sex), buttons = {},
            lines = { "The Grudgekeeper has heard nothing from them. A guildie's score reaches you from their "
                .. "own Grudgekeeper - if they have one." } }
    end
    if not d then return nil end
    -- their face: from the score when it brought one, else from the player in front of you
    local _, raceFile = UnitRace(unit)
    d.rf = d.rf or Plain(raceFile)
    d.sx = d.sx or Plain(UnitSex(unit))
    return d, false
end

-- The game's own page (paper doll, PvP or guild) we hid under ours. Laid over it, ours lost to the item
-- slots, which drew on top of it (the owner's screenshot, 2026-11-05) - so it is hidden, the way the
-- game's own tabs do it, and given back when ours goes.
local hidden

local function Close()
    if page then page:Hide() end
    if tab then tab:SetChecked(false) end
    if hidden then
        -- With the window closed this only marks it shown: its own OnShow runs when the window opens next.
        hidden:Show()
        hidden = nil
    end
end

-- One of the game's tabs was chosen: InspectSwitchTabs has hidden and shown its pages itself, so there is
-- nothing to give back - showing ours again would put two pages up at once.
local function Switched()
    hidden = nil
    Close()
end

local function BlizzardTabs()
    local modeTabs = InspectFrame and InspectFrame.ModeTabs
    return modeTabs and modeTabs.Tabs or {}
end

--- Our tab's place (below the last of Blizzard's that is shown: the Guild tab comes and goes), whether
--- it shows for this unit, its glow, and the page if it is open.
local function Update()
    if not tab then return end
    local last
    for _, t in ipairs(BlizzardTabs()) do
        if t:IsShown() then last = t end
    end
    tab:ClearAllPoints()
    if last then
        tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT")
    else
        tab:SetPoint("TOPLEFT", InspectFrame, "TOPRIGHT", -2, -60)
    end
    local d, wanted
    if GK.db and GK.db.inspectTab ~= false and GK.char then d, wanted = GK.InspectCard(Unit()) end
    tab:SetShown(d ~= nil)
    if tab.SetTabGlowAnimationPlaying then tab:SetTabGlowAnimationPlaying(wanted == true) end
    if page:IsShown() then
        if d then GK.FillCardPage(page, d) else Close() end
    end
end

local function Open()
    local d = GK.db and GK.char and GK.InspectCard(Unit())
    if not d then return end
    GK.FillCardPage(page, d)
    -- Blizzard's chosen tab stops looking chosen while ours is; choosing one of theirs puts it back
    -- (InspectSwitchTabs, hooked below).
    for _, t in ipairs(BlizzardTabs()) do t:SetChecked(false) end
    tab:SetChecked(true)
    for _, name in ipairs(INSPECTFRAME_SUBFRAMES or {}) do
        local f = _G[name]
        if f and f ~= hidden and f:IsShown() then
            f:Hide()
            hidden = f
        end
    end
    page:Show()
end

local function Build()
    if tab or not InspectFrame then return end
    local ok, t = pcall(CreateFrame, "Frame", nil, InspectFrame.ModeTabs or InspectFrame, "LargeSideTabButtonTemplate")
    if not ok or not t then return end            -- a client without the side tabs: no tab, nothing broken
    tab = t
    tab.tooltipText = "Grudgekeeper"
    tab.Icon:SetTexture(MEDIA .. "icon")
    -- the icon as big as Blizzard's own: the template leaves its size to the window (Forever's XML)
    local ref = BlizzardTabs()[1]
    local w, h = 0, 0
    if ref and ref.Icon then w, h = ref.Icon:GetSize() end
    if (w or 0) > 0 then tab.Icon:SetSize(w, h) else tab.Icon:SetSize(34, 34) end
    tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
        if button == "LeftButton" and upInside then Open() end
    end)
    tab:SetChecked(false)

    page = CreateFrame("Frame", nil, InspectFrame)
    -- Over the paper doll and its model; under the window's border, portrait and title (frame levels 400
    -- and up in Blizzard's templates), so those still frame our page.
    page:SetFrameLevel(InspectFrame:GetFrameLevel() + 40)
    page:SetPoint("TOPLEFT", 3, -26)
    page:SetPoint("BOTTOMRIGHT", -3, 3)
    page:EnableMouse(true)                         -- the item slots under it answer no hover
    local paper = page:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(MEDIA .. "sheet")
    GK.Tone(paper)
    GK.BuildCardPage(page, LAYOUT, Update)
    page:Hide()

    hooksecurefunc("InspectSwitchTabs", Switched)  -- one of Blizzard's tabs was chosen
    if InspectFrame.UpdateTabs then hooksecurefunc(InspectFrame, "UpdateTabs", Update) end   -- a new unit
    InspectFrame:HookScript("OnShow", Update)
    InspectFrame:HookScript("OnHide", Close)
    LIB.Listen("GRUDGEKEEPER_CHANGED", function()
        if InspectFrame:IsShown() then Update() end
    end)
    Update()
end

function GK.StartInspect()
    if InspectFrame then
        Build()
        return
    end
    LIB.On("ADDON_LOADED", function(name)
        if name == "Blizzard_InspectUI" then Build() end
    end)
end
