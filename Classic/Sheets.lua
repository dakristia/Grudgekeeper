-- Grudgekeeper - the Classic look: the two sheets you write on. The kill order sheet (who, the bounty, a
-- line about why) decides which of its three cases it is in with GK.PostPlan and sends with GK.PostSubmit
-- (Post.lua), the same as the parchment one. The note sheet (a note on a player, with a tag for the Watch
-- and Kudos lists) saves with GK.AddNote (Notes.lua).
local ADDON, GK = ...
local C = GK.Classic

local MAX_NOTE = 200

--- An edit box; digits: numeric, at most that many.
local function Box(parent, width, digits)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    if digits then
        e:SetNumeric(true)
        e:SetMaxLetters(digits)
    end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

--- Face, name and description across the top of a sheet's holder.
local function Header(c)
    local h = {}
    h.face = C.Face(c, 48)
    h.face:SetPoint("TOPLEFT", 12, -12)
    h.name = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    h.name:SetPoint("TOPLEFT", h.face.tex, "TOPRIGHT", 10, -4)
    h.name:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    h.name:SetJustifyH("LEFT")
    h.name:SetWordWrap(false)
    h.info = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    h.info:SetPoint("TOPLEFT", h.name, "BOTTOMLEFT", 0, -4)
    h.info:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    h.info:SetJustifyH("LEFT")
    h.info:SetWordWrap(false)
    function h:Set(t)
        self.face:Set(t)
        self.name:SetTextColor(C.ClassColor(t.c))
        self.name:SetText(GK.Show(t.key))
        self.info:SetText(GK.Describe(t.l, t.c, t.r))
    end
    return h
end

-- ---------------------------------------------------------------------------
-- The kill order sheet
-- ---------------------------------------------------------------------------
local post
local target, plan

local function BuildPost()
    local f = C.Frame("GrudgekeeperClassicPost", 380, 330, "Kill order", true)
    local c = CreateFrame("Frame", nil, f.Inset or f)
    c:SetAllPoints()
    f.head = Header(c)
    f.bounty = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.bounty:SetPoint("TOPLEFT", 14, -84)
    f.gold = Box(c, 46, 4)
    f.gold:SetPoint("LEFT", f.bounty, "RIGHT", 20, 0)
    local g = c:CreateTexture(nil, "ARTWORK")
    g:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    g:SetSize(13, 13)
    g:SetPoint("LEFT", f.gold, "RIGHT", 2, 0)
    f.silver = Box(c, 30, 2)
    f.silver:SetPoint("LEFT", g, "RIGHT", 12, 0)
    local s = c:CreateTexture(nil, "ARTWORK")
    s:SetTexture("Interface\\MoneyFrame\\UI-SilverIcon")
    s:SetSize(13, 13)
    s:SetPoint("LEFT", f.silver, "RIGHT", 2, 0)
    f.why = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.why:SetPoint("TOPLEFT", f.bounty, "BOTTOMLEFT", 0, -20)
    f.why:SetText("Why")
    f.note = Box(c, 220, nil)
    f.note:SetMaxLetters(80)
    f.note:SetPoint("LEFT", f.why, "RIGHT", 20, 0)
    f.small = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.small:SetPoint("TOPLEFT", 14, -150)
    f.small:SetPoint("RIGHT", c, "RIGHT", -14, 0)
    f.small:SetJustifyH("LEFT")
    f.small:SetSpacing(3)
    f.seal = C.Button(c, "", 110)
    f.seal:SetPoint("BOTTOMLEFT", 14, 12)
    f.seal:SetScript("OnClick", function()
        local copper = (tonumber(f.gold:GetText()) or 0) * 10000 + (tonumber(f.silver:GetText()) or 0) * 100
        if not GK.PostSubmit(target, copper, f.note:GetText(), plan) then return end
        f:Hide()
        GK.OpenWindow(1)
    end)
    local cancel = C.Button(c, CANCEL or "Cancel", 90)
    cancel:SetPoint("LEFT", f.seal, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function() f:Hide() end)
    post = f
end

C.Wraps.OpenPost = function(_, t)
    if not (t and t.key) then return end
    if not post then BuildPost() end
    target = t
    plan = GK.PostPlan(t)
    post.head:Set(t)
    post:SetTitle(plan.case == "pot" and "Add to the pot" or "Kill order")
    post.bounty:SetText(plan.bounty)
    post.small:SetText(plan.small)
    post.seal:SetText(plan.button)
    post.why:SetShown(plan.asksWhy)
    post.note:SetShown(plan.asksWhy)
    local amount = plan.amount
    post.gold:SetText(amount >= 10000 and tostring(math.floor(amount / 10000)) or "")
    post.silver:SetText(amount % 10000 >= 100 and tostring(math.floor(amount / 100) % 100) or "")
    post.note:SetText(plan.note)
    post:Show()
    post:Raise()
