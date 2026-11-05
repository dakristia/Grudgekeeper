-- Grudgekeeper - the Classic look: letters. One standard frame for the pile, whichever kind the letter is:
-- GK.LetterContent (Letters.lua) says what it contains - title, name, lines, buttons - and this draws it,
-- with a pager along the bottom. The parchment scroll, the small note and the stamp slamming down stay
-- with the ledger; here the stamp is a word in red.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local C = GK.Classic

local STAMPS = { stamp_fulfilled = "FULFILLED", stamp_paid = "PAID" }

local frame
local index                -- which letter in the pile is showing

local function Build()
    frame = C.Frame("GrudgekeeperClassicLetter", 420, 380, "Letters", true)
    local c = CreateFrame("Frame", nil, frame.Inset or frame)
    c:SetAllPoints()
    frame.c = c
    frame.face = C.Face(c, 56)
    frame.face:SetPoint("TOPLEFT", 12, -12)
    frame.title = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame.face.tex, "TOPRIGHT", 10, -2)
    frame.title:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.name = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.name:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.name:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)
    frame.info = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.info:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -3)
    frame.info:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    frame.info:SetJustifyH("LEFT")
    frame.info:SetWordWrap(false)
    local rule = c:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.15)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 12, -82)
    rule:SetPoint("TOPRIGHT", -12, -82)
    frame.body = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.body:SetPoint("TOPLEFT", 12, -92)
    frame.body:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetJustifyV("TOP")
    frame.body:SetSpacing(4)
    frame.foot = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.foot:SetPoint("BOTTOMLEFT", 12, 44)
    frame.stamp = c:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    frame.stamp:SetPoint("BOTTOMRIGHT", -12, 44)
    frame.stamp:SetTextColor(C.RED[1], C.RED[2], C.RED[3])
    frame.buttons = {}
    for i = 1, 2 do
        local b = C.Button(c, "", 130)
        if i == 1 then b:SetPoint("BOTTOMLEFT", 12, 10) else b:SetPoint("LEFT", frame.buttons[1], "RIGHT", 6, 0) end
        frame.buttons[i] = b
    end
    -- "2 of 5" with arrows either side, bottom right
    frame.next = C.Button(c, ">", 28)
    frame.next:SetPoint("BOTTOMRIGHT", -12, 10)
    frame.next:SetScript("OnClick", function() GK.ShowLetter(index + 1) end)
    frame.page = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.page:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
    frame.prev = C.Button(c, "<", 28)
    frame.prev:SetPoint("RIGHT", frame.page, "LEFT", -8, 0)
    frame.prev:SetScript("OnClick", function() GK.ShowLetter(index - 1) end)
end

local function Fill(L)
    local d = GK.LetterContent(L)
    frame.face:Set({ c = d.c, rf = d.rf, sx = d.sx, key = d.key })
    local tc = d.blood and C.RED or C.GOLD
    frame.title:SetTextColor(tc[1], tc[2], tc[3])
    frame.title:SetText(d.title or "")
    frame.name:SetText(d.name or "")
    frame.info:SetText(d.info or "")
    frame.body:SetText(table.concat(d.lines, "\n"))
    frame.foot:SetText(d.foot or "")
    frame.stamp:SetText(d.stamp and STAMPS[d.stamp] or "")
    for i, b in ipairs(frame.buttons) do
        local spec = d.buttons[i]
        b:SetShown(spec ~= nil)
        if spec then
            b:SetText(spec[1])
            b:SetEnabled(not d.sample)
            b:SetScript("OnClick", function()
                spec[2]()
                Fill(L)
            end)
        end
    end
    local n = #GK.char.letters
    frame.page:SetText(("%d of %d"):format(index, n))
    frame.prev:SetEnabled(index > 1)
    frame.next:SetEnabled(index < n)
end

--- Show letter i of the pile. Reading it marks it read.
C.Wraps.ShowLetter = function(_, i)
    local list = GK.char.letters
    if #list == 0 then
        GK.CloseLetters()
        return
    end
    if not frame then Build() end
    index = math.max(1, math.min(i or #list, #list))
    local L = list[index]
    L.read = true
    GK.Sound("IG_ABILITY_PAGE_TURN")
    Fill(L)
    frame:Show()
    frame:Raise()
    GK.NoticeUpdate(false)
    GK.Changed()
end

--- Open the pile at the first unread letter (or the newest).
C.Wraps.OpenLetters = function()
    local list = GK.char.letters
    if #list == 0 then
        print(GK.TAG .. ": no letters. Kill orders from your guild, and your own kills and deaths, arrive here.")
        return
    end
    local _, first = GK.Unread()
    GK.ShowLetter(first or #list)
end

C.Wraps.CloseLetters = function()
    if frame then frame:Hide() end
end

-- An open letter follows changes to its order (taken, paid, closed).
LIB.Listen("GRUDGEKEEPER_CHANGED", function()
    if not (GK.IsClassic() and frame and frame:IsShown() and index) then return end
    local L = GK.char.letters[index]
    if L then Fill(L) end
end)
