-- Grudgekeeper - notes on players: what the guild writes down about the people it meets. A free-text
-- note with a tag, a mark that puts a player on one of three lists (Marked, Shame, Kudos),
-- votes on notes, and a guild-shared list of funny character names. This file is the data and the
-- wire only; it makes no frames. The pages, menus and tooltip lines that show it are elsewhere.
-- It follows Guild.lua's rule: everyone sends only their OWN things - their notes, their marks, their
-- votes, their nice names - and the author of a record is always the SENDER of the message, never a
-- field in it, so nobody can write in another player's name. A client never re-sends what someone
-- else wrote. Every record is last-writer-wins by the author's time, per author and id; a delete is a
-- record kept 30 days (a tombstone) so a late sync can't bring the note back.
-- Messages on their own prefix, GrudgeNotes, fields separated by ';' (every text goes through GK.Clean
-- on the way in and out). A field added later goes on the END, so an older client reads what it knows
-- and ignores the rest:
--   N;1;key;id;ts;del;tag;c;r;l;text        my note (del: 1 or empty)
--   L;1;key;list;ts;del;c;r;l               my mark: which list I put them on
--   V;1;key;author;id;v;ts                  my vote on author's note id (v: 1, -1 or 0 to take it back)
--   M;1;key;ts;del;c;r;rf;sx;l              my nice name
--   G;1;key;v;ts                            my vote on a nice name
--   H;1;key;on;ts                           I hide (1) or show (0) a nice name - officers only
--   Q;1                                     tell me yours (at login)
-- Worst case a guild can make us keep: 500 people, 300 names, 20 live notes per author per player,
-- 100 voted-on notes per player, 300 voters on one. Every sender is also held to LibForever's
-- 30 messages / 10 s.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local PREFIX = "GrudgeNotes"
GK.NOTES_PREFIX = PREFIX
local PROTO = 1
local MAX_TEXT = 200
local MAX_NOTES = 20                        -- live notes per author per player
local MAX_PEOPLE = 500
local MAX_NAMES = 300
local MAX_VOTE_GROUPS = 100                 -- notes with votes, per player
local MAX_VOTERS = 300                      -- voters on one note or one name
local MAX_REPLY = 150                       -- records one client answers a Q with
local KEEP_TOMBSTONE = 30 * GK.DAY
local LISTS = { kos = true, watch = true, kudos = true }
local NONE = {}                             -- the usual answer, shared: callers only ever read it

GK.MAX_TAG = 24
-- Suggested tags per list; a player can type their own. Marked has none: its notes say why.
GK.TAGS = {
    watch = { "Ninja looter", "Scammer", "Toxic", "Griefer", "Leaver" },
    kudos = { "Helpful", "Kind", "Skilled", "Great healer", "Great tank", "Fair looter", "Fun to group with" },
}

-- One icon per preset tag, so a tag can be told apart at a glance; a tag a player typed gets the note.
local TAG_ICON = {
    ["Ninja looter"] = "Ability_Stealth", ["Scammer"] = "INV_Misc_Coin_01", ["Toxic"] = "Spell_Nature_NullifyPoison",
    ["Griefer"] = "Spell_Shadow_Possession", ["Leaver"] = "Ability_Rogue_Sprint",
    ["Helpful"] = "Spell_Holy_Renew", ["Kind"] = "INV_Misc_Gift_01", ["Skilled"] = "Ability_DualWield",
    ["Great healer"] = "Spell_Holy_FlashHeal", ["Great tank"] = "Ability_Warrior_DefensiveStance",
    ["Fair looter"] = "INV_Misc_Bag_08", ["Fun to group with"] = "INV_Drink_04",
}
local CUSTOM_ICON = "INV_Misc_Note_01"

--- The texture path of a tag's icon: the preset's own, or the note for any other tag. nil for no tag.
function GK.TagIcon(tag)
    if type(tag) ~= "string" or tag == "" then return nil end
    return "Interface\\Icons\\" .. (TAG_ICON[tag] or CUSTOM_ICON)
end

--- A tag as shown to a player: its icon, then the words. size is the icon's side in pixels (14). "" for no tag.
function GK.TagText(tag, size)
    local icon = GK.TagIcon(tag)
    if not icon then return "" end
    size = size or 14
    return ("|T%s:%d:%d|t %s"):format(icon, size, size, tag)
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

