-- Grudgekeeper - the notes, as the ledger shows them (the data is Notes.lua). What you see of them:
--   the list pages      four tabs in the ledger: Marked (after Grudges, among the owner's), then Shame, Kudos and
--                       Names over the right page
--   cards               the small card for a noted player or a nice name, and a line or two on the
--                       wanted poster and the record when there are notes on that player
--   the note sheet      a small parchment like the kill order's: the list, a tag, a few words, Write it
--   the right-click menu   a Grudgekeeper notes submenu on any player, friend or foe
--   quiet marks         a line on the tooltip, a dim mark on the nameplate. They never open anything
--   warnings            only when asked: a Marked player near (off by default), a Shame player
--                       near (off), a Shame or Kudos player joining your group (on)
-- It also wraps a few functions of the other files (docs/guild-grudge-merge.md, H7): the poster and
-- record cards, the tooltip line, GK.Warn (the alert style) and /grudge. Each wrapper calls the
-- original, and changes nothing unless its own setting or a notes command asks.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local Secret = GK.Secret

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local INK = { 0.22, 0.13, 0.05 }
local FADED = { 0.35, 0.25, 0.15 }
local BLOOD = { 0.47, 0.06, 0.04 }
local COL_RIGHT = 332                    -- Window.lua's right-hand column: the page's width less 36

local ORDER = { "kos", "watch", "kudos" }
local WORD = { kos = "Marked", watch = "Shame", kudos = "Kudos" }
local CARD_TITLE = { kos = "MARKED", watch = "SHAME", kudos = "KUDOS" }
local COLOUR = { kos = "c8281e", watch = "ffcc00", kudos = "4dff66" }
local NEAR_GAP = 90                      -- the same player warns you at most this often
local MAX_CARD_LINES = 9                 -- what the ledger's card has room for
local CARD_NOTES = 5                     -- notes on a card before "and 3 more"
local MENU_NOTES = 10                    -- notes a menu lists to vote on or delete

local function Plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

local function Who(key)
    if LIB.IsMyStoredName(key) then return "you" end
    return GK.Show(key)
end

--- "+3", "-2" or "0".
local function ScoreText(n) return n > 0 and ("+" .. n) or tostring(n) end

--- A name from the menu's context: a plain string the client lets us read, or nil.
local function Text(v)
    if type(v) ~= "string" or Secret(v) or v == "" then return nil end
    return v
end

--- "a, b and 2 more" from a list of keys, the first few by name.
local function NameList(keys, shown)
    local parts = {}
    for i = 1, math.min(shown or 3, #keys) do parts[i] = Who(keys[i]) end
    local text = table.concat(parts, ", ")
    if #keys > #parts then text = text .. (" and %d more"):format(#keys - #parts) end
    return text
end

local function Short(text, n)
    if #text <= n then return text end
    return text:sub(1, n - 3) .. "..."
end

-- ---------------------------------------------------------------------------
-- What we know of a noted player, worked out once per change
-- ---------------------------------------------------------------------------
-- The tooltip, the nameplates and the group check all ask about the same few players again and again, so
-- the answer is kept until the data changes (GK.version), as the tooltip line is in Social.lua. Players
-- nobody wrote about are kept as false: most of the world.
local cache, cacheVersion = {}, -1

local function Distinct(notes, authors)
    local tags, seen = {}, {}
    for _, n in ipairs(notes) do
        if n.tag and authors[n.author] and not seen[n.tag] then
            seen[n.tag] = true
            tags[#tags + 1] = n.tag
        end
    end
    return tags
end

--- { key, lists = GK.ListsOf, notes = GK.NotesOf (newest first), count, score, on = the lists they are on,
--- primary = the one to show, tags = [list] = the newest tag, taglist = [list] = every tag } or nil.
local function BuildSummary(key)
    if not GK.IsNoted(key) then return nil end
    local s = { key = key, lists = GK.ListsOf(key), notes = GK.NotesOf(key), on = {}, tags = {}, taglist = {}, score = 0 }
    s.count = #s.notes
    for _, n in ipairs(s.notes) do s.score = s.score + n.score end
    for _, list in ipairs(ORDER) do
        local authors = s.lists[list]
        if #authors > 0 then
            s.on[#s.on + 1] = list
            local set = {}
            for _, a in ipairs(authors) do set[a] = true end
            s.taglist[list] = Distinct(s.notes, set)
            s.tags[list] = s.taglist[list][1]
        end
    end
    -- the list I put them on, else the first of the three that has them
    local mine = GK.MyMark(key)
    s.primary = (mine and #s.lists[mine] > 0) and mine or s.on[1]
    return s.primary and s or nil
end

local function Summary(key)
    if cacheVersion ~= GK.version then cache, cacheVersion = {}, GK.version end
    local s = cache[key]
    if s == nil then
        s = BuildSummary(key) or false
        cache[key] = s
    end
    return s or nil
end
GK.NoteSummary = Summary

local function OnList(s, list)
    for _, l in ipairs(s.on) do
        if l == list then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------
--- Open a context menu of ours, filled by fill(root). The menu API is the game's own.
local function OpenMenu(fill)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(UIParent, function(_, root) fill(root) end)
end

--- A note as a card line: "text" - Author, 3 days ago (+2). A colon-and-space in the text would make the
--- ledger read the start of the line as a label, so the space after it is a no-break one.
local function NoteLine(n)
    local text = n.text and ('"' .. n.text:gsub(": ", ":\194\160") .. '"') or ("[" .. (n.tag and GK.TagText(n.tag, 12) or "?") .. "]")
    return ("%s - %s, %s%s"):format(text, Who(n.author), GK.Ago(n.ts), n.score ~= 0 and (" (" .. ScoreText(n.score) .. ")") or "")
end

--- The player's card: who put them on which list, the newest notes, the votes. Nil for nobody we keep a
--- record of. page is the list whose page the card was opened from, if any. key, page -> the card table
--- of Profile.lua.
function GK.NoteCard(key, page)
    local p = GK.Person(key, false)
    if not p then return nil end
    local s = Summary(key)
    -- the list the card is about: where I put them, else the page's list if they are on it, else the first
    local mark = GK.MyMark(key)
    local shown = s and ((mark and OnList(s, mark) and mark) or (page and OnList(s, page) and page) or s.primary)
    local t = { key = key, c = p.c, r = p.r, rf = p.rf, sx = p.sx, l = p.l }
    local d = { key = key, c = p.c, rf = p.rf, sx = p.sx, title = shown and CARD_TITLE[shown] or "NOTES",
        name = GK.Show(key), info = GK.Describe(p.l, p.c, p.r), lines = {}, buttons = {} }
    local lines = d.lines
    if s then
        for _, list in ipairs(s.on) do
            local tags = {}
            for i, tag in ipairs(s.taglist[list]) do tags[i] = GK.TagText(tag, 12) end
            lines[#lines + 1] = ("%s: %s%s"):format(WORD[list], NameList(s.lists[list]),
                #tags > 0 and (" - " .. table.concat(tags, ", ")) or "")
        end
        for i = 1, math.min(CARD_NOTES, s.count) do lines[#lines + 1] = NoteLine(s.notes[i]) end
        if s.count > CARD_NOTES then
            lines[#lines + 1] = ("and %d more note%s."):format(s.count - CARD_NOTES, s.count - CARD_NOTES == 1 and "" or "s")
        end
        d.big, d.caption = ScoreText(s.score), "votes"
    else
        lines[1] = "Nothing is written down about them."
    end
    d.buttons[1] = { "Add a note", function() GK.OpenNoteSheet(t, GK.MyMark(key) or shown or "kos") end }
    d.buttons[2] = { "More...", function() OpenMenu(function(root) GK.NoteMenu(root, key) end) end }
    return d
end

--- Is this someone from the other side: seen as one, a race of theirs, or a history with us.
local function IsEnemy(key, p)
    return (GK.Seen and GK.Seen(key) ~= nil) or (GK.EnemyRace and GK.EnemyRace(p.rf) == true)
        or (GK.char and GK.char.foes[key] ~= nil)
end

--- The "More..." menu of a player's card: move or remove my mark, vote on a note, delete one of mine, and
--- for an enemy the wanted poster. root is the game's menu description; tests pass a stand-in.
function GK.NoteMenu(root, key)
    local p = GK.Person(key, false)
    if not p then return end
    local mark = GK.MyMark(key)
    local move = root:CreateButton("Move my mark to")
    for _, list in ipairs(ORDER) do
        if list ~= mark then move:CreateButton(WORD[list], function() GK.SetMark(key, list) end) end
    end
    if mark then root:CreateButton("Remove my mark", function() GK.SetMark(key, nil) end) end
    local theirs, mine = {}, {}
    for _, n in ipairs(GK.NotesOf(key)) do
        local into = n.mine and mine or theirs
        if #into < MENU_NOTES then into[#into + 1] = n end
    end
    local function Label(n) return n.text and Short(n.text, 36) or ("[" .. (n.tag and GK.TagText(n.tag, 12) or "?") .. "]") end
    if #theirs > 0 then
        local vote = root:CreateButton("Vote on a note")
        for _, n in ipairs(theirs) do
            local sub = vote:CreateButton(Who(n.author) .. ": " .. Label(n))
            if n.myVote ~= 1 then sub:CreateButton("Up", function() GK.VoteNote(key, n.author, n.id, 1) end) end
            if n.myVote ~= -1 then sub:CreateButton("Down", function() GK.VoteNote(key, n.author, n.id, -1) end) end
            if n.myVote ~= 0 then sub:CreateButton("Take back", function() GK.VoteNote(key, n.author, n.id, 0) end) end
        end
    end
    if #mine > 0 then
        local del = root:CreateButton("Delete my note")
        for _, n in ipairs(mine) do del:CreateButton(Label(n), function() GK.DeleteNote(key, n.id) end) end
    end
    if IsEnemy(key, p) then
        root:CreateButton("Open their poster", function() GK.ShowPoster({ key = key, c = p.c, r = p.r, l = p.l }) end)
    end
end

--- The row of a nice name as GK.NiceNames lists it, for the one asking (an officer sees the hidden too).
local function NameRow(key)
    for _, row in ipairs(GK.NiceNames(GK.IsOfficer(LIB.Me()))) do
        if row.key == key then return row end
    end
    return nil
end

--- The "More..." menu of a nice name's card: my vote, removing my own, and an officer's hide.
function GK.NameMenu(root, key)
    local row = NameRow(key)
    if not row then return end
    if row.mine then
        root:CreateButton("Remove my name", function() GK.RemoveNiceName(key) end)
    else
        if row.myVote ~= 1 then root:CreateButton("Vote up", function() GK.VoteName(key, 1) end) end
        if row.myVote ~= -1 then root:CreateButton("Vote down", function() GK.VoteName(key, -1) end) end
        if row.myVote ~= 0 then root:CreateButton("Take back my vote", function() GK.VoteName(key, 0) end) end
    end
    if GK.IsOfficer(LIB.Me()) then
        root:CreateButton(row.hidden and "Show for everyone" or "Hide for everyone", function() GK.HideName(key, not row.hidden) end)
    end
end

--- A nice name's card. Nil for a name that is gone, or hidden from the one looking.
function GK.NameCard(key)
    local row = NameRow(key)
    if not row then return nil end
    local n = GK.Store().names[key]
    local officer = GK.IsOfficer(LIB.Me())
    local d = { key = key, c = n.c, rf = n.rf, sx = n.sx, title = "NICE NAME", name = GK.Show(key),
        info = GK.Describe(n.l, n.c, n.r), lines = {}, buttons = {}, big = ScoreText(row.score), caption = "votes" }
    d.lines[1] = "Added by: " .. (row.by and Who(row.by) or "someone")
    if row.hidden then d.lines[2] = "Hidden: an officer hid it from the list." end
    if row.mine then
        d.buttons[1] = { "Remove", function() GK.RemoveNiceName(key) end }
    else
        local up = row.myVote == 1
        d.buttons[1] = { up and "Take back" or "Vote up", function() GK.VoteName(key, up and 0 or 1) end }
    end
    if officer or not row.mine then
        d.buttons[2] = { "More...", function() OpenMenu(function(root) GK.NameMenu(root, key) end) end }
    end
    return d
end

-- ---------------------------------------------------------------------------
-- The four list pages
-- ---------------------------------------------------------------------------
-- A page each, because the list is the tab: Marked is the enemy's page, on the left between Grudges and News; Shame, Kudos and Names are the friendly ones, over the right page (side = "right").
local PAGE_WORD = { kos = "Marked", watch = "Shame", kudos = "Kudos", names = "Names" }
local EMPTY = {
    kos = "Nobody is marked. It is for an enemy you want to mark without a bounty or a history. "
        .. "Right-click a player and pick Grudgekeeper notes, or write /grudge note <first> <surname> <what they did>.",
    watch = "Nobody is on your Shame list. It is for players to be careful with - a ninja looter, a scammer. "
        .. "Right-click one and pick Grudgekeeper notes, or write /grudge shame <first> <surname>.",
    kudos = "Nobody has kudos yet. Right-click a good player and pick Grudgekeeper notes, or write "
        .. "/grudge kudos <first> <surname>.",
    names = "No nice names yet. Right-click a player with a funny character name and pick Add to nice names.",
}

--- The rows of one list, and the text for when there are none. list: kos, watch, kudos or names.
function GK.NotesItems(list)
    local items = {}
    if list == "names" then
        local rows = GK.NiceNames(GK.IsOfficer(LIB.Me()))
        local names = GK.Store().names
        for _, r in ipairs(rows) do
            local n = names[r.key]
            items[#items + 1] = { key = "nn:" .. r.key, name = GK.Show(r.key), faded = r.hidden or nil,
                face = { c = n.c, rf = n.rf, sx = n.sx },
                sub = (r.hidden and "hidden - " or "") .. "added by " .. (r.by and Who(r.by) or "someone"),
                right = r.score ~= 0 and ScoreText(r.score) or "", ts = r.ts, votes = r.score, own = r.mine or nil,
                select = { kind = "card", make = function() return GK.NameCard(r.key) end } }
        end
        return items, EMPTY.names
    end
    for _, e in ipairs(GK.PeopleOn(list)) do
        local p, s = e.person, Summary(e.key)
        local bits = {}
        if #e.tags > 0 then
            local shown = {}
            for i, tag in ipairs(e.tags) do shown[i] = GK.TagText(tag, 12) end
            bits[1] = table.concat(shown, ", ")
        end
        local newest = s and s.notes[1]
        if newest then bits[#bits + 1] = newest.text and ('"' .. newest.text .. '"') or nil end
        local key = e.key
        items[#items + 1] = { key = "p:" .. key, name = GK.Show(key), face = { c = p.c, rf = p.rf, sx = p.sx },
            sub = table.concat(bits, " - "), right = e.score ~= 0 and ScoreText(e.score) or "", ts = e.ts,
            votes = e.score, own = e.mine or nil,
            select = { kind = "card", make = function() return GK.NoteCard(key, list) end } }
    end
    -- the page's own order: the newest news first
    table.sort(items, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.name < b.name
    end)
    return items, EMPTY[list]
end

for _, list in ipairs({ "kos", "watch", "kudos", "names" }) do
    GK.AddLedgerPage({
        name = PAGE_WORD[list], list = list, sortable = true, side = list ~= "kos" and "right" or nil,
        before = list == "kos" and "News" or nil,
        items = function() return GK.NotesItems(list) end,
        headings = { { list == "names" and "Nice name" or "Player", 48 }, { "Votes", COL_RIGHT, "RIGHT" } },
        sub = function(items)
            if list == "names" then return Plural(#items, "nice name") .. " in the guild's list" end
            if list == "kos" then return Plural(#items, "player") .. " marked" end
            return ("%s on %s"):format(Plural(#items, "player"), PAGE_WORD[list])
        end,
    })
end

--- Open the ledger at the page of a list: "kos", "watch", "kudos" or "names" (Marked for anything else).
function GK.OpenNotes(list)
    local kos
    for i, def in ipairs(GK.LedgerPages) do
        if def.list == list then return GK.OpenWindow(i) end
        if def.list == "kos" then kos = i end
    end
    GK.OpenWindow(kos)
end

-- ---------------------------------------------------------------------------
-- Notes on the poster and the record
-- ---------------------------------------------------------------------------
--- Up to two lines for a card: how many notes and on which list, and the newest. nil for nobody noted.
function GK.NoteLines(key)
    local s = key and Summary(key)
    if not s then return nil end
    local where = {}
    for _, list in ipairs(s.on) do
        where[#where + 1] = WORD[list] .. ((list == s.primary and s.tags[list]) and (" (" .. GK.TagText(s.tags[list], 12) .. ")") or "")
    end
    local lines = { ("Notes: %s, on %s"):format(s.count == 0 and "none" or tostring(s.count),
        table.concat(where, " and ")) }
    if s.count > 0 then lines[2] = "Newest: " .. NoteLine(s.notes[1]) end
    return lines
end

local function WrapCard(name)
    local original = GK[name]
    GK[name] = function(...)
        local d = original(...)
        local lines = d and GK.NoteLines(d.key)
        for i = 1, lines and math.min(#lines, MAX_CARD_LINES - #d.lines) or 0 do d.lines[#d.lines + 1] = lines[i] end
        return d
    end
end
WrapCard("PosterCard")
WrapCard("RecordCard")

-- ---------------------------------------------------------------------------
-- Writing a note
-- ---------------------------------------------------------------------------
--- What the note sheet does with "Write it". t = { key, c, r, rf, sx, l }. A note needs a few words or a
--- tag; with neither, a list alone is still something to write down (it moves my mark). Returns true,
--- or nil and why not.
function GK.WriteNote(t, list, text, tag)
    local key = t and t.key
    if type(key) ~= "string" or not key:find("-", 1, true) then return nil, "That player has no name we can keep." end
    text, tag = strtrim(text or ""), strtrim(tag or "")
    local info = { c = t.c, r = t.r, rf = t.rf, sx = t.sx, l = t.l }
    if text == "" and tag == "" then
        if not list then return nil, "Write something, pick a tag or pick a list." end
        -- the record first, so the mark goes out with what we know of them
        if GK.Person(key, true) then GK.LearnPerson(key, info) end
        if not GK.SetMark(key, list) then return nil, "That didn't fit." end
        return true
    end
    local note, why = GK.AddNote(key, text, tag, list, info)
    if not note then return nil, why end
    return true
end

local sheet                -- the frame, made on first use
local draft                -- { t, list, tag }: what the sheet is about
local SHEET_W, SHEET_H = 330, 380
local TAGS_Y, TAG_ROWS, TAG_GAP = 146, 3, 18

local function Ink(fs, colour, font, size)
    fs:SetFont(font, size, "")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

--- An ink link: faded, or in blood and underlined when it is the one chosen (the ledger's own).
local function InkLink(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "ARTWORK")
    Ink(b.text, FADED, TEXT_FONT, 12)
    b.text:SetPoint("LEFT")
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetColorTexture(BLOOD[1], BLOOD[2], BLOOD[3], 0.7)
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", 0, 0)
    b:SetHeight(16)
    function b:Set(text, on)
        self.text:SetText(text)
        Ink(self.text, on and BLOOD or FADED, TEXT_FONT, 12)
        self.line:SetShown(on and true or false)
        self:SetWidth(math.ceil(self.text:GetStringWidth() or 40) + 2)
    end
    b:SetScript("OnClick", onClick)
    return b
end

local function Box(parent, width, letters)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(letters)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

--- The three list links and the tags of the chosen list, placed and coloured for the draft.
local function LayoutSheet()
    for i, list in ipairs(ORDER) do sheet.lists[i]:Set(WORD[list], draft.list == list) end
    local tags = GK.KnownTags(draft.list)
    local x, y = 0, 0
    for i, b in ipairs(sheet.tags) do
        local tag = tags[i]
        b.tag = tag
        b:SetShown(tag ~= nil)
        if tag then
            b:Set(GK.TagText(tag, 12), draft.tag == tag)
            if x > 0 and x + b:GetWidth() > SHEET_W - 68 then x, y = 0, y + TAG_GAP end
            if y >= TAG_ROWS * TAG_GAP then
                b:Hide()
            else
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", sheet, "TOPLEFT", 34 + x, -(TAGS_Y + y))
                x = x + b:GetWidth() + 10
            end
        end
    end
end

local function BuildSheet()
    local f = CreateFrame("Frame", "GrudgekeeperNote", UIParent)
    f:SetSize(SHEET_W, SHEET_H)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local paper = f:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(MEDIA .. "sheet")
    local top = GK.MakeRoll(f, 30)
    top:SetWidth(SHEET_W + 16)
    top:SetPoint("BOTTOM", f, "TOP", 0, -15)
    local bottom = GK.MakeRoll(f, 30, true)
    bottom:SetWidth(SHEET_W + 16)
    bottom:SetPoint("TOP", f, "BOTTOM", 0, 15)

    local title = f:CreateFontString(nil, "ARTWORK")
    Ink(title, BLOOD, TITLE_FONT, 24)
    title:SetPoint("TOP", 0, -22)
    title:SetText("A NOTE")
    f.name = f:CreateFontString(nil, "ARTWORK")
    Ink(f.name, INK, TITLE_FONT, 18)
    f.name:SetPoint("TOP", title, "BOTTOM", 0, -10)
    f.info = f:CreateFontString(nil, "ARTWORK")
    Ink(f.info, INK, TEXT_FONT, 12)
    f.info:SetPoint("TOP", f.name, "BOTTOM", 0, -4)

    local function Label(text, y)
        local fs = f:CreateFontString(nil, "ARTWORK")
        Ink(fs, INK, TEXT_FONT, 13)
        fs:SetPoint("TOPLEFT", 34, -y)
        fs:SetText(text)
        return fs
    end
    local listLabel = Label("List", 108)
    f.lists = {}
    for i, list in ipairs(ORDER) do
        local b = InkLink(f, function()
            draft.list, draft.tag = list, nil       -- the tags belong to the list
            LayoutSheet()
        end)
        if i == 1 then b:SetPoint("LEFT", listLabel, "RIGHT", 18, 0) else b:SetPoint("LEFT", f.lists[i - 1], "RIGHT", 12, 0) end
        f.lists[i] = b
    end
    Label("Tag", TAGS_Y - 2)
    f.tags = {}
    for i = 1, 12 do
        f.tags[i] = InkLink(f, function(self)
            draft.tag = (draft.tag ~= self.tag) and self.tag or nil
            f.custom:SetText("")
            LayoutSheet()
        end)
    end
    local own = Label("Own tag", TAGS_Y + TAG_ROWS * TAG_GAP + 8)
    f.custom = Box(f, 150, GK.MAX_TAG)
    f.custom:SetPoint("LEFT", own, "RIGHT", 14, 0)
    f.custom:SetScript("OnTextChanged", function(_, byHand)
        if byHand then
            draft.tag = nil
            LayoutSheet()
        end
    end)
    local say = Label("Note", TAGS_Y + TAG_ROWS * TAG_GAP + 40)
    f.note = Box(f, SHEET_W - 68, 200)
    f.note:SetPoint("TOPLEFT", say, "BOTTOMLEFT", 6, -6)
    local hint = f:CreateFontString(nil, "ARTWORK")
    Ink(hint, FADED, TEXT_FONT, 11)
    hint:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", -6, -8)
    hint:SetWidth(SHEET_W - 68)
    hint:SetJustifyH("LEFT")
    hint:SetText("Up to 200 letters. A tag or a list is enough on its own.")

    local write = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    write:SetSize(110, 22)
    write:SetPoint("BOTTOMLEFT", 34, 26)
    write:SetText("Write it")
    write:SetScript("OnClick", function()
        local tag = strtrim(f.custom:GetText())
        local ok, why = GK.WriteNote(draft.t, draft.list, f.note:GetText(), tag ~= "" and tag or draft.tag)
        if not ok then
            print(GK.TAG .. ": " .. (why or "the note couldn't be written."))
            return
        end
        GK.Sound("IG_QUEST_LIST_OPEN")
        f:Hide()
    end)
    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("LEFT", write, "RIGHT", 8, 0)
    cancel:SetText(CANCEL or "Cancel")
    cancel:SetScript("OnClick", function() f:Hide() end)
    local wax = f:CreateTexture(nil, "OVERLAY")
    wax:SetTexture(MEDIA .. "seal_red")
    wax:SetSize(56, 56)
    wax:SetPoint("BOTTOMRIGHT", -20, 12)

    f:Hide()
    if LIB.RegisterPopup then LIB.RegisterPopup(f) else tinsert(UISpecialFrames, "GrudgekeeperNote") end
    sheet = f
end

--- Open the note sheet for a player: t = { key, c, r, rf, sx, l, unit }, list = "kos", "watch" or "kudos"
--- (kos when it is anything else). The Classic look wraps this: keep the signature.
function GK.OpenNoteSheet(t, list)
    if not (t and t.key) then return end
    if not sheet then BuildSheet() end
    local known = false
    for _, l in ipairs(ORDER) do known = known or l == list end
    draft = { t = t, list = known and list or "kos" }
    sheet.name:SetText(GK.Show(t.key))
    sheet.info:SetText(GK.Describe(t.l, t.c, t.r))
    sheet.custom:SetText("")
    sheet.note:SetText("")
    LayoutSheet()
    sheet:Show()
    sheet:Raise()
end

-- ---------------------------------------------------------------------------
-- The game's right-click menu on a player
-- ---------------------------------------------------------------------------
-- Same hooks as Profile.lua: Menu.ModifyMenu adds our lines after Blizzard's own are built.
local FRIENDLY = { "SELF", "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "COMMUNITIES_GUILD_MEMBER", "GUILD" }

--- Who a unit is, if it is a player and not you: the key, or nil. Every read is cheap, and none keeps a
--- table, because the nameplates ask it for everyone in sight.
local function PlayerKey(unit)
    if not UnitExists(unit) then return nil end
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not ok or Secret(isPlayer) or not isPlayer then return nil end
    local key = LIB.UnitKey(unit)
    if not key or LIB.IsMyStoredName(key) then return nil end
    return key
end

--- What a unit shows of its player: { key, unit, c, r, rf, sx, l }, each field only if the client lets us.
local function ReadPlayer(unit)
    local key = PlayerKey(unit)
    if not key then return nil end
    local _, class = UnitClass(unit)
    local race, raceFile = UnitRace(unit)
    local sex, level = UnitSex(unit), UnitLevel(unit)
    return {
        key = key, unit = unit,
        c = not Secret(class) and GK.ValidClass(class) or nil,
        r = not Secret(race) and GK.Clean(race, 20) or nil,
        rf = not Secret(raceFile) and raceFile or nil,
        sx = (not Secret(sex) and (sex == 2 or sex == 3)) and sex or nil,
        l = not Secret(level) and GK.ValidLevel(level) or nil,
    }
end

local function ShowNotes(key)
    GK.ShowCard(function() return GK.NoteCard(key) end)
end

local function OnNotesMenu(_, root, ctx)
    if not (GK.db and GK.db.unitMenu and GK.char) or type(ctx) ~= "table" then return end
    local unit = Text(ctx.unit)
    local t
    if unit then
        t = ReadPlayer(unit)                -- nil for a mob, an NPC, a pet and yourself
    else
        local key = GK.MenuKey(ctx)         -- a name in chat or the roster: always a player
        if key and not LIB.IsMyStoredName(key) then t = { key = key } end
    end
    if not t then return end
    GK.LearnPerson(t.key, t)
    local key = t.key
    if root.CreateDivider then root:CreateDivider() end
    local sub = root:CreateButton("Grudgekeeper notes")
    sub:CreateButton("Add a note", function() GK.OpenNoteSheet(t, "kos") end)
    for _, list in ipairs({ "watch", "kudos" }) do
        local lists = sub:CreateButton(WORD[list] .. (list == "watch" and " list" or ""))
        for _, tag in ipairs(GK.TAGS[list]) do
            lists:CreateButton(GK.TagText(tag), function() GK.WriteNote(t, list, "", tag) end)
        end
        lists:CreateButton("No tag", function() GK.WriteNote(t, list, "", "") end)
    end
    sub:CreateButton("Add to nice names", function()
        local ok, why = GK.AddNiceName(key, t)
        print(GK.TAG .. ": " .. (ok and (GK.Show(key) .. " is on the nice names list.") or why))
    end)
    if GK.IsNoted(key) then sub:CreateButton("Their notes", function() ShowNotes(key) end) end
end

-- ---------------------------------------------------------------------------
-- The tooltip
-- ---------------------------------------------------------------------------
--- "Shame, 2 notes" - what an enemy's Grudge line gets added. nil for nobody noted.
local function NoteBits(key)
    local s = Summary(key)
    if not s then return nil end
    return WORD[s.primary] .. (s.count > 0 and (", " .. Plural(s.count, "note")) or "")
end

--- The line for a player who is not an enemy: `Shame  Ninja looter - 2 notes`, the list in its colour.
function GK.NoteTipLine(key)
    local s = key and Summary(key)
    if not s then return nil end
    local bits = {}
    if s.tags[s.primary] then bits[#bits + 1] = GK.TagText(s.tags[s.primary], 12) end
    if s.count > 0 then bits[#bits + 1] = Plural(s.count, "note") end
    local head = ("|cff%s%s|r"):format(COLOUR[s.primary], WORD[s.primary])
    return #bits > 0 and (head .. "  " .. table.concat(bits, " - ")) or head
end

local tooltipLine = GK.TooltipLine
--- An enemy's line, with the notes on them added.
GK.TooltipLine = function(key, guid)
    local line = tooltipLine(key, guid)
    local bits = key and NoteBits(key)
    if not bits then return line end
    if not line then return "|cffc8281eGrudge|r  " .. bits end
    return line .. "  -  " .. bits
end

local function OnNoteTip(tooltip)
    if tooltip ~= GameTooltip or not (GK.db and GK.db.tooltip) or not GK.InWorld() then return end
    if not tooltip.GetUnit then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or type(unit) ~= "string" or Secret(unit) then return end
    if GK.Hostile and GK.Hostile(unit) then return end       -- Social.lua has theirs
    local key = PlayerKey(unit)
    local line = key and GK.NoteTipLine(key)
    if not line then return end
    tooltip:AddLine(line, 0.85, 0.75, 0.6)
    tooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Nameplates, players nearby, players joining the group
-- ---------------------------------------------------------------------------
local WATCH_TEXTURE = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local plates = {}                                  -- nameplate units on screen
local marks = setmetatable({}, { __mode = "k" })   -- plate -> our mark on it (made once per plate)
local marked = {}                                  -- unit -> the plate its mark is on
local nearAt = {}                                  -- [key] = GetTime() of the last warning
local lastGroup = {}                               -- the keys in our group at the last roster update

local function PlateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and plate or nil
end

local function Unmark(unit)
    local plate = marked[unit]
    if plate and marks[plate] then marks[plate]:Hide() end
    marked[unit] = nil
end

--- The picture for a list: red-ish for Marked, the game's alert for Shame, a tick for Kudos.
local function MarkArt(tex, list)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(1, 1, 1)
    if list == "watch" then
        tex:SetTexture(WATCH_TEXTURE)
    elseif list == "kudos" then
        pcall(tex.SetAtlas, tex, "UI-LFG-ReadyMark")
    else
        pcall(tex.SetAtlas, tex, "UI-LFG-DeclineMark")
        tex:SetVertexColor(1, 0.35, 0.3)
    end
end

--- A small dim mark on the plate, left of the kill order's seal (Sightings.lua: 26 wide, centred, 6 down
--- into the plate) so the two never cover each other.
local function Mark(unit, list)
    Unmark(unit)
    local plate = PlateOf(unit)
    if not plate then return end
    local f = marks[plate]
    if not f then
        f = CreateFrame("Frame", nil, plate)
        f:SetSize(14, 14)
        f:EnableMouse(false)
        f:SetPoint("BOTTOMRIGHT", plate, "TOP", -15, -6)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f:SetAlpha(0.6)
        marks[plate] = f
    end
    MarkArt(f.tex, list)
    f:SetFrameLevel((plate:GetFrameLevel() or 1) + 20)
    f:Show()
    marked[unit] = plate
end

local function TagSuffix(tag) return tag and (" [" .. GK.TagText(tag) .. "]") or "" end

local function PruneNear(now)
    for key, at in pairs(nearAt) do
        if now - at > NEAR_GAP then nearAt[key] = nil end
    end
end

--- A noted player is in sight: Marked warns (when asked), Shame says one line (when asked). Never
--- twice within NEAR_GAP, and Kudos is never announced.
local function Nearby(key, s)
    local kos, watch = #s.lists.kos > 0, #s.lists.watch > 0
    local warn = kos and GK.db.noteAlerts
    local line = not kos and watch and GK.db.watchNearby
    if not (warn or line) then return end
    local now = GetTime()
    if nearAt[key] and now - nearAt[key] < NEAR_GAP then return end
    PruneNear(now)
    nearAt[key] = now
    local name = GK.Show(key)
    if warn then
        GK.Warn(("Marked: %s is near!%s"):format(name, TagSuffix(s.tags.kos)), true)
    else
        print(("%s: %s from your Shame list is near%s"):format(GK.TAG, name, TagSuffix(s.tags.watch)))
    end
end

--- Look at a unit (a nameplate, the target, the mouse): learn a noted player's face, mark their plate,
--- warn if asked. Runs for everyone in sight, so a stranger costs a few reads and a cache hit.
local function Look(unit)
    if not (GK.char and GK.db and GK.InWorld()) then return end
    local key = PlayerKey(unit)
    local s = key and Summary(key)
    if not s then
        if plates[unit] then Unmark(unit) end
        return
    end
    GK.LearnPerson(key, ReadPlayer(unit))
    local guid = UnitGUID(unit)
    local order = GK.OrderOn(key, (not Secret(guid) and type(guid) == "string") and guid or nil)
    if plates[unit] then
        if order or not GK.db.plateNotes then Unmark(unit) else Mark(unit, s.primary) end
    end
    if not order then Nearby(key, s) end
end

-- The plates on screen looked at again when the notes change: a mark appears, or goes, at once.
local function RefreshPlates()
    for unit in pairs(plates) do Look(unit) end
end

--- Who joined the group since the last update: Shame warns, Kudos says one friendly line.
function GK.CheckNotesGroup()
    if not (GK.db and GK.char) then return end
    local current = {}
    local function Add(unit)
        local key = PlayerKey(unit)
        if not key then return end
        current[key] = true
        if lastGroup[key] then return end
        local s = Summary(key)
        if not s then return end
        GK.LearnPerson(key, ReadPlayer(unit))
        local name = GK.Show(key)
        if #s.lists.watch > 0 and GK.db.watchGroup then
            GK.Warn(("Shame list: %s joined your group%s"):format(name, TagSuffix(s.tags.watch)), true)
        end
        if #s.lists.kudos > 0 and GK.db.kudosGroup then
            print(("%s: |cff4dff66Kudos:|r %s joined your group%s"):format(GK.TAG, name, TagSuffix(s.tags.kudos)))
        end
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i) end
    else
        for i = 1, 4 do Add("party" .. i) end
    end
    lastGroup = current
end

-- ---------------------------------------------------------------------------
-- The alert style
-- ---------------------------------------------------------------------------
local warnNotice = GK.Warn

local function RaidWarning(text)
    local colour = ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]
    if RaidWarningUtil and RaidWarningUtil.AddMessage then
        RaidWarningUtil.AddMessage(text, colour)
    elseif RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, colour)
    end
end

--- Every warning of the addon, in the style the player chose: the notice's red glow (Notice.lua), or a
--- raid warning in the middle of the screen and a line in chat.
GK.Warn = function(text, urgent)
    if GK.db and GK.db.alertStyle == "raid" then
        RaidWarning(text)
        GK.Sound("RAID_WARNING")
        print(GK.TAG .. ": " .. text)
        return
    end
    return warnNotice(text, urgent)
end

-- ---------------------------------------------------------------------------
-- After the import: tell the guild what is now mine
-- ---------------------------------------------------------------------------
local importGuildGrudge = GK.ImportGuildGrudge
--- The import makes records of mine that the guild has not heard (my notes from Guild Grudge), so they go out.
GK.ImportGuildGrudge = function(force)
    local counts, why = importGuildGrudge(force)
    if counts then GK.NotesBroadcast() end
    return counts, why
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
-- This file loads before Options.lua, which makes the list: start it here if it isn't there yet.
GK.OptionSections = GK.OptionSections or {}
GK.OptionSections[#GK.OptionSections + 1] = function(f, anchor, h)
    local head = h.Section(anchor, "Notes")
    local alerts = h.Check(head, "Warn me when a Marked player is near", "noteAlerts",
        "Off by default. A player you or a guildie wrote a note on, with no kill order on them, near you: the "
        .. "same warning as for a kill order's target, at most every 90 seconds per player.")
    local nearby = h.Check(alerts, "A chat line when a Shame list player is near", "watchNearby",
        "Off by default. One line in chat, no sound, at most every 90 seconds per player.")
    local group = h.Check(nearby, "Warn me when a Shame list player joins my group", "watchGroup",
        "On by default. A warning with their tag, so a ninja looter does not slip into the raid.")
    local kudos = h.Check(group, "A chat line when a Kudos player joins my group", "kudosGroup",
        "On by default. One friendly line in chat, no sound.")
    local plate = h.Check(kudos, "Mark the nameplates of players I have notes on", "plateNotes",
        "On by default. A small dim mark beside the nameplate: a cross for Marked, an exclamation for "
        .. "Shame, a tick for Kudos. Needs nameplates on (V).")
    local style = h.Box(plate, "Raid warning instead of the scroll's glow", "Off by default. Every warning, "
        .. "Grudgekeeper's own \"is near\" included, shows as a raid warning in the middle of the screen, with "
        .. "its sound, instead of the scroll's red glow.", function(on)
            GK.db.alertStyle = on and "raid" or "scroll"
            GK.Changed()
        end)
    -- not one of Options.lua's Checks, so it sets its own box each time the page is shown
    local function Set() style:SetChecked(GK.db.alertStyle == "raid") end
    style:SetScript("OnShow", Set)
    Set()
    local note = h.Note(f, "|cffffd100/grudge note|r [first surname] <text> writes a note (no name: your target).  "
        .. "|cffffd100/grudge shame|r and |cffffd100/grudge kudos|r <first> <surname> [text] put a player on a list.\n"
        .. "|cffffd100/grudge nice|r <first> <surname> adds a funny name.  |cffffd100/grudge move|r <first> "
        .. "<surname> marked|shame|kudos|none moves your mark.\n|cffffd100/grudge notes|r, |cffffd100shame|r, "
        .. "|cffffd100kudos|r and |cffffd100names|r with no name open their pages.  "
        .. "|cffffd100/grudge import|r takes over Guild Grudge's notes (import force: again).")
    note:SetPoint("TOPLEFT", style, "BOTTOMLEFT", 4, -10)
    return note
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local USAGE = {
    note = "Usage: /grudge note [first surname] <text> - with no name, a note on your target.",
    watch = "Usage: /grudge shame <first> <surname> [text] - or just a note, for your target.",
    kudos = "Usage: /grudge kudos <first> <surname> [text] - or just a note, for your target.",
    nice = "Usage: /grudge nice <first> <surname> - or with no name, your target.",
    move = "Usage: /grudge move <first> <surname> marked|shame|kudos|none - or without a name, your target.",
}
local MOVES = { kos = "kos", marked = "kos", watch = "watch", shame = "watch", kudos = "kudos", none = false, off = false, remove = false }

local function Words(s)
    local words = {}
    for w in s:gmatch("%S+") do words[#words + 1] = w end
    return words
end

--- The line without its first n words.
local function After(s, n)
    for _ = 1, n do s = s:gsub("^%s*%S+", "", 1) end
    return strtrim(s)
end

--- What a notes command asks for. cmd is note, watch, kudos, nice or move; rest is the line after it;
--- target is the key of the player you have targeted (or nil); known(key) says whether we keep anything on
--- that name already. Forever names are two words, "First Surname". Returns { key, text, list, clear } or
--- nil and the usage line.
function GK.ParseNotesCommand(cmd, rest, target, known)
    if cmd == "shame" then cmd = "watch" end    -- /grudge shame is what the player sees, watch still works
    rest = strtrim(rest or "")
    local w = Words(rest)
    local function Named() return GK.KeyOf(w[1] .. " " .. w[2]) end
    if cmd == "note" then
        if #w == 0 then return nil, USAGE.note end
        -- the first two words are a name only when it is a name we know: "he stole my loot" is a note
        if #w >= 2 and known(Named()) then
            local text = After(rest, 2)
            if text == "" then return nil, USAGE.note end
            return { key = Named(), text = text }
        end
        if target then return { key = target, text = rest } end
        if #w >= 3 then return { key = Named(), text = After(rest, 2) } end
        return nil, USAGE.note
    elseif cmd == "watch" or cmd == "kudos" then
        if #w >= 2 then return { key = Named(), text = After(rest, 2), list = cmd } end
        if target then return { key = target, text = rest, list = cmd } end
        return nil, USAGE[cmd]
    elseif cmd == "nice" then
        if #w >= 2 then return { key = Named() } end
        if #w == 0 and target then return { key = target } end
        return nil, USAGE.nice
    elseif cmd == "move" then
        local to = #w > 0 and MOVES[w[#w]:lower()]
        if to == nil or #w == 0 then return nil, USAGE.move end
        if #w == 3 then return { key = Named(), list = to or nil, clear = to == false } end
        if #w == 1 and target then return { key = target, list = to or nil, clear = to == false } end
        return nil, USAGE.move
    end
    return nil, nil
end

local function Say(text) print(GK.TAG .. ": " .. text) end

local function KnownName(key)
    return key ~= nil and (GK.IsNoted(key) or GK.Store().names[key] ~= nil or (LIB.roster and LIB.roster[key] ~= nil))
end

--- Run one of our subcommands. true when cmd was one of ours.
function GK.RunNotesCommand(cmd, rest)
    if cmd == "shame" then cmd = "watch" end
    if cmd == "notes" then
        GK.OpenNotes("kos")
        return true
    elseif cmd == "names" or ((cmd == "watch" or cmd == "kudos") and strtrim(rest or "") == "") then
        GK.OpenNotes(cmd)                   -- with a name they keep adding (below)
        return true
    elseif cmd == "import" then
        local counts, why = GK.ImportGuildGrudge(strtrim(rest or ""):lower() == "force")
        if not counts then
            Say(why == "done" and "Guild Grudge's notes are taken over already - /grudge import force does it again."
                or why == "nothing to import" and "Guild Grudge has nothing saved here - is it enabled?"
                or "Not ready yet - try again in a moment.")
        end
        return true
    end
    local t = ReadPlayer("target")
    local r, usage = GK.ParseNotesCommand(cmd, rest, t and t.key, KnownName)
    if not r then
        if usage then Say(usage) end
        return usage ~= nil
    end
    local info = (t and t.key == r.key) and t or { key = r.key }
    local name = GK.Show(r.key)
    if cmd == "nice" then
        local ok, why = GK.AddNiceName(r.key, info)
        Say(ok and (name .. " is on the nice names list.") or why)
    elseif cmd == "move" then
        if GK.SetMark(r.key, r.list) then
            Say(r.list and ("%s is on your %s list."):format(name, WORD[r.list]) or (name .. " is off your lists."))
        else
            Say("That didn't work.")
        end
    else
        local ok, why = GK.WriteNote(info, r.list, r.text, nil)
        Say(ok and ("Written down on %s."):format(name) or why)
    end
    return true
end

local OURS = { note = true, watch = true, shame = true, kudos = true, nice = true, move = true, notes = true, names = true,
    import = true }
-- what Core.lua's /grudge answers itself; anything else it meets it answers with its help
local CORE = { orders = true, hitlist = true, board = true, leaderboard = true, post = true, letters = true,
    read = true, test = true, notice = true, options = true, settings = true, debug = true }

local function PrintHelp()
    print("  /grudge note [first surname] <text>  - write a note on a player (no name: your target)")
    print("  /grudge shame <first> <surname> [text]  - put a player on your Shame list")
    print("  /grudge kudos <first> <surname> [text]  - put a player on your Kudos list")
    print("  /grudge nice <first> <surname>  - add a funny character name to the guild's list")
    print("  /grudge move <first> <surname> marked|shame|kudos|none  - move your mark on a player")
    print("  /grudge notes  - open the Marked page (/grudge shame, kudos and names open theirs)")
    print("  /grudge import  - take over Guild Grudge's notes (import force: again)")
end

local coreSlash = SlashCmdList.GRUDGEKEEPER
SlashCmdList.GRUDGEKEEPER = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower()
    if cmd and OURS[cmd] then
        GK.RunNotesCommand(cmd, rest)
        return
    end
    coreSlash(msg)
    if cmd and not CORE[cmd] then PrintHelp() end
end

-- ---------------------------------------------------------------------------
-- Startup
-- ---------------------------------------------------------------------------
-- Core.lua loads first, so its own login handler has made GK.db and GK.char by the time this runs.
LIB.On("PLAYER_LOGIN", function()
    if not (GK.db and GK.char) then return end
    -- /gg, for Guild Grudge's players; never when Guild Grudge is there to answer to it
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("GuildGrudge")) then
        SLASH_GRUDGEKEEPERGG1 = "/gg"
        SlashCmdList.GRUDGEKEEPERGG = function(msg) SlashCmdList.GRUDGEKEEPER(msg) end
    end
    if Menu and Menu.ModifyMenu then
        -- pcall: a menu tag this client doesn't have must not stop the others
        pcall(Menu.ModifyMenu, "MENU_UNIT_ENEMY_PLAYER", OnNotesMenu)
        for _, which in ipairs(FRIENDLY) do pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, OnNotesMenu) end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnNoteTip)
    end
    LIB.On("NAME_PLATE_UNIT_ADDED", function(unit)
        if type(unit) ~= "string" then return end
        plates[unit] = true
        Look(unit)
    end)
    LIB.On("NAME_PLATE_UNIT_REMOVED", function(unit)
        if type(unit) ~= "string" then return end
        plates[unit] = nil
        Unmark(unit)
    end)
    LIB.On("PLAYER_TARGET_CHANGED", function() Look("target") end)
    LIB.On("UPDATE_MOUSEOVER_UNIT", function() Look("mouseover") end)
    LIB.On("GROUP_ROSTER_UPDATE", GK.CheckNotesGroup)
    LIB.Listen("GRUDGEKEEPER_CHANGED", RefreshPlates)
end)
