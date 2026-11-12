-- Grudgekeeper - the notes, as the ledger shows them (the data is Notes.lua). What you see of them:
--   the list pages      three tabs in the ledger: Marked (after Grudges, among the owner's), then Shame and
--                       Kudos over the right page
--   cards               the small card for a noted player, and a line or two on the
--                       wanted poster and the record when there are notes on that player
--   the note sheet      in the game's own frame: whom, the list, a tag, a few words, Save
--   the right-click menu   a Grudgekeeper notes submenu on any player, friend or foe
--   quiet marks         a line on the tooltip, a dim mark on the nameplate. They never open anything
--   warnings            only when asked: a Marked player near (off by default), a Shame player
--                       near (off), a Shame player joining your group (on), a Kudos one (a chat line, off)
-- It also wraps a few functions of the other files (docs/guild-grudge-merge.md, H7): the poster and
-- record cards, the tooltip line and /grudge. Each wrapper calls the
-- original, and changes nothing unless its own setting or a notes command asks.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local Secret = GK.Secret

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local COL_RIGHT = 332                    -- Window.lua's right-hand column: the page's width less 36

local ORDER = { "kos", "watch", "kudos" }
local WORD = { kos = "Marked", watch = "Shame", kudos = "Kudos" }
local CARD_TITLE = { kos = "MARKED", watch = "SHAME", kudos = "KUDOS" }
local COLOUR = { kos = "c8281e", watch = "ffcc00", kudos = "4dff66" }
local NEAR_GAP = 90                      -- the same player warns you at most this often
local MAX_CARD_LINES = 9                 -- what the ledger's card has room for
local CARD_NOTES = 5                     -- notes on a card before "and 3 more"
local MENU_NOTES = 10                    -- notes a menu lists at once to vote on or delete; more go in submenus of this many

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
        into[#into + 1] = n
    end
    local function Label(n) return n.text and Short(n.text, 36) or ("[" .. (n.tag and GK.TagText(n.tag, 12) or "?") .. "]") end
    -- Every note can be reached: a few go straight in the menu, more are split into "Notes 1-10", "Notes 11-20"...
    local function EachNote(parent, notes, add)
        if #notes <= MENU_NOTES then
            for _, n in ipairs(notes) do add(parent, n) end
            return
        end
        for first = 1, #notes, MENU_NOTES do
            local last = math.min(first + MENU_NOTES - 1, #notes)
            local page = parent:CreateButton(("Notes %d-%d"):format(first, last))
            for i = first, last do add(page, notes[i]) end
        end
    end
    if #theirs > 0 then
        local vote = root:CreateButton("Vote on a note")
        EachNote(vote, theirs, function(parent, n)
            local sub = parent:CreateButton(Who(n.author) .. ": " .. Label(n))
            if n.myVote ~= 1 then sub:CreateButton("Up", function() GK.VoteNote(key, n.author, n.id, 1) end) end
            if n.myVote ~= -1 then sub:CreateButton("Down", function() GK.VoteNote(key, n.author, n.id, -1) end) end
            if n.myVote ~= 0 then sub:CreateButton("Take back", function() GK.VoteNote(key, n.author, n.id, 0) end) end
        end)
    end
    if #mine > 0 then
        local del = root:CreateButton("Delete my note")
        EachNote(del, mine, function(parent, n) parent:CreateButton(Label(n), function() GK.DeleteNote(key, n.id) end) end)
    end
    if IsEnemy(key, p) then
        root:CreateButton("Open their poster", function() GK.ShowPoster({ key = key, c = p.c, r = p.r, l = p.l }) end)
    end
end

-- ---------------------------------------------------------------------------
-- The three list pages
-- ---------------------------------------------------------------------------
-- A page each, because the list is the tab: Marked is the enemy's page, on the left between Grudges and
-- News; Shame and Kudos are the friendly ones, over the right page (side = "right").
local PAGE_WORD = { kos = "Marked", watch = "Shame", kudos = "Kudos" }
local EMPTY = {
    kos = "Nobody is marked. Right-click an enemy and pick Grudgekeeper notes to mark them.",
    watch = "Nobody is on your Shame list. It is for players to be careful with - a ninja looter, a scammer. "
        .. "Use Put someone on Shame, at the top of this page - someone who just left your group is on its list.",
    kudos = "Nobody has kudos yet. Use Give someone kudos, at the top of this page, or right-click a good "
        .. "player and pick Grudgekeeper notes.",
}

-- each list page's own action, at the top of the page: it opens the who-picker (Pick.lua)
local ADD = { watch = "Put someone on Shame", kudos = "Give someone kudos" }

--- Did I vote, one way or the other, on a note of this player's? Mine only keeps such a row (D9).
local function VotedOn(p)
    local me = LIB.Me()
    for _, group in pairs(p.votes) do
        local vote = me and group[me]
        if vote and vote.v ~= 0 then return true end
    end
    return false
end

--- The rows of one list, and the text for when there are none. list: kos, watch or kudos.
function GK.NotesItems(list)
    local items = {}
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
        items[#items + 1] = { key = "p:" .. key, name = GK.Show(key), face = { key = key, c = p.c, rf = p.rf, sx = p.sx },
            sub = table.concat(bits, " - "), right = e.score ~= 0 and ScoreText(e.score) or "", ts = e.ts,
            votes = e.score, own = (e.mine or VotedOn(p)) or nil,
            select = { kind = "card", make = function() return GK.NoteCard(key, list) end } }
    end
    -- the page's own order: the newest news first
    table.sort(items, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.name < b.name
    end)
    return items, EMPTY[list]
end

-- ---------------------------------------------------------------------------
-- The watched guild (Notes.lua), as a section of the kill orders page under Marked, and its card
-- ---------------------------------------------------------------------------
--- The card for the watched guild: who put it on watch and when, who of theirs we saw lately, and for an
--- officer the way to take it off. nil when it is not the watched guild (any more).
function GK.GuildCard(guild)
    local name, by, ts = GK.WatchedGuild()
    if not GK.SameGuild(name, guild) then return nil end
    guild = name                    -- as it is spelled now: a name typed in gets the game's spelling later
    local d = { title = "WATCHED GUILD", name = "<" .. guild .. ">", info = "Anyone of theirs near warns you.",
        lines = {}, buttons = {}, seal = "mark" }
    d.lines[1] = ("Put on watch by %s, %s."):format(by and Who(by) or "an officer", GK.Ago(ts))
    local seenNow = GK.GuildSeen and GK.GuildSeen(guild, 5) or {}
    if #seenNow == 0 then
        d.lines[2] = "Nobody of theirs seen in the last 15 minutes."
    else
        for _, s in ipairs(seenNow) do
            d.lines[#d.lines + 1] = ("Seen: %s%s"):format(GK.Show(s.key), s.z and (", " .. s.z) or "")
        end
    end
    if GK.CanWatchGuild() then
        d.buttons[1] = { "Stop watching", function() GK.WatchGuild(guild, false) end }
    end
    return d
end

--- The kill orders page's row for the watched guild, or none.
function GK.WatchedGuildItems()
    local name, by = GK.WatchedGuild()
    if not name then return {} end
    return { { key = "g:" .. name, name = "<" .. name .. ">", face = {},
        sub = "on watch - put there by " .. (by and Who(by) or "an officer"), right = "",
        own = (by ~= nil and by == LIB.Me()) or nil,
        select = { kind = "card", make = function() return GK.GuildCard(name) end } } }
end

-- The friendly lists have pages of their own, at the right. Marked has none since 2026-11-07: it is a
-- section of the kill orders page (Window.lua), as kill orders and Most wanted say the rest of it.
for _, list in ipairs({ "watch", "kudos" }) do
    GK.AddLedgerPage({
        name = PAGE_WORD[list], list = list, sortable = true, side = "right", add = { text = ADD[list], kind = list },
        max = GK.LIST_MAX,                  -- the latest 25 (Window.lua): "ikke evig pages" (the owner, 2026-11-10)
        -- its tab folded, down the frame's side (Window.lua): a rogue in the shadows for the ninja looters,
        -- a gift for a good player
        icon = "Interface\\Icons\\" .. (list == "watch" and "Ability_Stealth" or "INV_Misc_Gift_02"),
        items = function() return GK.NotesItems(list) end,
        headings = { { "Player", 48, nil, "name", "name, A to Z" }, { "Votes", COL_RIGHT, "RIGHT", "votes", "votes" } },
        -- how many are on it, all of them, and how many of those the page lists when not all
        sub = function(items, all)
            all = all or #items
            local text = ("%s on %s"):format(Plural(all, "player"), PAGE_WORD[list])
            return all > #items and ("%s - the latest %d here"):format(text, #items) or text
        end,
    })
end

--- Open the ledger at the page of a list: "watch" or "kudos"; Marked, and anything else, is on the kill
--- orders page, the first.
function GK.OpenNotes(list)
    for i, def in ipairs(GK.LedgerPages) do
        if def.list == list then return GK.OpenWindow(i) end
    end
    GK.OpenWindow(1)
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
        -- the ledger's card: a Notes section of its own, before the news (which gives way when room runs out)
        if lines and d.rich then
            local rows = {}
            for i, line in ipairs(lines) do
                local label, value = line:match("^(%a+): (.+)$")
                rows[i] = { label, value or line }
            end
            local at = #d.rich.sections + 1
            for i, sec in ipairs(d.rich.sections) do
                if sec.kind == "events" then at = i break end
            end
            table.insert(d.rich.sections, at, { head = "Notes", kind = "facts", rows = rows })
        end
        return d
    end
end
WrapCard("PosterCard")
WrapCard("RecordCard")

-- ---------------------------------------------------------------------------
-- Writing a note
-- ---------------------------------------------------------------------------
--- What the note sheet does with "Save". t = { key, c, r, rf, sx, l }. A note needs a few words or a
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
-- In the game's frame on parchment (Letters.lua, GK.MakeFrameSheet): the head, the list's radio buttons,
-- the tags in two columns, your own tag, the note, Save and Cancel; the parts named as the kill order's
-- are, in small capitals over a rule. What comes after the tags moves with how many rows they take, and
-- the frame's height with it, so no list leaves a hole.
local SHEET_W = 340
local LIST_Y, TAG_Y, TAGS_Y, TAG_GAP, TAG_COL = 96, 144, 162, 20, 148
local MAX_TAGS = 10                      -- two columns of five
-- Each list's seal beside its name: the black skull for Marked, the red one for Shame, and for Kudos
-- the gold laurel the leaderboard's first place wears.
local SEAL = { kos = "seal_black", watch = "seal_red", kudos = "rank_1" }
local HINT = "Up to 200 letters. A tag or a list is enough on its own."
-- in the skin's colours (Core.lua), as the sheet is in the game's frame: parchment ink, or classic white
-- and gold - and drawn again when the skin is switched
local INK, FADED, BLOOD = GK.INK, GK.FADED, GK.BLOOD
local function Ink(fs, colour, size) GK.Ink(fs, colour, GK.TEXT_FONT, size) end

--- One of the game's radio buttons, with a picture and words in ink beside it; the words are part of
--- what you click. Set(text, on).
local function Choice(parent, size, textSize, onClick)
    local b = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    b:SetSize(16, 16)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(size, size)
    b.icon:SetPoint("LEFT", b, "RIGHT", 4, 0)
    b.label = b:CreateFontString(nil, "ARTWORK")
    Ink(b.label, INK, textSize)
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    function b:Set(text, on)
        self.on = on and true or false
        self.label:SetText(text)
        self:SetChecked(self.on)
        self:SetHitRectInsets(0, -(size + 8 + math.ceil(self.label:GetStringWidth() or 40)), 0, 0)
    end
    b:SetScript("OnClick", onClick)
    return b
end

--- The lists' and tags' radio buttons for the draft, and the rest of the sheet placed under the tags.
local function LayoutSheet()
    for i, list in ipairs(ORDER) do sheet.lists[i]:Set(WORD[list], draft.list == list) end
    local tags = GK.KnownTags(draft.list)
    local shown = math.min(#tags, MAX_TAGS)
    for i, b in ipairs(sheet.tags) do
        local tag = i <= shown and tags[i] or nil
        b.tag = tag
        b:SetShown(tag ~= nil)
        if tag then
            b.icon:SetTexture(GK.TagIcon(tag))
            b:Set(tag, draft.tag == tag)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", sheet, "TOPLEFT", 30 + ((i - 1) % 2) * TAG_COL,
                -(TAGS_Y + math.floor((i - 1) / 2) * TAG_GAP))
        end
    end
    sheet.noTags:SetShown(shown == 0)
    local y = TAGS_Y + math.max(1, math.ceil(shown / 2)) * TAG_GAP + 4
    sheet.custom:ClearAllPoints()
    sheet.custom:SetPoint("TOPLEFT", 36, -y)
    sheet.noteLabel:Place(y + 34)
    sheet.note:ClearAllPoints()
    sheet.note:SetPoint("TOPLEFT", 36, -(y + 52))
    sheet:SetHeight(y + 150)         -- the note at y + 52, the line under it (two for a refusal), the buttons
end

--- The line under the note: what it takes, or in blood why it couldn't be written - on the sheet, where
--- the eye is, not in chat.
local function SayOnSheet(why)
    Ink(sheet.hint, why and BLOOD or FADED, 10)     -- the font first: the game refuses text before it
    sheet.hint:SetText(why or HINT)
end

local function BuildSheet()
    local f = GK.MakeFrameSheet("GrudgekeeperNoteSheet", SHEET_W, 360, "Grudgekeeper notes")
    sheet = f
    f.head = GK.FrameHead(f, SHEET_W)
    f.name, f.info = f.head.name, f.head.info

    GK.SheetSection(f, "List", LIST_Y)
    f.lists = {}
    for i, list in ipairs(ORDER) do
        local b = Choice(f, 20, 13, function()
            draft.list, draft.tag = list, nil       -- the tags belong to the list
            LayoutSheet()
        end)
        b.icon:SetTexture(MEDIA .. SEAL[list])
        b:SetPoint("TOPLEFT", 30 + (i - 1) * 98, -(LIST_Y + 20))
        f.lists[i] = b
    end

    GK.SheetSection(f, "Tag", TAG_Y)
    f.tags = {}
    for i = 1, MAX_TAGS do
        local b = Choice(f, 14, 12, function(self)
            draft.tag = (draft.tag ~= self.tag) and self.tag or nil     -- a second click lets it go
            f.custom:SetText("")
            LayoutSheet()
        end)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)          -- the icon's own dark border trimmed off
        f.tags[i] = b
    end
    f.noTags = f:CreateFontString(nil, "ARTWORK")
    Ink(f.noTags, FADED, 11)
    f.noTags:SetPoint("TOPLEFT", 30, -(TAGS_Y + 3))
    f.noTags:SetText("No ready tags for this list: write your own.")
    f.custom = GK.FrameBox(f, 200, GK.MAX_TAG, "or write your own tag")
    f.custom:HookScript("OnTextChanged", function(_, byHand)
        if byHand then
            draft.tag = nil
            LayoutSheet()
        end
    end)

    f.noteLabel = GK.SheetSection(f, "Note", 0)
    f.note = GK.FrameBox(f, SHEET_W - 68, 200, "a few words on what happened")
    f.hint = f:CreateFontString(nil, "ARTWORK")
    f.hint:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", -6, -8)
    f.hint:SetWidth(SHEET_W - 60)
    f.hint:SetJustifyH("LEFT")
    SayOnSheet()

    f.save = GK.FrameButton(f, "Save", 96, function()
        local tag = strtrim(f.custom:GetText() or "")
        local ok, why = GK.WriteNote(draft.t, draft.list, f.note:GetText(), tag ~= "" and tag or draft.tag)
        if not ok then return SayOnSheet(why or "The note couldn't be written.") end
        GK.Sound("IG_QUEST_LIST_OPEN")
        f:Hide()
    end)
    f.save:SetPoint("BOTTOMRIGHT", -20, 16)
    local cancel = GK.FrameButton(f, CANCEL or "Cancel", 96, function() f:Hide() end)
    cancel:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
end

--- Open the note sheet for a player: t = { key, c, r, rf, sx, l, unit }, list = "kos", "watch" or "kudos"
--- (kos when it is anything else).
function GK.OpenNoteSheet(t, list)
    if not (t and t.key) then return end
    if not sheet then BuildSheet() end
    local known = false
    for _, l in ipairs(ORDER) do known = known or l == list end
    draft = { t = t, list = known and list or "kos" }
    sheet.head:Set(t)
    sheet.custom:SetText("")
    sheet.note:SetText("")
    SayOnSheet()
    LayoutSheet()
    GK.PlaceSheet(sheet)
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
    local key = GK.UnitKey(unit)
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
-- the who-picker (Pick.lua) reads the group with them
GK.UnitPlayerKey = PlayerKey
GK.ReadPlayer = ReadPlayer

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
    -- the Shame line stands in only when the Marked warning will not run (a player can be on both lists)
    local line = not warn and watch and GK.db.watchNearby
    if not (warn or line) then return end
    local now = GetTime()
    if nearAt[key] and now - nearAt[key] < NEAR_GAP then return end
    PruneNear(now)
    nearAt[key] = now
    local name = GK.Show(key)
    if warn then
        GK.Warn(("Marked: %s is near!%s"):format(name, TagSuffix(s.tags.kos)), true, nil, key, key)
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

--- The sound for a Shame player joining: the one picked in the settings, the chime when that one can't be
--- played (a warning must never go silent because a file went missing), nothing for None.
local function ShameSound()
    local key = GK.ShameSoundKey()
    if not GK.db.sound or key == "off" then return end
    if not GK.PlayChoice(key) then GK.Sound("UI_RAID_BOSS_WHISPER_WARNING") end
end

--- Who joined the group since the last update: Shame warns, Kudos says one friendly line.
function GK.CheckNotesGroup()
    if not (GK.db and GK.char) then return end
    local current, shamed = {}, false
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
            GK.Warn(("Shame list: %s joined your group%s"):format(name, TagSuffix(s.tags.watch)), true, true)
            shamed = true
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
    -- one sound however many of them joined at once
    if shamed then ShameSound() end
end

-- (Guild Grudge's raid-warning alert style was left out of the merge, 2026-11-05: Grudgekeeper's warnings
-- are the letter's red glow and chime - letters, never popups.)

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
-- A sound to pick, under its box: the game's own dropdown. Picking one plays it, so you hear what you chose,
-- and picking the same one again plays it again. No dropdown in this client: no row. get() is the key in use,
-- set(key) keeps a new one; for a Shame player joining here, and for a target near (Options.lua). `text`
-- names the row ("Sound" when none): a row with a name gets a label of one width, so a list lines up.
function GK.SoundRow(f, above, get, set, text)
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(400, 28)
    row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -2)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", 30, 0)                 -- under the box's label, not its box
    label:SetText(text or "Sound")
    if text then label:SetWidth(120) label:SetJustifyH("LEFT") end
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    if not (ok and type(dd) == "table" and dd.SetupMenu) then
        label:Hide()
        row:SetHeight(1)
        return row
    end
    dd:SetWidth(200)
    dd:SetPoint("LEFT", label, "RIGHT", 10, 0)
    -- shown when the one picked is gone (a sound pack uninstalled): the chime is what then plays
    if dd.SetDefaultText then dd:SetDefaultText("The chime") end
    dd:SetupMenu(function(_, root)
        for _, c in ipairs(GK.SoundChoices()) do
            local key = c[1]
            root:CreateRadio(c[2], function() return get() == key end, function()
                set(key)
                GK.PlayChoice(key)
            end)
        end
    end)
    row.dropdown = dd
    return row
end

-- This file loads before Options.lua, which makes the list: start it here if it isn't there yet.
GK.OptionSections = GK.OptionSections or {}
GK.OptionSections[#GK.OptionSections + 1] = function(f, anchor, h)
    -- short names, what each does in its (i); the slash commands are on the CurseForge page, not here
    local head = h.Section(anchor, "Notes")
    local alerts = h.Check(head, "When a Marked player is near", "noteAlerts", "The same warning as for a kill order's target.")
    local nearby = h.Check(alerts, "When a Shame player is near", "watchNearby", "One line in chat, no sound.")
    local group = h.Check(nearby, "When a Shame player joins my group", "watchGroup",
        "A warning with their tag, and the sound below.")
    local sound = GK.SoundRow(f, group, GK.ShameSoundKey, function(key) GK.db.shameSound = key end)
    sound.which = "shame"
    local kudos = h.Check(sound, "When a Kudos player joins my group", "kudosGroup", "One friendly line in chat.")
    local plate = h.Check(kudos, "Mark their nameplates", "plateNotes",
        "A small mark beside players you have notes on. Needs nameplates on (V).")
    return plate
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local USAGE = {
    note = "Usage: /grudge note [first surname] <text> - with no name, a note on your target.",
    watch = "Usage: /grudge shame <first> <surname> [text] - or just a note, for your target.",
    kudos = "Usage: /grudge kudos <first> <surname> [text] - or just a note, for your target.",
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

--- What a notes command asks for. cmd is note, watch, kudos or move; rest is the line after it;
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
    return key ~= nil and (GK.IsNoted(key) or (LIB.roster and LIB.roster[key] ~= nil))
end

--- Run one of our subcommands. true when cmd was one of ours.
function GK.RunNotesCommand(cmd, rest)
    if cmd == "shame" then cmd = "watch" end
    if cmd == "notes" then
        GK.OpenNotes("kos")
        return true
    elseif (cmd == "watch" or cmd == "kudos") and strtrim(rest or "") == "" then
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
    if cmd == "move" then
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

local OURS = { note = true, watch = true, shame = true, kudos = true, move = true, notes = true, import = true }
-- what Core.lua's /grudge answers itself; anything else it meets it answers with its help
local CORE = { orders = true, hitlist = true, board = true, leaderboard = true, post = true, letters = true,
    read = true, test = true, notice = true, options = true, settings = true, debug = true, guild = true }

local function PrintHelp()
    print("  /grudge note [first surname] <text>  - write a note on a player (no name: your target)")
    print("  /grudge shame <first> <surname> [text]  - put a player on your Shame list")
    print("  /grudge kudos <first> <surname> [text]  - put a player on your Kudos list")
    print("  /grudge move <first> <surname> marked|shame|kudos|none  - move your mark on a player")
    print("  /grudge notes  - open the kill orders page, where Marked is (/grudge shame and kudos open theirs)")
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
