-- Grudgekeeper - the who-picker: who a page's own action is for. The ledger's "Post a kill order",
-- "Mark someone", "Put someone on Shame" and "Give someone kudos" open it, and so does /grudge post with
-- no enemy targeted (it used to do nothing but print a line: "trykke post a kill order gjør ingenting
-- fordi man må ha et target", the owner, 2026-11-06).
-- A small window with a name box and the people you most likely mean: your target, then for Shame and
-- Kudos your group and whoever left it lately, for a kill order or a mark the enemies seen in the last
-- 15 minutes and your grudges. Typing narrows them, and searches everyone we keep a record of; a name
-- nobody has met is taken as typed. A pick opens the sheet the right-click menu opens: the kill order
-- (GK.OpenPost) or the note (GK.OpenNoteSheet), filled in.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

-- In the game's own frame (Letters.lua, GK.MakeFrameSheet), in the skin as the note sheet it leads to:
-- parchment and ink, or the game's dark panel in white and gold (Core.lua, GK.SetLook).
local W, H = 300, 400
local INK, FADED, BLOOD = GK.INK, GK.FADED, GK.BLOOD
local ROWS, ROW_H, ROWS_TOP = 9, 30, 68
local LEFT_FOR = 2 * 3600       -- who left the group stays a suggestion this long
local MAX_RECENT = 40           -- and at most this many of them are remembered

-- What each kind asks, and whom it suggests: enemies (orders, marks) or the people you group with.
local KINDS = {
    order = { title = "Who gets the kill order?", enemy = true },
    kos = { title = "Who do you mark?", enemy = true, list = "kos" },
    watch = { title = "Who goes on Shame?", list = "watch" },
    kudos = { title = "Who gets kudos?", list = "kudos" },
}

local function Ink(fs, colour, size) GK.Ink(fs, colour, GK.TEXT_FONT, size) end

local function Times(n) return n == 1 and "once" or (n .. " times") end

-- ---------------------------------------------------------------------------
-- Who was in the group: this session only, never saved. A ninja looter has usually left the group by
-- the time you want to put them on Shame, and nothing else remembers them.
-- ---------------------------------------------------------------------------
local recent, recentCount = {}, 0       -- [key] = { key, c, r, rf, sx, l, now = in the group now, left = time() }

local function Forget()
    while recentCount > MAX_RECENT do
        local oldKey, oldest
        for key, e in pairs(recent) do
            if not e.now and (not oldest or (e.left or 0) < oldest) then oldKey, oldest = key, e.left or 0 end
        end
        if not oldKey then return end                 -- all 40 are in the group now: a raid, keep them
        recent[oldKey] = nil
        recentCount = recentCount - 1
    end
end

--- Who is in the group now, and who just left it. Each member is read once, when they first show up.
function GK.GroupChanged()
    if not (GK.db and GK.ReadPlayer) then return end      -- before login: nobody to read yet
    local was = {}
    for key, e in pairs(recent) do
        if e.now then was[key] = true end
        e.now = nil
    end
    local function Add(unit)
        local key = GK.UnitPlayerKey and GK.UnitPlayerKey(unit)
        if not key then return end
        local e = recent[key]
        if not e then
            e = GK.ReadPlayer(unit)
            if not e then return end
            recent[key] = e
            recentCount = recentCount + 1
        end
        e.now, e.left = true, nil
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, 4 do Add("party" .. i) end
    end
    local now = time()
    for key in pairs(was) do
        local e = recent[key]
        if e and not e.now then e.left = now end
    end
    Forget()
end

-- ---------------------------------------------------------------------------
-- The suggestions
-- ---------------------------------------------------------------------------
--- The rows for a kind, before any typing: { section = "..." } headings and { t, why } people, each
--- person once, in the order of the sections.
local function Suggestions(kind)
    local k = KINDS[kind]
    local out, have = {}, {}
    local section
    local function Add(t, why, sec)
        if not (t and type(t.key) == "string") or have[t.key] or LIB.IsMyStoredName(t.key) then return end
        if k.enemy and LIB.roster and LIB.roster[t.key] then return end     -- no kill order on a guildie
        have[t.key] = true
        if sec ~= section then
            out[#out + 1] = { section = sec }
            section = sec
        end
        out[#out + 1] = { t = t, why = why }
    end
    -- your target: an enemy for a kill order, any player for the lists
    local target = (kind == "order") and GK.ReadUnit("target") or (GK.ReadPlayer and GK.ReadPlayer("target"))
    if target then
        Add(target, GK.Describe(target.l, target.c, target.r, GK.SexOf(target.key, target.sx)), "Your target")
    end
    if not k.enemy then
        local now, left = {}, {}
        local cut = time() - LEFT_FOR
        for _, e in pairs(recent) do
            if e.now then now[#now + 1] = e
            elseif (e.left or 0) >= cut then left[#left + 1] = e end
        end
        table.sort(now, function(a, b) return a.key < b.key end)
        table.sort(left, function(a, b) return a.left > b.left end)
        for _, e in ipairs(now) do Add(e, GK.Describe(e.l, e.c, e.r, GK.SexOf(e.key, e.sx)), "In your group") end
        for _, e in ipairs(left) do Add(e, "left the group " .. GK.Ago(e.left), "Left your group lately") end
        return out
    end
    local clock, wall = GetTime(), time()
    for _, s in ipairs(GK.SeenList()) do
        Add(s, "seen " .. GK.Ago(wall - (clock - s.t)) .. (s.z and (" - " .. s.z) or ""), "Seen lately")
    end
    local foes = {}
    for key, f in pairs(GK.char.foes) do
        if (f.k or 0) + (f.d or 0) > 0 then foes[#foes + 1] = { key = key, f = f } end
    end
    table.sort(foes, function(a, b)
        if (a.f.last or 0) ~= (b.f.last or 0) then return (a.f.last or 0) > (b.f.last or 0) end
        return a.key < b.key
    end)
    for i = 1, math.min(#foes, 30) do
        local key, f = foes[i].key, foes[i].f
        local why = (f.d or 0) > 0 and ("killed you " .. Times(f.d)) or ("you killed them " .. Times(f.k))
        Add({ key = key, c = f.c, r = f.r, l = f.l }, why .. " - " .. GK.Ago(f.last), "Your grudges")
    end
    return out
end

--- A typed name as a key, if it can be one: one or two words of letters ("First Surname"), each given
--- a capital first letter. nil for anything else - digits, a realm, a link.
function GK.TypedName(text)
    text = strtrim(text or ""):gsub("%s+", " ")
    if text == "" or #text > 40 then return nil end
    local words = {}
    for w in text:gmatch("%S+") do
        if w:find("[%d%p]") then return nil end
        words[#words + 1] = (w:gsub("^%l", string.upper))
    end
    if #words > 2 then return nil end
    return GK.KeyOf(table.concat(words, " "))
end

--- The rows for what is typed: the suggestions whose name has it in them, then everyone else we keep a
--- record of who does (the guild's notes, the leaderboard's names on an enemy kind, your grudges), and
--- the name as typed when it is nobody's. Without typing, the suggestions.
function GK.PickRows(kind, text)
    local rows = Suggestions(kind)
    text = strtrim(text or ""):lower()
    if text == "" then return rows end
    local out, have, section = {}, {}, nil
    local function Match(key) return GK.Show(key):lower():find(text, 1, true) ~= nil end
    for _, r in ipairs(rows) do
        if r.section then section = r.section
        elseif Match(r.t.key) then
            if section then
                out[#out + 1] = { section = section }
                section = nil
            end
            out[#out + 1] = r
            have[r.t.key] = true
        end
    end
    local more = {}
    local function Known(key, t, why)
        if have[key] or LIB.IsMyStoredName(key) or not Match(key) then return end
        if KINDS[kind].enemy and LIB.roster and LIB.roster[key] then return end
        have[key] = true
        more[#more + 1] = { t = t, why = why }
    end
    for key, p in pairs(GK.Store().people or {}) do
        Known(key, { key = key, c = p.c, r = p.r, rf = p.rf, sx = p.sx, l = p.l }, "in the guild's notes")
    end
    for key, f in pairs(GK.char.foes) do Known(key, { key = key, c = f.c, r = f.r, l = f.l }, "in your grudges") end
    table.sort(more, function(a, b) return a.t.key < b.t.key end)
    if #more > 0 then out[#out + 1] = { section = "Known" } end
    for i = 1, math.min(#more, 20) do out[#out + 1] = more[i] end
    -- the name as typed: first when nobody matches (Enter takes it), last when someone does - "gaer" is
    -- more likely the start of Gaerd Balle than a player called Gaer
    local typed = GK.TypedName(text)
    if typed and not have[typed] and not LIB.IsMyStoredName(typed)
        and not (KINDS[kind].enemy and LIB.roster and LIB.roster[typed]) then
        table.insert(out, next(have) and #out + 1 or 1, { t = { key = typed }, why = "as you wrote it", typed = true })
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The sheet
-- ---------------------------------------------------------------------------
local frame                 -- made on first use
local kind = "order"
local rows = {}             -- what the sheet lists now
local offset = 0

local function Pick(r)
    if not (r and r.t) then return end
    frame:Hide()
    if kind == "order" then
        GK.OpenPost(r.t)
    else
        GK.OpenNoteSheet(r.t, KINDS[kind].list)
    end
end

local function Fill()
    rows = GK.PickRows(kind, frame.box:GetText())
    offset = math.max(0, math.min(offset, #rows - ROWS))
    for i, b in ipairs(frame.rows) do
        local r = rows[i + offset]
        b.r = r
        b:SetShown(r ~= nil)
        if r and r.section then
            b:EnableMouse(false)
            b.face:SetShown(false)
            b.name:SetText("")
            b.why:SetText("")
            b.head:SetText(r.section:upper())
        elseif r then
            b:EnableMouse(true)
            b.head:SetText("")
            b.face:SetShown(true)
            b.face:Set(r.t)
            b.name:SetText(r.typed and ('"' .. GK.Show(r.t.key) .. '"') or GK.Show(r.t.key))
            b.why:SetText(r.why or "")
        end
    end
    local any = false
    for _, r in ipairs(rows) do any = any or r.t ~= nil end
    frame.none:SetShown(not any)
end

local function Build()
    local f = GK.MakeFrameSheet("GrudgekeeperPick", W, H, "")
    f.box = GK.FrameBox(f, W - 48, 40, "Type a name, or pick one")
    f.box:SetPoint("TOPLEFT", 26, -38)
    f.box:HookScript("OnTextChanged", function()
        offset = 0
        Fill()
    end)
    f.box:SetScript("OnEscapePressed", function() f:Hide() end)
    f.box:SetScript("OnEnterPressed", function()
        for _, r in ipairs(rows) do
            if r.t then return Pick(r) end
        end
    end)

    -- a row is a person (a face in the ring, the name, why they are offered) or a section's heading in
    -- small capitals, in the ink of the ledger
    local inner = W - 40
    f.rows = {}
    for i = 1, ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(inner, ROW_H)
        b:SetPoint("TOPLEFT", 20, -(ROWS_TOP + (i - 1) * ROW_H))
        local hi = b:CreateTexture(nil, "BACKGROUND")
        hi:SetAllPoints()
        GK.Paint(hi, "blood", 0.10)
        hi:Hide()
        b.face = GK.MakePortrait(b, 26)
        b.face.tex:SetPoint("CENTER", b, "LEFT", 16, 0)
        b.name = b:CreateFontString(nil, "ARTWORK")
        Ink(b.name, INK, 12)
        b.name:SetPoint("TOPLEFT", 34, -2)
        b.name:SetWidth(inner - 38)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b.why = b:CreateFontString(nil, "ARTWORK")
        Ink(b.why, FADED, 10)
        b.why:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
        b.why:SetWidth(inner - 38)
        b.why:SetJustifyH("LEFT")
        b.why:SetWordWrap(false)
        b.head = b:CreateFontString(nil, "ARTWORK")
        Ink(b.head, FADED, 10)
        b.head:SetPoint("BOTTOMLEFT", 4, 5)
        b:SetScript("OnEnter", function() hi:Show() end)
        b:SetScript("OnLeave", function() hi:Hide() end)
        b:SetScript("OnClick", function(self) Pick(self.r) end)
        f.rows[i] = b
    end
    f.none = f:CreateFontString(nil, "ARTWORK")
    Ink(f.none, FADED, 11)
    f.none:SetPoint("TOPLEFT", 26, -(ROWS_TOP + 8))
    f.none:SetWidth(W - 52)
    f.none:SetJustifyH("LEFT")
    f.none:SetSpacing(3)
    f.none:SetText("Nobody to suggest yet. Type their name: first name and surname, as the game shows it.")
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 2)
        Fill()
    end)
    local cancel = GK.FrameButton(f, CANCEL or "Cancel", 96, function() f:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    frame = f
end

--- Open the picker for a kind: "order" (a kill order), or a list - "kos", "watch" or "kudos".
function GK.OpenPicker(k)
    if not KINDS[k] then return end
    if not frame then Build() end
    kind, offset = k, 0
    frame.title:SetText(KINDS[k].title)
    frame.box:SetText("")
    Fill()
    GK.PlaceSheet(frame)
    frame:Show()
    frame:Raise()
    frame.box:SetFocus()
end

LIB.On("GROUP_ROSTER_UPDATE", function() GK.GroupChanged() end)
LIB.On("PLAYER_ENTERING_WORLD", function() GK.GroupChanged() end)
