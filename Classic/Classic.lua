-- Grudgekeeper - the Classic look: Guild Grudge's own style, in the game's standard frames, as a setting
-- (GK.db.look = "classic"; the ledger is the default and stays exactly as it is while the setting is off).
-- While it is on, every surface is replaced: the window, the small cards, the letters, the letter icon,
-- the kill order sheet, the note sheet and the Inspect tab's page. The ledger's own frames are never
-- drawn then, and none of its code is edited for it: the files here wrap the GK.* functions that open
-- or fill a surface (H7 in docs/guild-grudge-merge.md), at PLAYER_LOGIN so they are the outermost wrapper,
-- and each wrapper calls the original whenever the look is the ledger.
--   Classic.lua   this file: the setting, the wrapping, and the pieces every surface shares
--   Cards.lua     the card view and the small cards (poster, record)
--   Window.lua    the window
--   Letters.lua   the letters
--   Notice.lua    the letter icon and the warning flash
--   Sheets.lua    the kill order sheet and the note sheet
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local C = {}
GK.Classic = C

C.MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
C.ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"
C.MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
C.GOLD = { 1, 0.82, 0 }
C.RED = { 1, 0.3, 0.25 }

--- The classic version of each wrapped function: C.Wraps.Name = function(original, ...). Other files of
--- the look add theirs as they load; Apply wraps GK.Name with them at login.
C.Wraps = {}
--- The same, for functions that serve both looks themselves (the Inspect page): always called.
C.Always = {}
--- Every frame of the look, so the ledger coming back can hide them.
C.frames = {}
--- The ledger's frames by global name, hidden when the look changes to classic. A file that adds a ledger
--- frame of its own adds its name here.
C.LedgerFrames = { "GrudgekeeperFrame", "GrudgekeeperLetter", "GrudgekeeperNote", "GrudgekeeperProfile",
    "GrudgekeeperPost", "GrudgekeeperNotice", "GrudgekeeperNoteSheet" }

function GK.IsClassic() return GK.db ~= nil and GK.db.look == "classic" end

--- A class's colour as r, g, b; the gold of a name nobody knows.
function C.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return C.GOLD[1], C.GOLD[2], C.GOLD[3]
end

--- A tooltip on a frame. HookScript keeps the handlers the template already set.
function C.Tip(frame, text)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

--- A standard button.
function C.Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text or "")
    return b
end

