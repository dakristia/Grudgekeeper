-- Offline tests for the notes data layer (Notes.lua) and the Guild Grudge import (Import.lua).
-- Run from the repo root with Lua 5.1:
--   lua5.1 tests/run.lua
package.path = "tests/?.lua;" .. package.path
local say = print            -- the mock takes over print, to see what the addon says
local W = require("wow_mock")
W.dir = ""

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        say("PASS  " .. name)
    else
        failed = failed + 1
        say("FAIL  " .. name .. "\n      " .. tostring(err))
    end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
local function has(list, v)
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

local ME, KARI, EDVARD = "Meyer-Realm", "Kari-Realm", "Edvard-Realm"
local GANK, NICE = "Gank Master-Realm", "Nina Nice-Realm"
local B = W.base

--- A message as the wire has it: fields joined with ';'.
local function msg(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[i] = v == nil and "" or tostring(v)
    end
    return table.concat(parts, ";")
end

local function boot(opts)
    local GK, LIB = W.boot(opts)
    LIB.roster[ME] = { rankIndex = 5 }
    return GK, LIB
end

-- ---------------------------------------------------------------------------
-- Merging
-- ---------------------------------------------------------------------------
test("a note arrives, and a later version of it replaces it", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 10, "", "Toxic", "WARRIOR", "Orc", 60, "first"))
    local notes = GK.NotesOf(GANK)
    eq(#notes, 1)
    eq(notes[1].text, "first")
    eq(notes[1].tag, "Toxic")
    eq(notes[1].author, KARI)
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 20, "", "Toxic", "WARRIOR", "Orc", 60, "second"))
    eq(GK.NotesOf(GANK)[1].text, "second")
    eq(#GK.NotesOf(GANK), 1)
end)

test("an older or equal version is ignored", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 20, "", "", "", "", "", "newer"))
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 5, "", "", "", "", "", "older"))
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 20, "", "", "", "", "", "same time"))
    eq(GK.NotesOf(GANK)[1].text, "newer")
end)

test("a delete is a tombstone that a late older version can't undo", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 10, "", "", "", "", "", "rude"))
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 20, 1))
    eq(#GK.NotesOf(GANK), 0)
    eq(GK.IsNoted(GANK), false)
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 15, "", "", "", "", "", "rude"))
    eq(#GK.NotesOf(GANK), 0, "the late version stays dead")
    local rec = GK.Person(GANK).notes[KARI][7]
    assert(rec.del and rec.text == nil, "the tombstone holds no text")
end)

test("tombstones are pruned after 30 days, and then a player with nothing left goes", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B, "", "", "", "", "", "rude"))
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 1, 1))
    eq(GK.PruneNotes(), 0, "too young")
    assert(GK.Person(GANK), "still there")
    W.advance(31 * 24 * 3600)
    assert(GK.PruneNotes() >= 1, "pruned")
    eq(GK.Person(GANK), nil)
end)

test("the author is the sender: nobody writes or deletes another player's note", function()
    local GK = boot()
    W.receive(GK, EDVARD, msg("N", 1, GANK, 7, B + 10, "", "", "", "", "", "Edvard's note"))
    -- Kari sends a delete for the same id: it is Kari's own record 7, not Edvard's
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 20, 1))
    local notes = GK.NotesOf(GANK)
    eq(#notes, 1)
    eq(notes[1].author, EDVARD)
    eq(notes[1].text, "Edvard's note")
    -- an extra field that names an author means nothing
    W.receive(GK, KARI, msg("N", 1, GANK, 8, B + 30, "", "", "", "", "", "mine", EDVARD))
    eq(GK.NotesOf(GANK)[1].author, KARI)
end)

test("a message from someone outside the guild channel, or from me, or of another version, is dropped", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B, "", "", "", "", "", "x"), "WHISPER")
    W.receive(GK, ME, msg("N", 1, GANK, 7, B, "", "", "", "", "", "x"))
    W.receive(GK, KARI, msg("N", 2, GANK, 7, B, "", "", "", "", "", "x"))
    W.receive(GK, KARI, "garbage")
    W.receive(GK, KARI, msg("N", 1, "NoRealmKey", 7, B, "", "", "", "", "", "x"))
    eq(count(GK.Store().people), 0)
end)

-- ---------------------------------------------------------------------------
-- Limits and cleaning
-- ---------------------------------------------------------------------------
test("text and tags are cleaned and capped on the way in", function()
    local GK = boot()
    local long = string.rep("a", 300)
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", string.rep("t", 40), "WARRIOR", "Orc", 60, long))
    local n = GK.NotesOf(GANK)[1]
    eq(#n.text, 200)
    eq(#n.tag, 24)
    W.receive(GK, KARI, msg("N", 1, GANK, 2, B, "", "", "", "", "", "|cffff0000red|r and |Hlink|h\1control"))
    for _, note in ipairs(GK.NotesOf(GANK)) do
        assert(not note.text:find("|", 1, true), "no escape codes: " .. note.text)
        assert(not note.text:find("%c"), "no control characters")
    end
end)

test("a note with no text and no tag is dropped; a bad class or level is not believed", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "WARRIOR", "", "", ""))
    eq(count(GK.Store().people), 0)
    W.receive(GK, KARI, msg("N", 1, GANK, 2, B, "", "", "NOTACLASS", "Orc", 9000, "hello"))
    local p = GK.Person(GANK)
    eq(p.c, nil)
    eq(p.l, nil)
    eq(p.r, "Orc")
end)

test("a player learned from a message never overwrites what we saw", function()
    local GK = boot()
    GK.AddNote(GANK, "mine", nil, nil, { c = "MAGE", l = 50 })
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "WARRIOR", "Orc", 60, "hello"))
    eq(GK.Person(GANK).c, "MAGE")
    eq(GK.Person(GANK).l, 50)
    eq(GK.Person(GANK).r, "Orc", "filled in, because we had none")
end)

test("20 live notes per author per player", function()
    local GK = boot()
    for i = 1, 25 do W.receive(GK, KARI, msg("N", 1, GANK, i, B + i, "", "", "", "", "", "note " .. i)) end
    eq(#GK.NotesOf(GANK), 20)
    -- one of the 20 can still be edited
    W.receive(GK, KARI, msg("N", 1, GANK, 3, B + 100, "", "", "", "", "", "edited"))
    eq(#GK.NotesOf(GANK), 20)
    -- and a deleted one makes room
    W.receive(GK, KARI, msg("N", 1, GANK, 4, B + 101, 1))
    W.receive(GK, KARI, msg("N", 1, GANK, 30, B + 102, "", "", "", "", "", "new"))
    eq(#GK.NotesOf(GANK), 20)
    -- another author has 20 of their own
    W.receive(GK, EDVARD, msg("N", 1, GANK, 1, B, "", "", "", "", "", "his"))
    eq(#GK.NotesOf(GANK), 21)
end)

test("500 people", function()
    local GK = boot()
    for i = 1, 520 do W.receive(GK, KARI, msg("N", 1, "Player" .. i .. "-Realm", 1, B + i, "", "", "", "", "", "x")) end
    eq(count(GK.Store().people), 500)
end)

test("I can't write a 201st character, a 25th tag character, or a 21st note", function()
    local GK = boot()
    local n = GK.AddNote(GANK, string.rep("x", 250), string.rep("y", 40))
    eq(#n.text, 200)
    eq(#n.tag, 24)
    for _ = 1, 19 do assert(GK.AddNote(GANK, "note")) end
    local none, why = GK.AddNote(GANK, "one too many")
    eq(none, nil)
    assert(why and why:find("20"), "says why")
    eq(select(1, GK.AddNote(GANK, "   ", "  ")), nil, "nothing to say")
end)

-- ---------------------------------------------------------------------------
-- Lists
-- ---------------------------------------------------------------------------
test("two authors put a player on different lists, and each moves only their own mark", function()
    local GK = boot()
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B + 1, "", "WARRIOR", "Orc", 60))
    W.receive(GK, EDVARD, msg("N", 1, GANK, 1, B + 2, "", "Kind", "", "", "", "a note, no mark"))
    local lists = GK.ListsOf(GANK)
    eq(#lists.watch, 1)
    eq(lists.watch[1], KARI)
    eq(#lists.kos, 1)
    eq(lists.kos[1], EDVARD, "a note without a mark counts as kos for its author")
    eq(#lists.kudos, 0)
    W.receive(GK, EDVARD, msg("L", 1, GANK, "kudos", B + 3))
    lists = GK.ListsOf(GANK)
    eq(#lists.kos, 0)
    eq(lists.kudos[1], EDVARD)
    eq(lists.watch[1], KARI, "Kari's mark didn't move")
    -- my own
    eq(GK.SetMark(GANK, "watch"), true)
    eq(GK.MyMark(GANK), "watch")
    lists = GK.ListsOf(GANK)
    eq(#lists.watch, 2)
    eq(GK.SetMark(GANK, nil), true)
    eq(GK.MyMark(GANK), nil)
    eq(#GK.ListsOf(GANK).watch, 1)
    eq(GK.SetMark(GANK, "enemies"), false, "no such list")
end)

test("a removed mark stays removed against a late older one", function()
    local GK = boot()
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B + 10))
    W.receive(GK, KARI, msg("L", 1, GANK, "", B + 20, 1))
    W.receive(GK, KARI, msg("L", 1, GANK, "kudos", B + 15))
    local lists = GK.ListsOf(GANK)
    eq(#lists.watch + #lists.kudos + #lists.kos, 0)
end)

test("PeopleOn gathers a list with the latest time, the score, the tags and whether it is mine", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 10, "", "Scammer", "", "", "", "took my gold"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B + 12))
    W.receive(GK, EDVARD, msg("N", 1, GANK, 5, B + 50, "", "Helpful", "", "", "", "kind"))
    W.receive(GK, EDVARD, msg("L", 1, GANK, "kudos", B + 51))
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 1, 1, B + 60))
    local watch = GK.PeopleOn("watch")
    eq(#watch, 1)
    eq(watch[1].key, GANK)
    eq(watch[1].ts, B + 12, "Edvard's later kudos note isn't the Shame list's news")
    eq(watch[1].score, 1)
    eq(#watch[1].tags, 1)
    eq(watch[1].tags[1], "Scammer")
    eq(watch[1].mine, false)
    eq(watch[1].person, GK.Person(GANK))
    eq(GK.PeopleOn("kudos")[1].tags[1], "Helpful")
    eq(#GK.PeopleOn("kos"), 0)
    GK.AddNote(GANK, "I think so too", nil, "watch")
    watch = GK.PeopleOn("watch")
    eq(watch[1].mine, true)
    eq(#watch[1].authors, 2)
end)

test("a tag's icon and text: the preset's own, the note for a custom tag, nothing for no tag", function()
    local GK = boot()
    eq(GK.TagIcon("Ninja looter"), "Interface\\Icons\\Ability_Stealth")
    eq(GK.TagIcon("Fun to group with"), "Interface\\Icons\\INV_Drink_04")
    eq(GK.TagIcon("Bad at tanks"), "Interface\\Icons\\INV_Misc_Note_01")
    eq(GK.TagIcon(nil), nil)
    eq(GK.TagIcon(""), nil)
    for _, list in pairs(GK.TAGS) do
        for _, tag in ipairs(list) do assert(GK.TagIcon(tag) ~= "Interface\\Icons\\INV_Misc_Note_01", tag) end
    end
    eq(GK.TagText("Toxic"), "|TInterface\\Icons\\Spell_Nature_NullifyPoison:14:14|t Toxic")
    eq(GK.TagText("Toxic", 12), "|TInterface\\Icons\\Spell_Nature_NullifyPoison:12:12|t Toxic")
    eq(GK.TagText("Zen"), "|TInterface\\Icons\\INV_Misc_Note_01:14:14|t Zen")
    eq(GK.TagText(nil), "")
end)

test("known tags are the presets and then the custom ones in use on that list", function()
    local GK = boot()
    local tags = GK.KnownTags("watch")
    eq(tags[1], "Ninja looter")
    eq(#tags, #GK.TAGS.watch)
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "Bad at tanks", "", "", "", "x"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B))
    W.receive(GK, EDVARD, msg("N", 1, NICE, 1, B, "", "Zen", "", "", "", "x"))
    W.receive(GK, EDVARD, msg("L", 1, NICE, "kudos", B))
    tags = GK.KnownTags("watch")
    eq(tags[#tags], "Bad at tanks")
    eq(#tags, #GK.TAGS.watch + 1)
    assert(has(GK.KnownTags("kudos"), "Zen"))
    assert(not has(GK.KnownTags("kudos"), "Bad at tanks"))
    eq(#GK.KnownTags("kos"), 0)
end)

test("a note I write can put the player on a list, and I can delete only my own", function()
    local GK = boot()
    local n = GK.AddNote(GANK, "took my gold", "Scammer", "watch", { c = "ROGUE", l = 60 })
    assert(n and n.mine and n.id)
    eq(GK.MyMark(GANK), "watch")
    eq(GK.Person(GANK).c, "ROGUE")
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "", "", "", "hers"))
    eq(GK.DeleteNote(GANK, 1), false, "Kari's note id 1 is not mine")
    eq(#GK.NotesOf(GANK), 2)
    eq(GK.DeleteNote(GANK, n.id), true)
    eq(#GK.NotesOf(GANK), 1)
    eq(GK.NotesOf(GANK)[1].author, KARI)
    eq(GK.DeleteNote(GANK, n.id), false, "already gone")
end)

test("notes come newest first", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 30, "", "", "", "", "", "middle"))
    W.receive(GK, EDVARD, msg("N", 1, GANK, 1, B + 10, "", "", "", "", "", "oldest"))
    W.receive(GK, KARI, msg("N", 1, GANK, 2, B + 50, "", "", "", "", "", "newest"))
    local notes = GK.NotesOf(GANK)
    eq(notes[1].text, "newest")
    eq(notes[2].text, "middle")
    eq(notes[3].text, "oldest")
end)

-- ---------------------------------------------------------------------------
-- Votes
-- ---------------------------------------------------------------------------
test("votes: one per player, changeable, takeable back", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 1, "", "", "", "", "", "hers"))
    eq(GK.VoteNote(GANK, KARI, 7, 1), true)
    eq(GK.NoteScore(GANK, KARI, 7), 1)
    eq(GK.MyNoteVote(GANK, KARI, 7), 1)
    eq(GK.VoteNote(GANK, KARI, 7, -1), true)
    eq(GK.NoteScore(GANK, KARI, 7), -1, "changed, not added")
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, 1, B + 5))
    eq(GK.NoteScore(GANK, KARI, 7), 0)
    eq(GK.VoteNote(GANK, KARI, 7, 0), true)
    eq(GK.NoteScore(GANK, KARI, 7), 1, "mine taken back, Edvard's stays")
    eq(GK.MyNoteVote(GANK, KARI, 7), 0)
    eq(GK.NotesOf(GANK)[1].score, 1)
end)

test("votes: not on my own note, not on a note nobody has, not with a strange value", function()
    local GK = boot()
    local n = GK.AddNote(GANK, "mine")
    eq(GK.VoteNote(GANK, ME, n.id, 1), false)
    eq(GK.VoteNote(GANK, KARI, 99, 1), false)
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B, "", "", "", "", "", "hers"))
    eq(GK.VoteNote(GANK, KARI, 7, 5), false)
    eq(GK.NoteScore(GANK, KARI, 7), 0)
end)

test("votes: the author can't vote on their own note by message either; a late older vote is ignored", function()
    local GK = boot()
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B, "", "", "", "", "", "hers"))
    W.receive(GK, KARI, msg("V", 1, GANK, KARI, 7, 1, B + 1))
    eq(GK.NoteScore(GANK, KARI, 7), 0)
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, -1, B + 10))
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, 1, B + 5))
    eq(GK.NoteScore(GANK, KARI, 7), -1)
    -- the voter is the sender: nobody votes in another name
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, 1, B + 20, EDVARD))
    eq(GK.NoteScore(GANK, KARI, 7), 1)
    eq(count(GK.Person(GANK).votes[KARI .. "#7"]), 1)
end)

test("a vote on a player we know nothing of is dropped", function()
    local GK = boot()
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, 1, B))
    eq(count(GK.Store().people), 0)