end

-- ---------------------------------------------------------------------------
-- The note sheet
-- ---------------------------------------------------------------------------
local LISTS = {
    kos = { "Kill on sight", 1, 0.3, 0.25 },
    watch = { "Watch", 1, 0.82, 0 },
    kudos = { "Kudos", 0.3, 1, 0.4 },
}

local sheet
local noteTarget, noteList

local function BuildNote()
    local f = C.Frame("GrudgekeeperClassicNote", 380, 310, "Note", true)
    local c = CreateFrame("Frame", nil, f.Inset or f)
    c:SetAllPoints()
    f.head = Header(c)
    f.list = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.list:SetPoint("TOPLEFT", 14, -74)
    f.tagLabel = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.tagLabel:SetPoint("TOPLEFT", f.list, "BOTTOMLEFT", 0, -16)
    f.tagLabel:SetText("Tag")
    f.tag = Box(c, 120, nil)
    f.tag:SetMaxLetters(GK.MAX_TAG)
    f.tag:SetPoint("LEFT", f.tagLabel, "RIGHT", 18, 0)
    -- the tags to pick from: the presets and the ones others use, or write your own in the box
    f.tags = CreateFrame("DropdownButton", nil, c, "WowStyle1DropdownTemplate")
    f.tags:SetWidth(120)
    f.tags:SetPoint("LEFT", f.tag, "RIGHT", 8, 0)
    if f.tags.SetDefaultText then f.tags:SetDefaultText("Pick a tag") end
    if f.tags.SetupMenu then
        f.tags:SetupMenu(function(_, root)
            for _, tag in ipairs(noteList and GK.KnownTags(noteList) or {}) do
                root:CreateButton(GK.TagText(tag), function() f.tag:SetText(tag) end)
            end
            root:CreateButton("No tag", function() f.tag:SetText("") end)
        end)
    end
    f.textLabel = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.textLabel:SetPoint("TOPLEFT", f.tagLabel, "BOTTOMLEFT", 0, -22)
    f.textLabel:SetText("Note")
    f.text = Box(c, 280, nil)
    f.text:SetMaxLetters(MAX_NOTE)
    f.text:SetPoint("TOPLEFT", f.textLabel, "BOTTOMLEFT", 6, -6)
    f.hint = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", -6, -8)
    f.hint:SetPoint("RIGHT", c, "RIGHT", -14, 0)
    f.hint:SetJustifyH("LEFT")
    f.save = C.Button(c, SAVE or "Save", 100)
    f.save:SetPoint("BOTTOMLEFT", 14, 12)
    f.save:SetScript("OnClick", function()
        local text, tag = strtrim(f.text:GetText() or ""), strtrim(f.tag:GetText() or "")
        local row, why = GK.AddNote(noteTarget.key, text, tag ~= "" and tag or nil, noteList,
            { c = noteTarget.c, r = noteTarget.r, rf = noteTarget.rf, sx = noteTarget.sx, l = noteTarget.l })
        if not row then
            print(GK.TAG .. ": " .. (why or "the note couldn't be saved."))
            return
        end
        f:Hide()
    end)
    local cancel = C.Button(c, CANCEL or "Cancel", 90)
    cancel:SetPoint("LEFT", f.save, "RIGHT", 8, 0)
    cancel:SetScript("OnClick", function() f:Hide() end)
    sheet = f
end

--- A note on a player. t = { key, c, r, rf, sx, l, unit }; list: "kos", "watch" or "kudos" - the list the
--- player is put on with it. Only the Watch and Kudos lists have tags.
C.Wraps.OpenNoteSheet = function(_, t, list)
    if not (t and t.key) then return end
    if not sheet then BuildNote() end
    noteTarget, noteList = t, list
    sheet.head:Set(t)
    local info = LISTS[list] or LISTS.kos
    sheet.list:SetText(info[1])
    sheet.list:SetTextColor(info[2], info[3], info[4])
    sheet.hint:SetText(list == "kos" and "Goes on the Kill on sight list." or ("Puts them on the " .. info[1] .. " list."))
    local tagged = list == "watch" or list == "kudos"
    sheet.tagLabel:SetShown(tagged)
    sheet.tag:SetShown(tagged)
    sheet.tags:SetShown(tagged)
    sheet.tag:SetText("")
    sheet.text:SetText("")
    if sheet.tags.GenerateMenu then sheet.tags:GenerateMenu() end
    sheet:Show()
    sheet:Raise()
end
