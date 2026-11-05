-- A permissive stand-in for the game's frames, enough to build the Classic look's windows outside the
-- game and click through them. Every method a frame is asked for exists and answers itself, so the code
-- under test runs to the end; what the tests look at is what it stored (text, shown, scripts) and what
-- the data it showed said. It checks nothing about the real API: a call the game would refuse passes here.
local M = {}

local Obj = {}
local methods = {}

local function new(kind, name, parent, template)
    local o = setmetatable({ kind = kind, name = name, parent = parent, template = template, shown = false,
        scripts = {}, hooks = {}, children = {} }, Obj)
    if name then _G[name] = o end
    if parent and type(parent) == "table" and parent.children then parent.children[#parent.children + 1] = o end
    return o
end

Obj.__index = function(o, k)
    local m = methods[k]
    if m then return m end
    -- fields the game's templates put on a frame
    if k == "Inset" or k == "CloseButton" then
        if o.template == "ButtonFrameTemplate" then
            local child = new("Frame", nil, o, "InsetFrameTemplate")
            rawset(o, k, child)
            return child
        end
        return nil
    end
    if k == "Text" or k == "Icon" then return nil end
    if k:match("^[A-Z]") then
        return function(self, ...) return self end
    end
    return nil
end

local function set(k, fn) methods[k] = fn end

set("SetText", function(o, t) o.text = t end)
set("GetText", function(o) return o.text or "" end)
set("Show", function(o) o.shown = true if o.scripts.OnShow then o.scripts.OnShow(o) end end)
set("Hide", function(o) o.shown = false if o.scripts.OnHide then o.scripts.OnHide(o) end end)
set("IsShown", function(o) return o.shown end)
set("SetShown", function(o, on) if on then o:Show() else o.shown = false end end)
set("IsVisible", function(o) return o.shown end)
set("SetChecked", function(o, on) o.checked = on and true or false end)
set("GetChecked", function(o) return o.checked end)
set("SetEnabled", function(o, on) o.enabled = on and true or false end)
set("IsEnabled", function(o) return o.enabled ~= false end)
set("SetScript", function(o, k, fn) o.scripts[k] = fn end)
set("GetScript", function(o, k) return o.scripts[k] end)
set("HookScript", function(o, k, fn) o.hooks[k] = fn end)
set("GetFrameLevel", function() return 1 end)
set("GetStringWidth", function() return 40 end)
set("GetUnboundedStringWidth", function() return 40 end)
set("GetStringHeight", function() return 12 end)
set("GetWidth", function() return 100 end)
set("GetHeight", function() return 100 end)
set("GetPoint", function() return "CENTER", nil, "CENTER", 0, 0 end)
set("IsPlaying", function() return false end)
set("GetID", function(o) return o.id end)
set("SetID", function(o, id) o.id = id end)
set("LockHighlight", function(o) o.locked = true end)
set("UnlockHighlight", function(o) o.locked = false end)
set("GetParent", function(o) return o.parent end)
set("Raise", function() end)
set("SetTexture", function(o, t) o.texture = t end)
set("GetNormalTexture", function(o) return o end)
set("SetupMenu", function(o, fn) o.menu = fn end)
set("SetDataProvider", function(o, dp)
    o.provided = dp.items
    o.rows = {}
    for i, el in ipairs(dp.items) do
        local row = new("Button", nil, o)
        o.rows[i] = row
        o.view.init(row, el)
    end
end)
set("ForEachFrame", function(o, fn) for _, row in ipairs(o.rows or {}) do fn(row) end end)
set("CreateFontString", function(o) return new("FontString", nil, o) end)
set("CreateTexture", function(o) return new("Texture", nil, o) end)
set("CreateMaskTexture", function(o) return new("Texture", nil, o) end)
set("CreateAnimationGroup", function(o) return new("AnimationGroup", nil, o) end)
set("CreateAnimation", function(o) return new("Animation", nil, o) end)

--- Put the stand-ins in _G. Returns a list of every frame made, for the tests to look through.
function M.install()
    local made = {}
    _G.CreateFrame = function(kind, name, parent, template)
        local o = new(kind, name, parent, template)
        made[#made + 1] = o
        return o
    end
    _G.UIParent = new("Frame", "UIParent")
    _G.UISpecialFrames = {}
    _G.tinsert = table.insert
    _G.unpack = unpack
    _G.GameTooltip = new("Frame", "GameTooltip")
    _G.CLASS_ICON_TCOORDS = { MAGE = { 0, 1, 0, 1 }, ROGUE = { 0, 1, 0, 1 } }
    _G.RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 0.94 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    _G.InCombatLockdown = function() return false end
    _G.PanelTemplates_SetNumTabs = function(f, n) f.numTabs = n end
    _G.PanelTemplates_SetTab = function(f, i) f.selectedTab = i end
    _G.ScrollBoxConstants = { RetainScrollPosition = true }
    _G.CreateDataProvider = function()
        local dp = { items = {} }
        function dp:Insert(el) self.items[#self.items + 1] = el end
        return dp
    end
    _G.CreateScrollBoxListLinearView = function()
        local v = {}
        function v:SetElementExtent() end
        function v:SetElementInitializer(_, fn) self.init = fn end
        return v
    end
    _G.ScrollUtil = {
        InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end,
        AddManagedScrollBarVisibilityBehavior = function() end,
    }
    _G.SOUNDKIT = nil
    _G.C_Texture = nil
    _G.SetPortraitTexture = nil
    _G.UnitExists = function() return false end
    _G.ButtonFrameTemplate_HideButtonBar = function() end
    _G.CANCEL, _G.SAVE, _G.SETTINGS = "Cancel", "Save", "Settings"
    return made
end

--- Click a frame the way the game would.
function M.click(o, button)
    local fn = o.scripts.OnClick
    assert(fn, "nothing to click")
    fn(o, button or "LeftButton")
end

--- Every frame under `root` (a frame made by CreateFrame), depth first.
function M.walk(root, fn)
    fn(root)
    for _, c in ipairs(root.children) do M.walk(c, fn) end
end

return M