end)

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
test("a Q goes out about ten seconds after login, and only once", function()
    local GK = boot()
    W.advance(9)
    eq(#W.sent, 0)
    W.advance(2)
    eq(#W.sent, 1)
    eq(W.sent[1].text, "Q;1")
    eq(W.sent[1].prefix, "GrudgeNotes")
    eq(W.sent[1].dist, "GUILD")
    W.advance(60)
    eq(#W.sent, 1)
    assert(W.comm.GrudgeNotes, "listening on the prefix")
end)

test("nothing is sent out of a guild or in test mode", function()
    local GK = boot({ inGuild = false })
    W.advance(15)
    GK.AddNote(GANK, "hello")
    eq(#W.sent, 0)
    local GK2 = boot()
    GK2.testMode = true
    GK2.AddNote(GANK, "hello")
    W.advance(15)
    eq(#W.sent, 0)
    eq(#GK2.NotesOf(GANK), 1, "still kept")
end)

test("live changes go out through the queue, and tell the windows", function()
    local GK = boot()
    local before = W.changes
    local n = GK.AddNote(GANK, "took my gold", "Scammer", "watch", { c = "ROGUE", l = 60 })
    eq(#W.sent, 1, "the first goes at once")
    W.advance(1)
    local sent = W.takeSent()
    eq(#sent, 2)
    eq(sent[1].text, msg("N", 1, GANK, n.id, B, "", "Scammer", "ROGUE", "", 60, "took my gold"))
    eq(sent[2].text, msg("L", 1, GANK, "watch", B, "", "ROGUE", "", 60))
    assert(W.changes > before, "Changed was called")
    GK.DeleteNote(GANK, n.id)
    W.advance(2)
    eq(W.takeSent()[1].text, msg("N", 1, GANK, n.id, B + 1, 1, "", "ROGUE", "", 60, ""))
    GK.SetMark(GANK, nil)
    W.advance(2)
    eq(W.takeSent()[1].text, msg("L", 1, GANK, "", B + 3, 1, "ROGUE", "", 60))
end)

test("a Q is answered with my own records only, after 2 to 6 seconds, once per 30 seconds", function()
    local GK = boot()
    W.advance(11)
    W.takeSent()
    GK.AddNote(GANK, "mine", "Toxic", "watch")
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "", "", "", "Kari's note"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B))
    eq(GK.VoteNote(GANK, KARI, 1, 1), true)
    W.advance(10)
    W.takeSent()
    W.receive(GK, KARI, "Q;1")
    W.advance(1.5)
    eq(#W.sent, 0, "not before 2 seconds")
    W.advance(10)
    local sent = W.takeSent()
    -- my N, L and V, and not Kari's N or L
    eq(#sent, 3)
    local kinds = {}
    for _, m in ipairs(sent) do
        kinds[#kinds + 1] = m.text:sub(1, 1)
        assert(not m.text:find("Kari's note", 1, true), "never someone else's record")
    end
    eq(table.concat(kinds), "NLV", "players before the votes on them")
    W.receive(GK, EDVARD, "Q;1")
    W.advance(10)
    eq(#W.sent, 0, "asked again within 30 seconds: no second answer yet")
    W.advance(30)
    -- an ask in the half minute used to get nothing at all: Edvard, logging in just after Kari, heard
    -- none of our notes (2026-11-07)
    eq(#W.sent, 3, "...but one once the half minute is over")
    W.receive(GK, KARI, "Q;1")
    W.receive(GK, EDVARD, "Q;1")
    W.advance(60)
    eq(#W.sent, 6, "two asks in one half minute: one answer for both")
end)

test("a Q reply is capped at 150, newest first, two a second", function()
    local GK = boot()
    W.advance(11)
    -- 160 notes of mine on 8 players, one second apart
    for p = 1, 8 do
        for i = 1, 20 do
            W.advance(1)
            assert(GK.AddNote("Player" .. p .. "-Realm", "p" .. p .. " n" .. i))
        end
    end
    W.takeSent()
    local start = W.clock
    W.receive(GK, KARI, "Q;1")
    W.advance(120)
    local sent = W.takeSent()
    eq(#sent, 150)
    local perMoment, last = {}, 0
    for _, m in ipairs(sent) do
        perMoment[m.at] = (perMoment[m.at] or 0) + 1
        last = math.max(last, m.at)
    end
    for at, n in pairs(perMoment) do assert(n <= 2, "at most 2 at one moment, got " .. n .. " at " .. at) end
    assert(last - start >= 74, "150 messages at 2 a second take 75 seconds, took " .. (last - start))
    -- the ten oldest notes are the ones left out
    local text = {}
    for _, m in ipairs(sent) do text[#text + 1] = m.text end
    local all = table.concat(text, "\n")
    assert(not all:find("p1 n1;", 1, true) and not all:find("p1 n10;", 1, true), "oldest left out")
    assert(all:find("p8 n20", 1, true), "newest kept")
end)

test("a reply is not made in test mode", function()
    local GK = boot()
    GK.AddNote(GANK, "mine")
    W.takeSent()
    GK.testMode = true
    W.receive(GK, KARI, "Q;1")
    W.advance(10)
    eq(#W.sent, 0)
end)

-- ---------------------------------------------------------------------------
-- Every message type, from one client to another
-- ---------------------------------------------------------------------------
test("every message type survives the trip from my client to another", function()
    -- the first client
    local GK = boot()
    local sent = {}
    local function flush()
        W.advance(30)                       -- the queue lets two a second out
        for _, m in ipairs(W.takeSent()) do sent[#sent + 1] = m.text end
    end
    local n1 = GK.AddNote(GANK, "took my gold", "Scammer", "watch", { c = "ROGUE", r = "Orc", l = 60 })
    local n2 = GK.AddNote(NICE, "great healer", "Great healer", "kudos")
    local n3 = GK.AddNote("Old Foe-Realm", "gone again")
    GK.DeleteNote("Old Foe-Realm", n3.id)
    GK.SetMark(NICE, nil)
    flush()
    -- a vote needs someone else's note; give both clients Kari's
    local kariNote = msg("N", 1, GANK, 5, B, "", "", "", "", "", "Kari's note")
    W.receive(GK, KARI, kariNote)
    GK.VoteNote(GANK, KARI, 5, 1)
    GK.VoteNote(GANK, KARI, 5, -1)
    flush()
    sent[#sent + 1] = GK.NotesEncode.Q()
    local want = {}
    for _, key in ipairs({ GANK, NICE, "Old Foe-Realm" }) do
        want[key] = { notes = GK.NotesOf(key), mark = GK.MyMark(key) }
    end

    -- the other client, which hears them all from me
    local GK2 = boot({ me = "Other-Realm" })
    W.receive(GK2, KARI, kariNote)
    local kinds = {}
    for _, text in ipairs(sent) do
        kinds[text:sub(1, 1)] = true
        W.receive(GK2, ME, text)
    end
    for _, k in ipairs({ "N", "L", "V", "Q" }) do assert(kinds[k], "a " .. k .. " was sent") end
    for key, w in pairs(want) do
        local got = GK2.NotesOf(key)
        eq(#got, #w.notes, key .. " notes")
        for i, n in ipairs(got) do
            eq(n.text, w.notes[i].text)
            eq(n.tag, w.notes[i].tag)
            eq(n.author, w.notes[i].author)
            eq(n.ts, w.notes[i].ts)
            eq(n.id, w.notes[i].id)
        end
    end
    eq(GK2.ListsOf(GANK).watch[1], ME)
    eq(#GK2.ListsOf(NICE).kudos, 0, "the removed mark travelled")
    eq(GK2.Person(GANK).c, "ROGUE")
    eq(GK2.Person(GANK).r, "Orc")
    eq(GK2.Person(GANK).l, 60)
    eq(GK2.Person("Old Foe-Realm").notes[ME][n3.id].del, true, "the tombstone travelled")
    eq(GK2.NoteScore(GANK, KARI, 5), -1, "the last vote won")
end)

test("the encoders clean what they are given", function()
    local GK = boot()
    local text = GK.NotesEncode.N(GANK, 3, { ts = B, text = "a;b|c", tag = "x;y" }, { c = "MAGE", r = "Orc", l = 5 })
    eq(text, msg("N", 1, GANK, 3, B, "", "x,y", "MAGE", "Orc", 5, "a,b/c"))
end)

test("the nice names' old messages (M, G, H) are ignored, and keep nothing", function()
    local GK = boot()
    W.receive(GK, KARI, msg("M", 1, "Funny Name-Realm", B))
    W.receive(GK, KARI, msg("G", 1, "Funny Name-Realm", 1, B))
    W.receive(GK, KARI, msg("H", 1, "Funny Name-Realm", 1, B))
    eq(GK.Store().names, nil)
    eq(count(GK.Store().people), 0)
end)

-- ---------------------------------------------------------------------------
-- The import from Guild Grudge
-- ---------------------------------------------------------------------------
-- The shape of GuildGrudgeDB as GuildGrudge/Core.lua keeps it (see its "Data model" comment): entries by
-- lowercase key, notes with string ids and per-voter votes, and the nice names list (which Grudgekeeper
-- leaves behind: BACKLOG.md). Names are
-- "First Surname"; the player here is "Meyer Self".
local function sampleDB()
    local t = B - 5000
    return {
        settings = { alerts = true },
        entries = {
            ["ganker forever"] = {
                name = "Ganker Forever", class = "ROGUE", race = "Orc", raceFile = "Orc", sex = 2, level = 60,
                profileTs = t, lastSeen = t, lastSeenZone = "Barrens", lastSeenBy = "Kari Hansen",
                notes = {
                    ["Meyer Self-1-1"] = { id = "Meyer Self-1-1", author = "Meyer Self", ts = t + 10, zone = "Barrens",
                        text = "camped me at the FP", tag = "Griefer",
                        votes = { ["Kari Hansen"] = { v = 1, ts = t + 20 }, ["Edvard Eide"] = { v = 0, ts = t + 21 } } },
                    ["Kari Hansen-2-2"] = { id = "Kari Hansen-2-2", author = "Kari Hansen", ts = t + 30, zone = "",
                        text = "ganked my alt", votes = { ["Meyer Self"] = { v = -1, ts = t + 40 } } },
                    ["Kari Hansen-3-3"] = { id = "Kari Hansen-3-3", author = "Kari Hansen", ts = t + 31, zone = "",
                        text = "deleted one", deleted = true },
                },
                bounty = { poster = "Kari Hansen", reward = "50g", ts = t, claimedBy = "", claimedTs = 0 },
            },
            ["nina nice"] = {
                name = "Nina Nice", class = "PRIEST", race = "Human", raceFile = "Human", sex = 3, level = 70,
                list = "kudos", listTs = t + 60,
                notes = {
                    ["Kari Hansen-4-4"] = { id = "Kari Hansen-4-4", author = "Kari Hansen", ts = t + 50, zone = "",
                        text = "heals through anything", tag = "Great healer",
                        votes = { ["Meyer Self"] = { v = 1, ts = t + 55 } } },
                },
            },
            ["wanda watch"] = { name = "Wanda Watch", class = "MAGE", list = "watch", listTs = t + 70, notes = {} },
            ["bounty only"] = { name = "Bounty Only", notes = {},
                bounty = { poster = "Kari Hansen", reward = "1g", ts = t, claimedBy = "Edvard Eide", claimedTs = t } },
        },
        names = {
            ["funny name"] = { name = "Funny Name", by = "Meyer Self", ts = t + 5, class = "MAGE", race = "Gnome",
                raceFile = "Gnome", sex = 3, level = 20,
                votes = { ["Kari Hansen"] = { v = 1, ts = t + 6 }, ["Meyer Self"] = { v = 1, ts = t + 7 } } },
            ["third silly"] = { name = "Third Silly", by = "Kari Hansen", ts = t + 8,
                votes = { ["Meyer Self"] = { v = 1, ts = t + 9 } } },
            ["old name"] = { name = "Old Name", by = "Kari Hansen", ts = t + 8, deleted = true },
        },
    }
end

local IME, IKARI = "Meyer Self-Realm", "Kari Hansen-Realm"

test("import: notes, tags, lists and votes land under their authors; the nice names stay behind", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    local counts = GK.ImportGuildGrudge()
    eq(counts.notes, 3)
    eq(counts.marks, 2)
    eq(counts.names, nil)
    eq(counts.votes, 3, "the three on notes, less the removed one")
    -- Ganker: my note and Kari's live one; no deleted one; no bounty
    local key = "Ganker Forever-Realm"
    local notes = GK.NotesOf(key)
    eq(#notes, 2)
    eq(notes[1].author, IKARI)
    eq(notes[1].text, "ganked my alt")
    eq(notes[1].score, -1)
    eq(notes[1].myVote, -1)
    eq(notes[2].author, IME)
    eq(notes[2].tag, "Griefer")
    eq(notes[2].score, 1, "Kari's vote counts, the removed one doesn't")
    eq(notes[2].mine, true)
    local p = GK.Person(key)
    eq(p.c, "ROGUE")
    eq(p.rf, "Orc")
    eq(p.sx, 2)
    eq(p.l, 60)
    local lists = GK.ListsOf(key)
    eq(#lists.kos, 2, "both note authors, as kos")
    eq(#lists.watch + #lists.kudos, 0)
    -- Nina: kudos, under the author of the note
    lists = GK.ListsOf("Nina Nice-Realm")
    eq(lists.kudos[1], IKARI)
    eq(#lists.kudos, 1)
    eq(GK.NotesOf("Nina Nice-Realm")[1].tag, "Great healer")
    -- Wanda: a list and no note: mine
    eq(GK.MyMark("Wanda Watch-Realm"), "watch")
    eq(GK.Person("Wanda Watch-Realm").c, "MAGE")
    -- the bounty-only entry is not brought over
    eq(GK.Person("Bounty Only-Realm"), nil)
    -- the nice names are not taken over
    eq(GK.Store().names, nil)
    eq(GK.Person("Funny Name-Realm"), nil)
    assert(GK.db.importedGG["Guild-Realm"], "marked done")
    eq(#W.printed, 1)
    assert(W.printed[1]:find(GK.TAG, 1, true), "says who")
    assert(W.printed[1]:find("3 notes"), W.printed[1])
end)

test("import: only my own records are ever sent", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    GK.ImportGuildGrudge()
    W.receive(GK, KARI, "Q;1")
    W.advance(30)
    local sent = W.takeSent()
    local text = {}
    for _, m in ipairs(sent) do text[#text + 1] = m.text end
    local all = table.concat(text, "\n")
    assert(all:find("camped me at the FP", 1, true), "my note is sent")
    assert(not all:find("ganked my alt", 1, true), "Kari's isn't")
    assert(not all:find("heals through anything", 1, true), "Kari's isn't")
    assert(all:find("L;1;Wanda Watch-Realm;watch", 1, true), "my mark is")
    assert(not all:find("L;1;Nina Nice-Realm", 1, true), "Kari's mark isn't")
    assert(not all:find("Funny Name", 1, true) and not all:find("Third Silly", 1, true), "no nice name goes out")
    -- my votes on Kari's imported notes carry ids that are only ours: not sent
    for _, line in ipairs(text) do
        assert(line:sub(1, 1) ~= "V", "no vote on an imported note: " .. line)
    end
end)

test("import runs once per guild, unless forced, and forcing it again makes nothing twice", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    assert(GK.ImportGuildGrudge())
    local again, why = GK.ImportGuildGrudge()
    eq(again, nil)
    eq(why, "done")
    eq(#W.printed, 1, "quiet the second time")
    local forced = GK.ImportGuildGrudge(true)
    eq(forced.notes, 0)
    eq(forced.marks, 0)
    eq(#GK.NotesOf("Ganker Forever-Realm"), 2)
end)

test("import: nothing to do without a GuildGrudgeDB", function()
    local GK = boot({ me = IME })
    local r, why = GK.ImportGuildGrudge()
    eq(r, nil)
    eq(why, "nothing to import")
    eq(count(GK.Store().people), 0)
end)

test("import runs by itself after login when Guild Grudge is on", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    eq(GK.db.importedGG, nil)
    W.advance(16)
    assert(GK.db.importedGG["Guild-Realm"], "imported")
    assert(GK.IsNoted("Ganker Forever-Realm"))
    local GK2 = boot({ me = IME, guildGrudge = sampleDB(), loaded = false })
    W.advance(60)
    eq(GK2.db.importedGG, nil, "Guild Grudge is not loaded: nothing")
    eq(GK2.IsNoted("Ganker Forever-Realm"), false)
end)

test("import: odd data in Guild Grudge's tables does not stop it", function()
    local db = sampleDB()
    db.entries["broken"] = "not a table"
    db.entries["no name"] = { notes = {} }
    db.entries["ganker forever"].notes["bad"] = "nope"
    db.entries["ganker forever"].notes["no author"] = { ts = B - 100, text = "x" }
    db.entries["ganker forever"].notes["bad ts"] = { author = "Kari Hansen", ts = "soon", text = "x" }
    db.names["junk"] = 5
    local GK = boot({ me = IME, guildGrudge = db })
    local counts = GK.ImportGuildGrudge()
    eq(counts.notes, 3)
end)

test("import: a vote that is not a table is skipped and counted, and the import goes on", function()
    local db = sampleDB()
    db.entries["ganker forever"].notes["Meyer Self-1-1"].votes["Edvard Eide"] = 1
    local GK = boot({ me = IME, guildGrudge = db })
    local counts = GK.ImportGuildGrudge()
    eq(counts.skipped, 1)
    eq(counts.votes, 3)
    assert(GK.db.importedGG["Guild-Realm"], "finished")
end)

test("import: note ids come from the note, not from the order it was walked in", function()
    local function ids(reverse)
        local db = sampleDB()
        local notes = db.entries["ganker forever"].notes
        local a = { author = "Kari Hansen", ts = B + 100, text = "first", id = "Kari Hansen-9-1" }
        local b = { author = "Kari Hansen", ts = B + 100, text = "second", id = "Kari Hansen-9-2" }
        local c = { author = "Kari Hansen", ts = B + 100, text = "no id of its own" }
        local order = reverse and { c, b, a } or { a, b, c }
        for i, n in ipairs(order) do notes["k" .. i] = n end
        local GK = boot({ me = IME, guildGrudge = db })
        GK.ImportGuildGrudge()
        local out = {}
        for _, n in ipairs(GK.NotesOf("Ganker Forever-Realm")) do out[n.text] = n.id end
        return out, GK
    end
    local one, GK = ids(false)
    local two = ids(true)
    for _, text in ipairs({ "first", "second", "no id of its own", "camped me at the FP" }) do
        assert(one[text], text .. " was imported")
        eq(one[text], two[text], text)
    end
end)

test("import: an imported note of mine reaches another client under the same id", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    GK.ImportGuildGrudge()
    local mine
    for _, n in ipairs(GK.NotesOf("Ganker Forever-Realm")) do
        if n.author == IME then mine = n end
    end
    assert(mine.id > 2 ^ 31, "bigger than a time, so it can't meet one")
    W.advance(200)
    W.takeSent()
    GK.NotesBroadcast()
    W.advance(200)
    local sent = W.takeSent()
    local GK2 = boot({ me = "Other-Realm" })
    for _, m in ipairs(sent) do W.receive(GK2, IME, m.text) end
    local got = GK2.NotesOf("Ganker Forever-Realm")
    eq(#got, 1, "only mine travelled")
    eq(got[1].id, mine.id)
end)

test("import: not while the test panel is open; it tries again later", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    GK.testMode = true
    local r, why = GK.ImportGuildGrudge()
    eq(r, nil)
    eq(why, "test mode")
    W.advance(16)
    eq(GK.db.importedGG, nil, "no marker was set")
    eq(GK.IsNoted("Ganker Forever-Realm"), false)
    GK.testMode = false
    W.advance(40)
    assert(GK.db.importedGG["Guild-Realm"], "imported once the panel closed")
end)

test("import: in a guild it waits for the guild's name, and gives up quietly", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    W.guildKey = false
    local r, why = GK.ImportGuildGrudge()
    eq(r, nil)
    eq(why, "not yet")
    W.advance(200)
    eq(GK.db.importedGG, nil, "no marker, no store of the wrong guild")
    eq(GK.IsNoted("Ganker Forever-Realm"), false)
    eq(#W.printed, 0, "quiet")
    -- the name turns up in time
    local GK2 = boot({ me = IME, guildGrudge = sampleDB() })
    W.guildKey = false
    W.advance(16)
    W.guildKey = nil
    W.advance(16)
    assert(GK2.db.importedGG["Guild-Realm"], "imported under the guild")
    -- without a guild at all the guildless store is the one
    local GK3 = boot({ me = IME, guildGrudge = sampleDB(), inGuild = false })
    W.advance(16)
    assert(GK3.db.importedGG["-"], "imported into the store of your own")
end)

-- ---------------------------------------------------------------------------
-- What a letter says and which way the kill order sheet goes (Letters.lua, Post.lua)
-- ---------------------------------------------------------------------------
local function bootSheets(opts)
    local GK = boot(opts)
    for _, file in ipairs({ "Letters.lua", "Post.lua" }) do
        assert(loadfile(W.dir .. file))("Grudgekeeper", GK)
    end
    GK.orders = {}                                     -- stand-ins for Guild.lua: the orders on a player
    function GK.OrdersOn(key) return GK.orders[key] or {} end
    function GK.OrderOn(key) return (GK.orders[key] or {})[1] end
    function GK.Pot(o) return o.reward or 0, 0 end
    function GK.Accept() end
    -- and what a fulfilled order's letter asks of it: who was there, and whether it is yours to tell
    function GK.Helped() return false end
    function GK.NameList(keys) return table.concat(keys, " and ") end
    function GK.CanTellOrder(o, L)
        local t = o or L
        return not t.told and t.doneBy == ME
    end
    function GK.TellOrder() return false end
    return GK
end

-- A kill gets a letter only for a new title, in three short lines (the owner, 2026-11-07: "kanskje ikke så
-- mye text?" - seven lines ran into the seal).
test("letter content: a kill letter is a note: greeted by the title, its own line, the kill, where you stand", function()
    local GK = bootSheets({ me = ME })
    local L = { id = 2, kind = "kill", n = GANK, c = "ROGUE", r = "Orc", l = 35, z = "Hillsbrad", title = "Bloodhound",
        rank = 4, of = 12, total = 31, sample = true }
    local d = GK.LetterContent(L)
    eq(d.note, true)
    eq(d.title, "Rise, Bloodhound")
    eq(d.seal, "seal_red")
    eq(d.blood, false)
    eq(d.key, GANK)
    eq(d.c, "ROGUE")
    eq(d.sample, true)
    eq(#d.buttons, 1)
    eq(d.buttons[1][1], "Leaderboard")
    eq(table.concat(d.lines, "\n"), "So, Gank Master is dead - in Hillsbrad, I hear. From today I'm writing "
        .. "you down as Bloodhound.\nThat makes you 4th of 12 in the guild, with 31 points. Keep hunting.")
end)

test("letter content: a kill letter from before titles says the kill and where you stand", function()
    local GK = bootSheets({ me = ME })
    local L = { id = 1, kind = "kill", n = GANK, p = 2, revenge = 2, avenged = KARI, streak = 5, of = 3, rank = 1,
        total = 40 }
    local d = GK.LetterContent(L)
    eq(d.title, "Blood drawn")
    eq(table.concat(d.lines, "\n"), "So, Gank Master is dead.\nThat makes you 1st of 3 in the guild, with 40 points.\n\n"
        .. "They'll remember your name.")
end)

test("letter content: a slain letter has blood, a black seal and no buttons when it cannot act", function()
    local GK = bootSheets({ me = ME })
    GK.orders[GANK] = { { by = KARI, reward = 100 } }
    local d = GK.LetterContent({ id = 1, kind = "slain", n = GANK, times = 1 })
    eq(d.title, "Slain")
    eq(d.seal, "seal_black")
    eq(d.blood, true)
    eq(d.buttons[1][1], "Hitlist")
    local e = GK.LetterContent({ id = 1, kind = "expired", n = GANK })
    eq(e.buttons[1][1], "Post it again")
    eq(e.blood, false)
end)

-- The scroll's own buttons are only what it asks of you; Open kill orders and Close are the bar under it
-- (Letters.lua, BuildScroll; "X oppe i høyre funker ikke så bra", the owner, 2026-11-07).
test("letter content: an order is a scroll with a name and a foot, and no buttons of its own to read it", function()
    local GK = bootSheets({ me = ME })
    local d = GK.LetterContent({ id = 1, kind = "order", n = GANK, c = "MAGE", l = 60, by = KARI, reward = 20000,
        note = "Camps the flight master.", times = 3 })
    eq(d.note, nil)
    eq(d.title, "KILL ORDER")
    eq(d.name, "Gank Master")
    eq(d.foot, "Posted by Kari")
    eq(d.seal, "seal_red")
    eq(d.stamp, nil)
    eq(d.lines[1], '"Camps the flight master."')
    eq(d.lines[2], "Has killed Kari 3 times.")
    eq(#d.buttons, 0)
    local done = GK.LetterContent({ id = 2, kind = "complete", n = GANK, by = KARI, doneBy = ME, z = "Hillsbrad" })
    eq(done.title, "ORDER COMPLETE")
    eq(done.name, "Gank Master is dead")
    eq(done.stamp, "stamp_fulfilled")
    eq(done.seal, "seal_broken")
    eq(done.lines[1], "You collected the bounty in Hillsbrad.")
    eq(done.buttons[1][1], "Tell the guild")
    eq(done.buttons[2], nil)
end)

test("kill order sheet: a new order, one of yours, and someone else's pot", function()
    local GK = bootSheets({ me = ME })
    local t = { key = GANK }
    local p = GK.PostPlan(t)
    eq(p.case, "new")
    eq(p.title, "KILL ORDER")
    eq(p.bounty, "Bounty")
    eq(p.button, "Seal it")
    eq(p.amount, 0)
    eq(p.note, "")
    eq(p.asksWhy, true)
    eq(p.pot, nil)
    GK.orders[GANK] = { { by = ME, reward = 25000, note = "camper" } }
    p = GK.PostPlan(t)
    eq(p.case, "change")
    eq(p.button, "Change it")
    eq(p.amount, 25000)
    eq(p.note, "camper")
    eq(GK.PostLabel(t), "Change your kill order")
    local theirs = { by = KARI, reward = 5000, pot = { [ME] = 300 } }
    GK.orders[GANK] = { theirs }
    p = GK.PostPlan(t)
    eq(p.case, "pot")
    eq(p.pot, theirs)
    eq(p.title, "ADD TO THE POT")
    eq(p.bounty, "Your share")
    eq(p.button, "Add it")
    eq(p.amount, 300)
    eq(p.asksWhy, false)
    eq(p.small, "Kari already has an order on them: 50s. Your share goes on top, and you pay it to whoever fulfils it.")
    eq(GK.PostLabel(t), "Add to the pot")
end)

test("kill order sheet: sealing posts a new order, or adds to the pot it was opened on", function()
    local GK = bootSheets({ me = ME })
    local posted, added = {}, {}
    function GK.PostOrder(t, copper, note) posted[#posted + 1] = { t, copper, note } return { key = "o1" } end
    function GK.Contribute(o, copper) added[#added + 1] = { o, copper } end
    local t = { key = GANK }
    eq(GK.PostSubmit(t, 12000, "why"), true)
    eq(#posted, 1)
    eq(posted[1][2], 12000)
    eq(posted[1][3], "why")
    local theirs = { by = KARI, reward = 5000 }
    GK.orders[GANK] = { theirs }
    eq(GK.PostSubmit(t, 700, "ignored"), true)
    eq(added[1][1], theirs)
    eq(added[1][2], 700)
    eq(#posted, 1, "no second order")
    -- the plan the sheet was opened with decides, even if an order has appeared since
    GK.orders[GANK] = nil
    eq(GK.PostSubmit(t, 900, "n", { case = "pot", pot = theirs }), true)
    eq(added[2][1], theirs)
    -- a refused order says why and answers false
    function GK.PostOrder() return nil, "Too many orders." end
    W.printed = {}
    eq(GK.PostSubmit(t, 1, ""), false)
    assert(W.printed[1] and W.printed[1]:find("Too many orders.", 1, true), "said why")
end)

-- ---------------------------------------------------------------------------
-- Telling the guild what the import made
-- ---------------------------------------------------------------------------
test("NotesBroadcast sends my own records two a second, never someone else's, never in test mode", function()
    local GK = boot()
    W.advance(11)
    for i = 1, 5 do GK.AddNote("Player" .. i .. "-Realm", "my note " .. i) end
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "", "", "", "Kari's note"))
    W.advance(10)
    W.takeSent()
    eq(GK.NotesBroadcast(), true)
    W.advance(10)
    local sent = W.takeSent()
    eq(#sent, 5)
    local per = {}
    for _, m in ipairs(sent) do
        per[m.at] = (per[m.at] or 0) + 1
        assert(not m.text:find("Kari's note", 1, true), "never someone else's")
    end
    for at, n in pairs(per) do assert(n <= 2, "at most 2 at one moment, got " .. n .. " at " .. at) end
    GK.testMode = true
    eq(GK.NotesBroadcast(), false)
    W.advance(10)
    eq(#W.sent, 0)
    local GK2 = boot({ inGuild = false })
    eq(GK2.NotesBroadcast(), false, "outside a guild")
end)

-- ---------------------------------------------------------------------------
-- The outbound queue, the limits, ownership and ties
-- ---------------------------------------------------------------------------
test("sync: live changes, a Q reply and a broadcast share one queue of two a second", function()
    local GK = boot()
    W.advance(11)
    for i = 1, 30 do GK.AddNote("Player" .. i .. "-Realm", "note " .. i) end
    W.takeSent()
    for i = 31, 70 do GK.AddNote("Player" .. i .. "-Realm", "note " .. i) end
    W.receive(GK, KARI, "Q;1")
    W.advance(3)
    GK.AddNote("Late Player-Realm", "typed meanwhile")
    GK.NotesBroadcast()
    W.advance(200)
    local sent = W.takeSent()
    local per = {}
    for _, m in ipairs(sent) do per[m.at] = (per[m.at] or 0) + 1 end
    for at, n in pairs(per) do assert(n <= 2, "at most 2 in one second, got " .. n .. " at " .. at) end
    local all = {}
    for _, m in ipairs(sent) do all[#all + 1] = m.text end
    assert(table.concat(all, "\n"):find("typed meanwhile", 1, true), "the live change got out as well")
end)

test("sync: a broadcast while one is waiting is the same stream", function()
    local GK = boot()
    W.advance(11)
    for i = 1, 6 do GK.AddNote("Player" .. i .. "-Realm", "note " .. i) end
    W.advance(10)
    W.takeSent()
    -- a live change keeps the line busy, so the broadcast waits unsent: a second ask is the same one
    GK.AddNote("Player 7-Realm", "note 7")
    W.takeSent()
    eq(GK.NotesBroadcast(), true)
    eq(GK.NotesBroadcast(), true, "merged")
    W.advance(30)
    eq(#W.takeSent(), 7, "each record once")
    -- asked again once it is partly gone: the newcomer missed the start, so one more follows, shared
    eq(GK.NotesBroadcast(), true)
    W.advance(2)
    eq(GK.NotesBroadcast(), true)
    eq(GK.NotesBroadcast(), true)
    W.advance(60)
    eq(#W.takeSent(), 14, "the first again, and one follow-up for both asks")
    W.advance(60)
    eq(#W.takeSent(), 0)
end)

test("sync: what waits for the old guild is not sent to the new one", function()
    local GK = boot()
    W.advance(11)
    for i = 1, 10 do GK.AddNote("Player" .. i .. "-Realm", "note " .. i) end
    W.advance(1)
    eq(#W.takeSent(), 4)
    -- the guild changes without a roster event: the send itself checks
    W.guildKey = "Other-Realm"
    W.advance(10)
    eq(#W.takeSent(), 0, "the rest was meant for the first guild")
    GK.AddNote("New Player-Realm", "in the new guild")
    eq(#W.takeSent(), 1, "a change made here goes out")
end)

test("sync: a guild update that changes the guild clears the queue", function()
    local GK, LIB = boot()
    W.advance(11)
    for i = 1, 10 do GK.AddNote("Player" .. i .. "-Realm", "note " .. i) end
    W.takeSent()
    W.guildKey = "Other-Realm"
    LIB.fire("GUILD_ROSTER_UPDATE")
    -- back in the first guild before the timers run: the cleared entries stay gone
    W.guildKey = nil
    LIB.fire("GUILD_ROSTER_UPDATE")
    W.advance(20)
    eq(#W.takeSent(), 0)
    -- the same guild again clears nothing
    GK.AddNote("Player 11-Realm", "x")
    LIB.fire("PLAYER_GUILD_UPDATE")
    W.advance(5)
    eq(#W.takeSent(), 1)
end)

test("sync: nothing is sent at send time in test mode, whatever was queued", function()
    local GK = boot()
    W.advance(11)
    for i = 1, 6 do GK.AddNote("Player" .. i .. "-Realm", "note " .. i) end
    W.takeSent()
    GK.testMode = true
    W.advance(20)
    eq(#W.takeSent(), 0)
end)

test("limits: deletion records count against 40 ids per author per player, and expired ones make room", function()
    local GK = boot()
    for i = 1, 50 do W.receive(GK, KARI, msg("N", 1, GANK, i, B + i, 1)) end
    eq(count(GK.Person(GANK).notes[KARI]), 40, "the rest was turned away")
    eq(GK.Person(GANK).notes[KARI][41], nil)
    W.advance(31 * 24 * 3600)
    W.receive(GK, KARI, msg("N", 1, GANK, 99, B + 31 * 24 * 3600, "", "", "", "", "", "fresh"))
    eq(count(GK.Person(GANK).notes[KARI]), 40, "still 40")
    eq(GK.Person(GANK).notes[KARI][1], nil, "the oldest expired one went")
    eq(#GK.NotesOf(GANK), 1)
end)

test("limits: 5000 note ids in all, and a new one needs an expired deletion record to go", function()
    local GK = boot()
    for p = 1, 126 do
        for i = 1, 40 do
            GK.NotesPut.Note("Player" .. p .. "-Realm", KARI, i, { ts = B + i, del = true })
        end
    end
    local n = 0
    for _, person in pairs(GK.Store().people) do n = n + count(person.notes[KARI]) end
    eq(n, 5000)
    eq(GK.Person("Player126-Realm"), nil, "the 126th player got nothing")
    eq(GK.NotesPut.Note("Other-Realm", EDVARD, 1, { text = "x", ts = B + 1 }), false, "full of young deletions")
    W.advance(31 * 24 * 3600)
    eq(GK.NotesPut.Note("Other-Realm", EDVARD, 1, { text = "x", ts = B + 31 * 24 * 3600 }), true)
    n = 0
    for _, person in pairs(GK.Store().people) do
        for _, byId in pairs(person.notes) do n = n + count(byId) end
    end
    eq(n, 5000, "one in, one out")
end)

test("limits: at 500 people only one whose every record has expired is forgotten", function()
    local GK = boot()
    for i = 1, 500 do
        assert(GK.NotesPut.Note("Player" .. i .. "-Realm", KARI, 1, { text = "n", ts = B + 1 }))
    end
    GK.NotesPut.Note("Player1-Realm", KARI, 1, { ts = B + 2, del = true })
    eq(GK.NotesPut.Note("Newcomer-Realm", KARI, 1, { text = "n", ts = B + 3 }), false, "Player1's deletion is young")
    assert(GK.Person("Player1-Realm"), "and kept")
    W.advance(31 * 24 * 3600)
    eq(GK.NotesPut.Note("Newcomer-Realm", KARI, 1, { text = "n", ts = B + 31 * 24 * 3600 }), true)
    eq(GK.Person("Player1-Realm"), nil)
    assert(GK.Person("Player2-Realm"), "a live one is never forgotten")
end)

test("a removed mark outlives its 30 days while its author still has a live note", function()
    local GK = boot()
    local month = 31 * 24 * 3600
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "", "", "", "ninja"))
    W.receive(GK, KARI, msg("L", 1, GANK, "kudos", B + 1))
    W.receive(GK, KARI, msg("L", 1, GANK, "", B + 2, 1))
    eq(#GK.ListsOf(GANK).kos, 0, "the removed mark keeps them off Marked")
    W.advance(month)
    GK.PruneNotes()
    eq(#GK.ListsOf(GANK).kos, 0, "still off Marked a month on")
    assert(GK.Person(GANK).marks[KARI], "the tombstone was kept")
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + month, 1))
    W.advance(month)
    GK.PruneNotes()
    eq(GK.Person(GANK), nil, "with no note left it goes, mark and all")
end)

test("votes that beat their note wait for it, a few and for ten minutes", function()
    local GK = boot()
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, 1, B + 3))
    eq(GK.Person(GANK), nil, "a vote makes no player")
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 1, "", "", "", "", "", "ninja"))
    eq(GK.NoteScore(GANK, KARI, 7), 1, "applied when the note came")
    -- too late
    W.receive(GK, EDVARD, msg("V", 1, "Slow-Realm", KARI, 7, 1, B + 3))
    W.advance(11 * 60)
    W.receive(GK, KARI, msg("N", 1, "Slow-Realm", 7, B + 1, "", "", "", "", "", "ninja"))
    eq(GK.NoteScore("Slow-Realm", KARI, 7), 0, "it had expired")
    -- a bounded set: the newest 200 are kept
    for i = 1, 250 do W.receive(GK, EDVARD, msg("V", 1, "Held" .. i .. "-Realm", KARI, 7, 1, B + 3)) end
    local applied = 0
    for i = 1, 250 do
        W.receive(GK, KARI, msg("N", 1, "Held" .. i .. "-Realm", 7, B + 1, "", "", "", "", "", "x"))
        applied = applied + GK.NoteScore("Held" .. i .. "-Realm", KARI, 7)
    end
    eq(applied, 200)
end)

test("held votes keep the newest per voter, and an old copy does not keep them alive", function()
    local GK = boot()
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, 1, B + 200))
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, -1, B + 100))
    W.receive(GK, KARI, msg("N", 1, GANK, 7, B + 1, "", "", "", "", "", "ninja"))
    eq(GK.NoteScore(GANK, KARI, 7), 1, "the later vote, not the older copy")
    -- an older copy later on doesn't renew the wait
    W.receive(GK, EDVARD, msg("V", 1, "Slow-Realm", KARI, 7, 1, B + 200))
    W.advance(9 * 60)
    W.receive(GK, EDVARD, msg("V", 1, "Slow-Realm", KARI, 7, 1, B + 100))
    W.advance(2 * 60)
    W.receive(GK, KARI, msg("N", 1, "Slow-Realm", 7, B + 1, "", "", "", "", "", "ninja"))
    eq(GK.NoteScore("Slow-Realm", KARI, 7), 0, "it expired ten minutes after the first")
end)

test("held votes are applied when the player is made here or by the import", function()
    local GK = boot()
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 7, 1, B + 3))
    GK.AddNote(GANK, "my own note")
    eq(GK.NoteScore(GANK, KARI, 7), 1, "a note of mine made the player")
    -- the import
    local IM = "Meyer Self-Realm"
    local GK2 = boot({ me = IM, guildGrudge = sampleDB() })
    W.receive(GK2, EDVARD, msg("V", 1, "Wanda Watch-Realm", KARI, 7, 1, B + 3))
    GK2.ImportGuildGrudge()
    eq(GK2.NoteScore("Wanda Watch-Realm", KARI, 7), 1, "the import made the player")
end)

test("sync: a change still waiting is replaced by a newer one to the same record", function()
    local GK = boot()
    W.advance(11)
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "", "", "", "hers"))
    GK.AddNote("Busy-Realm", "keeps the line busy")
    W.takeSent()
    for i = 1, 31 do GK.VoteNote(GANK, KARI, 1, i % 2 == 1 and 1 or -1) end
    W.advance(10)
    local votes = {}
    for _, m in ipairs(W.takeSent()) do
        if m.text:sub(1, 1) == "V" then votes[#votes + 1] = m.text end
    end
    eq(#votes, 1, "one message, the latest")
    assert(votes[1]:find(";1;", 1, true), "the last of 31 toggles was a vote up: " .. votes[1])
    eq(GK.MyNoteVote(GANK, KARI, 1), 1)
end)

test("sync: past 400 waiting, the live changes give way to a fresh broadcast", function()
    local GK = boot()
    W.advance(11)
    for i = 1, 450 do GK.AddNote("Many" .. i .. "-Realm", "note " .. i) end
    W.advance(1000)
    local sent = W.takeSent()
    assert(#sent < 450, "not every intermediate message was kept, sent " .. #sent)
    assert(#sent >= 150, "the broadcast stood in, sent " .. #sent)
    local per = {}
    for _, m in ipairs(sent) do per[m.at] = (per[m.at] or 0) + 1 end
    for at, n in pairs(per) do assert(n <= 2, "at most 2 in a second, got " .. n) end
end)

test("sync: nothing is queued or sent while the guild's name is unknown", function()
    local GK, LIB = boot()
    W.advance(11)
    W.takeSent()
    W.guildKey = false
    eq(GK.NotesBroadcast(), false)
    GK.AddNote(GANK, "written in between")
    W.advance(5)
    eq(#W.takeSent(), 0)
    W.guildKey = nil
    W.advance(20)
    eq(#W.takeSent(), 0, "and it was not held for later either")
    -- the question at login waits for the name
    local GK2 = boot()
    W.guildKey = false
    W.advance(12)
    eq(#W.sent, 0)
    W.guildKey = nil
    W.advance(10)
    eq(W.sent[1] and W.sent[1].text, "Q;1")
end)

test("import: notes of one second get ids from their order by text, whatever the walk order", function()
    local function ids(reverse)
        local db = sampleDB()
        local notes = {}
        db.entries["id test"] = { name = "Id Test", notes = notes }
        local t = B - 50
        local list = {
            { author = "Kari Hansen", ts = t, text = "gamma", id = "Aa" },
            { author = "Kari Hansen", ts = t, text = "alpha", id = "BB" },
            { author = "Kari Hansen", ts = t, text = "beta", id = "Cc" },
            { author = "Kari Hansen", ts = t, text = "beta", tag = "Toxic", id = "Dd" },
        }
        if reverse then
            for i = #list, 1, -1 do notes["n" .. i] = list[i] end
        else
            for i = 1, #list do notes["n" .. i] = list[i] end
        end
        local GK = boot({ me = IME, guildGrudge = db })
        GK.ImportGuildGrudge()
        local out = {}
        for _, n in ipairs(GK.NotesOf("Id Test-Realm")) do
            out[(n.text or "") .. "/" .. (n.tag or "")] = n.id
        end
        return out
    end
    local one, two = ids(false), ids(true)
    eq(one["alpha/"], (B - 50) * 100)
    eq(one["beta/"], (B - 50) * 100 + 1)
    eq(one["beta/Toxic"], (B - 50) * 100 + 2)
    eq(one["gamma/"], (B - 50) * 100 + 3)
    for k, id in pairs(one) do eq(two[k], id, k) end
end)

test("a vote on an imported note is kept here and never sent", function()
    local GK = boot()
    W.advance(11)
    GK.NotesPut.Note(GANK, KARI, 5, { text = "imported", ts = B, imp = true })
    GK.NotesPut.Note(GANK, KARI, 6, { text = "heard", ts = B })
    W.takeSent()
    eq(GK.VoteNote(GANK, KARI, 5, 1), true)
    eq(GK.NoteScore(GANK, KARI, 5), 1)
    W.advance(5)
    eq(#W.takeSent(), 0)
    eq(GK.VoteNote(GANK, KARI, 6, 1), true)
    W.advance(5)
    eq(#W.takeSent(), 1, "an ordinary one is")
end)

-- ---------------------------------------------------------------------------
-- The ledger side: NotesUI.lua, against stand-ins for the files it builds on (tests/ui_mock.lua)
-- ---------------------------------------------------------------------------
local function bootUI(opts)
    opts = opts or {}
    opts.ui = true
    return boot(opts)
end

--- A stand-in for the game's menu description: remembers the buttons made on it, and their children.
local function fakeNode(label)
    local n = { label = label, kids = {} }
    function n:CreateButton(text, fn)
        local k = fakeNode(text)
        k.fn = fn
        table.insert(self.kids, k)
        return k
    end
    function n:CreateDivider() end
    return n
end
local function kid(node, label)
    for _, k in ipairs(node.kids) do
        if k.label == label then return k end
    end
end
local function labels(node)
    local out = {}
    for _, k in ipairs(node.kids) do out[#out + 1] = k.label end
    return table.concat(out, "|")
end

-- Marked has no page since 2026-11-07: it is a section of the kill orders page (Window.lua), as kill orders
-- and Most wanted say the rest ("most wanted og kill orders holder kanskje?", the owner).
test("the list pages: Shame and Kudos on the right, none with links; Marked has none", function()
    local GK = bootUI()
    eq(#GK.LedgerPages, 7)
    local want = { { "Shame", "right", 6 }, { "Kudos", "right", 7 } }
    local order = {}
    for i, page in ipairs(GK.LedgerPages) do order[i] = page.name end
    eq(table.concat(order, "|"), "Kill orders|Leaderboard|Most wanted|Grudges|News|Shame|Kudos")
    for _, w in ipairs(want) do
        local page = GK.LedgerPages[w[3]]
        eq(page.name, w[1])
        eq(page.side, w[2])
        eq(page.sortable, true)
        eq(page.links, nil, "the list is the tab")
        eq(#page.headings, 2)
    end
    for i = 1, 5 do eq(GK.LedgerPages[i].side, nil) end
    eq(GK.LedgerPages[6].headings[1][1], "Player")
    eq(GK.db.notesList, nil, "the list is not a setting any more")
end)

test("GK.OpenNotes opens the page of the list", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    GK.OpenNotes("kos")
    eq(W2.opened, 1, "Marked is on the kill orders page")
    GK.OpenNotes("watch")
    eq(W2.opened, 6)
    GK.OpenNotes("kudos")
    eq(W2.opened, 7)
    GK.OpenNotes("names")
    eq(W2.opened, 1, "the nice names' page is gone: the kill orders page, as for any unknown list")
    GK.OpenNotes("somewhere")
    eq(W2.opened, 1, "an unknown list: the kill orders page")
end)

test("/grudge move accepts marked next to kos and shame next to watch", function()
    local GK = bootUI()
    local known = function() return true end
    eq(GK.ParseNotesCommand("move", "Gank Master marked", nil, known).list, "kos")
    eq(GK.ParseNotesCommand("move", "Gank Master kos", nil, known).list, "kos")
    eq(GK.ParseNotesCommand("move", "Gank Master shame", nil, known).list, "watch")
end)

test("/grudge shame and /grudge watch open the same page", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    GK.RunNotesCommand("shame", "")
    eq(W2.opened, 6)
    GK.RunNotesCommand("kudos", "")
    GK.RunNotesCommand("watch", "")
    eq(W2.opened, 6)
    eq(GK.ParseNotesCommand("shame", "Gank Ster", nil, function() return false end).list, "watch")
end)

test("the page's rows: newest first, with tags, the newest note, the score and my own", function()
    local GK = bootUI()
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 10, "", "Scammer", "ROGUE", "Orc", 60, "took my gold"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B + 11))
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 1, 1, B + 12))
    W.receive(GK, KARI, msg("N", 1, "Older Foe-Realm", 1, B + 5, "", "", "", "", "", "ganked me"))
    local items, empty = GK.NotesItems("kos")
    eq(#items, 1, "Gank is on Shame, not on kos")
    eq(items[1].name, "Older Foe")
    eq(items[1].sub, '"ganked me"')
    eq(items[1].right, "")
    eq(items[1].own, nil)
    assert(empty:find("Nobody is marked"), empty)
    items, empty = GK.NotesItems("watch")
    eq(#items, 1)
    local it = items[1]
    eq(it.key, "p:" .. GANK)
    eq(it.name, "Gank Master")
    eq(it.sub, GK.TagText("Scammer", 12) .. ' - "took my gold"')
    eq(it.right, "+1")
    eq(it.votes, 1)
    eq(it.ts, B + 11)
    eq(it.face.c, "ROGUE")
    eq(it.select.kind, "card")
    eq(it.select.make().key, GANK)
    GK.AddNote(GANK, "mine too", nil, "watch")
    eq(GK.NotesItems("watch")[1].own, true)
    -- two rows come in the order of their news
    GK.AddNote("Older Foe-Realm", "again", nil, "watch")
    W.advance(20)
    GK.AddNote("Older Foe-Realm", "and again")
    local rows = GK.NotesItems("watch")
    eq(#rows, 2)
    eq(rows[1].name, "Older Foe", "the newest news first")
    eq(GK.LedgerPages[6].sub(rows), "2 players on Shame")
    eq(#GK.LedgerPages[6].items(), 2)
end)

test("a noted player's card: title, who put them where, the notes with their votes, the score", function()
    local GK = bootUI()
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 10, "", "Ninja looter", "ROGUE", "Orc", 60, "took the chest: twice"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B + 11))
    W.receive(GK, EDVARD, msg("N", 1, GANK, 1, B + 20, "", "", "", "", "", "agreed"))
    W.receive(GK, EDVARD, msg("V", 1, GANK, KARI, 1, 1, B + 21))
    local d = GK.NoteCard(GANK)
    eq(d.title, "MARKED", "Edvard's note without a mark counts as kos, and no list of mine is chosen")
    eq(d.name, "Gank Master")
    eq(d.info, "Level 60 Orc")
    eq(d.big, "+1")
    eq(d.caption, "votes")
    eq(d.c, "ROGUE")
    eq(d.lines[1], "Marked: Edvard")
    eq(d.lines[2], "Shame: Kari - " .. GK.TagText("Ninja looter", 12))
    eq(#d.lines, 4)
    eq(d.lines[3], '"agreed" - Edvard, 3 days ago')
    assert(d.lines[4]:find('^"took the chest:\194\160twice" %- Kari, 3 days ago %(%+1%)$'), d.lines[4])
    assert(not d.lines[4]:find("^[^:,]+: "), "the ledger would read that as a label")
    -- the page's list wins when they are on it; my own mark wins over that
    eq(GK.NoteCard(GANK, "watch").title, "SHAME")
    eq(GK.NoteCard(GANK, "kudos").title, "MARKED", "not on that list")
    GK.SetMark(GANK, "kudos")
    eq(GK.NoteCard(GANK, "watch").title, "KUDOS")
    eq(GK.NoteCard(GANK).lines[3], "Kudos: you")
    -- buttons
    local t
    GK.OpenNoteSheet = function(arg, list) t = { arg = arg, list = list } end
    d.buttons[1][2]()
    eq(t.arg.key, GANK)
    eq(t.arg.c, "ROGUE")
    eq(t.list, "kudos", "my mark at the time of the click")
    eq(GK.NoteCard(GANK).buttons[1][1], "Add a note")
    eq(GK.NoteCard(GANK).buttons[2][1], "More...")
    eq(GK.NoteCard("Nobody-Realm"), nil)
end)

test("a card gives five notes and then says how many more", function()
    local GK = bootUI()
    for i = 1, 8 do W.receive(GK, KARI, msg("N", 1, GANK, i, B + i, "", "", "", "", "", "note " .. i)) end
    local d = GK.NoteCard(GANK)
    eq(#d.lines, 7, "one list, five notes, the rest counted")
    eq(d.lines[2], '"note 8" - Kari, 3 days ago')
    eq(d.lines[7], "and 3 more notes.")
    GK.Person("Empty-Realm", true)
    local e = GK.NoteCard("Empty-Realm")
    eq(e.title, "NOTES")
    eq(e.lines[1], "Nothing is written down about them.")
end)

test("the More menu: move or remove my mark, vote on others' notes, delete mine, the poster for an enemy", function()
    local GK = bootUI()
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 10, "", "", "ROGUE", "Orc", 60, "hers"))
    local mine = GK.AddNote(GANK, "my own note", nil, "watch")
    require("wow_mock").seen[GANK] = true
    local root = fakeNode("root")
    GK.NoteMenu(root, GANK)
    eq(labels(root), "Move my mark to|Remove my mark|Vote on a note|Delete my note|Open their poster",
        "we have seen them as an enemy")
    eq(labels(kid(root, "Move my mark to")), "Marked|Kudos", "not the list I am on")
    kid(kid(root, "Move my mark to"), "Kudos").fn()
    eq(GK.MyMark(GANK), "kudos")
    local vote = kid(root, "Vote on a note")
    eq(#vote.kids, 1, "only Kari's note, not mine")
    local row = vote.kids[1]
    eq(row.label, "Kari: hers")
    eq(labels(row), "Up|Down")
    kid(row, "Up").fn()
    eq(GK.NoteScore(GANK, KARI, 1), 1)
    root = fakeNode("root")
    GK.NoteMenu(root, GANK)
    eq(labels(kid(root, "Vote on a note").kids[1]), "Down|Take back")
    kid(kid(root, "Delete my note"), "my own note").fn()
    eq(#GK.NotesOf(GANK), 1)
    kid(root, "Remove my mark").fn()
    eq(GK.MyMark(GANK), nil)
    kid(root, "Open their poster").fn()
    eq(require("wow_mock").poster.key, GANK)
    -- a human has no poster, and nothing to vote on or delete
    W.receive(GK, KARI, msg("N", 1, "Pal Human-Realm", 1, B, "", "", "MAGE", "Human", 20, "nice"))
    root = fakeNode("root")
    GK.NoteMenu(root, "Pal Human-Realm")
    eq(labels(root), "Move my mark to|Vote on a note")
end)

local function LiveMine(GK)
    local n = 0
    for _, note in ipairs(GK.NotesOf(GANK)) do
        if note.mine then n = n + 1 end
    end
    return n
end

test("the More menu reaches every note, in submenus of ten past ten", function()
    local GK = bootUI()
    for i = 1, 15 do W.receive(GK, KARI, msg("N", 1, GANK, i, B + i, "", "", "", "", "", "kari " .. i)) end
    for i = 1, 10 do W.receive(GK, EDVARD, msg("N", 1, GANK, i, B + 20 + i, "", "", "", "", "", "edvard " .. i)) end
    for i = 1, 20 do GK.AddNote(GANK, "mine " .. i) end
    local root = fakeNode("root")
    GK.NoteMenu(root, GANK)
    local vote, del = kid(root, "Vote on a note"), kid(root, "Delete my note")
    eq(labels(vote), "Notes 1-10|Notes 11-20|Notes 21-25")
    eq(labels(del), "Notes 1-10|Notes 11-20")
    eq(#kid(vote, "Notes 21-25").kids, 5)
    eq(#kid(del, "Notes 11-20").kids, 10)
    -- the oldest note is in the last page, and works
    local last = kid(vote, "Notes 21-25").kids[5]
    eq(last.label, "Kari: kari 1")
    kid(last, "Up").fn()
    eq(GK.NoteScore(GANK, KARI, 1), 1)
    kid(del, "Notes 11-20").kids[10].fn()
    eq(LiveMine(GK), 19)
    -- ten or fewer need no pages
    local GK2 = bootUI()
    for i = 1, 10 do W.receive(GK2, KARI, msg("N", 1, GANK, i, B + i, "", "", "", "", "", "kari " .. i)) end
    root = fakeNode("root")
    GK2.NoteMenu(root, GANK)
    eq(#kid(root, "Vote on a note").kids, 10)
    eq(kid(kid(root, "Vote on a note"), "Notes 1-10"), nil)
end)

test("Mine only keeps a row I voted on, and a vote taken back lets it go", function()
    local GK = bootUI()
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 10, "", "", "ROGUE", "Orc", 60, "hers"))
    eq(GK.NotesItems("kos")[1].own, nil)
    GK.VoteNote(GANK, KARI, 1, 1)
    eq(GK.NotesItems("kos")[1].own, true, "voted on the note")
    eq(GK.NotesItems("kos")[1].mine, nil, "the tint is for what I wrote")
    GK.VoteNote(GANK, KARI, 1, 0)
    eq(GK.NotesItems("kos")[1].own, nil)
end)

test("the note sheet and the small letter have frames of their own names", function()
    local file = assert(io.open(W.dir .. "NotesUI.lua"))
    local source = file:read("*a")
    file:close()
    assert(not source:find('"GrudgekeeperNote"', 1, true), "that name is the small letter's (Letters.lua)")
    local _, n = source:gsub('"GrudgekeeperNoteSheet"', "")
    eq(n, 1, "the frame's name, given to GK.MakeSheet (Letters.lua), which also puts it on Escape")
end)

test("the poster and the record get at most two lines about notes, and never more than nine in all", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    W2.posterLines = {}
    eq(#GK.PosterCard({ key = GANK }).lines, 0, "nobody noted: nothing added")
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 10, "", "Ninja looter", "", "", "", "took the chest"))
    W.receive(GK, KARI, msg("N", 1, GANK, 2, B + 11, "", "", "", "", "", "again"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B + 12))
    local d = GK.PosterCard({ key = GANK })
    eq(#d.lines, 2)
    eq(d.lines[1], "Notes: 2, on Shame (" .. GK.TagText("Ninja looter", 12) .. ")")
    eq(d.lines[2], 'Newest: "again" - Kari, 3 days ago')
    W2.posterLines = { 1, 2, 3, 4, 5, 6, 7, 8 }
    d = GK.PosterCard({ key = GANK })
    eq(#d.lines, 9, "one fits")
    eq(d.lines[9], "Notes: 2, on Shame (" .. GK.TagText("Ninja looter", 12) .. ")")
    W2.posterLines = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    eq(#GK.PosterCard({ key = GANK }).lines, 9)
    W2.recordLines = {}
    eq(#GK.RecordCard(GANK).lines, 2)
    eq(#GK.RecordCard("Stranger-Realm").lines, 0)
    -- a mark with no note
    GK.SetMark("Marked-Realm", "kudos")
    eq(GK.RecordCard("Marked-Realm").lines[1], "Notes: none, on Kudos")
    eq(#GK.RecordCard("Marked-Realm").lines, 1)
    W2.posterLines, W2.recordLines = nil, nil
end)

test("writing a note: a few words, a tag or a list is enough; nothing at all is not", function()
    local GK = bootUI()
    local t = { key = GANK, c = "ROGUE", r = "Orc", l = 60 }
    eq(select(1, GK.WriteNote(t, "kos", "  ", " ")), true, "a list alone sets my mark")
    eq(GK.MyMark(GANK), "kos")
    eq(GK.Person(GANK).c, "ROGUE", "and what we know of them goes with it")
    eq(#GK.NotesOf(GANK), 0)
    local ok, why = GK.WriteNote(t, nil, "", "")
    eq(ok, nil)
    assert(why:find("Write something"), why)
    eq(GK.WriteNote(t, "watch", "took my gold", "Scammer"), true)
    eq(GK.MyMark(GANK), "watch")
    eq(GK.NotesOf(GANK)[1].text, "took my gold")
    eq(GK.NotesOf(GANK)[1].tag, "Scammer")
    eq(GK.WriteNote(t, "watch", "", "Toxic"), true, "a tag alone is a note")
    eq(#GK.NotesOf(GANK), 2)
    eq(GK.WriteNote(t, nil, "no list, only words", ""), true)
    eq(GK.MyMark(GANK), "watch", "no list chosen: my mark stays")
    ok, why = GK.WriteNote({ key = "NoRealm" }, "kos", "x")
    eq(ok, nil)
    assert(why:find("no name"), why)
    eq(select(1, GK.WriteNote(nil, "kos", "x")), nil)
    eq(count(GK.Store().people), 1, "no record made for a name that can't be kept")
end)

test("slash parsing: names are two words, and a note's own words are not taken for one", function()
    local GK = bootUI()
    local known = function(key) return key == GANK end
    local P = GK.ParseNotesCommand
    local r = P("note", "Gank Master he took my loot", nil, known)
    eq(r.key, GANK)
    eq(r.text, "he took my loot")
    r = P("note", "he took my loot", KARI, known)
    eq(r.key, KARI, "no known name: the target")
    eq(r.text, "he took my loot")
    r = P("note", "Gank Master he took my loot", KARI, known)
    eq(r.key, GANK, "a known name wins over the target")
    r = P("note", "Brand New took my loot", nil, known)
    eq(r.key, "Brand New-Realm", "no target: the first two words")
    eq(r.text, "took my loot")
    local none, usage = P("note", "too short", nil, known)
    eq(none, nil)
    assert(usage:find("Usage: /grudge note"), usage)
    eq(select(1, P("note", "", KARI, known)), nil)
    eq(select(1, P("note", "Gank Master", KARI, known)), nil, "a name and nothing to say")
    r = P("watch", "Gank Master ninja looter", KARI, known)
    eq(r.key, GANK)
    eq(r.text, "ninja looter")
    eq(r.list, "watch")
    r = P("kudos", "Nina Nice", nil, known)
    eq(r.key, NICE)
    eq(r.text, "")
    eq(r.list, "kudos")
    r = P("kudos", "", KARI, known)
    eq(r.key, KARI)
    eq(select(1, P("watch", "", nil, known)), nil)
    eq(select(1, P("nice", "Funny Name", KARI, known)), nil, "the nice names' command is gone")
    r = P("move", "Gank Master Watch", nil, known)
    eq(r.key, GANK)
    eq(r.list, "watch")
    eq(r.clear, false)
    r = P("move", "Gank Master none", nil, known)
    eq(r.list, nil)
    eq(r.clear, true)
    r = P("move", "kudos", KARI, known)
    eq(r.key, KARI)
    eq(r.list, "kudos")
    eq(select(1, P("move", "Gank Master", nil, known)), nil, "no list")
    eq(select(1, P("move", "Gank Master elsewhere", nil, known)), nil)
    eq(select(1, P("move", "", KARI, known)), nil)
    eq(select(1, P("move", "kudos", nil, known)), nil, "no name and no target")
end)

test("/grudge: our subcommands act, everything else is Core's, and the help grows", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    W.units.target = GANK
    local slash = SlashCmdList.GRUDGEKEEPER
    slash("note he took my loot")
    eq(GK.NotesOf(GANK)[1].text, "he took my loot")
    assert(W.printed[#W.printed]:find("Written down on Gank Master"), W.printed[#W.printed])
    slash("watch Nina Nice great healer")
    eq(GK.MyMark(NICE), "watch")
    eq(GK.NotesOf(NICE)[1].text, "great healer")
    slash("move Nina Nice kudos")
    eq(GK.MyMark(NICE), "kudos")
    slash("move Nina Nice none")
    eq(GK.MyMark(NICE), nil)
    W.units.target = nil
    slash("notes")
    eq(W2.opened, 1, "the kill orders page, where Marked is")
    slash("watch")
    eq(W2.opened, 6)
    slash("kudos")
    eq(W2.opened, 7)
    slash("watch Nina Nice")
    eq(W2.opened, 7, "with a name, watch adds")
    eq(GK.MyMark(NICE), "watch")
    slash("note")
    assert(W.printed[#W.printed]:find("Usage: /grudge note"), W.printed[#W.printed])
    -- Core's own, untouched
    slash("options")
    eq(W2.optionsOpened, true)
    -- its help for what nobody knows, with ours below
    W.printed = {}
    slash("bogus")
    local all = table.concat(W.printed, "\n")
    assert(all:find("commands:", 1, true), "Core's help")
    assert(all:find("/grudge notes", 1, true), "ours")
    -- a command Core knows gets no help from us
    W.printed = {}
    slash("notice")
    assert(not table.concat(W.printed, "\n"):find("/grudge notes", 1, true))
end)

test("/gg is ours only when Guild Grudge isn't loaded", function()
    SLASH_GRUDGEKEEPERGG1 = nil
    local GK = bootUI({ me = IME, guildGrudge = {} })
    eq(SLASH_GRUDGEKEEPERGG1, nil, "Guild Grudge has it")
    local GK2 = bootUI()
    eq(SLASH_GRUDGEKEEPERGG1, "/gg")
    SlashCmdList.GRUDGEKEEPERGG("watch Nina Nice")
    eq(GK2.MyMark(NICE), "watch", "it forwards")
end)

test("the tooltip: an enemy's Grudge line gets the notes, anyone else gets a line of their own", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    eq(GK.TooltipLine(GANK, nil), nil, "nobody noted: the original's answer")
    W2.tipLine = "|cffc8281eGrudge|r  killed you 3"
    eq(GK.TooltipLine(GANK, nil), W2.tipLine)
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B + 10, "", "Ninja looter", "", "", "", "x"))
    W.receive(GK, KARI, msg("N", 1, GANK, 2, B + 11, "", "", "", "", "", "y"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B + 12))
    eq(GK.TooltipLine(GANK, nil), W2.tipLine .. "  -  Shame, 2 notes")
    W2.tipLine = nil
    eq(GK.TooltipLine(GANK, nil), "|cffc8281eGrudge|r  Shame, 2 notes")
    eq(GK.NoteTipLine(GANK), "|cffffcc00Shame|r  " .. GK.TagText("Ninja looter", 12) .. " - 2 notes")
    W.receive(GK, EDVARD, msg("L", 1, NICE, "kudos", B))
    eq(GK.NoteTipLine(NICE), "|cff4dff66Kudos|r")
    eq(GK.NoteTipLine("Stranger-Realm"), nil)
    -- the answer follows the data
    GK.SetMark(NICE, "kos")
    W.receive(GK, EDVARD, msg("L", 1, NICE, "", B + 1, 1))
    eq(GK.NoteTipLine(NICE), "|cffc8281eMarked|r")
end)

test("a noted player in sight: Marked warns when asked, Shame says a line, both at most every 90 seconds", function()
    local GK, LIB = bootUI()
    local W2 = require("wow_mock")
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "ROGUE", "Orc", 60, "x"))
    W.receive(GK, KARI, msg("N", 1, NICE, 1, B, "", "Ninja looter", "", "", "", "y"))
    W.receive(GK, KARI, msg("L", 1, NICE, "watch", B))
    W.units.mouseover = GANK
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 0, "off by default")
    GK.db.noteAlerts = true
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 1)
    eq(W2.warned[1].text, "Marked: Gank Master is near!")
    eq(W2.warned[1].urgent, true)
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 1, "within 90 seconds")
    W.advance(91)
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 2)
    -- an open kill order says it already
    W.advance(91)
    W2.order = { key = "o1" }
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 2, "Sightings.lua warns about that one")
    W2.order = nil
    -- Shame: a line in chat
    W.units.mouseover = NICE
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 2)
    GK.db.watchNearby = true
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    assert(W.printed[#W.printed]:find("Nina Nice from your Shame list is near [" .. GK.TagText("Ninja looter") .. "]", 1, true), W.printed[#W.printed])
    eq(#W2.warned, 2, "a line, not a warning")
    local lines = #W.printed
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W.printed, lines, "within 90 seconds")
    -- kudos is never announced; a mob and myself are not players of the book
    W.receive(GK, EDVARD, msg("L", 1, "Pal Human-Realm", "kudos", B))
    W.units.mouseover = "Pal Human-Realm"
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W.printed, lines)
    W.mobs.mouseover = true
    W.units.mouseover = GANK
    W.advance(91)
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 2, "a mob")
    -- what we saw of a noted player is kept
    W.mobs.mouseover = nil
    GK.db.noteAlerts = false
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(GK.Person(GANK).l, 60)
end)

test("a player on both Marked and Shame: the Shame line is not lost when the Marked warning is off", function()
    local GK, LIB = bootUI()
    local W2 = require("wow_mock")
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "ROGUE", "Orc", 60, "x"))
    W.receive(GK, EDVARD, msg("L", 1, GANK, "watch", B))
    W.units.mouseover = GANK
    GK.db.noteAlerts = false
    GK.db.watchNearby = true
    local lines = #W.printed
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 0)
    eq(#W.printed, lines + 1, "the Shame line, as the Marked warning does not run")
    assert(W.printed[#W.printed]:find("from your Shame list is near", 1, true))
    -- with the Marked warning on, it is that one alone
    W.advance(91)
    GK.db.noteAlerts = true
    LIB.fire("UPDATE_MOUSEOVER_UNIT")
    eq(#W2.warned, 1)
    eq(#W.printed, lines + 1, "no second line")
end)

test("joining the group: Shame warns with the tag, Kudos says one green line, each once", function()
    local GK, LIB = bootUI()
    local W2 = require("wow_mock")
    eq(GK.db.kudosGroup, false, "the Kudos chat line is off unless asked for")
    GK.db.kudosGroup = true
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "Ninja looter", "", "", "", "x"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B))
    W.receive(GK, KARI, msg("L", 1, NICE, "kudos", B))
    W.units.party1 = GANK
    LIB.fire("GROUP_ROSTER_UPDATE")
    eq(#W2.warned, 1)
    eq(W2.warned[1].text, "Shame list: Gank Master joined your group [" .. GK.TagText("Ninja looter") .. "]")
    eq(W2.warned[1].urgent, true)
    LIB.fire("GROUP_ROSTER_UPDATE")
    eq(#W2.warned, 1, "once")
    W.units.party2 = NICE
    LIB.fire("GROUP_ROSTER_UPDATE")
    eq(#W2.warned, 1)
    assert(W.printed[#W.printed]:find("|cff4dff66Kudos:|r Nina Nice joined your group", 1, true), W.printed[#W.printed])
    -- leaving and joining again repeats it
    W.units.party1 = nil
    LIB.fire("GROUP_ROSTER_UPDATE")
    W.units.party1 = GANK
    LIB.fire("GROUP_ROSTER_UPDATE")
    eq(#W2.warned, 2)
    -- the settings
    W.units.party1 = nil
    LIB.fire("GROUP_ROSTER_UPDATE")
    GK.db.watchGroup, GK.db.kudosGroup = false, false
    W.units.party1 = GANK
    W.units.party2 = nil
    LIB.fire("GROUP_ROSTER_UPDATE")
    eq(#W2.warned, 2)
    -- a raid is read by raidN
    W.units.party1 = nil
    LIB.fire("GROUP_ROSTER_UPDATE")
    GK.db.watchGroup = true
    W2.group = { raid = true, size = 3 }
    W.units.raid3 = GANK
    LIB.fire("GROUP_ROSTER_UPDATE")
    eq(#W2.warned, 3)
    W.units.raid3 = nil
end)

test("the right-click menu: a submenu for any player but a mob or myself, with the watch and kudos tags", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    local menu = W2.menus["MENU_UNIT_ENEMY_PLAYER"]
    assert(menu, "hooked")
    for _, which in ipairs({ "SELF", "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "COMMUNITIES_GUILD_MEMBER", "GUILD" }) do
        assert(W2.menus["MENU_UNIT_" .. which], which)
    end
    W.units.mouseover = GANK
    local root = fakeNode("root")
    menu(nil, root, { unit = "mouseover" })
    local sub = kid(root, "Grudgekeeper notes")
    assert(sub)
    eq(labels(sub), "Add a note|Shame list|Kudos", "no Their notes: nobody wrote about them")
    eq(#kid(sub, "Shame list").kids, #GK.TAGS.watch + 1)
    eq(kid(sub, "Shame list").kids[1].label, GK.TagText("Ninja looter"))
    eq(kid(sub, "Shame list").kids[#GK.TAGS.watch + 1].label, "No tag")
    eq(kid(sub, "Kudos").kids[1].label, GK.TagText("Helpful"))
    -- a tag puts them on the list with that tag
    kid(sub, "Shame list").kids[1].fn()
    eq(GK.MyMark(GANK), "watch")
    eq(GK.NotesOf(GANK)[1].tag, "Ninja looter")
    eq(GK.Person(GANK).c, "ROGUE", "learned from the unit")
    kid(sub, "Kudos").kids[#GK.TAGS.kudos + 1].fn()
    eq(GK.MyMark(GANK), "kudos", "No tag: just the mark")
    -- now they are noted
    root = fakeNode("root")
    menu(nil, root, { unit = "mouseover" })
    sub = kid(root, "Grudgekeeper notes")
    assert(kid(sub, "Their notes"))
    kid(sub, "Their notes").fn()
    eq(W2.card().key, GANK)
    -- not a mob, not me, not when the setting is off
    W2.mobs.mouseover = true
    root = fakeNode("root")
    menu(nil, root, { unit = "mouseover" })
    eq(#root.kids, 0)
    W2.mobs.mouseover = nil
    menu(nil, root, { unit = "player" })
    eq(#root.kids, 0, "myself")
    GK.db.unitMenu = false
    menu(nil, root, { unit = "mouseover" })
    eq(#root.kids, 0)
    GK.db.unitMenu = true
    -- a name in chat has no unit: the key comes from the menu's own fields
    W2.menuKey = "Chatter One-Realm"
    menu(nil, root, { name = "Chatter One" })
    eq(#root.kids, 1)
    W2.menuKey = nil
end)

test("the import tells the guild afterwards, once", function()
    local GK = bootUI({ me = IME, guildGrudge = sampleDB() })
    W.takeSent()
    assert(GK.ImportGuildGrudge())
    W.advance(30)
    local text = {}
    for _, m in ipairs(W.takeSent()) do text[#text + 1] = m.text end
    local all = table.concat(text, "\n")
    assert(all:find("camped me at the FP", 1, true), "my note went out")
    assert(not all:find("ganked my alt", 1, true), "Kari's did not")
    assert(GK.ImportGuildGrudge() == nil)
    W.advance(30)
    eq(#W.sent, 0, "nothing more: it was done already")
end)

test("the settings: defaults for every new setting, and a section for them", function()
    local GK = bootUI()
    eq(GK.db.noteAlerts, false)
    eq(GK.db.watchNearby, false)
    eq(GK.db.watchGroup, true)
    eq(GK.db.kudosGroup, false)
    eq(GK.db.plateNotes, true)
    eq(GK.db.alertStyle, nil, "no raid-warning style")
    eq(#GK.OptionSections, 1)
end)

-- ---------------------------------------------------------------------------
-- Assists (Kills.lua): a groupmate's blow on an enemy you were fighting
-- ---------------------------------------------------------------------------
local FOE_GUID, KARI_GUID = "Player-1-0000FOE", "Player-1-000KARI"

--- Kills.lua over a fake group: Kari in party1, an Orc rogue to fight. W.fight.combat is whether you are
--- in combat, W.fight.dmg[guid] the meter's list of { attacker name, amount } on that enemy, and
--- W.fight.secret whether the meter is unreadable.
local function bootKills()
    local GK, LIB = boot({ me = ME })
    W.fight = { combat = true, dmg = {} }
    _G.InCombatLockdown = function() return W.fight.combat end
    _G.UnitGUID = function(unit)
        if unit == "player" then return "Player-1-0000ME" end
        if unit == "party1" then return KARI_GUID end
        return nil
    end
    _G.UnitExists = function(unit) return _G.UnitGUID(unit) ~= nil end
    _G.UnitName = function(unit)
        if unit == "player" then return "Me" end
        return unit == "party1" and "Kari" or nil
    end
    _G.Enum = _G.Enum or {}
    _G.Enum.DamageMeterType = { EnemyDamageTaken = 2 }
    _G.Enum.DamageMeterSessionType = { Current = 1 }
    _G.C_DamageMeter = {
        GetCombatSessionSourceFromType = function(session, kind, guid)
            if W.fight.secret then return nil end
            local list = {}
            for _, e in ipairs(W.fight.dmg[guid] or {}) do
                list[#list + 1] = { totalAmount = e[2], combatSpellDetails = { unitName = e[1] } }
            end
            return { combatSpells = list }
        end,
    }
    _G.UnitLevel = function() return 60 end
    _G.IsInRaid = function() return false end
    _G.GetNumSubgroupMembers = function() return 1 end
    _G.GetNumGroupMembers = function() return 2 end
    _G.GetPlayerInfoByGUID = function(guid)
        if guid == FOE_GUID then return "Rogue", "ROGUE", "Orc", "Orc", 2, "Gank Master", "Realm" end
    end
    _G.IsInInstance = function() return false end
    _G.GetRealZoneText = function() return "Hillsbrad" end
    GK.sentKills, GK.sentAssists = {}, {}
    function GK.Seen() return nil end
    function GK.KeepLooks() end
    function GK.OrdersOn() return {} end
    function GK.Avenged() return nil end
    function GK.SendKill(v, zone, points) table.insert(GK.sentKills, { v = v, p = points }) end
    function GK.SendAssist(v, zone, points) table.insert(GK.sentAssists, { v = v, p = points }) end
    function GK.SendBoard() end
    function GK.KillLetter() end
    assert(loadfile(W.dir .. "Kills.lua"))("Grudgekeeper", GK)
    GK.StartKills()
    return GK, LIB
end

test("assist points: a little less than the kill, never below 1, nothing for a kill worth nothing", function()
    local GK = boot()
    eq(GK.AssistPoints(60, 65), 3, "red: 4 for the kill")
    eq(GK.AssistPoints(60, 60), 1, "yellow: 2 for the kill")
    eq(GK.AssistPoints(60, 55), 1, "green: 1 for the kill, still 1")
    eq(GK.AssistPoints(60, nil), 1, "a level we never saw")
    eq(GK.AssistPoints(60, 20), 0, "grey")
    eq(GK.AssistPoints(60, 65, 2), 0, "farmed today")
    eq(GK.AssistPoints(60, 60, 0, true), 2, "revenge counts")
end)

--- The fight ends with the meter showing this, and the game says so.
local function endFight(LIB, dmg)
    W.fight.combat = false
    W.fight.dmg[FOE_GUID] = dmg
    LIB.fire("PLAYER_REGEN_ENABLED")
    W.advance(1)
end

test("assist: a groupmate's kill is your assist when the meter shows your damage, after the fight", function()
    local GK, LIB = bootKills()
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    eq(GK.char.assists, 0, "not while the fight goes on")
    endFight(LIB, { { "Kari", 900 }, { "Me", 65 } })
    eq(GK.char.assists, 1)
    eq(GK.char.kills, 0, "no kill")
    local f = GK.char.foes[GANK]
    assert(f, "a grudge with them")
    eq(f.a, 1)
    eq(f.k, 0)
    eq(GK.char.log[1].k, "A")
    eq(GK.char.log[1].w, "Kari")
    eq(GK.Week().a, 1)
    eq(#GK.sentAssists, 1)
    eq(#GK.sentKills, 0)
    eq(GK.char.points, GK.sentAssists[1].p)
    assert(GK.char.points >= 1, "points for it")
end)

test("assist: none when the meter shows only the groupmate's damage", function()
    local GK, LIB = bootKills()
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    endFight(LIB, { { "Kari", 900 } })
    eq(GK.char.assists, 0)
    LIB.fire("PLAYER_REGEN_ENABLED")
    W.advance(1)
    eq(GK.char.assists, 0, "settled once, not again")
end)

test("assist: a kill out of combat settles a moment later, no event needed", function()
    local GK = bootKills()
    W.fight.combat = false
    W.fight.dmg[FOE_GUID] = { { "Kari", 900 }, { "Me", 65 } }
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    eq(GK.char.assists, 0, "the meter gets a moment first")
    W.advance(1)
    eq(GK.char.assists, 1)
end)

test("assist: a meter that won't say at the end of the fight is asked again a few seconds on", function()
    local GK, LIB = bootKills()
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    W.fight.secret = true
    endFight(LIB, { { "Me", 65 } })
    eq(GK.char.assists, 0, "secret at 1 s")
    W.fight.secret = false
    W.advance(2)
    eq(GK.char.assists, 1, "read at 3 s")
end)

test("assist: none for a stranger's kill, even with your damage in the meter", function()
    local GK, LIB = bootKills()
    GK.OnPartyKill("Player-1-STRANGER", FOE_GUID)
    endFight(LIB, { { "Me", 65 } })
    eq(GK.char.assists, 0)
end)

test("assist: a secret meter waits for the next end of combat, and is dropped after two minutes", function()
    local GK, LIB = bootKills()
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    W.fight.secret = true
    endFight(LIB, { { "Me", 65 } })
    eq(GK.char.assists, 0, "meter unreadable")
    W.fight.secret = false
    W.fight.combat = true
    LIB.fire("PLAYER_REGEN_ENABLED")
    W.advance(1)
    eq(GK.char.assists, 0, "a new fight began")
    W.fight.combat = false
    LIB.fire("PLAYER_REGEN_ENABLED")
    W.advance(1)
    eq(GK.char.assists, 1, "readable at last")

    local GK2, LIB2 = bootKills()
    GK2.OnPartyKill(KARI_GUID, FOE_GUID)
    W.fight.secret = true
    endFight(LIB2, { { "Me", 65 } })
    W.advance(125)
    LIB2.fire("PLAYER_REGEN_ENABLED")
    W.advance(1)
    W.fight.secret = false
    LIB2.fire("PLAYER_REGEN_ENABLED")
    W.advance(1)
    eq(GK2.char.assists, 0, "dropped, never counted")
end)

--- Guild.lua over the plain client: a guildie's message goes through its reader (GK.ReceiveForTest).
local function bootGuild()
    local GK = boot({ me = ME })
    assert(loadfile(W.dir .. "Guild.lua"))("Grudgekeeper", GK)
    return GK
end

test("assists on the wire: B carries them at 20-21, R after heard, H is news, and older clients' rows have none", function()
    local GK = bootGuild()
    local week = GK.WeekId()
    GK.ReceiveForTest("Grudgekeeper", msg("B", 1, 10, 2, 1, 60, "ROGUE", 5, 1, 0, week, 1, 2, 0, 0, "", "", "Orc", 2, 4, 3),
        "GUILD", KARI)
    local r = GK.Store().board[KARI]
    eq(r.a, 4)
    eq(r.wa, 3)
    eq(r.sx, 2, "the fields before are where they were")
    -- an older client's B: no assists
    GK.ReceiveForTest("Grudgekeeper", msg("B", 1, 10, 2, 1, 60, "ROGUE", 5, 1, 0, week, 1, 2, 0, 0, "", "", "Orc", 2),
        "GUILD", KARI)
    eq(GK.Store().board[KARI].a, nil)
    -- R: B's fields to sex, heard, then the assists - so an older client still finds heard at 21
    local heard = time() - 100
    GK.ReceiveForTest("Grudgekeeper", msg("R", 1, EDVARD, 10, 2, 1, 60, "ROGUE", 5, 1, 0, week, 1, 2, 0, 0, "", "",
        "Orc", 2, heard, 6, 1), "GUILD", KARI)
    local e = GK.Store().board[EDVARD]
    eq(e.t, heard)
    eq(e.a, 6)
    eq(e.wa, 1)
    -- H: the news, and nothing in the guild's tally of kills
    GK.ReceiveForTest("Grudgekeeper", msg("H", 1, GANK, "ROGUE", "Orc", 60, "Hillsbrad", 2), "GUILD", KARI)
    local n = GK.Store().feed[1]
    eq(n.kind, "H")
    eq(n.who, KARI)
    eq(n.p, 2)
    eq(GK.Store().slain[GANK], nil)
end)

test("assists on the board: yours from 0, a guildie's as sent, none for a client that sends none", function()
    local GK = bootGuild()
    _G.UnitClass = _G.UnitClass or function() return "Rogue", "ROGUE" end
    _G.UnitRace = _G.UnitRace or function() return "Human", "Human" end
    _G.UnitLevel = _G.UnitLevel or function() return 60 end
    _G.UnitSex = _G.UnitSex or function() return 2 end
    local week = GK.WeekId()
    GK.ReceiveForTest("Grudgekeeper", msg("B", 1, 10, 2, 1, 60, "ROGUE", 5, 1, 0, week, 1, 2, 0, 0, "", "", "Orc", 2, 4, 3),
        "GUILD", KARI)
    GK.ReceiveForTest("Grudgekeeper", msg("B", 1, 8, 2, 1, 60, "ROGUE", 5, 1, 0, week, 1, 2, 0, 0, "", "", "Orc", 2),
        "GUILD", EDVARD)
    local function AssistsOnBoard(weekly)
        local out = {}
        for _, e in ipairs(GK.Board(weekly)) do out[e.me and "me" or e.who] = e.a == nil and "none" or e.a end
        return out
    end
    local all, now = AssistsOnBoard(false), AssistsOnBoard(true)
    eq(all.me, 0)
    eq(all[KARI], 4)
    eq(all[EDVARD], "none")
    eq(now[KARI], 3)
    eq(now[EDVARD], "none")
end)

test("assist: your own blow is still a kill, not an assist", function()
    local GK = bootKills()
    GK.OnPartyKill("Player-1-0000ME", FOE_GUID)
    eq(GK.char.kills, 1)
    eq(GK.char.assists, 0)
    eq(#GK.sentKills, 1)
end)

-- The meter writes you "First Surname" ("Critical Mango", /grudge debug meter, 2026-11-11) while UnitName
-- gives the two apart (DECISIONS.md, 2026-09-26). The PR's test said "Me" on both sides and could not see
-- that its match on the first name alone never found you.
test("assist: the meter names you first name and surname, as the game does", function()
    local GK, LIB = bootKills()
    _G.UnitName = function(unit)
        if unit == "player" then return "Me", "Surname" end
        return unit == "party1" and "Kari" or nil
    end
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    endFight(LIB, { { "Kari Dottir", 900 }, { "Me Surname", 65 } })
    eq(GK.char.assists, 1, "your 65, under the name the meter gives you")
end)

test("assist: your pet's damage is yours, as its blow is", function()
    local GK, LIB = bootKills()
    local guid, name = _G.UnitGUID, _G.UnitName
    _G.UnitGUID = function(unit) if unit == "pet" then return "Pet-0-WOLF" end return guid(unit) end
    _G.UnitExists = function(unit) return _G.UnitGUID(unit) ~= nil end
    _G.UnitName = function(unit) if unit == "pet" then return "Wolfie" end return name(unit) end
    _G.C_DamageMeter.GetCombatSessionSourceFromType = function()
        return { combatSpells = {
            { totalAmount = 900, combatSpellDetails = { unitName = "Kari" } },
            { totalAmount = 300, combatSpellDetails = { unitName = "Wolfie", isPet = true } } } }
    end
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    endFight(LIB, {})
    eq(GK.char.assists, 1, "the wolf's 300")
end)

test("assist: a fight begun before the meter was read hides ours in Current, so the fights before are asked", function()
    local GK, LIB = bootKills()
    local m = _G.C_DamageMeter
    m.GetCombatSessionSourceFromType = function() return { combatSpells = {} } end   -- the new fight: not them
    m.GetAvailableCombatSessions = function() return { { sessionID = 7 }, { sessionID = 9 }, { sessionID = 8 } } end
    local asked = {}
    m.GetCombatSessionSourceFromID = function(id, kind, guid)
        asked[#asked + 1] = id
        if id == 8 and guid == FOE_GUID then
            return { combatSpells = { { totalAmount = 65, combatSpellDetails = { unitName = "Me" } } } }
        end
        return { combatSpells = {} }
    end
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    endFight(LIB, {})
    eq(GK.char.assists, 1, "found in the fight before")
    eq(table.concat(asked, ","), "9,8", "newest first, and no further than it had to")
end)

test("assist: the points of an assist that cross a title bring the title's letter", function()
    local GK, LIB = bootKills()
    local letters = {}
    function GK.KillLetter(v, zone, title) letters[#letters + 1] = title end
    GK.db.myLetters = true
    GK.char.points = 9
    GK.OnPartyKill(KARI_GUID, FOE_GUID)
    endFight(LIB, { { "Me", 65 } })
    eq(GK.char.points, 10)
    eq(letters[1], "Cutthroat", "the letter, as a kill's")
end)

test("old race portraits: the face from the old sheet, today's icon for a race it lacks, no face guessed", function()
    local GK = bootSheets({ me = ME })
    local tex = {}
    function tex:SetAtlas(atlas) self.atlas, self.file = atlas, nil end
    function tex:SetTexture(file) self.file, self.atlas = file, nil end
    function tex:SetTexCoord(...) self.coords = { ... } end
    eq(GK.db.oldPortraits, true, "on by default, whichever skin")
    eq(GK.SetPortrait(tex, { rf = "Orc", sx = 3 }), "race")
    eq(tex.file, "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races", "the old sheet, out of the box")
    GK.db.look = "classic"
    eq(GK.SetPortrait(tex, { rf = "Orc", sx = 3 }), "race")
    eq(tex.file, "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races", "the Classic skin as well")
    GK.db.look = nil
    GK.db.oldPortraits = true
    eq(GK.SetPortrait(tex, { rf = "Orc", sx = 3 }), "race")
    eq(tex.file, "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races", "the old sheet")
    eq(math.floor(tex.coords[1] * 1000 + 0.5), 385, "Orc: the fourth column")
    eq(math.floor(tex.coords[3] * 1000 + 0.5), 770, "female: the fourth row")
    eq(GK.SetPortrait(tex, { rf = "Vulpera", sx = 2 }), "race")
    eq(tex.atlas, "raceicon128-vulpera-male", "not on the sheet: today's icon")
    local old = CLASS_ICON_TCOORDS
    CLASS_ICON_TCOORDS = { MAGE = { 0, 1, 0, 1 } }
    eq(GK.SetPortrait(tex, { rf = "Orc", c = "MAGE" }), "class", "no sex known: the crest, never a guessed face")
    CLASS_ICON_TCOORDS = old
    GK.db.oldPortraits = false
    eq(GK.SetPortrait(tex, { rf = "Orc", sx = 3 }), "race")
    eq(tex.atlas, "raceicon128-orc-female", "the setting off: today's icon")
end)

-- ---------------------------------------------------------------------------
-- One character, more than one PC (Guild.lua): Happy Idiot logged in on a second PC, started from 0
-- there, and its first B wrote 0 over his row on every board (2026-11-11)
-- ---------------------------------------------------------------------------
--- A part as a B or an R says it: mark:u:points:kills:deaths:assists:week:wPoints:wKills:wDeaths:wAssists
local function part(id, u, p, k, d, w, wp, wk)
    return table.concat({ id, u and "1" or "", p, k, d, 0, w or "", w and wp or "", w and wk or "",
        w and 0 or "", w and 0 or "" }, ":")
end

local function bootPCs()
    local GK = bootGuild()
    W.LIB.Debounce = function(_, _, fn) fn() end
    _G.UnitClass = _G.UnitClass or function() return "Rogue", "ROGUE" end
    _G.UnitRace = _G.UnitRace or function() return "Human", "Human" end
    _G.UnitLevel = _G.UnitLevel or function() return 60 end
    _G.UnitSex = _G.UnitSex or function() return 2 end
    local function hear(sender, text) GK.ReceiveForTest("Grudgekeeper", text, "GUILD", sender) end
    -- a guildie's own B, with parts (or none, as an older client sends it)
    local function HearB(sender, p, k, d, parts)
        local w = GK.WeekId()
        if parts == nil then
            hear(sender, msg("B", 1, p, k, d, 60, "ROGUE", 0, 0, 0, w, 0, 0, 0, 0, "", "", "Orc", 2, 0, 0))
        else
            hear(sender, msg("B", 1, p, k, d, 60, "ROGUE", 0, 0, 0, w, 0, 0, 0, 0, "", "", "Orc", 2, 0, 0, parts))
        end
    end
    -- a row passed on by `sender`: field 24 is the parts; parts == nil leaves it off, as an older client does
    local function HearR(sender, who, p, k, d, parts)
        local w = GK.WeekId()
        if parts == nil then
            hear(sender, msg("R", 1, who, p, k, d, 60, "ROGUE", 0, 0, 0, w, 0, 0, 0, 0, "", "", "Orc", 2, time(), 0, 0))
        else
            hear(sender, msg("R", 1, who, p, k, d, 60, "ROGUE", 0, 0, 0, w, 0, 0, 0, 0, "", "", "Orc", 2, time(), 0, 0,
                parts))
        end
    end
    return GK, HearB, HearR
end

local function ScoreOf(r) return ("%d/%d/%d"):format(r.p or r.points, r.k or r.kills, r.d or r.deaths) end

test("two PCs of one guildie: the board adds up their parts, whichever spoke last", function()
    local GK, B = bootPCs()
    B(KARI, 26, 21, 4, part("aaaaaa", true, 26, 21, 4))
    B(KARI, 0, 5, 0, part("bbbbbb", true, 0, 5, 0))
    local r = GK.Store().board[KARI]
    eq(ScoreOf(r), "26/26/4", "the second PC's B is added, not written over the first")
    B(KARI, 27, 22, 4, part("aaaaaa", true, 27, 22, 4))
    eq(ScoreOf(r), "27/27/4", "the first PC again, one kill on")
    B(KARI, 20, 15, 4, part("aaaaaa", true, 20, 15, 4))
    eq(ScoreOf(r), "27/27/4", "an older copy of a part takes nothing away")
end)

test("a row from before parts is kept as '?' until parts from before marks add up to as much", function()
    local GK, B, R = bootPCs()
    local board = GK.Store().board
    -- Happy Idiot's own shape: the board last heard the new PC (an older client, 0 points, 5 kills); the old
    -- PC, updated, sends its whole score from before marks
    B(KARI, 0, 5, 0)
    B(KARI, 26, 21, 4, part("aaaaaa", true, 26, 21, 4))
    eq(ScoreOf(board[KARI]), "26/21/4", "the old PC's score is back, and the 5 kills it holds are not counted twice")
    eq(board[KARI].parts["?"], nil)
    -- the board last heard a PC that played a lot: the old PC's part doesn't hold that, so both count
    B(EDVARD, 10, 30, 2)
    B(EDVARD, 26, 21, 4, part("aaaaaa", true, 26, 21, 4))
    eq(ScoreOf(board[EDVARD]), "36/51/6", "kept as '?' and added")
    B(EDVARD, 36, 51, 6, part("aaaaaa", true, 26, 21, 4) .. "," .. part("bbbbbb", true, 10, 30, 2))
    eq(ScoreOf(board[EDVARD]), "36/51/6", "once that PC sends its own part, '?' goes and nothing counts twice")
    eq(board[EDVARD].parts["?"], nil)
    -- the bug itself: a brand-new PC's first B, 0 of everything, over a row from before parts
    B(GANK, 26, 21, 4)
    B(GANK, 0, 0, 0, part("nnnnnn", false, 0, 0, 0))
    eq(ScoreOf(board[GANK]), "26/21/4", "a new PC's 0 is added to the row, never written over it")
    B(GANK, 30, 30, 5, part("nnnnnn", false, 30, 30, 5))
    eq(ScoreOf(board[GANK]), "56/51/9", "however far a new PC gets, it began at 0: the old row is not in it")
    -- a row an older client passed on may be a copy of one with parts, all of them in one: not kept
    R(KARI, NICE, 26, 21, 4)
    B(NICE, 0, 0, 0, part("nnnnnn", false, 0, 0, 0))
    eq(ScoreOf(board[NICE]), "0/0/0", "a relayed row without the parts field is not counted as another PC")
end)

test("Happy Idiot updates and logs in on the old PC first: nothing is lost", function()
    local GK, _, R = bootPCs()
    local c = GK.char
    c.points, c.kills, c.deaths = 26, 21, 4
    c.pc = nil
    GK.ClaimPC(c)                   -- the old PC's first load with marks: its score is from before them
    eq(c.u, true)
    R(KARI, ME, 0, 5, 0)            -- an older client passes our row back, no parts: nothing taken from it
    eq(ScoreOf(c), "26/21/4")
    -- the guild's old row of us (the new PC's 0/5/0), and a part under our own mark that says far more
    R(KARI, ME, 999, 999, 999, part("?", false, 0, 5, 0) .. "," .. part(c.pc, true, 999, 999, 999))
    eq(ScoreOf(c), "26/21/4", "our own part is ours to say, and the old row is held in our score from before marks")
    eq(c.parts["?"], nil)
    -- the new PC is updated too: its part reaches us, and is added
    R(KARI, ME, 26, 26, 4, part("bbbbbb", true, 0, 5, 0))
    eq(ScoreOf(c), "26/26/4")
    R(EDVARD, ME, 26, 26, 4, part("bbbbbb", true, 0, 5, 0))
    eq(ScoreOf(c), "26/26/4", "the same part again adds nothing")
    -- and our B says both parts, ours first by its mark's share
    W.takeSent()
    GK.SendBoard(true)
    local sent = W.takeSent()
    local text = sent[1] and sent[1].text or ""
    local f = {}
    for x in (text .. ";"):gmatch("([^;]*);") do f[#f + 1] = x end
    eq(f[1], "B")
    eq(f[3], "26", "the score is the sum")
    local parts = f[22] or ""
    assert(parts:find(c.pc .. ":1:26:21:4:", 1, true), "our own part is what we made: " .. parts)
    assert(parts:find("bbbbbb:1:0:5:0:", 1, true), "the other PC's part goes with it: " .. parts)
end)

test("a brand-new PC takes the guild's parts of it, and its own kills go on top", function()
    local GK, _, R = bootPCs()
    local c = GK.char
    eq(c.u, nil, "a record that starts here held nothing from before marks")
    R(KARI, ME, 26, 21, 4, part("?", false, 26, 21, 4))     -- the guild's row of us, from before parts
    eq(ScoreOf(c), "26/21/4")
    c.points, c.kills = c.points + 2, c.kills + 1               -- a kill on this PC
    -- the old PC updated and killed once more: its part holds the old row, so the old row goes
    R(KARI, ME, 30, 23, 4, part("?", false, 26, 21, 4) .. "," .. part("aaaaaa", true, 28, 22, 4))
    eq(ScoreOf(c), "30/23/4", "this PC's kill, plus the old PC's whole part, and the old row only once")
    eq(c.parts["?"], nil)
end)

test("synced, one more kill on one PC, then the other logs in: the kill counts once", function()
    local GK, B, R = bootPCs()
    local c, week = GK.char, GK.WeekId()
    c.pc, c.u, c.parts = "bbbbbb", true, {}
    c.points, c.kills, c.deaths = 0, 5, 0
    -- synced: the old PC's part has reached this one
    R(KARI, ME, 26, 26, 4, part("aaaaaa", true, 26, 21, 4, week, 0, 0) .. "," .. part("bbbbbb", true, 0, 5, 0))
    eq(ScoreOf(c), "26/26/4")
    local wk = GK.Week().k
    -- one more kill on the old PC; this one logs in and a guildie hands the row back
    R(KARI, ME, 28, 27, 4, part("aaaaaa", true, 28, 22, 4, week, 2, 1) .. "," .. part("bbbbbb", true, 0, 5, 0))
    eq(ScoreOf(c), "28/27/4", "the one kill, not the old PC's whole score again")
    eq(GK.Week().k, wk + 1, "and once in this week")
    -- every guildie online answers, and a late one still has the row from before the kill
    R(EDVARD, ME, 28, 27, 4, part("aaaaaa", true, 28, 22, 4, week, 2, 1))
    R(GANK, ME, 26, 26, 4, part("aaaaaa", true, 26, 21, 4, week, 0, 0))
    eq(ScoreOf(c), "28/27/4", "the same part again, or an older copy of it, changes nothing")
    eq(GK.Week().k, wk + 1)
    -- a kill on this PC: our part grows by that kill alone
    c.points, c.kills = c.points + 2, c.kills + 1
    W.takeSent()
    GK.SendBoard(true)
    local sent = W.takeSent()
    local text = sent[1] and sent[1].text or ""
    local f = {}
    for x in (text .. ";"):gmatch("([^;]*);") do f[#f + 1] = x end
    local parts = f[22] or ""
    assert(parts:find("bbbbbb:1:2:6:0:", 1, true), "our part is our 5 kills and this one: " .. text)
    assert(parts:find("aaaaaa:1:28:22:4:", 1, true), "the old PC's part as it was handed to us: " .. text)
    -- a guildie's board hears that B, then the old PC's from before it heard of this kill
    B(GANK, 30, 28, 4, parts)
    B(GANK, 28, 27, 4, part("aaaaaa", true, 28, 22, 4) .. "," .. part("bbbbbb", true, 0, 5, 0))
    eq(ScoreOf(GK.Store().board[GANK]), "30/28/4", "each kill once on the board too, whichever PC spoke last")
end)

test("another PC's week counts in this week only", function()
    local GK, _, R = bootPCs()
    local week = GK.WeekId()
    R(KARI, ME, 16, 8, 1, part("aaaaaa", true, 10, 5, 1, week, 4, 2) .. "," .. part("bbbbbb", true, 6, 3, 0, week - 1, 6, 3))
    eq(GK.char.points, 16)
    eq(GK.Week().p, 4, "last week's part is in the score, not in this week's")
    eq(GK.Week().k, 2)
end)

test("a broken part is not read, a mark must be one, and six parts at most", function()
    local GK, _, R = bootPCs()
    local list = { "zz:1:5:5:5:0:::::", "aaaaaa:1:-5:1:1:0:::::", "AAAAAA:1:5:5:5:0:::::", "aaaaaa:1:5:5:5" }
    for i = 1, 8 do list[#list + 1] = part("c0000" .. i, true, 1, 1, 0) end
    R(KARI, ME, 0, 0, 0, table.concat(list, ","))
    eq(GK.char.kills, 6, "six good parts, the rest left out")
end)

test("the answer gives whoever asked their own row back, once", function()
    local GK, B, R = bootPCs()
    B(KARI, 26, 21, 4, part("aaaaaa", true, 26, 21, 4))
    W.takeSent()
    GK.ReceiveForTest("Grudgekeeper", msg("Q", 1), "GUILD", KARI)
    W.advance(10)
    local mine, all = nil, {}
    for _, m in ipairs(W.takeSent()) do
        all[#all + 1] = m.text
        if m.text:sub(1, #("R;1;" .. KARI)) == "R;1;" .. KARI then mine = mine or m.text end
    end
    assert(mine, "Kari's own row went back to her; sent: " .. table.concat(all, " | "))
    assert(mine:sub(-#";aaaaaa:1:26:21:4:0:::::") == ";aaaaaa:1:26:21:4:0:::::", "with its parts last: " .. mine)
    -- she asks again, and another guildie passes her row on before we would: we don't say it twice
    GK.ReceiveForTest("Grudgekeeper", msg("Q", 1), "GUILD", KARI)
    R(EDVARD, KARI, 26, 21, 4, part("aaaaaa", true, 26, 21, 4))
    W.advance(40)
    for _, m in ipairs(W.takeSent()) do
        assert(m.text:sub(1, #("R;1;" .. KARI)) ~= "R;1;" .. KARI, "said again: " .. m.text)
    end
end)

-- ---------------------------------------------------------------------------
-- Avenging only in a later fight (Guild.lua GK.Avenged, Kills.lua): "trenger en combat reset i mellom"
-- (the owner, 2026-11-12) - one of the group dying first was a point more for everyone on their killer
-- ---------------------------------------------------------------------------
test("avenge: a guildie who fell before this fight began, not one who fell in it", function()
    local GK = bootGuild()
    function GK.KeepLooks() end                    -- Sightings.lua's: the face a death brings
    GK.ReceiveForTest("Grudgekeeper", msg("D", 1, GANK, "ROGUE", "Orc", 60, "Hillsbrad", 1, "Orc", 2), "GUILD", KARI)
    local fell = time()
    W.advance(30)
    eq(GK.Avenged(GANK, time(), fell - 20), nil, "the fight was on when she fell: the same fight")
    eq(GK.Avenged(GANK, time(), fell), nil, "a fight begun the second she fell: the same fight")
    eq(GK.Avenged(GANK, time(), fell + 10), KARI, "a fight begun after she fell")
    eq(GK.Avenged(GANK, time()), KARI, "asked without a fight, as before")
    W.advance(GK.AVENGE_FOR)
    eq(GK.Avenged(GANK, time(), time() - 1), nil, "fifteen minutes on, not at all")
end)

test("avenge: a kill asks about the fight it is in, an assist about the fight it came from", function()
    local GK, LIB = bootKills()
    local asked = {}
    function GK.Avenged(_, _, before) asked[#asked + 1] = before end
    W.advance(100)
    LIB.fire("PLAYER_REGEN_DISABLED")
    local first = time()
    W.advance(5)
    GK.OnPartyKill(KARI_GUID, FOE_GUID)            -- Kari's blow: our assist, once the meter says
    W.fight.secret = true
    endFight(LIB, { { "Me", 65 } })                -- and it can't be read yet
    W.advance(20)
    eq(#asked, 0, "nothing settled")
    W.fight.combat = true
    LIB.fire("PLAYER_REGEN_DISABLED")              -- the next fight
    local second = time()
    W.advance(5)
    GK.OnPartyKill("Player-1-0000ME", FOE_GUID)    -- our own blow in it
    eq(asked[1], second, "our kill: the fight it is in")
    W.fight.secret = false
    endFight(LIB, { { "Me", 65 } })
    eq(GK.char.assists, 1)
    eq(asked[2], first, "the assist: the fight Kari's blow was in, not the one it was read after")
end)

-- ---------------------------------------------------------------------------
-- What's new (Letters.lua GK.DeliverNews): a small letter once per account after an update, never on a
-- first install (the owner, 2026-11-12)
-- ---------------------------------------------------------------------------
test("what's new: login says whether the account is new", function()
    boot({ me = ME })
    eq(W.started.StartLetters[1], true, "no saved table: a first install")
    boot({ me = ME, db = { share = true } })
    eq(W.started.StartLetters[1], false, "a saved table from before")
end)

test("what's new: every letter missed, oldest first, once; none on a first install or with letters off", function()
    local GK = bootSheets({ me = ME })
    function GK.NoticeUpdate() end
    GK.db.newsSeen = nil                           -- on 1.3.0, which had no letters: both
    GK.DeliverNews(false)
    eq(#GK.char.letters, 0, "a moment after login, not under the loading screen")
    W.advance(6)
    eq(#GK.char.letters, 2)
    eq(GK.char.letters[1].news, "1.4.0", "the oldest first")
    eq(GK.char.letters[2].news, "1.5.0")
    eq(GK.db.newsSeen, "1.5.0")
    GK.DeliverNews(false)                          -- the next login
    W.advance(6)
    eq(#GK.char.letters, 2, "once")

    local GK1 = bootSheets({ me = ME })
    function GK1.NoticeUpdate() end
    GK1.db.newsSeen = "1.4.0"                      -- on 1.4.0: its letter came then
    GK1.DeliverNews(false)
    W.advance(6)
    eq(#GK1.char.letters, 1)
    eq(GK1.char.letters[1].news, "1.5.0", "only the one after it")

    local GK2 = bootSheets({ me = ME })
    function GK2.NoticeUpdate() end
    GK2.DeliverNews(true)
    W.advance(6)
    eq(#GK2.char.letters, 0, "a first install: nothing is new")
    eq(GK2.db.newsSeen, "1.5.0", "and not later either")

    local GK3 = bootSheets({ me = ME })
    function GK3.NoticeUpdate() end
    GK3.db.anyLetters = false
    GK3.DeliverNews(false)
    W.advance(6)
    eq(#GK3.char.letters, 0, "letters off: none")
    eq(GK3.db.newsSeen, "1.5.0")

    local GK4 = bootSheets({ me = ME })
    function GK4.NoticeUpdate() end
    GK4.db.newsSeen = "9.0.0"                      -- a newer Grudgekeeper's, back on this one
    GK4.DeliverNews(false)
    W.advance(6)
    eq(#GK4.char.letters, 0, "a letter from a newer version: none of these")
    eq(GK4.db.newsSeen, "9.0.0", "and its id kept")
end)

-- "nei, dette synes jeg ikke er et bra brev" (the owner, 2026-11-12, of three paragraphs of rules with
-- their numbers, in a block): him talking, two short paragraphs with air between, no numbers.
test("what's new: short notes from him about no one, each with a button to where it is", function()
    local GK = bootSheets({ me = ME })
    local want = { ["1.4.0"] = { "A word from the keeper", "assists", "Leaderboard" },
        ["1.5.0"] = { "Eyes on them", "Track an enemy", "Grudges" } }
    for id, w in pairs(want) do
        local d = GK.LetterContent({ id = 1, kind = "news", news = id })
        eq(d.note, true, id)
        eq(d.title, w[1], id)
        eq(d.c, nil, id .. ": no class badge, it is about no one")
        eq(#d.lines, 3, id .. ": two paragraphs and the line between, no closing line")
        eq(d.lines[2], "", id .. ": air between them")
        assert(d.lines[1]:find(w[2], 1, true), d.lines[1])
        assert(not table.concat(d.lines, " "):find("%d"), id .. ": no numbers, those are on the Points heading")
        eq(d.buttons[1][1], w[3], id)
    end
    eq(GK.LetterContent({ id = 1, kind = "news", sample = true }).title, "Eyes on them", "a sample: the latest")
end)

test("the settings page and the help say the release, not how many changes there have been", function()
    local GK = boot({ me = ME })
    GK.Changed()
    GK.Changed()
    W.printed = {}
    SlashCmdList.GRUDGEKEEPER("help")
    assert((W.printed[1] or ""):find("v0.0.0-test commands", 1, true), tostring(W.printed[1]))
end)

-- ---------------------------------------------------------------------------
-- Sprees: kills worth points in a row (Core.lua, Kills.lua, Guild.lua)
-- ---------------------------------------------------------------------------
test("spree tiers: Bloodied 3, Merciless 5, Butcher 7, Reaper 10, Grudgebound 15 and every 5 after", function()
    local GK = boot()
    local want = { [3] = "Bloodied", [5] = "Merciless", [7] = "Butcher", [10] = "Reaper", [15] = "Grudgebound",
        [20] = "Grudgebound" }
    for n = 25, 100, 5 do want[n] = "Grudgebound" end
    for n = 0, 101 do eq(GK.SpreeTier(n), want[n], "milestone " .. n) end
    eq(select(2, GK.SpreeTier(10)), "reaper", "the key for the art file names")
    eq(GK.SPREE_TIERS[1].key, "bloodied")
    eq(GK.SPREE_TIERS[5].key, "grudgebound")
    eq(GK.SpreeTier(nil), nil)
end)

test("spree tier of a spree: the tier it is in now, nothing below 3", function()
    local GK = boot()
    eq(GK.SpreeTierOf(2), nil)
    eq(GK.SpreeTierOf(3), "Bloodied")
    eq(GK.SpreeTierOf(4), "Bloodied")
    eq(GK.SpreeTierOf(6), "Merciless")
    eq(GK.SpreeTierOf(9), "Butcher")
    eq(GK.SpreeTierOf(14), "Reaper")
    eq(GK.SpreeTierOf(16), "Grudgebound")
    eq(GK.SpreeTierOf(99), "Grudgebound")
    eq(select(2, GK.SpreeTierOf(6)), "merciless")
end)

--- Kills.lua with the guild's side stubbed, and what the addon fires collected in `heard`.
local function bootSpree()
    local GK, LIB = bootKills()
    local heard = {}
    for _, name in ipairs({ "GK_SPREE", "GK_SPREE_ENDED", "GK_TORMENTOR" }) do
        LIB.Listen(name, function(...) heard[#heard + 1] = { name, ... } end)
    end
    GK.sentSprees = {}
    function GK.SendKill(v, zone, points, avenged, times, spree) table.insert(GK.sentSprees, spree) end
    function GK.SendDeath() end
    function GK.AutoOrder() return nil end
    function GK.SlainLetter() end
    return GK, LIB, heard
end

--- A kill of ours on enemy number i: red (level 65 to our 60) by default, grey at level 20.
local function killOf(GK, i, level)
    GK.RecordKill({ key = "Foe" .. i .. "-Realm", guid = "Player-1-" .. i, c = "ROGUE", r = "Orc", l = level or 65,
        rf = "Orc", sx = 2 })
end

test("spree: +1 for a kill worth points; a grey kill adds to the streak and not the spree", function()
    local GK = bootSpree()
    eq(GK.char.spree, 0)
    killOf(GK, 1)
    killOf(GK, 2, 20)
    killOf(GK, 3)
    eq(GK.char.streak, 3, "the streak counts every kill")
    eq(GK.char.spree, 2, "the spree only the kills worth points")
end)

test("spree: a kill farmed today is worth nothing and doesn't count", function()
    local GK = bootSpree()
    for _ = 1, GK.REPEATS do GK.RecordKill({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65, rf = "Orc", sx = 2 }) end
    local before = GK.char.spree
    GK.RecordKill({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65, rf = "Orc", sx = 2 })
    eq(GK.char.spree, before, "the farmed kill")
    eq(GK.char.streak, GK.REPEATS + 1)
end)

test("spree: an assist never changes it", function()
    local GK = bootSpree()
    killOf(GK, 1)
    GK.RecordAssist({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65, with = "Kari" })
    eq(GK.char.spree, 1)
    eq(GK.char.assists, 1)
end)

test("spree: the kill sends the spree it made, and the next one counts on", function()
    local GK = bootSpree()
    killOf(GK, 1)
    killOf(GK, 2, 20)
    killOf(GK, 3)
    eq(GK.sentSprees[1], 1)
    eq(GK.sentSprees[2], 1, "a kill worth nothing sends the spree as it stands")
    eq(GK.sentSprees[3], 2)
end)

test("spree: a milestone of ours fires GK_SPREE once, at 3, 5, 7, 10, 15, then 20 and 25 as Grudgebound", function()
    local GK, _, heard = bootSpree()
    for i = 1, 25 do killOf(GK, i) end
    local got = {}
    for _, e in ipairs(heard) do
        eq(e[1], "GK_SPREE")
        eq(e[2], ME, "who")
        eq(e[5], true, "mine")
        got[#got + 1] = e[3] .. ":" .. e[4]
    end
    eq(table.concat(got, " "), "3:Bloodied 5:Merciless 7:Butcher 10:Reaper 15:Grudgebound 20:Grudgebound 25:Grudgebound")
end)

test("spree: a grey kill on a milestone number fires nothing", function()
    local GK, _, heard = bootSpree()
    killOf(GK, 1)
    killOf(GK, 2)
    killOf(GK, 3, 20)
    eq(#heard, 0)
    killOf(GK, 4)
    eq(heard[1][3], 3)
end)

test("spree: our death to an enemy ends it, and says what it was", function()
    local GK, _, heard = bootSpree()
    for i = 1, 4 do killOf(GK, i) end
    heard[1], heard[2] = nil, nil
    eq(#heard, 0)
    local had = GK.RecordDeath({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65 })
    eq(had, 4, "the spree it had, for the caller")
    eq(GK.char.spree, 0)
    eq(GK.char.streak, 0)
    eq(#heard, 1)
    eq(heard[1][1], "GK_SPREE_ENDED")
    eq(heard[1][2], ME)
    eq(heard[1][3], 4)
    eq(heard[1][4], GK.Show(GANK), "who ended it")
    eq(heard[1][5], true)
end)

test("spree: dying with less than 3 ends nothing to announce, but still resets it", function()
    local GK, _, heard = bootSpree()
    killOf(GK, 1)
    killOf(GK, 2)
    eq(GK.RecordDeath({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65 }), 2)
    eq(GK.char.spree, 0)
    eq(#heard, 0)
end)

test("tormentor: three of the guild dead, then our kill ends them and the count goes to 0", function()
    local GK, _, heard = bootSpree()
    local G = GK.Store()
    for _ = 1, 3 do GK.RecordDeath({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65 }) end
    eq(G.tormentors[GANK], 3)
    eq(#heard, 0)
    GK.RecordKill({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65, rf = "Orc", sx = 2 })
    eq(G.tormentors[GANK] or 0, 0)
    eq(#heard, 1)
    eq(heard[1][1], "GK_TORMENTOR")
    eq(heard[1][2], ME)
    eq(heard[1][3], GK.Show(GANK))
    eq(heard[1][4], 3)
    eq(heard[1][5], true)
end)

test("tormentor: fewer than 3 is no tormentor, and a kill still clears the count", function()
    local GK, _, heard = bootSpree()
    GK.RecordDeath({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65 })
    GK.RecordKill({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65, rf = "Orc", sx = 2 })
    eq(GK.Store().tormentors[GANK] or 0, 0)
    eq(#heard, 0)
end)

test("tormentor: a grey kill on one still ends them", function()
    local GK, _, heard = bootSpree()
    for _ = 1, 3 do GK.RecordDeath({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 65 }) end
    GK.RecordKill({ key = GANK, guid = FOE_GUID, c = "ROGUE", r = "Orc", l = 20, rf = "Orc", sx = 2 })
    eq(#heard, 1)
    eq(heard[1][4], 3)
end)

test("tormentor: kept per guild, at most 200, the smallest count dropped first", function()
    local GK = boot()
    for i = 1, 200 do
        GK.TormentorGrew("Foe" .. i .. "-Realm")
        GK.TormentorGrew("Foe" .. i .. "-Realm")
    end
    GK.TormentorGrew("Low-Realm")      -- 1: the smallest, but the table is full, so it is let in and one goes
    eq(count(GK.Store().tormentors), 200)
    GK.TormentorGrew("Next-Realm")
    eq(count(GK.Store().tormentors), 200)
    eq(GK.Store().tormentors["Low-Realm"], nil, "the smallest went")
    eq(GK.Store().tormentors["Next-Realm"], 1)
end)

test("K on the wire: field 13 is the spree after the kill, the fields before it are where they were", function()
    local GK = bootGuild()
    W.takeSent()
    GK.SendKill({ key = GANK, c = "ROGUE", r = "Orc", l = 65, rf = "Orc", sx = 2 }, "Hillsbrad", 4, nil, 7, 5)
    local text = W.takeSent()[1].text
    local f = {}
    for part in (text .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
    eq(f[1], "K")
    eq(f[10], "7", "times, where upstream reads it")
    eq(f[12], "2", "sex")
    eq(f[13], "5", "the spree")
    eq(#f, 13)
    assert(#text < 600)
end)

--- Guild.lua with the guild's messages, and what it fires collected in `heard`.
local function bootHeard()
    local GK = bootGuild()
    function GK.KeepLooks() end
    local heard = {}
    for _, name in ipairs({ "GK_SPREE", "GK_SPREE_ENDED", "GK_TORMENTOR" }) do
        W.LIB.Listen(name, function(...) heard[#heard + 1] = { name, ... } end)
    end
    local function K(sender, spree)
        GK.ReceiveForTest("Grudgekeeper", msg("K", 1, GANK, "ROGUE", "Orc", 60, "Hillsbrad", 2, "", 5, "Orc", 2, spree),
            "GUILD", sender)
    end
    local function D(sender, killer)
        GK.ReceiveForTest("Grudgekeeper", msg("D", 1, killer or GANK, "ROGUE", "Orc", 60, "Hillsbrad", 1, "Orc", 2),
            "GUILD", sender)
    end
    return GK, K, D, heard
end

test("a guildie's K with a spree at a tier fires GK_SPREE; between tiers, nothing", function()
    local _, K, _, heard = bootHeard()
    for _, n in ipairs({ 1, 2, 4, 6, 14 }) do K(EDVARD, n) end
    eq(#heard, 0)
    K(KARI, 3)
    eq(#heard, 1)
    eq(heard[1][1], "GK_SPREE")
    eq(heard[1][2], KARI)
    eq(heard[1][3], 3)
    eq(heard[1][4], "Bloodied")
    eq(heard[1][5], false, "not mine")
    K(KARI, 15)
    K(KARI, 20)
    K(KARI, 25)
    eq(heard[2][4], "Grudgebound")
    eq(heard[3][4], "Grudgebound")
    eq(heard[4][4], "Grudgebound")
    eq(#heard, 4)
end)

test("a guildie's milestone is told once: a kill worth nothing at 5 does not tell it again", function()
    local _, K, D, heard = bootHeard()
    K(KARI, 5)
    K(KARI, 5)
    K(KARI, 5)
    eq(#heard, 1)
    K(KARI, 7)
    eq(#heard, 2)
    D(KARI)
    K(KARI, 3)
    eq(#heard, 4, "the end (heard[3]) and then a new spree's first milestone")
    eq(heard[4][1], "GK_SPREE")
end)

test("a guildie's spree that started over on a D we missed tells its milestones again", function()
    local _, K, _, heard = bootHeard()
    K(KARI, 7)
    eq(#heard, 1)
    K(KARI, 3)
    eq(#heard, 2, "3 after 7 with no D: they died and we missed it")
    eq(heard[2][1], "GK_SPREE")
    eq(heard[2][3], 3)
end)

test("a K from an older version has no field 13 and fires nothing; a bad one reads as none", function()
    local GK, K, _, heard = bootHeard()
    GK.ReceiveForTest("Grudgekeeper", msg("K", 1, GANK, "ROGUE", "Orc", 60, "Hillsbrad", 2, "", 5, "Orc", 2), "GUILD", KARI)
    K(KARI, "")
    K(KARI, "three")
    K(KARI, 3.5)
    K(KARI, -3)
    eq(#heard, 0)
    eq(GK.Store().slain[GANK].by[KARI], 5, "the kill itself is still taken in")
end)

test("a guildie's D after a spree of 3 or more ends it, once", function()
    local _, K, D, heard = bootHeard()
    K(KARI, 6)
    eq(#heard, 0)
    D(KARI)
    eq(#heard, 1)
    eq(heard[1][1], "GK_SPREE_ENDED")
    eq(heard[1][2], KARI)
    eq(heard[1][3], 6)
    assert(heard[1][4], "who killed them")
    eq(heard[1][5], false)
    D(KARI)
    eq(#heard, 1, "no spree left to end")
end)

test("a guildie's D after a spree under 3, or one we never heard of, ends nothing", function()
    local _, K, D, heard = bootHeard()
    K(KARI, 2)
    D(KARI)
    D(EDVARD)
    eq(#heard, 0)
end)

test("a guildie's spree is kept per guildie, and the next K takes it on from where it was", function()
    local _, K, D, heard = bootHeard()
    K(KARI, 4)
    K(EDVARD, 8)
    D(EDVARD)
    eq(#heard, 1)
    eq(heard[1][2], EDVARD)
    K(KARI, 9)
    D(KARI)
    eq(heard[#heard][3], 9, "the last one heard")
end)

test("tormentor: three guildie deaths to one enemy, then a guildie's K on them ends it", function()
    local GK, K, D, heard = bootHeard()
    D(KARI)
    D(EDVARD)
    D(KARI)
    eq(GK.Store().tormentors[GANK], 3)
    eq(#heard, 0)
    K(EDVARD, 1)
    eq(GK.Store().tormentors[GANK] or 0, 0)
    eq(#heard, 1)
    eq(heard[1][1], "GK_TORMENTOR")
    eq(heard[1][2], EDVARD)
    eq(heard[1][3], GK.Show(GANK))
    eq(heard[1][4], 3)
    eq(heard[1][5], false)
end)

test("tormentor: our own death counts with the guild's, and a K from an older client still clears it", function()
    local GK, _, D, heard = bootHeard()
    D(KARI)
    D(EDVARD)
    GK.TormentorGrew(GANK)
    eq(GK.Store().tormentors[GANK], 3)
    GK.ReceiveForTest("Grudgekeeper", msg("K", 1, GANK, "ROGUE", "Orc", 60, "Hillsbrad", 2, "", 5, "Orc", 2), "GUILD", KARI)
    eq(#heard, 1)
    eq(heard[1][1], "GK_TORMENTOR")
end)

-- ---------------------------------------------------------------------------
-- Announcements (Announce.lua): a splash or a toast, held while the when-setting says no
-- ---------------------------------------------------------------------------
--- Announce.lua over frames that do nothing but remember: A.tex has every texture it was given (a seal and a
--- ribbon for each announcement, "nil" for no ribbon; not the glow), A.txt every line, A.played every sound.
local function bootAnnounce()
    local GK, LIB = boot({ me = ME })
    local A = { tex = {}, txt = {}, played = {}, frames = {}, combat = false, instance = false, lockdown = false }
    local object = {}
    object.__index = function(self, method)
        if method:find("^%l") then return nil end    -- a field of our own, never set: nil, as on a real frame
        -- where each frame was put and how big it is, for the placement and size tests
        if method == "ClearAllPoints" then return function(f) rawset(f, "pts", {}) end end
        if method == "SetPoint" then
            return function(f, ...)
                if not rawget(f, "pts") then rawset(f, "pts", {}) end
                table.insert(f.pts, { ... })
            end
        end
        if method == "SetSize" then return function(f, w, h) rawset(f, "size", { w, h }) end end
        if method == "SetScript" then return function(f, name, fn) rawset(f, name, fn) end end
        if method == "SetShown" then return function(f, on) rawset(f, "shown", on and true or false) end end
        -- the glow, flames, shine and sparks are set once, when the splash is built, and the shine's mask is
        -- the ribbon again: none of them is an announcement's own
        if method == "SetTexture" then
            return function(f, path)
                if rawget(f, "mask") then return end
                for _, built in ipairs({ "glow$", "flames$", "shine$", "spark$" }) do
                    if tostring(path):find(built) then return end
                end
                table.insert(A.tex, tostring(path))
            end
        end
        if method == "SetText" then return function(_, text) table.insert(A.txt, text) end end
        if method == "CreateMaskTexture" then return function() return setmetatable({ mask = true }, object) end end
        if method:find("^Create") then return function() return setmetatable({}, object) end end
        return function() end
    end
    _G.CreateFrame = function()
        local f = setmetatable({}, object)
        table.insert(A.frames, f)
        return f
    end
    _G.UIParent = setmetatable({}, object)
    _G.InCombatLockdown = function() return A.lockdown end
    _G.UnitAffectingCombat = function() return A.combat end
    _G.IsInInstance = function() return A.instance end
    _G.SOUNDKIT = { IG_PVP_UPDATE = 1, RAID_WARNING = 2, PVP_THROUGH_QUEUE = 3, HARDCORE_DUEL = 4,
        UI_PVP_HONOR_PRESTIGE_RANK_UP = 5, UI_RAID_BOSS_DEFEATED = 6, UI_GARRISON_TOAST_INVASION_ALERT = 7,
        RAID_WARNING_2 = 8, RAID_BOSS_EMOTE_WARNING = 9 }
    _G.PlaySound = function(id) table.insert(A.played, id) end
    -- a file is remembered by its name, voice_butcher for ...\\Media\\voice_butcher.mp3
    _G.PlaySoundFile = function(path) table.insert(A.played, path:match("([%w_]+)%.mp3$") or path) return true end
    LIB.fire("PLAYER_ENTERING_WORLD")
    assert(loadfile("Notice.lua"))("Grudgekeeper", GK)     -- the toasts ask it where the letter icon is
    assert(loadfile("Announce.lua"))("Grudgekeeper", GK)
    return GK, LIB, A
end
local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"

--- The nth announcement shown: its seal, its ribbon ("nil" for none) and its line.
local function shownAt(A, n) return A.tex[2 * n - 1], A.tex[2 * n], A.txt[n] end

test("announce when: always, noCombat, noCombatInInstance and noInstance", function()
    local GK = bootAnnounce()
    for _, c in ipairs({ true, false }) do
        for _, i in ipairs({ true, false }) do
            eq(GK.AnnounceAllowed("always", c, i), true)
            eq(GK.AnnounceAllowed("noCombat", c, i), not c)
            eq(GK.AnnounceAllowed("noCombatInInstance", c, i), not (c and i))
            eq(GK.AnnounceAllowed("noInstance", c, i), not i)
        end
    end
end)

test("announce: the settings start as asked", function()
    local GK = bootAnnounce()
    eq(GK.db.spreeMine, "splash")
    eq(GK.db.spreeGuild, "toast")
    eq(GK.db.spreeEnded, "toast")
    eq(GK.db.spreeTormentor, "toast")
    eq(GK.db.announceWhenMine, "always")
    eq(GK.db.announceWhenGuild, "noCombat")
    eq(next(GK.db.spreeSounds), nil)
end)

test("announce: a guildie's spree in a fight is held, and shown with the next one when it ends", function()
    local GK, LIB, A = bootAnnounce()
    A.combat = true
    LIB.Fire("GK_SPREE", KARI, 5, "Merciless", false, "merciless")
    LIB.Fire("GK_SPREE", EDVARD, 3, "Bloodied", false, "bloodied")
    eq(#A.txt, 0)
    eq(#A.played, 0, "no sound while it is held")
    A.combat = false
    LIB.fire("PLAYER_REGEN_ENABLED")
    eq(#A.txt, 2)
    eq(A.txt[1], "Kari: 5 kills in a row")
    eq(A.txt[2], "Edvard: 3 kills in a row")
    eq(A.played[1], "voice_merciless", "Merciless: the Grudgekeeper calls it")
    eq(A.played[2], "voice_bloodied")
    LIB.fire("PLAYER_REGEN_ENABLED")
    eq(#A.txt, 2, "nothing twice")
end)

test("announce: a held splash waits for the one before it, one after another", function()
    local GK, LIB, A = bootAnnounce()
    GK.db.spreeGuild = "splash"
    A.combat = true
    LIB.Fire("GK_SPREE", KARI, 5, "Merciless", false, "merciless")
    LIB.Fire("GK_SPREE", EDVARD, 7, "Butcher", false, "butcher")
    A.combat = false
    LIB.fire("PLAYER_REGEN_ENABLED")
    eq(#A.txt, 1)
    eq(A.txt[1], "Kari: 5 kills in a row")
    W.advance(3)
    eq(#A.txt, 1, "still the first one's time")
    W.advance(1)
    eq(#A.txt, 2)
    eq(A.txt[2], "Edvard: 7 kills in a row")
end)

test("announce: held ones are released when the area changes, if it allows them", function()
    local GK, LIB, A = bootAnnounce()
    GK.db.announceWhenGuild = "noInstance"
    A.instance = true
    LIB.fire("PLAYER_ENTERING_WORLD")
    LIB.Fire("GK_SPREE", KARI, 3, "Bloodied", false, "bloodied")
    eq(#A.txt, 0)
    LIB.fire("ZONE_CHANGED_NEW_AREA")
    eq(#A.txt, 0, "still inside")
    A.instance = false
    LIB.fire("ZONE_CHANGED_NEW_AREA")
    eq(#A.txt, 1)
end)

test("announce: your own spree comes in a fight with the setting at always, and the game's own combat state counts", function()
    local GK, LIB, A = bootAnnounce()
    A.lockdown = true
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher")
    eq(#A.txt, 1)
    GK.db.announceWhenMine = "noCombat"
    LIB.Fire("GK_SPREE", ME, 10, "Reaper", true, "reaper")
    eq(#A.txt, 1, "held in the lockdown")
    A.lockdown = false
    A.combat = true
    LIB.Fire("GK_SPREE", ME, 15, "Grudgebound", true, "grudgebound")
    eq(#A.txt, 1, "held in combat without the lockdown")
end)

test("announce: no more than 30 are held, the oldest goes", function()
    local GK, LIB, A = bootAnnounce()
    A.combat = true
    for i = 1, 31 do LIB.Fire("GK_SPREE", "P" .. i .. "-Realm", 3, "Bloodied", false, "bloodied") end
    A.combat = false
    LIB.fire("PLAYER_REGEN_ENABLED")
    eq(#A.txt, 30)
    eq(A.txt[1], "P2: 3 kills in a row")
    eq(A.txt[30], "P31: 3 kills in a row")
end)

test("announce: a kind set to off shows nothing at all, not even later", function()
    local GK, LIB, A = bootAnnounce()
    GK.db.spreeMine, GK.db.spreeGuild, GK.db.spreeEnded, GK.db.spreeTormentor = "off", "off", "off", "off"
    A.combat = true
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher")
    LIB.Fire("GK_SPREE", KARI, 7, "Butcher", false, "butcher")
    LIB.Fire("GK_SPREE_ENDED", KARI, 8, "Gankalot", false)
    LIB.Fire("GK_TORMENTOR", ME, "Gankalot", 6, true)
    A.combat = false
    LIB.fire("PLAYER_REGEN_ENABLED")
    eq(#A.txt, 0)
    eq(#A.tex, 0)
    eq(#A.played, 0)
end)

test("announce: the sound is the one picked, else the tier's own, and none when sounds are off", function()
    local GK, LIB, A = bootAnnounce()
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher") W.advance(4)
    eq(A.played[1], "voice_butcher", "Butcher's own: the Grudgekeeper's call")
    GK.db.spreeSounds.butcher = "kit:RAID_WARNING_2"
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher") W.advance(4)
    eq(A.played[2], 8, "the pick")
    GK.db.spreeSounds.butcher = "off"
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher") W.advance(4)
    eq(#A.played, 2, "None picked")
    GK.db.spreeSounds.butcher = nil
    LIB.Fire("GK_SPREE_ENDED", ME, 5, "Gankalot", true)
    LIB.Fire("GK_TORMENTOR", ME, "Gankalot", 4, true)
    eq(A.played[3], 6)
    eq(A.played[4], 7)
    GK.db.sound = false
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher") W.advance(4)
    LIB.Fire("GK_SPREE_ENDED", ME, 5, "Gankalot", true)
    eq(#A.played, 4, "Sounds off mutes them")
    eq(#A.txt, 7, "the announcement still comes")
end)

test("announce: the art of a tier, of a spree ended and of a tormentor", function()
    local GK, LIB, A = bootAnnounce()
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher")
    local seal, ribbon = shownAt(A, 1)
    eq(seal, MEDIA .. "spree_butcher")
    eq(ribbon, MEDIA .. "spree_butcher_name")
    LIB.Fire("GK_SPREE", KARI, 20, "Grudgebound", false, "grudgebound")
    seal, ribbon = shownAt(A, 2)
    eq(seal, MEDIA .. "spree_grudgebound", "Grudgebound again at 20")
    eq(ribbon, MEDIA .. "spree_grudgebound_name")
    LIB.Fire("GK_SPREE_ENDED", ME, 12, "Gankalot", true)
    seal, ribbon = shownAt(A, 3)
    eq(seal, MEDIA .. "seal_broken")
    eq(ribbon, "nil", "no ribbon")
    LIB.Fire("GK_TORMENTOR", KARI, "Gankalot", 6, false)
    seal, ribbon = shownAt(A, 4)
    eq(seal, MEDIA .. "seal_black")
    eq(ribbon, "nil", "no ribbon")
end)

test("announce: the lines", function()
    local GK, LIB, A = bootAnnounce()
    LIB.Fire("GK_SPREE", ME, 7, "Butcher", true, "butcher") W.advance(4)
    LIB.Fire("GK_SPREE", KARI, 7, "Butcher", false, "butcher")
    LIB.Fire("GK_SPREE", ME, 25, "Grudgebound", true, "grudgebound") W.advance(4)
    LIB.Fire("GK_SPREE_ENDED", ME, 12, "Gankalot", true)
    LIB.Fire("GK_SPREE_ENDED", KARI, 12, "Gankalot", false)
    LIB.Fire("GK_TORMENTOR", ME, "Gankalot", 6, true)
    LIB.Fire("GK_TORMENTOR", KARI, "Gankalot", 6, false)
    local want = { "7 kills in a row", "Kari: 7 kills in a row", "25 kills in a row",
        "Your 12-kill spree ended (Gankalot)", "Kari's 12-kill spree ended (Gankalot)",
        "You put an end to Gankalot, who had killed 6 of us", "Kari put an end to Gankalot, who had killed 6 of us" }
    for i, line in ipairs(want) do eq(A.txt[i], line, "line " .. i) end
    eq(#A.txt, #want)
    local seal3 = shownAt(A, 3)
    eq(seal3, MEDIA .. "spree_grudgebound")
end)

test("announce: toasts stack up to four, and /grudge spree shows a sample of both", function()
    local GK, LIB, A = bootAnnounce()
    for i = 1, 6 do LIB.Fire("GK_SPREE", KARI, 3, "Bloodied", false, "bloodied") end
    eq(#A.txt, 6)
    GK.AnnounceSample()
    eq(#A.txt, 8)
    eq(A.txt[7], "7 kills in a row")
    local seal7 = shownAt(A, 7)
    eq(seal7, MEDIA .. "spree_butcher")
    eq(A.txt[8], "Glue Enjoyer: 7 kills in a row")
    A.combat = true
    local before = #A.played
    GK.AnnounceSample()
    eq(#A.txt, 10, "the sample ignores the when-rules")
    eq(#A.played, before + 1, "one sound for the pair")
end)

test("a pick of a sound taken off the list goes back to the default, everywhere it was picked", function()
    local GK = boot({ me = ME })
    GK.db.nearSound, GK.db.spreeSounds = "kit:HARDCORE_DUEL", { butcher = "kit:HARDCORE_DUEL", reaper = "kit:RAID_WARNING" }
    GK.ForgetGoneSounds(GK.db)
    eq(GK.db.nearSound, "kit:PVP_THROUGH_QUEUE")
    eq(GK.db.spreeSounds.butcher, nil, "the tier's default plays again")
    eq(GK.db.spreeSounds.reaper, "kit:RAID_WARNING", "a pick still on the list stays")
end)

test("announce: a burning splash and a cold one both play through to the end", function()
    local GK, LIB, A = bootAnnounce()
    GK.db.spreeMine, GK.db.spreeEnded = "splash", "splash"
    LIB.Fire("GK_SPREE", ME, 15, "Grudgebound", true, "grudgebound")
    local splash = A.frames[1]
    for _ = 1, 200 do splash.OnUpdate(splash, 1 / 60) end
    eq(splash.flames.shown, true, "a spree burns")
    eq(splash.embers[22].shown, true, "Grudgebound has every ember")
    GK.db.announceWhenMine = "always"
    _G.GetTime = function() return 1e6 end
    LIB.Fire("GK_SPREE_ENDED", ME, 15, "Gankalot", true)
    for _ = 1, 200 do splash.OnUpdate(splash, 1 / 60) end
    eq(splash.flames.shown, false, "an ended spree doesn't burn")
    eq(splash.embers[1].shown, false)
end)

test("announce: a new splash waits for the one on screen, even when nothing is queued", function()
    local GK, LIB, A = bootAnnounce()
    GK.db.spreeGuild = "splash"
    LIB.Fire("GK_SPREE", KARI, 5, "Merciless", false, "merciless")
    eq(#A.txt, 1)
    W.advance(1)
    LIB.Fire("GK_SPREE", EDVARD, 7, "Butcher", false, "butcher")
    eq(#A.txt, 1, "the first is still showing")
    W.advance(2)
    eq(#A.txt, 1, "3 s in: not yet")
    W.advance(1)
    eq(#A.txt, 2, "after the first one's time")
    eq(A.txt[2], "Edvard: 7 kills in a row")
end)

test("announce: a toast does not wait for a splash that is waiting", function()
    local GK, LIB, A = bootAnnounce()
    GK.db.spreeGuild = "splash"
    LIB.Fire("GK_SPREE", KARI, 5, "Merciless", false, "merciless")
    LIB.Fire("GK_SPREE", EDVARD, 7, "Butcher", false, "butcher")      -- waits
    LIB.Fire("GK_SPREE_ENDED", KARI, 8, "Gankalot", false) -- a toast: at once
    eq(#A.txt, 2)
    eq(A.txt[2], "Kari's 8-kill spree ended (Gankalot)")
    W.advance(4)
    eq(#A.txt, 3)
    eq(A.txt[3], "Edvard: 7 kills in a row", "the splash in its own turn")
end)

test("announce: a toast before the letter icon exists sits where the icon would be", function()
    local GK, LIB, A = bootAnnounce()
    LIB.Fire("GK_SPREE", KARI, 3, "Bloodied", false, "bloodied")
    local toast = A.frames[1]
    local p = toast.pts[1]
    eq(p[1], "TOPRIGHT")
    eq(p[2], UIParent)
    eq(p[3], "TOPRIGHT")
    eq(p[4], -300, "the default place of the icon, its right edge")
    eq(p[5], -250 - 46 - 26, "under it")
end)

test("announce: a toast before the letter icon exists follows the place that was saved", function()
    local GK, LIB, A = bootAnnounce()
    GK.db.notice = { point = "CENTER", relPoint = "BOTTOMLEFT", x = 100, y = 200 }
    LIB.Fire("GK_SPREE", KARI, 3, "Bloodied", false, "bloodied")
    local p = A.frames[1].pts[1]
    eq(p[3], "BOTTOMLEFT")
    eq(p[4], 100 + 23, "the icon's right edge: half its width from its centre")
    eq(p[5], 200 - 23 - 26)
end)

test("announce: a toast's seal is 64 by 64 and its ribbon 256 by 64", function()
    local GK, LIB, A = bootAnnounce()
    LIB.Fire("GK_SPREE", KARI, 3, "Bloodied", false, "bloodied")
    local toast = A.frames[1]
    eq(toast.seal.size[1], 64)
    eq(toast.seal.size[2], 64)
    eq(toast.ribbon.size[1], 256)
    eq(toast.ribbon.size[2], 64)
end)

test("announce: a name the game hides is a question mark in every line", function()
    local GK, LIB, A = bootAnnounce()
    GK.Secret = function(v) return v == "Hidden" end
    LIB.Fire("GK_SPREE_ENDED", ME, 5, "Hidden", true)
    LIB.Fire("GK_SPREE_ENDED", KARI, 5, "Hidden", false)
    LIB.Fire("GK_TORMENTOR", ME, "Hidden", 4, true)
    eq(A.txt[1], "Your 5-kill spree ended (?)")
    eq(A.txt[2], "Kari's 5-kill spree ended (?)")
    assert(not A.txt[2]:find("Hidden"), A.txt[2])
    eq(A.txt[3], "You put an end to ?, who had killed 4 of us")
end)

-- ---------------------------------------------------------------------------
-- The settings page (Options.lua): the kill spree rows write the right setting
-- ---------------------------------------------------------------------------
--- Options.lua built over recording frames: O.menus[key] is the dropdown for that setting (its menu entries once
--- opened), O.sounds[key] the sound row for that sound key. Every other widget does nothing.
local function bootOptions()
    local GK = bootAnnounce()
    GK.addonVersion = "test"
    local O = { menus = {}, sounds = {}, texts = {} }
    local object = {}
    object.__index = function(self, method)
        if method == "SetScript" then return function(_, name, fn) rawset(self, "on" .. name, fn) end end
        if method == "SetupMenu" then return function(dd, fn) rawset(dd, "menu", fn) end end
        if method == "SetText" then return function(_, text) table.insert(O.texts, text) end end
        if method:find("^Create") then return function() return setmetatable({}, object) end end
        return function() end
    end
    _G.CreateFrame = function(kind, _, parent)
        local frame = setmetatable({}, object)
        if kind == "DropdownButton" then table.insert(O.menus, { dd = frame, row = parent }) end
        return frame
    end
    GK.SoundRow = function(_, _, get, set, text)
        local row = { get = get, set = set, text = text }
        table.insert(O.sounds, row)
        return row
    end
    assert(loadfile("Options.lua"))("Grudgekeeper", GK)
    local panel
    local create = _G.CreateFrame
    _G.CreateFrame = function(kind, ...) local f = create(kind, ...) panel = panel or f return f end
    GK.RegisterOptions()
    _G.CreateFrame = create
    panel.onOnShow()
    return GK, O
end

--- The entries of the dropdown for a setting: { { text, selected(), pick() }, ... }.
local function menuOf(O, key)
    for _, m in ipairs(O.menus) do
        if rawget(m.row, "key") == key then
            local entries, root = {}, {}
            function root.CreateRadio(_, text, selected, pick) table.insert(entries, { text, selected, pick }) end
            m.dd.menu(m.dd, root)
            return entries
        end
    end
    error("no dropdown for " .. key)
end

test("settings page: the kill sprees heading and its note", function()
    local _, O = bootOptions()
    local heading, note
    for _, t in ipairs(O.texts) do
        if t == "Kill sprees" then heading = true end
        if t:find("^A splash in the middle of the screen") then note = t end
    end
    assert(heading, "no Kill sprees heading")
    eq(note, "A splash in the middle of the screen, or a small toast by the letter icon. /grudge spree shows both.")
end)

test("settings page: each kind row writes off, toast or splash", function()
    local GK, O = bootOptions()
    for _, key in ipairs({ "spreeMine", "spreeGuild", "spreeEnded", "spreeTormentor" }) do
        local entries = menuOf(O, key)
        eq(#entries, 3)
        eq(entries[1][1], "Off")
        for i, want in ipairs({ "off", "toast", "splash" }) do
            entries[i][3]()
            eq(GK.db[key], want, key)
            eq(menuOf(O, key)[i][2](), true, key .. " selected")
        end
    end
end)

test("settings page: each when row writes its four choices", function()
    local GK, O = bootOptions()
    for _, key in ipairs({ "announceWhenMine", "announceWhenGuild" }) do
        local entries = menuOf(O, key)
        eq(#entries, 4)
        eq(entries[3][1], "Not in combat in a dungeon or raid")
        for i, want in ipairs({ "always", "noCombat", "noCombatInInstance", "noInstance" }) do
            entries[i][3]()
            eq(GK.db[key], want, key)
        end
    end
end)

test("settings page: a sound row for each tier, the end and the tormentor", function()
    local GK, O = bootOptions()
    local want = { "bloodied", "merciless", "butcher", "reaper", "grudgebound", "ended", "tormentor" }
    local names = { "Bloodied", "Merciless", "Butcher", "Reaper", "Grudgebound", "Spree ended", "Tormentor" }
    local sounds = {}                     -- the target-near row is the page's first, and is not one of these
    for _, row in ipairs(O.sounds) do if row.text then table.insert(sounds, row) end end
    eq(#sounds, #want)
    for i, key in ipairs(want) do
        local row = sounds[i]
        eq(row.text, names[i])
        eq(row.get(), GK.SPREE_DEFAULT_SOUNDS[key], key .. " shows the default")
        row.set("kit:TEST")
        eq(GK.db.spreeSounds[key], "kit:TEST", key)
        eq(row.get(), "kit:TEST")
    end
end)

say(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
