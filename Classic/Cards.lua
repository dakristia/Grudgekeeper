-- Grudgekeeper - the Classic look: cards. A card table (Profile.lua: title, name, info, lines, big, caption,
-- seal, blood, buttons, c, rf, sx, key, unit) drawn in standard frames - by the window's detail panel, by
-- the Inspect page, and here as the small card a poster, a record or any GK.ShowCard opens.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local C = GK.Classic

--- A card's contents, in a frame of their own: view:Fill(d, refill). refill is called after one of the
--- card's buttons has run. Anchor it, or SetAllPoints it, in whatever holds it.
function C.CardView(parent)
    local v = CreateFrame("Frame", nil, parent)
    v.face = C.Face(v, 56)
    v.face:SetPoint("TOPLEFT", 12, -12)
    v.title = v:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    v.title:SetPoint("TOPLEFT", v.face.tex, "TOPRIGHT", 10, -2)
    v.title:SetPoint("RIGHT", v, "RIGHT", -12, 0)
    v.title:SetJustifyH("LEFT")
    v.title:SetWordWrap(false)
    v.name = v:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    v.name:SetPoint("TOPLEFT", v.title, "BOTTOMLEFT", 0, -3)
    v.name:SetPoint("RIGHT", v, "RIGHT", -12, 0)
    v.name:SetJustifyH("LEFT")
    v.name:SetWordWrap(false)
    v.info = v:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    v.info:SetPoint("TOPLEFT", v.name, "BOTTOMLEFT", 0, -3)
    v.info:SetPoint("RIGHT", v, "RIGHT", -12, 0)
    v.info:SetJustifyH("LEFT")
    v.info:SetWordWrap(false)
    v.big = v:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    v.big:SetPoint("TOPLEFT", 12, -80)
    v.caption = v:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    v.caption:SetPoint("BOTTOMLEFT", v.big, "BOTTOMRIGHT", 6, 3)
    v.rule = v:CreateTexture(nil, "ARTWORK")
    v.rule:SetColorTexture(1, 1, 1, 0.15)
    v.rule:SetHeight(1)
    v.rule:SetPoint("TOPLEFT", 12, -114)
    v.rule:SetPoint("TOPRIGHT", -12, -114)
    v.body = v:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    v.body:SetPoint("TOPLEFT", 12, -124)
    v.body:SetPoint("RIGHT", v, "RIGHT", -12, 0)
    v.body:SetJustifyH("LEFT")
    v.body:SetJustifyV("TOP")
    v.body:SetSpacing(5)
    v.buttons = {}
    for i = 1, 2 do
        local b = C.Button(v, "", 140)
        if i == 1 then b:SetPoint("BOTTOMLEFT", 12, 10) else b:SetPoint("LEFT", v.buttons[1], "RIGHT", 6, 0) end
        v.buttons[i] = b
    end

    function v:Fill(d, refill)
        self.face:Set(d)
        local gold, red = C.GOLD, C.RED
        local tc = d.seal == "mark" and red or gold
        self.title:SetTextColor(tc[1], tc[2], tc[3])
        self.title:SetText(d.title or "")
        if d.blood then
            self.name:SetTextColor(red[1], red[2], red[3])
        else
            self.name:SetTextColor(C.ClassColor(d.c))
        end
        self.name:SetText(d.name or "")
        self.info:SetText(d.info or "")
        self.big:SetText(d.big or "")
        self.caption:SetText(d.caption or "")
        self.body:SetText(C.FormatLines(d.lines))
        for i, b in ipairs(self.buttons) do
            local spec = d.buttons and d.buttons[i]
            b:SetShown(spec ~= nil)
            if spec then
                b:SetText(spec[1])
                b:SetScript("OnClick", function()
                    spec[2]()
                    if refill then refill() end
                end)
            end
        end
    end
    return v
end

-- ---------------------------------------------------------------------------
-- The small card
-- ---------------------------------------------------------------------------
local frame, view
local showing           -- { poster = t } or { record = key, unit = unit } or { make = fn }

local Refill

local function Build()
    frame = C.Frame("GrudgekeeperClassicCard", 380, 360, "Grudgekeeper", true)
    view = C.CardView(frame.Inset or frame)
    view:SetAllPoints()
end

local function Open(d)
    if not frame then Build() end
    view:Fill(d, Refill)
    frame:Show()
    frame:Raise()
    GK.Sound("IG_ABILITY_PAGE_TURN")
end

--- The card as it stands now, after a button or a change in the data; it closes if there is nothing to show.
Refill = function()
    if not (frame and frame:IsShown() and showing) then return end
    local d
    if showing.make then d = showing.make()
    elseif showing.poster then d = GK.PosterCard(showing.poster)
    else d = GK.RecordCard(showing.record, showing.unit) end
    if d then view:Fill(d, Refill) else frame:Hide() end
end

C.Wraps.ShowPoster = function(_, t)
    if not (t and t.key) then return end
    showing = { poster = t }
    Open(GK.PosterCard(t))
end

C.Wraps.ShowRecord = function(_, key, unit)
    local d = GK.RecordCard(key, unit)
    if not d then return end
    showing = { record = d.key, unit = unit }
    Open(d)
end

C.Wraps.ShowCard = function(_, make)
    local d = make()
    if not d then return end
    showing = { make = make }
    Open(d)
end

LIB.Listen("GRUDGEKEEPER_CHANGED", Refill)

-- ---------------------------------------------------------------------------
-- The Inspect window's page (Inspect.lua): its own card laid over the ledger's, for as long as the look
-- is classic. The ledger's page is built as ever (BuildCardPage) and hidden under ours.
-- ---------------------------------------------------------------------------
C.Always.BuildCardPage = function(original, page, layout, refill)
    original(page, layout, refill)
    local cover = CreateFrame("Frame", nil, page)
    cover:SetAllPoints()
    cover:SetFrameLevel(page:GetFrameLevel() + 20)
    cover:EnableMouse(true)
    local bg = cover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background", "REPEAT", "REPEAT")
    cover.view = C.CardView(cover)
    cover.view:SetAllPoints()
    cover.refill = refill
    cover:Hide()
    page.classic = cover
end

C.Always.FillCardPage = function(original, page, d)
    local cover = page.classic
    if cover and GK.IsClassic() then
        cover:Show()
        cover.view:Fill(d, cover.refill)
        return
    end
    if cover then cover:Hide() end
    original(page, d)
end
