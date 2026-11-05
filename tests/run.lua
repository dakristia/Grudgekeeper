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

test("500 people and 300 nice names", function()
    local GK = boot()
    for i = 1, 520 do W.receive(GK, KARI, msg("N", 1, "Player" .. i .. "-Realm", 1, B + i, "", "", "", "", "", "x")) end
    eq(count(GK.Store().people), 500)
    for i = 1, 320 do W.receive(GK, KARI, msg("M", 1, "Name" .. i .. "-Realm", B + i)) end
    eq(count(GK.Store().names), 300)
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
    eq(watch[1].ts, B + 12, "Edvard's later kudos note isn't the Watch list's news")
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
-- Nice names
-- ---------------------------------------------------------------------------
test("nice names: add, vote, and remove only my own", function()
    local GK = boot()
    eq(GK.AddNiceName(NICE, { c = "PRIEST", r = "Human", l = 40 }), true)
    eq(select(1, GK.AddNiceName(NICE)), nil, "already there")
    W.receive(GK, KARI, msg("M", 1, "Bob Bobson-Realm", B + 5, "", "MAGE", "Gnome", "Gnome", 3, 20))
    local names = GK.NiceNames()
    eq(#names, 2)
    local bob
    for _, n in ipairs(names) do if n.key == "Bob Bobson-Realm" then bob = n end end
    eq(bob.by, KARI)
    eq(bob.mine, false)
    -- not other people's
    eq(GK.RemoveNiceName("Bob Bobson-Realm"), false)
    W.receive(GK, EDVARD, msg("M", 1, "Bob Bobson-Realm", B + 99, 1))
    eq(#GK.NiceNames(), 2, "Edvard can't remove Kari's name")
    W.receive(GK, EDVARD, msg("M", 1, "Bob Bobson-Realm", B + 98, "", "MAGE"))
    eq(GK.Store().names["Bob Bobson-Realm"].by, KARI, "nor take it over")
    -- votes: not on mine, on Kari's
    eq(GK.VoteName(NICE, 1), false)
    eq(GK.VoteName("Bob Bobson-Realm", 1), true)
    W.receive(GK, EDVARD, msg("G", 1, "Bob Bobson-Realm", 1, B + 7))
    W.receive(GK, KARI, msg("G", 1, "Bob Bobson-Realm", 1, B + 7))
    eq(GK.NameScore("Bob Bobson-Realm"), 2, "Kari can't vote on her own name")
    eq(GK.VoteName("Bob Bobson-Realm", 0), true)
    eq(GK.NameScore("Bob Bobson-Realm"), 1)
    -- remove mine
    eq(GK.RemoveNiceName(NICE), true)
    eq(#GK.NiceNames(), 1)
    eq(GK.RemoveNiceName(NICE), false)
    -- Kari removes hers
    W.receive(GK, KARI, msg("M", 1, "Bob Bobson-Realm", B + 500, 1))
    eq(#GK.NiceNames(), 0)
    -- and a removed name can be added again, by anyone
    eq(GK.AddNiceName("Bob Bobson-Realm"), true)
    eq(GK.Store().names["Bob Bobson-Realm"].by, ME)
end)

test("a vote on a name we don't have is dropped", function()
    local GK = boot()
    W.receive(GK, KARI, msg("G", 1, "Nobody-Realm", 1, B))
    eq(count(GK.Store().nameVotes), 0)
end)

test("hiding a name: refused for a non-officer, accepted from an officer", function()
    local GK, LIB = boot()
    W.receive(GK, KARI, msg("M", 1, NICE, B + 1))
    -- I am rank 5 and no flags are known: I can't hide
    eq(GK.IsOfficer(ME), false)
    eq(GK.HideName(NICE, true), false)
    eq(#GK.NiceNames(), 1)
    -- Edvard is no officer either
    LIB.roster[EDVARD] = { rankIndex = 4 }
    W.receive(GK, EDVARD, msg("H", 1, NICE, 1, B + 5))
    eq(#GK.NiceNames(), 1)
    -- the guild master is
    LIB.roster["Master-Realm"] = { rankIndex = 0 }
    W.receive(GK, "Master-Realm", msg("H", 1, NICE, 1, B + 6))
    eq(#GK.NiceNames(), 0, "hidden")
    local all = GK.NiceNames(true)
    eq(#all, 1)
    eq(all[1].hidden, true)
    -- a sender that isn't on the roster at all is not an officer
    W.receive(GK, "Stranger-Realm", msg("H", 1, NICE, 0, B + 9))
    eq(#GK.NiceNames(), 0)
    -- shown again
    W.receive(GK, "Master-Realm", msg("H", 1, NICE, 0, B + 10))
    eq(#GK.NiceNames(), 1)
    eq(GK.NiceNames()[1].hidden, false)
end)

test("officer by rank flag 3, when the client has the call", function()
    local GK, LIB = boot()
    LIB.roster["Lieutenant-Realm"] = { rankIndex = 2 }
    LIB.roster["Raider-Realm"] = { rankIndex = 3 }
    W.rankFlags = { [3] = { true, true, true }, [4] = { true, true, false } }
    eq(GK.IsOfficer("Lieutenant-Realm"), true)
    eq(GK.IsOfficer("Raider-Realm"), false)
    eq(GK.IsOfficer("Stranger-Realm"), false)
    -- a call that raises is not an officer
    C_GuildInfo.GuildControlGetRankFlags = function() error("restricted") end
    eq(GK.IsOfficer("Lieutenant-Realm"), false)
    C_GuildInfo = nil
    eq(GK.IsOfficer("Lieutenant-Realm"), false, "no call: the guild master only")
    LIB.roster[ME] = { rankIndex = 0 }
    eq(GK.IsOfficer(ME), true)
end)

test("an officer hides my name and a hide may come before the name does", function()
    local GK, LIB = boot()
    LIB.roster[ME] = { rankIndex = 0 }
    eq(GK.AddNiceName(NICE), true)
    eq(GK.HideName(NICE, true), true)
    eq(#GK.NiceNames(), 0)
    eq(GK.HideName(NICE, false), true)
    eq(#GK.NiceNames(), 1)
    eq(GK.HideName("Unknown-Realm", true), false, "no such name")
    -- a hide arrives first
    LIB.roster["Master-Realm"] = { rankIndex = 0 }
    W.receive(GK, "Master-Realm", msg("H", 1, "Late-Realm", 1, B + 4))
    eq(#GK.NiceNames(true), 1, "the bare record isn't a name")
    W.receive(GK, KARI, msg("M", 1, "Late-Realm", B + 8))
    eq(#GK.NiceNames(), 1, "the name is there, hidden")
    eq(#GK.NiceNames(true), 2)
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

test("live changes go out at once, and tell the windows", function()
    local GK = boot()
    local before = W.changes
    local n = GK.AddNote(GANK, "took my gold", "Scammer", "watch", { c = "ROGUE", l = 60 })
    local sent = W.takeSent()
    eq(#sent, 2)
    eq(sent[1].text, msg("N", 1, GANK, n.id, B, "", "Scammer", "ROGUE", "", 60, "took my gold"))
    eq(sent[2].text, msg("L", 1, GANK, "watch", B, "", "ROGUE", "", 60))
    assert(W.changes > before, "Changed was called")
    GK.DeleteNote(GANK, n.id)
    eq(W.takeSent()[1].text, msg("N", 1, GANK, n.id, B + 1, 1, "", "ROGUE", "", 60, ""))
    GK.SetMark(GANK, nil)
    eq(W.takeSent()[1].text, msg("L", 1, GANK, "", B + 1, 1, "ROGUE", "", 60))
end)

test("a Q is answered with my own records only, after 2 to 6 seconds, once per 30 seconds", function()
    local GK = boot()
    W.advance(11)
    W.takeSent()
    GK.AddNote(GANK, "mine", "Toxic", "watch")
    GK.AddNiceName(NICE)
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "", "", "", "Kari's note"))
    W.receive(GK, KARI, msg("L", 1, GANK, "watch", B))
    W.receive(GK, KARI, msg("M", 1, "Hers-Realm", B))
    W.receive(GK, EDVARD, msg("G", 1, NICE, 1, B))
    eq(GK.VoteNote(GANK, KARI, 1, 1), true)
    eq(GK.VoteName("Hers-Realm", 1), true)
    W.takeSent()
    W.receive(GK, KARI, "Q;1")
    W.advance(1.5)
    eq(#W.sent, 0, "not before 2 seconds")
    W.advance(10)
    local sent = W.takeSent()
    -- N, L, M, V, G(vote on Hers), and not Kari's N, L, M or Edvard's G
    eq(#sent, 5)
    local kinds = {}
    for _, m in ipairs(sent) do
        kinds[#kinds + 1] = m.text:sub(1, 1)
        assert(not m.text:find("Kari's note", 1, true), "never someone else's record")
        assert(not m.text:find("Hers-Realm;" .. B, 1, true) or m.text:sub(1, 1) ~= "M", "never her name")
    end
    eq(table.concat(kinds), "MNLVG", "players before the votes on them")
    W.receive(GK, EDVARD, "Q;1")
    W.advance(10)
    eq(#W.sent, 0, "asked again within 30 seconds: no second answer")
    W.advance(30)
    W.receive(GK, EDVARD, "Q;1")
    W.advance(10)
    eq(#W.sent, 5, "and again after")
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
    local GK, LIB = boot()
    LIB.roster[ME] = { rankIndex = 0 }
    local sent = {}
    local function flush() for _, m in ipairs(W.takeSent()) do sent[#sent + 1] = m.text end end
    local n1 = GK.AddNote(GANK, "took my gold", "Scammer", "watch", { c = "ROGUE", r = "Orc", l = 60 })
    local n2 = GK.AddNote(NICE, "great healer", "Great healer", "kudos")
    local n3 = GK.AddNote("Old Foe-Realm", "gone again")
    GK.DeleteNote("Old Foe-Realm", n3.id)
    GK.SetMark(NICE, nil)
    GK.AddNiceName("Funny Name-Realm", { c = "MAGE", r = "Gnome", rf = "Gnome", sx = 3, l = 33 })
    GK.AddNiceName("Gone Name-Realm")
    GK.RemoveNiceName("Gone Name-Realm")
    GK.HideName("Funny Name-Realm", true)
    GK.HideName("Funny Name-Realm", false)
    GK.HideName("Funny Name-Realm", true)
    flush()
    -- votes need someone else's note and name; give both clients Kari's
    local kariNote = msg("N", 1, GANK, 5, B, "", "", "", "", "", "Kari's note")
    local kariName = msg("M", 1, "Kari Name-Realm", B)
    W.receive(GK, KARI, kariNote)
    W.receive(GK, KARI, kariName)
    GK.VoteNote(GANK, KARI, 5, 1)
    GK.VoteNote(GANK, KARI, 5, -1)
    GK.VoteName("Kari Name-Realm", 1)
    GK.VoteName("Kari Name-Realm", 0)
    flush()
    sent[#sent + 1] = GK.NotesEncode.Q()
    local want = {}
    for _, key in ipairs({ GANK, NICE, "Old Foe-Realm" }) do
        want[key] = { notes = GK.NotesOf(key), mark = GK.MyMark(key) }
    end
    local names = GK.NiceNames(true)

    -- the other client, which hears them all from me
    local GK2, LIB2 = boot({ me = "Other-Realm" })
    LIB2.roster[ME] = { rankIndex = 0 }
    W.receive(GK2, KARI, kariNote)
    W.receive(GK2, KARI, kariName)
    local kinds = {}
    for _, text in ipairs(sent) do
        kinds[text:sub(1, 1)] = true
        W.receive(GK2, ME, text)
    end
    for _, k in ipairs({ "N", "L", "V", "M", "G", "H", "Q" }) do assert(kinds[k], "a " .. k .. " was sent") end
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
    eq(GK2.NameScore("Kari Name-Realm"), 0, "the vote taken back")
    local got = GK2.NiceNames(true)
    eq(#got, #names)
    local fun = GK2.Store().names["Funny Name-Realm"]
    eq(fun.by, ME)
    eq(fun.c, "MAGE")
    eq(fun.r, "Gnome")
    eq(fun.rf, "Gnome")
    eq(fun.sx, 3)
    eq(fun.l, 33)
    eq(fun.hidden.on, true, "hidden, shown again, hidden")
    eq(GK2.Store().names["Gone Name-Realm"].del, true)
end)

test("the encoders clean what they are given", function()
    local GK = boot()
    local text = GK.NotesEncode.N(GANK, 3, { ts = B, text = "a;b|c", tag = "x;y" }, { c = "MAGE", r = "Orc", l = 5 })
    eq(text, msg("N", 1, GANK, 3, B, "", "x,y", "MAGE", "Orc", 5, "a,b/c"))
    eq(GK.NotesEncode.H(GANK, true, B), msg("H", 1, GANK, 1, B))
    eq(GK.NotesEncode.H(GANK, false, B), msg("H", 1, GANK, 0, B))
end)

-- ---------------------------------------------------------------------------
-- The import from Guild Grudge
-- ---------------------------------------------------------------------------
-- The shape of GuildGrudgeDB as GuildGrudge/Core.lua keeps it (see its "Data model" comment): entries by
-- lowercase key, notes with string ids and per-voter votes, and the nice names list. Names are
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

test("import: notes, tags, lists, names and votes land under their authors", function()
    local GK = boot({ me = IME, guildGrudge = sampleDB() })
    local counts = GK.ImportGuildGrudge()
    eq(counts.notes, 3)
    eq(counts.marks, 2)
    eq(counts.names, 2)
    eq(counts.votes, 5, "three on notes and two on names, less the removed one and my vote on my own name")
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
    -- names
    local names = GK.NiceNames()
    eq(#names, 2)
    local funny = GK.Store().names["Funny Name-Realm"]
    eq(funny.by, IME)
    eq(funny.l, 20)
    eq(GK.NameScore("Funny Name-Realm"), 1, "Kari's vote; mine on my own name was never one")
    eq(GK.NameScore("Third Silly-Realm"), 1)
    eq(GK.Store().names["Old Name-Realm"], nil, "removed names stay removed")
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
    assert(all:find("M;1;Funny Name-Realm", 1, true), "my name is")
    assert(not all:find("Third Silly", 1, true) or all:find("G;1;Third Silly-Realm;1;", 1, true), "only my vote on it")
    assert(not all:find("M;1;Third Silly", 1, true), "not her name")
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
    eq(forced.names, 0)
    eq(#GK.NotesOf("Ganker Forever-Realm"), 2)
    eq(GK.NameScore("Funny Name-Realm"), 1)
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

say(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