--- The game's own frame, the way Guild Grudge's window is made: ButtonFrameTemplate, a title, a portrait,
--- dragged by its body, Escape closes it. noBar: no button bar along the bottom (the cards and sheets).
function C.Frame(name, width, height, title, noBar)
    local f = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetTitle then f:SetTitle(title or "Grudgekeeper") end
    if f.SetPortraitToAsset then f:SetPortraitToAsset(C.ICON) end
    -- icon files carry their own border: crop it to sit centred in the round mask
    if f.SetPortraitTexCoord then f:SetPortraitTexCoord(0.08, 0.92, 0.08, 0.92) end
    if noBar and ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    -- our own Hide, so closing works in combat too
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    tinsert(UISpecialFrames, name)
    f:Hide()
    C.frames[#C.frames + 1] = f
    return f
end

--- A round face: whoever a card or a row is about. Their live portrait while the unit it was opened from
--- is still them; else their race's portrait when we know race and sex, with their class as a badge;
--- else their class crest; else a question mark. Face:Set(d) with d = { c, rf, sx, key, unit }.
function C.Face(parent, size)
    local face = {}
    face.tex = parent:CreateTexture(nil, "ARTWORK")
    face.tex:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(C.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(face.tex)
    face.tex:AddMaskTexture(mask)
    face.badge = parent:CreateTexture(nil, "OVERLAY")
    face.badge:SetSize(size * 0.42, size * 0.42)
    face.badge:SetPoint("CENTER", face.tex, "BOTTOMRIGHT", -size * 0.1, size * 0.1)
    function face:SetPoint(...) self.tex:SetPoint(...) end
    function face:SetShown(on)
        self.tex:SetShown(on)
        if not on then self.badge:Hide() end
    end
    function face:Set(d)
        d = d or {}
        local coords = d.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.c]
        local shown = false
        if d.unit and SetPortraitTexture and UnitExists(d.unit) then
            local key = LIB.UnitKey(d.unit)
            if key and d.key and GK.SameName(key, d.key) then shown = pcall(SetPortraitTexture, self.tex, d.unit) end
        end
        if shown then
            self.tex:SetTexCoord(0, 1, 0, 1)
        else
            local kind = GK.SetPortrait(self.tex, d)
            shown = kind == "race"
            if kind == "seal" then
                self.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                self.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
        self.badge:SetShown(shown and coords and true or false)
        if shown and coords then
            self.badge:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            self.badge:SetTexCoord(unpack(coords))
        end
    end
    return face
end

--- Lines of a card as one text: a short "Label: value" gets its label in gold, anything else is a paragraph.
function C.FormatLines(lines)
    local out = {}
    for i, line in ipairs(lines or {}) do
        local label, value = line:match("^([^:,]+): (.+)$")
        if label and #label <= 14 then
            out[i] = ("|cffffd100%s:|r %s"):format(label, value)
        else
            out[i] = line
        end
    end
    return table.concat(out, "\n")
end

--- Switch the look, hiding every open frame of the one that goes. The letter icon follows at once.
function C.SetLook(look)
    GK.db.look = look
    if look == "classic" then
        for _, name in ipairs(C.LedgerFrames) do
            local f = _G[name]
            if f and f.Hide then f:Hide() end
        end
    else
        for _, f in ipairs(C.frames) do f:Hide() end
    end
    if GK.char then GK.NoticeUpdate(false) end
end

--- Wrap every GK.Name that has a classic version. Once, at login, after every file has loaded.
local function Apply()
    for name, fn in pairs(C.Wraps) do
        local original = GK[name]
        if original then
            GK[name] = function(...)
                if GK.IsClassic() then return fn(original, ...) end
                return original(...)
            end
        end
    end
    for name, fn in pairs(C.Always) do
        local original = GK[name]
        if original then GK[name] = function(...) return fn(original, ...) end end
    end
    -- /grudge classic switches the look; everything else is the original's
    local slash = SlashCmdList.GRUDGEKEEPER
    SlashCmdList.GRUDGEKEEPER = function(msg)
        if strtrim((msg or ""):lower()) == "classic" then
            C.SetLook(GK.IsClassic() and "ledger" or "classic")
            print(GK.TAG .. ": the " .. (GK.IsClassic() and "Classic" or "ledger") .. " look is on.")
            return
        end
        return slash(msg)
    end
    -- the ledger's letter icon was built at login, before the wrapper: hand it over
    if GK.IsClassic() and GK.char then
        local old = _G.GrudgekeeperNotice
        if old then old:Hide() end
        GK.NoticeUpdate(false)
    end
end

C.Apply = Apply                  -- for the tests, which load the files after the login has fired
LIB.On("PLAYER_LOGIN", Apply)

-- ---------------------------------------------------------------------------
-- The setting
-- ---------------------------------------------------------------------------
table.insert(GK.OptionSections, function(f, anchor, h)
    local head = h.Section(anchor, "Look")
    local box = h.Box(head, "Classic look (Guild Grudge's standard game frames)",
        "Off by default, which keeps the ledger. On, every Grudgekeeper surface is drawn in the game's own "
        .. "frames instead: the window with tabs, a search box and a detail panel, the cards, the letters, "
        .. "the letter icon, and the sheets for kill orders and notes. Nothing about the data changes. "
        .. "/grudge classic switches it too.", function(on)
            C.SetLook(on and "classic" or "ledger")
        end)
    box:SetChecked(GK.IsClassic())
    box:SetScript("OnShow", function(self) self:SetChecked(GK.IsClassic()) end)
    return box
end)