--- A player key as other players may send it: clean, "Name-Realm", not absurdly long. nil otherwise.
local function ValidKey(s)
    s = GK.Clean(s, 64)
    return (s and s:find("-", 1, true)) and s or nil
end

--- A time from another client. One from far in the future would never lose to an honest edit, so it
--- counts as at most a day ahead.
local function Ts(v)
    v = Int(v, 1, 2 ^ 31)
    return v and math.min(v, time() + GK.DAY)
end

--- The time for my next change to a record: now, and always after the version I'm replacing.
local function NextTs(old)
    local now = time()
    if old and (old.ts or 0) >= now then return old.ts + 1 end
    return now
end

local function Vote(v)
    v = tonumber(v)
    if v == 1 or v == -1 or v == 0 then return v end
    return nil
end

--- What a client may say about a player or a name beyond its key: class file, race, race file, sex
--- (2 or 3) and level. Each field that isn't valid is nil.
local function ParseInfo(c, r, rf, sx, l)
    return {
        c = GK.ValidClass(c),
        r = GK.Clean(r, 20),
        rf = (type(rf) == "string" and #rf <= 20 and rf:match("^%a+$")) and rf or nil,
        sx = Int(sx, 2, 3),
        l = GK.ValidLevel(l),
    }
end

--- The guild's notes, in its store, made when first needed.
local function Tables()
    local s = GK.Store()
    s.people = s.people or {}
    s.names = s.names or {}
    s.nameVotes = s.nameVotes or {}
    return s
end

local function LiveCount(byId)
    local n = 0
    for _, rec in pairs(byId) do
        if not rec.del then n = n + 1 end
    end
    return n
end

local function HasLive(p)
    for _, m in pairs(p.marks) do
        if not m.del then return true end
    end
    for _, byId in pairs(p.notes) do
        if LiveCount(byId) > 0 then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The wire: reading and writing messages
-- ---------------------------------------------------------------------------
-- One table for the fields of every message, refilled each time, as in Guild.lua. Fields past the
-- sixteenth are ignored.
local fields, fieldCount = {}, 0
local function Split(text)
    local n, start = 0, 1
    while n < 16 do
        local i = text:find(";", start, true)
        n = n + 1
        if not i then
            fields[n] = text:sub(start)
            break
        end
        fields[n] = text:sub(start, i - 1)
        start = i + 1
    end
    for j = n + 1, fieldCount do fields[j] = nil end
    fieldCount = n
    return fields
end

--- Fields joined with ';'. nil travels as an empty field.
local function Msg(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[i] = v == nil and "" or tostring(v)
    end
    return table.concat(parts, ";")
end

local function Send(text)
    -- The test panel (Debug.lua) is open: what its buttons do stays on this client.
    if GK.testMode or not IsInGuild() then return false end
    return LIB.Send(PREFIX, text, "GUILD")
end

-- Each encoder takes what the record holds and cleans it again, so nothing leaves this client that
-- the receiving end would have to throw away.
local Encode = {}

--- My note id on key. A deleted note travels with no text or tag.
function Encode.N(key, id, n, p)
    local live = not n.del
    return Msg("N", PROTO, key, id, n.ts, n.del and 1 or nil, live and GK.Clean(n.tag, GK.MAX_TAG) or nil,
        p.c, p.r, p.l, live and GK.Clean(n.text, MAX_TEXT) or nil)
end

--- My mark on key (m.list is nil in a removed one).
function Encode.L(key, m, p)
    return Msg("L", PROTO, key, m.list, m.ts, m.del and 1 or nil, p.c, p.r, p.l)
end

function Encode.V(key, author, id, v, ts)
    return Msg("V", PROTO, key, author, id, v, ts)
end

--- My nice name; n is the record in store.names.
function Encode.M(key, n)
    return Msg("M", PROTO, key, n.ts, n.del and 1 or nil, n.c, n.r, n.rf, n.sx, n.l)
end

function Encode.G(key, v, ts)
    return Msg("G", PROTO, key, v, ts)
end

function Encode.H(key, on, ts)
    return Msg("H", PROTO, key, on and 1 or 0, ts)
end

function Encode.Q()
    return Msg("Q", PROTO)
end
GK.NotesEncode = Encode

-- ---------------------------------------------------------------------------
-- Writing records: the one place that applies last-writer-wins and the limits
-- ---------------------------------------------------------------------------
-- Messages from others and my own changes both end here, so a limit can't be one that only the
-- network is held to. Each returns true when the record was taken (it was newer, and fit).
local Put = {}
GK.NotesPut = Put

--- Make room for a new player: one with nothing live on them goes. false when everyone has something.
local function MakeRoom(people)
    for key, p in pairs(people) do
        if not HasLive(p) then
            people[key] = nil
            return true
        end
    end
    return false
end

--- Our record of one player, made when first needed (create). nil at the 500 limit.
function GK.Person(key, create)
    if type(key) ~= "string" then return nil end
    local people = Tables().people
    local p = people[key]
    if p or not create then return p end
    if Count(people) >= MAX_PEOPLE and not MakeRoom(people) then return nil end
    p = { n = key, marks = {}, notes = {}, votes = {} }
    people[key] = p
    return p
end

--- What we know about the player's class, race, sex and level: a field is set when info has it. With
--- fill, only a field we don't have yet - what another client says never overwrites what we saw.
local function Learn(p, info, fill)
    if not info then return end
    local function set(field, v)
        if v ~= nil and (not fill or p[field] == nil) then p[field] = v end
    end
    set("c", GK.ValidClass(info.c))
    set("r", GK.Clean(info.r, 20))
    set("rf", (type(info.rf) == "string" and #info.rf <= 20 and info.rf:match("^%a+$")) and info.rf or nil)
    set("sx", Int(info.sx, 2, 3))
    set("l", GK.ValidLevel(info.l))
end

--- A unit we saw told us more about a player we already keep a record of. Never makes a record: every
--- nameplate in the world would fill the book.
function GK.LearnPerson(key, info)
    local p = GK.Person(key, false)
    if p then Learn(p, info, false) end
    return p
end

--- rec = { text, tag, ts, del, imp }. imp marks a note the Guild Grudge import wrote for someone else:
--- its id is ours, not theirs, so a vote on it is never sent.
function Put.Note(key, author, id, rec)
    local p = GK.Person(key, true)
    if not p then return false end
    local byId = p.notes[author]
    local old = byId and byId[id]
    if old and rec.ts <= old.ts then return false end
    if not rec.del and (not old or old.del) and byId and LiveCount(byId) >= MAX_NOTES then return false end
    if not byId then
        byId = {}
        p.notes[author] = byId
    end
    byId[id] = { text = rec.text, tag = rec.tag, ts = rec.ts, del = rec.del or nil, imp = rec.imp or nil }
    return true
end

--- rec = { list, ts, del }: list is one of kos, watch, kudos, and nil in a removed mark.
function Put.Mark(key, author, rec)
    local p = GK.Person(key, true)
    if not p then return false end
    local old = p.marks[author]
    if old and rec.ts <= old.ts then return false end
    p.marks[author] = { list = (not rec.del) and rec.list or nil, ts = rec.ts, del = rec.del or nil }
    return true
end

--- voter's vote on author's note id on key. The player must be known; nobody votes on their own note.
function Put.Vote(key, author, id, voter, v, ts)
    local p = GK.Person(key, false)
    if not p or voter == author then return false end
    local gk = author .. "#" .. id
    local group = p.votes[gk]
    local old = group and group[voter]
    if old and ts <= old.ts then return false end
    if not group then
        if Count(p.votes) >= MAX_VOTE_GROUPS then return false end
        group = {}
        p.votes[gk] = group
    end
    if not old and Count(group) >= MAX_VOTERS then return false end
    group[voter] = { v = v, ts = ts }
    return true
end

--- A nice name added by `by`. rec = { ts, del, c, r, rf, sx, l }. A live name belongs to whoever added
--- it first: another player's version of it is ignored (D2). A removed one can be added again by anyone.
function Put.Name(key, by, rec)
    local names = Tables().names
    local old = names[key]
    if old and old.by and old.by ~= by and not old.del then return false end
    if old and rec.ts <= old.ts then return false end
    if not old and Count(names) >= MAX_NAMES then return false end
    names[key] = { by = by, ts = rec.ts, del = rec.del or nil, hidden = old and old.hidden,
        c = rec.c, r = rec.r, rf = rec.rf, sx = rec.sx, l = rec.l }
    return true
end

function Put.NameVote(key, voter, v, ts)
    local s = Tables()
    local n = s.names[key]
    if not n or n.by == voter then return false end
    local votes = s.nameVotes[key]
    local old = votes and votes[voter]
    if old and ts <= old.ts then return false end
    if not votes then
        votes = {}
        s.nameVotes[key] = votes
    end
    if not old and Count(votes) >= MAX_VOTERS then return false end
    votes[voter] = { v = v, ts = ts }
    return true
end

--- `by` hid (on) or showed a name. The hide may come before the name does, so it can make a bare
--- record (no `by`, deleted) that the name's own message fills in later.
function Put.Hide(key, by, on, ts)
    local names = Tables().names
    local n = names[key]
    if not n then
        if Count(names) >= MAX_NAMES then return false end
        n = { ts = 0, del = true }
        names[key] = n
    end
    if n.hidden and ts <= n.hidden.ts then return false end
    n.hidden = { by = by, ts = ts, on = on and true or false }
    return true
end

-- ---------------------------------------------------------------------------
-- Officers
-- ---------------------------------------------------------------------------
--- Is this guildie the guild master, or a rank that can listen to officer chat? Judged on their rank in
--- the roster as it is now. If the client has no call to read a rank's flags, only the guild master.
function GK.IsOfficer(who)
    if not who then return false end
    local row = LIB.roster and LIB.roster[who]
    local rank = row and row.rankIndex
    if type(rank) ~= "number" then return false end
    if rank == 0 then return true end
    local get = (C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags) or GuildControlGetRankFlags
    if not get then return false end
    local ok, first, second, third = pcall(get, rank + 1)
    if not ok then return false end
    if type(first) == "table" then return first[3] == true end
    return third == true
end

-- ---------------------------------------------------------------------------
-- Tags, marks, lists
-- ---------------------------------------------------------------------------
--- The list this author's records put the player on: their live mark, else kos when they have a live
--- note and never made a mark. nil when neither. (A mark they removed stays removed.)
local function AuthorList(p, author)
    local m = p.marks[author]
    if m then return (not m.del) and m.list or nil end
    local byId = p.notes[author]
    if byId and LiveCount(byId) > 0 then return "kos" end
    return nil
end

--- Who has put this player on which list: { kos = { authors }, watch = {...}, kudos = {...} }.
function GK.ListsOf(key)
    local lists = { kos = {}, watch = {}, kudos = {} }
    local p = GK.Person(key, false)
    if not p then return lists end
    for author in pairs(p.marks) do
        local list = AuthorList(p, author)
        if list then lists[list][#lists[list] + 1] = author end
    end
    for author in pairs(p.notes) do
        if not p.marks[author] then
            local list = AuthorList(p, author)
            if list then lists[list][#lists[list] + 1] = author end
        end
    end
    for _, authors in pairs(lists) do table.sort(authors) end
    return lists
end

--- The tags to offer for a list: the presets, then every other tag in use on a live note by someone
--- who has that list, A to Z.
function GK.KnownTags(list)
    local tags, seen = {}, {}
    for _, tag in ipairs(GK.TAGS[list] or NONE) do
        seen[tag] = true
        tags[#tags + 1] = tag
    end
    local extra = {}
    for _, p in pairs(Tables().people) do
        for author, byId in pairs(p.notes) do
            if AuthorList(p, author) == list then
                for _, n in pairs(byId) do
                    if n.tag and not n.del and not seen[n.tag] then
                        seen[n.tag] = true
                        extra[#extra + 1] = n.tag
                    end
                end
            end
        end
    end
    table.sort(extra)
    for _, tag in ipairs(extra) do tags[#tags + 1] = tag end
    return tags
end

--- Is anything written down about this player: a note, or a place on a list?
function GK.IsNoted(key)
    local p = GK.Person(key, false)
    return p ~= nil and HasLive(p)
end

--- The list I put this player on, or nil.
function GK.MyMark(key)
    local p, me = GK.Person(key, false), LIB.Me()
    local m = p and me and p.marks[me]
    return m and not m.del and m.list or nil
end

--- Put the player on a list, or take them off mine (list nil). Only my own mark moves (D5).
function GK.SetMark(key, list)
    local me = LIB.Me()
    key = ValidKey(key)
    if not (me and key) or (list ~= nil and not LISTS[list]) then return false end
    local p = GK.Person(key, list ~= nil)
    if not p then return list == nil end
    local old = p.marks[me]
    if list == nil and (not old or old.del) then return true end
    if list and old and not old.del and old.list == list then return true end
    local rec = { list = list, ts = NextTs(old), del = list == nil }
    if not Put.Mark(key, me, rec) then return false end
    Send(Encode.L(key, p.marks[me], p))
    GK.Changed()
    return true
end

-- ---------------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------------
local function NoteScoreOf(p, author, id)
    local group = p.votes[author .. "#" .. id]
    local score = 0
    if group then
        for _, vote in pairs(group) do score = score + vote.v end
    end
    return score
end

local function MyVoteOf(p, author, id)
    local me = LIB.Me()
    local group = me and p.votes[author .. "#" .. id]
    local vote = group and group[me]
    return vote and vote.v or 0
end

local function NoteRow(p, author, id, n, me)
    return { author = author, id = id, text = n.text, tag = n.tag, ts = n.ts,
        score = NoteScoreOf(p, author, id), myVote = MyVoteOf(p, author, id), mine = author == me }
end

--- Write a note on a player, and put them on a list when list is given (it moves my mark). info is
--- what we know of them: { c, r, rf, sx, l }. Returns the note as NotesOf lists it, or nil and why not.
function GK.AddNote(key, text, tag, list, info)
    local me = LIB.Me()
    if not me then return nil, "The game hasn't said who you are yet - try again in a moment." end
    key = ValidKey(key)
    if not key then return nil, "That player has no name we can keep." end
    text, tag = GK.Clean(text, MAX_TEXT), GK.Clean(tag, GK.MAX_TAG)
    if not (text or tag) then return nil, "Write something first." end
    if list ~= nil and not LISTS[list] then return nil, "There is no such list." end
    local p = GK.Person(key, true)
    if not p then return nil, "The book is full - " .. MAX_PEOPLE .. " players." end
    if p.notes[me] and LiveCount(p.notes[me]) >= MAX_NOTES then
        return nil, ("You have %d notes on them already - remove one first."):format(MAX_NOTES)
    end
    Learn(p, info, false)
    -- Seconds since 1970 make an id no reinstall can hand out twice.
    local s = Tables()
    local id = math.max(time(), s.nextNote or 1)
    s.nextNote = id + 1
    if not Put.Note(key, me, id, { text = text, tag = tag, ts = time() }) then return nil, "That note didn't fit." end
    Send(Encode.N(key, id, p.notes[me][id], p))
    if list then GK.SetMark(key, list) end
    GK.Changed()
    return NoteRow(p, me, id, p.notes[me][id], me)
end

--- Remove one of my notes. Nobody removes another player's (D2).
function GK.DeleteNote(key, id)
    local me, p = LIB.Me(), GK.Person(key, false)
    local n = me and p and p.notes[me] and p.notes[me][id]
    if not n or n.del then return false end
    Put.Note(key, me, id, { ts = NextTs(n), del = true })
    Send(Encode.N(key, id, p.notes[me][id], p))
    GK.Changed()
    return true
end

--- The live notes on a player, newest first, with their votes counted.
function GK.NotesOf(key)
    local list, p, me = {}, GK.Person(key, false), LIB.Me()
    if not p then return list end
    for author, byId in pairs(p.notes) do
        for id, n in pairs(byId) do
            if not n.del then list[#list + 1] = NoteRow(p, author, id, n, me) end
        end
    end
    table.sort(list, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        if a.author ~= b.author then return a.author < b.author end
        return a.id > b.id
    end)
    return list
end

--- The players on a list, each { key, person, authors, ts, score, tags, mine }. ts is the latest note
--- or mark of those who put them there, score the sum of their notes' scores, tags the distinct tags
--- on those notes (newest first), mine whether I have a mark or a note on them. Unordered.
function GK.PeopleOn(list)
    local out, me = {}, LIB.Me()
    for key, p in pairs(Tables().people) do
        local authors, ts, score, notes = {}, 0, 0, {}
        for author in pairs(p.marks) do
            if AuthorList(p, author) == list then authors[#authors + 1] = author end
        end
        for author in pairs(p.notes) do
            if not p.marks[author] and AuthorList(p, author) == list then authors[#authors + 1] = author end
        end
        for _, author in ipairs(authors) do
            local m = p.marks[author]
            if m and m.ts > ts then ts = m.ts end
            for id, n in pairs(p.notes[author] or NONE) do
                if not n.del then
                    if n.ts > ts then ts = n.ts end
                    score = score + NoteScoreOf(p, author, id)
                    notes[#notes + 1] = n
                end
            end
        end
        if #authors > 0 then
            table.sort(authors)
            table.sort(notes, function(a, b) return a.ts > b.ts end)
            local tags, seen = {}, {}
            for _, n in ipairs(notes) do
                if n.tag and not seen[n.tag] then
                    seen[n.tag] = true
                    tags[#tags + 1] = n.tag
                end
            end
            local mm = me and p.marks[me]
            local mine = (mm and not mm.del) or (me and p.notes[me] and LiveCount(p.notes[me]) > 0) or false
            out[#out + 1] = { key = key, person = p, authors = authors, ts = ts, score = score, tags = tags,
                mine = mine and true or false }
        end
    end
    return out
end

--- My vote (1, -1, or 0 to take it back) on author's note id. Not on my own.
function GK.VoteNote(key, author, id, v)
    local me, p = LIB.Me(), GK.Person(key, false)
    v = Vote(v)
    local n = p and p.notes[author] and p.notes[author][id]
    if not (me and v and n) or n.del or author == me then return false end
    local group = p.votes[author .. "#" .. id]
    if not Put.Vote(key, author, id, me, v, NextTs(group and group[me])) then return false end
    Send(Encode.V(key, author, id, v, p.votes[author .. "#" .. id][me].ts))
    GK.Changed()
    return true
end

function GK.NoteScore(key, author, id)
    local p = GK.Person(key, false)
    return p and NoteScoreOf(p, author, id) or 0
end

function GK.MyNoteVote(key, author, id)
    local p = GK.Person(key, false)
    return p and MyVoteOf(p, author, id) or 0
end

-- ---------------------------------------------------------------------------
-- Nice names
-- ---------------------------------------------------------------------------
--- Add a funny character name to the guild's list. info = { c, r, rf, sx, l } as far as known.
--- Returns true, or nil and why not.
function GK.AddNiceName(key, info)
    local me = LIB.Me()
    key = ValidKey(key)
    if not (me and key) then return nil, "That name can't be kept." end
    local names = Tables().names
    local old = names[key]
    if old and not old.del then return nil, "That name is on the list already." end
    local i = ParseInfo(info and info.c, info and info.r, info and info.rf, info and info.sx, info and info.l)
    i.ts = NextTs(old)
    if not Put.Name(key, me, i) then return nil, "The list is full - " .. MAX_NAMES .. " names." end
    Send(Encode.M(key, names[key]))
    GK.Changed()
    return true
end

--- Take a name I added off the list. Not another player's (D2); an officer hides it instead.
function GK.RemoveNiceName(key)
    local me = LIB.Me()
    local n = Tables().names[key]
    if not (me and n) or n.del or n.by ~= me then return false end
    Put.Name(key, me, { ts = NextTs(n), del = true })
    Send(Encode.M(key, Tables().names[key]))
    GK.Changed()
    return true
end

--- The names on the list, newest first: { key, by, ts, score, myVote, mine, hidden }. A name an officer
--- hid is left out unless showHidden.
function GK.NiceNames(showHidden)
    local out, me = {}, LIB.Me()
    local s = Tables()
    for key, n in pairs(s.names) do
        local hidden = n.hidden and n.hidden.on or false
        if not n.del and (showHidden or not hidden) then
            local score, mine = 0, 0
            for voter, vote in pairs(s.nameVotes[key] or NONE) do
                score = score + vote.v
                if voter == me then mine = vote.v end
            end
            out[#out + 1] = { key = key, by = n.by, ts = n.ts, score = score, myVote = mine, mine = n.by == me,
                hidden = hidden }
        end
    end
    table.sort(out, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.key < b.key
    end)
    return out
end

--- My vote on a nice name (1, -1, or 0 to take it back). Not on my own.
function GK.VoteName(key, v)
    local me, s = LIB.Me(), Tables()
    local n = s.names[key]
    v = Vote(v)
    if not (me and v and n) or n.del or n.by == me then return false end
    local votes = s.nameVotes[key]
    if not Put.NameVote(key, me, v, NextTs(votes and votes[me])) then return false end
    Send(Encode.G(key, v, s.nameVotes[key][me].ts))
    GK.Changed()
    return true
end

function GK.NameScore(key)
    local score = 0
    for _, vote in pairs(Tables().nameVotes[key] or NONE) do score = score + vote.v end
    return score
end

--- Hide a nice name from everyone (on), or show it again. Officers only; the name stays in the data.
function GK.HideName(key, on)
    local me = LIB.Me()
    if not me or not GK.IsOfficer(me) or not Tables().names[key] then return false end
    local n = Tables().names[key]
    if not Put.Hide(key, me, on, NextTs(n.hidden)) then return false end
    Send(Encode.H(key, on, n.hidden.ts))
    GK.Changed()
    return true
end

-- ---------------------------------------------------------------------------
-- What others send
-- ---------------------------------------------------------------------------
--- A message tells us a little about the player it is about: fill in what we lack.
local function LearnWire(key, c, r, l)
    local p = GK.Person(key, false)
    if p then Learn(p, ParseInfo(c, r, nil, nil, l), true) end
end

local function OnNote(sender, f)
    local key, id, ts = ValidKey(f[3]), Int(f[4], 1, 2 ^ 31), Ts(f[5])
    if not (key and id and ts) then return false end
    local del = f[6] == "1"
    local text, tag = GK.Clean(f[11], MAX_TEXT), GK.Clean(f[7], GK.MAX_TAG)
    if del then
        text, tag = nil, nil
    elseif not (text or tag) then
        return false
    end
    if not Put.Note(key, sender, id, { text = text, tag = tag, ts = ts, del = del }) then return false end
    LearnWire(key, f[8], f[9], f[10])
    return true
end

local function OnMark(sender, f)
    local key, ts = ValidKey(f[3]), Ts(f[5])
    local del = f[6] == "1"
    local list = LISTS[f[4]] and f[4] or nil
    if not (key and ts) or (not del and not list) then return false end
    if not Put.Mark(key, sender, { list = list, ts = ts, del = del }) then return false end
    LearnWire(key, f[7], f[8], f[9])
    return true
end

local function OnVote(sender, f)
    local key, author, id = ValidKey(f[3]), ValidKey(f[4]), Int(f[5], 1, 2 ^ 31)
    local v, ts = Vote(f[6]), Ts(f[7])
    if not (key and author and id and v and ts) then return false end
    return Put.Vote(key, author, id, sender, v, ts)
end

local function OnName(sender, f)
    local key, ts = ValidKey(f[3]), Ts(f[4])
    if not (key and ts) then return false end
    local i = ParseInfo(f[6], f[7], f[8], f[9], f[10])
    i.ts, i.del = ts, f[5] == "1"
    return Put.Name(key, sender, i)
end

local function OnNameVote(sender, f)
    local key, v, ts = ValidKey(f[3]), Vote(f[4]), Ts(f[5])
    if not (key and v and ts) then return false end
    return Put.NameVote(key, sender, v, ts)
end

local function OnHide(sender, f)
    local key, ts = ValidKey(f[3]), Ts(f[5])
    if not (key and ts) or (f[4] ~= "0" and f[4] ~= "1") then return false end
    if not GK.IsOfficer(sender) then return false end
    return Put.Hide(key, sender, f[4] == "1", ts)
end

-- ---------------------------------------------------------------------------
-- Answering a Q: my own records, newest first, a few at a time
-- ---------------------------------------------------------------------------
-- Players are told about before the votes on their notes, because a vote on a player we don't know is
-- dropped; the cap still keeps the newest 150 of everything.
local RANK = { M = 1, N = 2, L = 3, V = 4, G = 5, H = 6 }

local function OwnRecords()
    local me, out = LIB.Me(), {}
    if not me then return out end
    local function add(ts, text) out[#out + 1] = { ts = ts, rank = RANK[text:sub(1, 1)], text = text } end
    local s = Tables()
    for key, p in pairs(s.people) do
        for id, n in pairs(p.notes[me] or NONE) do add(n.ts, Encode.N(key, id, n, p)) end
        local m = p.marks[me]
        if m then add(m.ts, Encode.L(key, m, p)) end
        for gk, group in pairs(p.votes) do
            local mine = group[me]
            local author, id = gk:match("^(.*)#(%d+)$")
            id = tonumber(id)
            local note = author and p.notes[author] and p.notes[author][id]
            if mine and author and not (note and note.imp) then
                add(mine.ts, Encode.V(key, author, id, mine.v, mine.ts))
            end
        end
    end
    for key, n in pairs(s.names) do
        if n.by == me then add(n.ts, Encode.M(key, n)) end
        if n.hidden and n.hidden.by == me then add(n.hidden.ts, Encode.H(key, n.hidden.on, n.hidden.ts)) end
        local mine = s.nameVotes[key] and s.nameVotes[key][me]
        if mine then add(mine.ts, Encode.G(key, mine.v, mine.ts)) end
    end
    table.sort(out, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.text < b.text
    end)
    for i = #out, MAX_REPLY + 1, -1 do out[i] = nil end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.text < b.text
    end)
    return out
end
GK.NotesOwnRecords = OwnRecords

-- Two a second: well inside LibForever's 30 messages per sender per 10 seconds, for the other end.
local function Drip(list, i)
    for _ = 1, 2 do
        if list[i] then
            Send(list[i].text)
            i = i + 1
        end
    end
    if list[i] then C_Timer.After(1, function() Drip(list, i) end) end
end

--- Send all my own records now, paced like the answer to a Q. For after the import, which makes
--- records the rest of the guild has not heard. false when nothing can be sent.
function GK.NotesBroadcast()
    if GK.testMode or not IsInGuild() then return false end
    Drip(OwnRecords(), 1)
    return true
end

local replyAfter = 0
local function OnAsk()
    -- Everyone logging in at once asks at once: answer once, a few seconds later.
    if GetTime() < replyAfter then return false end
    replyAfter = GetTime() + 30
    C_Timer.After(2 + math.random() * 4, GK.NotesBroadcast)
    return false
end

local HANDLERS = { N = OnNote, L = OnMark, V = OnVote, M = OnName, G = OnNameVote, H = OnHide, Q = OnAsk }

local function OnMessage(_, text, dist, sender)
    if dist ~= "GUILD" or type(text) ~= "string" or #text > 600 or not (GK.char and GK.db) then return end
    if type(sender) ~= "string" or sender == "" or sender == LIB.Me() then return end
    local f = Split(text)
    if Int(f[2], 1, 1000) ~= PROTO then return end
    local fn = HANDLERS[f[1]]
    if fn and fn(sender, f) then GK.Changed() end
end
-- The tests (and the test panel) feed messages through the same reader as real ones.
GK.NotesReceive = OnMessage

-- ---------------------------------------------------------------------------
-- Housekeeping and startup
-- ---------------------------------------------------------------------------
--- Forget the deleted things that have been deleted long enough that no late sync could bring them
--- back, and what only they held up. Returns how many records went.
function GK.PruneNotes()
    local s, cutoff, gone = Tables(), time() - KEEP_TOMBSTONE, 0
    for key, p in pairs(s.people) do
        for author, byId in pairs(p.notes) do
            for id, n in pairs(byId) do
                if n.del and n.ts < cutoff then
                    byId[id] = nil
                    gone = gone + 1
                end
            end
            if next(byId) == nil then p.notes[author] = nil end
        end
        for author, m in pairs(p.marks) do
            if m.del and m.ts < cutoff then
                p.marks[author] = nil
                gone = gone + 1
            end
        end
        for gk, group in pairs(p.votes) do
            local author, id = gk:match("^(.*)#(%d+)$")
            local note = author and p.notes[author] and p.notes[author][tonumber(id)]
            local allOld = true
            for voter, vote in pairs(group) do
                if vote.v == 0 and vote.ts < cutoff then
                    group[voter] = nil
                    gone = gone + 1
                elseif vote.ts >= cutoff then
                    allOld = false
                end
            end
            -- votes whose note is gone, or never reached us, wait out the same 30 days
            if next(group) == nil or (not note and allOld) then p.votes[gk] = nil end
        end
        if next(p.marks) == nil and next(p.notes) == nil and next(p.votes) == nil then s.people[key] = nil end
    end
    for key, n in pairs(s.names) do
        if n.hidden and n.hidden.ts < cutoff and not n.hidden.on then n.hidden = nil end
        if (n.del and n.ts < cutoff) and not (n.hidden and n.hidden.ts >= cutoff) then
            s.names[key] = nil
            s.nameVotes[key] = nil
            gone = gone + 1
        end
    end
    for key, votes in pairs(s.nameVotes) do
        for voter, vote in pairs(votes) do
            if vote.v == 0 and vote.ts < cutoff then
                votes[voter] = nil
                gone = gone + 1
            end
        end
        if next(votes) == nil or not s.names[key] then s.nameVotes[key] = nil end
    end
    if gone > 0 then GK.Changed() end
    return gone
end

-- Core.lua loads first, so its own login handler has made GK.db and GK.char by the time this runs.
LIB.On("PLAYER_LOGIN", function()
    if not (GK.db and GK.char) then return end
    LIB.RegisterComm(PREFIX, OnMessage)
    C_Timer.After(10, function() Send(Encode.Q()) end)
    C_Timer.After(20, GK.PruneNotes)
end)
