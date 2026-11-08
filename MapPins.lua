-- Grudgekeeper - where the targets of open kill orders were last seen, on the world map and the zone
-- map: the red seal from their nameplates, put where whoever saw them was standing at the time. A
-- nameplate shows only within a few dozen yards, so that is near enough to start looking.
-- Blizzard's map is built for this: data providers are called by the map, and pins come from its own
-- pool. The same way Campfire draws its dots (Campfire/MapPins.lua), including the one trap: the map
-- calls CheckMouseButtonPassthrough on every pin, which uses a call that is protected for addons in
-- Forever, so our pin has its own that does nothing. A closed map costs nothing.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local TEMPLATE = "GrudgekeeperMapPinTemplate"
local PIN_FOR = 15 * 60     -- a sighting older than this is no place to look any more
local MAX_PINS = 30
local SIZE, SIZE_HOVER = 20, 24

--- The pins to draw: every open order whose target was seen in the last 15 minutes at a spot we know.
--- { { o, m, x, y } }, x and y as fractions of map m. Plain data, so the smoke test can ask it.
function GK.MapPinData(now)
    local list = {}
    if not (GK.db and GK.db.mapPins) then return list end
    now = now or time()
    for _, o in pairs(GK.Store().orders) do
        local s = o.seen
        if o.state == "o" and s and s.m and s.x and s.y and now - (s.t or 0) <= PIN_FOR then
            list[#list + 1] = { o = o, m = s.m, x = s.x / 1000, y = s.y / 1000 }
        end
    end
    -- the freshest first, so the cap drops the oldest sightings
    table.sort(list, function(a, b) return (a.o.seen.t or 0) > (b.o.seen.t or 0) end)
    return list
end

--- A spot on map m, on the map being shown: the same map, or converted through world coordinates (a
--- zone sighting shown on its continent). nil when it isn't on this map. As Campfire does it.
local function PositionOnMap(m, x, y, mapID)
    if m == mapID then return x, y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
    if not (ok and continent and world) then return nil end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
    if not (ok2 and pos) then return nil end
    local px, py = pos:GetXY()
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
    return px, py
end

-- ---------------------------------------------------------------------------
-- The pin
-- ---------------------------------------------------------------------------
-- Blizzard's map mixins; without them (a client that lays the map out differently) no pins at all.
GrudgekeeperMapPinMixin = MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

-- See the top of the file: Blizzard's own version calls a protected function in Forever.
function GrudgekeeperMapPinMixin:CheckMouseButtonPassthrough()
end

function GrudgekeeperMapPinMixin:OnLoad()
    pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_GROUP_MEMBER")
    self.ignoreGlobalPinScale = true
    if self.SetScalingLimits then pcall(self.SetScalingLimits, self, 1, 1, 1) end
end

function GrudgekeeperMapPinMixin:Setup(o)
    self.order = o
    self:SetSize(SIZE, SIZE)
end

function GrudgekeeperMapPinMixin:OnMouseEnter()
    local o = self.order
    if not o then return end
    self:SetSize(SIZE_HOVER, SIZE_HOVER)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GK.Show(o.n), 1, 0.3, 0.22)
    local d = GK.Describe(o.l, o.c, o.r, GK.SexOf(o.n, o.sx))
    if d ~= "" then GameTooltip:AddLine(d, 1, 1, 1) end
    local s = o.seen
    if s then
        local by = LIB.IsMyStoredName(s.by) and "you" or GK.Show(s.by)
        GameTooltip:AddLine(("Seen here by %s, %s"):format(by, GK.Ago(s.t)), 0.9, 0.8, 0.6)
    end
    local pot = GK.Pot(o)
    GameTooltip:AddLine(pot > 0 and ("Bounty " .. GK.MoneyText(pot)) or "A kill order for honour", 1, 0.82, 0)
    GameTooltip:AddLine("Click: wanted poster", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function GrudgekeeperMapPinMixin:OnMouseLeave()
    self:SetSize(SIZE, SIZE)
    GameTooltip:Hide()
end

local function Poster(pin)
    local o = pin.order
    if o then GK.ShowPoster({ key = o.n, guid = o.guid, c = o.c, r = o.r, l = o.l }) end
end

-- The map calls one of these depending on its pin code; both do the same.
function GrudgekeeperMapPinMixin:OnMouseClickAction(button)
    if button == "LeftButton" then Poster(self) end
end

function GrudgekeeperMapPinMixin:OnClick(button)
    if button == "LeftButton" then Poster(self) end
end

-- ---------------------------------------------------------------------------
-- The data provider, one per map
-- ---------------------------------------------------------------------------
local providers = {}

local function NewProvider()
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)

    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    end

    function provider:RefreshAllData()
        self:RemoveAllData()
        if not GK.char then return end
        local map = self:GetMap()
        local mapID = map:GetMapID()
        if not mapID then return end
        local drawn = 0
        for _, d in ipairs(GK.MapPinData()) do
            local x, y = PositionOnMap(d.m, d.x, d.y, mapID)
            if x then
                local pin = map:AcquirePin(TEMPLATE)
                pin:Setup(d.o)
                pin:SetPosition(x, y)
                drawn = drawn + 1
                if drawn >= MAX_PINS then break end
            end
        end
    end

    function provider:OnMapChanged()
        MapCanvasDataProviderMixin.OnMapChanged(self)
        self:RefreshAllData()
    end

    return provider
end

--- Redraw every open map: a sighting came in, an order closed.
function GK.RefreshMapPins()
    for canvas, provider in pairs(providers) do
        if canvas:IsShown() then pcall(provider.RefreshAllData, provider) end
    end
end

local function AddTo(canvas)
    if not (canvas and canvas.AddDataProvider) or providers[canvas] then return end
    local provider = NewProvider()
    providers[canvas] = provider
    canvas:AddDataProvider(provider)
    -- A map opened after a quarter of an hour drops the pins that went stale meanwhile. HookScript,
    -- never SetScript: the map has its own OnShow.
    canvas:HookScript("OnShow", function() pcall(provider.RefreshAllData, provider) end)
end

function GK.StartMapPins()
    if not (MapCanvasPinMixin and MapCanvasDataProviderMixin and CreateFromMixins) then return end
    AddTo(WorldMapFrame)
    AddTo(BattlefieldMapFrame)
    if not BattlefieldMapFrame then
        -- The zone map is load-on-demand.
        LIB.On("ADDON_LOADED", function(name)
            if name == "Blizzard_BattlefieldMap" then AddTo(BattlefieldMapFrame) end
        end)
    end
    -- Once per burst of changes (GK.Changed gathers them), and only for a map that is open.
    LIB.Listen("GRUDGEKEEPER_CHANGED", GK.RefreshMapPins)
end
