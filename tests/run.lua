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
    return GK
end

test("letter content: a kill letter is a note with its closing line after a blank line", function()
    local GK = bootSheets({ me = ME })
    local L = { id = 2, kind = "kill", n = GANK, c = "ROGUE", r = "Orc", l = 35, p = 2, z = "Hillsbrad",
        rank = 4, of = 12, total = 31, sample = true }
    local d = GK.LetterContent(L)
    eq(d.note, true)
    eq(d.title, "Blood drawn")
    eq(d.seal, "seal_red")
    eq(d.blood, false)
    eq(d.key, GANK)
    eq(d.c, "ROGUE")
    eq(d.sample, true)
    eq(#d.buttons, 1)
    eq(d.buttons[1][1], "Leaderboard")
    eq(table.concat(d.lines, "\n"), "You killed Gank Master, a level 35 Orc in Hillsbrad.\n"
        .. "Worth 2 points.\nThat puts you at 31 points - #4 of 12 in the guild.\n\nKeep them coming.")
end)

test("letter content: a long note leaves the closing line out", function()
    local GK = bootSheets({ me = ME })
    local L = { id = 1, kind = "kill", n = GANK, p = 2, revenge = 2, avenged = KARI, streak = 5, of = 3, rank = 1,
        total = 40 }
    local d = GK.LetterContent(L)
    eq(#d.lines, 6)
    eq(d.lines[#d.lines], "That puts you at 40 points - #1 of 3 in the guild.")
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

test("letter content: an order is a scroll with a name, a foot and Take the order", function()
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
    eq(#d.buttons, 1)
    eq(d.buttons[1][1], "Hitlist")
    local done = GK.LetterContent({ id = 2, kind = "complete", n = GANK, by = KARI, doneBy = ME, z = "Hillsbrad" })
    eq(done.title, "ORDER COMPLETE")
    eq(done.name, "Gank Master is dead")
    eq(done.stamp, "stamp_fulfilled")
    eq(done.seal, "seal_broken")
    eq(done.lines[1], "You collected the bounty in Hillsbrad.")
    eq(done.buttons[1][1], "Tell the guild")
    eq(done.buttons[2][1], "Hitlist")
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
-- The Classic look, built against stand-in frames (tests/frames_mock.lua): the frames are built, filled
-- from the same data the ledger uses, and clicked. What they look like is for the game to say.
-- ---------------------------------------------------------------------------
local F = require("frames_mock")

local CARD = { title = "WANTED", name = "Gank Master", info = "Level 60 Orc", c = "MAGE", lines = { "Bounty 5g." },
    big = "5g", caption = "bounty", buttons = { { "Take the order", function() end } } }

local function bootClassic(look)
    local GK = bootSheets({ me = ME })
    F.install()
    GK.db.look = look
    for _, file in ipairs({ "Window.lua", "Profile.lua", "Notice.lua", "Inspect.lua", "Options.lua",
            "Classic/Classic.lua", "Classic/Cards.lua", "Classic/Window.lua", "Classic/Letters.lua",
            "Classic/Notice.lua", "Classic/Sheets.lua" }) do
        assert(loadfile(W.dir .. file))("Grudgekeeper", GK)
    end
    GK.called = {}
    for _, name in ipairs({ "OpenWindow", "ToggleWindow", "ShowPoster", "ShowRecord", "ShowCard", "OpenLetters",
            "ShowLetter", "CloseLetters", "NoticeUpdate", "PlaceNotice", "Warn", "OpenPost", "OpenNoteSheet" }) do
        GK[name] = function(...) GK.called[#GK.called + 1] = name end   -- the ledger's, stood in for
    end
    GK.built, GK.filled = 0, 0
    GK.BuildCardPage = function() GK.built = GK.built + 1 end     -- the ledger's page for the Inspect tab
    GK.FillCardPage = function() GK.filled = GK.filled + 1 end
    GK.PosterCard = function() return CARD end
    GK.RecordCard = function() return CARD end
    GK.Sound = function() end
    local sorted = 0
    GK.LedgerPages = {}
    for i = 1, 6 do
        local page = { name = "Page" .. i, sortable = i == 1, side = i > 4 and "right" or nil }
        page.items = function()
            local items = { { header = true, name = "Group" } }
            for n = 1, 3 do
                items[#items + 1] = { key = "k" .. n, name = (n == 2 and "Beta" or "Alpha") .. n, sub = "sub" .. n,
                    face = { c = "MAGE" }, right = "5g", ts = n, select = { kind = "card", make = function() return CARD end } }
            end
            return items, "Nothing here."
        end
        if i == 2 then
            page.links = function()
                return { { text = "This week", on = true, click = function() end },
                         { text = "All time", on = false, click = function() sorted = sorted + 1 end } }
            end
        end
        GK.LedgerPages[i] = page
    end
    GK.Classic.Apply()
    return GK
end

local function visible(name) return _G[name] and _G[name].shown end

test("classic: every wrapped function calls the ledger's own while the look is the ledger", function()
    local GK = bootClassic("ledger")
    GK.OpenWindow(1)
    GK.ShowCard(function() return CARD end)
    GK.OpenPost({ key = GANK })
    GK.NoticeUpdate(false)
    eq(#GK.called, 4)
    eq(GK.called[1], "OpenWindow")
    eq(visible("GrudgekeeperClassicWindow"), nil)
    eq(visible("GrudgekeeperClassicCard"), nil)
    eq(GK.IsClassic(), false)
end)

test("classic: the window lists the rows, headers included, and shows the chosen row's card", function()
    local GK = bootClassic("classic")
    GK.OpenWindow(1)
    local win = _G.GrudgekeeperClassicWindow
    eq(win.shown, true)
    eq(#win.box.provided, 4)
    eq(win.box.rows[1].name.text, "Group")
    eq(win.box.rows[2].name.text, "Alpha1")
    eq(win.box.rows[2].sub.text, "sub1")
    eq(win.box.rows[2].right.text, "5g")
    eq(win.detail.view.title.text, "WANTED")
    eq(win.detail.view.name.text, "Gank Master")
    eq(win.detail.view.buttons[1].text, "Take the order")
    eq(win.sort.shown, true)
    eq(win.mine.shown, true)
    eq(win.numTabs, 6)
    eq(win.selectedTab, 1)
    eq(#GK.called, 0)
end)

test("classic: the search box filters by name and sub, and a click on a row chooses it", function()
    local GK = bootClassic("classic")
    GK.OpenWindow(1)
    local win = _G.GrudgekeeperClassicWindow
    win.search.text = "beta"
    win.search.hooks.OnTextChanged()
    eq(#win.box.provided, 1)
    eq(win.box.rows[1].name.text, "Beta2")
    win.search.text = "sub3"
    win.search.hooks.OnTextChanged()
    eq(win.box.rows[1].name.text, "Alpha3")
    win.search.text = "nobody"
    win.search.hooks.OnTextChanged()
    eq(win.empty.text, "No matches.")
    win.search.text = ""
    win.search.hooks.OnTextChanged()
    F.click(win.box.rows[3])
    eq(win.box.rows[3].locked, true, "the clicked row is the highlighted one")
end)

test("classic: sort and Mine only act on the sortable page and sit out the others", function()
    local GK = bootClassic("classic")
    GK.OpenWindow(1)
    local win = _G.GrudgekeeperClassicWindow
    GK.db.sortMode = "newest"
    GK.OpenWindow(1)
    eq(win.box.rows[1].name.text, "Alpha3", "newest first, headers dropped")
    eq(#win.box.provided, 3)
    GK.db.mineOnly = true
    GK.OpenWindow(1)
    eq(#win.box.provided, 0, "none of the rows is mine")
    eq(win.empty.text, "Nothing of yours here.")
    GK.OpenWindow(2)
    eq(win.sort.shown, false)
    eq(win.mine.shown, false)
    eq(#win.box.provided, 4, "other pages keep their own order")
    eq(win.links[1].text, "This week")
    eq(win.links[1].enabled, false, "the chosen link is the one that does nothing")
    eq(win.links[2].enabled, true)
end)

test("classic: the tabs are the pages, the ones with side = right in the right group", function()
    local GK = bootClassic("classic")
    GK.OpenWindow(5)
    local win = _G.GrudgekeeperClassicWindow
    eq(#win.tabs, 6)
    eq(win.tabs[5].text, "Page5")
    eq(win.selectedTab, 5)
    F.click(win.tabs[3])
    eq(win.selectedTab, 3)
    eq(win.tabs[4].side, nil)
    eq(win.tabs[5].side, "right")
end)

test("classic: a card opens in its own frame and a ledger one is hidden when the look changes", function()
    local GK = bootClassic("ledger")
    local ledger = CreateFrame("Frame", "GrudgekeeperFrame")
    ledger:Show()
    GK.ShowCard(function() return CARD end)
    GK.Classic.SetLook("classic")
    eq(ledger.shown, false, "the ledger's window is hidden")
    GK.ShowCard(function() return CARD end)
    local card = _G.GrudgekeeperClassicCard
    eq(card.shown, true)
    GK.Classic.SetLook("ledger")
    eq(card.shown, false, "the classic card is hidden")
    eq(GK.db.look, "ledger")
end)

test("classic: a letter shows its content, buttons and place in the pile", function()
    local GK = bootClassic("classic")
    table.insert(GK.char.letters, { id = 1, kind = "kill", n = GANK, p = 2, of = 1, total = 5, t = W.base, read = false })
    table.insert(GK.char.letters, { id = 2, kind = "expired", n = GANK, t = W.base, read = false })
    eq((GK.Unread()), 2)
    GK.OpenLetters()
    local f = _G.GrudgekeeperClassicLetter
    eq(f.shown, true)
    eq(f.title.text, "Blood drawn")
    eq(f.page.text, "1 of 2")
    eq(f.buttons[1].text, "Leaderboard")
    eq(f.buttons[2].shown, false)
    eq(GK.char.letters[1].read, true)
    F.click(f.next)
    eq(f.title.text, "Order expired")
    eq(f.page.text, "2 of 2")
    eq(f.buttons[1].text, "Post it again")
    GK.CloseLetters()
    eq(f.shown, false)
end)

test("classic: the letter icon shows the unread count, in place of the parchment one", function()
    local GK = bootClassic("classic")
    local old = CreateFrame("Button", "GrudgekeeperNotice")
    old:Show()
    GK.NoticeUpdate(false)
    eq(visible("GrudgekeeperClassicNotice"), false, "nothing to read")
    table.insert(GK.char.letters, { id = 1, kind = "slain", n = GANK, t = W.base, read = false })
    GK.NoticeUpdate(true)
    local btn = _G.GrudgekeeperClassicNotice
    eq(btn.shown, true)
    eq(btn.count.text, 1)
    eq(old.shown, false)
    F.click(btn)
    eq(GK.char.letters[1].read, true, "a click reads the pile")
    GK.PlaceNotice()
    eq(btn.line.text, "Drag me - click when done")
end)

test("classic: a warning is a chat line and a glow, or the original's when the style is the raid warning", function()
    local GK = bootClassic("classic")
    W.printed = {}
    GK.Warn("Gank is near!", true)
    assert(W.printed[1] and W.printed[1]:find("Gank is near!", 1, true), "said it in chat")
    eq(_G.GrudgekeeperClassicNotice.shown, true)
    eq(#GK.called, 0, "the ledger's warning stayed out of it")
    GK.db.alertStyle = "raid"
    GK.Warn("Again", true)
    eq(GK.called[#GK.called], "Warn")
end)

test("classic: the kill order sheet is filled from the plan and seals through PostSubmit", function()
    local GK = bootClassic("classic")
    local posted
    function GK.PostOrder(t, copper, note) posted = { t, copper, note } return { key = "o" } end
    GK.OpenPost({ key = GANK, c = "MAGE", l = 60 })
    local f = _G.GrudgekeeperClassicPost
    eq(f.shown, true)
    eq(f.small.text, "No gold is taken now. Whoever fulfils the order is owed the bounty, and you pay them by mail. "
        .. "The order runs for a week.")
    eq(f.seal.text, "Seal it")
    f.gold.text = "5"
    f.silver.text = "20"
    f.note.text = "camper"
    F.click(f.seal)
    eq(posted[2], 52000)
    eq(posted[3], "camper")
    eq(f.shown, false)
    eq(_G.GrudgekeeperClassicWindow.shown, true, "sealing opens the hitlist, in this look")
end)

test("classic: the note sheet saves through AddNote with the list and the tag", function()
    local GK = bootClassic("classic")
    local added
    GK.AddNote = function(key, text, tag, list, info) added = { key, text, tag, list, info } return {} end
    GK.KnownTags = function() return { "Toxic" } end
    GK.OpenNoteSheet({ key = GANK, c = "MAGE", r = "Orc", l = 60 }, "watch")
    local f = _G.GrudgekeeperClassicNote
    eq(f.shown, true)
    eq(f.list.text, "Shame")
    f.tag.text = "Toxic"
    f.text.text = "rude in chat"
    F.click(f.save)
    eq(added[1], GANK)
    eq(added[2], "rude in chat")
    eq(added[3], "Toxic")
    eq(added[4], "watch")
    eq(added[5].c, "MAGE")
    eq(f.shown, false)
    GK.AddNote = function() return nil, "Write something first." end
    GK.OpenNoteSheet({ key = GANK }, "kos")
    f.text.text = ""
    W.printed = {}
    F.click(f.save)
    eq(f.shown, true, "it stays open when the note was refused")
    assert(W.printed[1]:find("Write something first.", 1, true), "said why")
end)

test("classic: the setting and /grudge classic switch the look", function()
    local GK = bootClassic("ledger")
    local section = GK.OptionSections[#GK.OptionSections]
    local clicked
    local box = CreateFrame("CheckButton")
    local helpers = { Section = function() return {} end, Box = function(_, _, _, onClick) clicked = onClick return box end }
    eq(section({}, {}, helpers), box)
    eq(box.checked, false)
    clicked(true)
    eq(GK.db.look, "classic")
    clicked(false)
    eq(GK.db.look, "ledger")
    SlashCmdList.GRUDGEKEEPER("classic")
    eq(GK.db.look, "classic")
    SlashCmdList.GRUDGEKEEPER("classic")
    eq(GK.db.look, "ledger")
    SlashCmdList.GRUDGEKEEPER("letters")
    eq(GK.called[#GK.called], "OpenLetters", "anything else goes to the original")
end)

test("classic: the Inspect page gets a card of ours over the ledger's while the look is classic", function()
    local GK = bootClassic("classic")
    local page = CreateFrame("Frame")
    GK.BuildCardPage(page, {}, function() end)
    eq(GK.built, 1)
    GK.FillCardPage(page, CARD)
    eq(GK.filled, 0, "the ledger's page is not filled")
    eq(page.classic.shown, true)
    eq(page.classic.view.title.text, "WANTED")
    GK.db.look = "ledger"
    GK.FillCardPage(page, CARD)
    eq(GK.filled, 1)
    eq(page.classic.shown, false)
end)

-- ---------------------------------------------------------------------------
-- Telling the guild what the import made
-- ---------------------------------------------------------------------------
test("NotesBroadcast sends my own records two a second, never someone else's, never in test mode", function()
    local GK = boot()
    W.advance(11)
    for i = 1, 5 do GK.AddNote("Player" .. i .. "-Realm", "my note " .. i) end
    W.receive(GK, KARI, msg("N", 1, GANK, 1, B, "", "", "", "", "", "Kari's note"))
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

test("the four list pages: Marked between Grudges and News, the rest on the right, none with links", function()
    local GK = bootUI()
    eq(#GK.LedgerPages, 8)
    local want = { { "Marked", nil, 4 }, { "Shame", "right", 6 }, { "Kudos", "right", 7 }, { "Names", "right", 8 } }
    local order = {}
    for i, page in ipairs(GK.LedgerPages) do order[i] = page.name end
    eq(table.concat(order, "|"), "Kill orders|Leaderboard|Grudges|Marked|News|Shame|Kudos|Names")
    for _, w in ipairs(want) do
        local page = GK.LedgerPages[w[3]]
        eq(page.name, w[1])
        eq(page.side, w[2])
        eq(page.sortable, true)
        eq(page.links, nil, "the list is the tab")
        eq(#page.headings, 2)
    end
    for i = 1, 5 do eq(GK.LedgerPages[i].side, nil) end
    eq(GK.LedgerPages[4].headings[1][1], "Player")
    eq(GK.LedgerPages[8].headings[1][1], "Nice name")
    eq(GK.db.notesList, nil, "the list is not a setting any more")
end)

test("GK.OpenNotes opens the page of the list", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    GK.OpenNotes("kos")
    eq(W2.opened, 4)
    GK.OpenNotes("watch")
    eq(W2.opened, 6)
    GK.OpenNotes("kudos")
    eq(W2.opened, 7)
    GK.OpenNotes("names")
    eq(W2.opened, 8)
    GK.OpenNotes("somewhere")
    eq(W2.opened, 4, "an unknown list is kos")
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
    local items, empty = GK.LedgerPages[4].items()
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
    eq(GK.LedgerPages[4].sub({ 1 }), "1 player marked")
    eq(GK.LedgerPages[6].sub(rows), "2 players on Shame")
    eq(#GK.LedgerPages[6].items(), 2)
end)

test("the Names list: hidden ones only for officers, and faded", function()
    local GK, LIB = bootUI()
    W.receive(GK, KARI, msg("M", 1, NICE, B + 1, "", "PRIEST", "Human", "Human", 3, 40))
    W.receive(GK, KARI, msg("M", 1, "Silly Two-Realm", B + 2))
    W.receive(GK, EDVARD, msg("G", 1, NICE, 1, B + 3))
    LIB.roster["Master-Realm"] = { rankIndex = 0 }
    W.receive(GK, "Master-Realm", msg("H", 1, "Silly Two-Realm", 1, B + 4))
    local items, empty = GK.NotesItems("names")
    eq(#items, 1)
    eq(items[1].name, "Nina Nice")
    eq(items[1].right, "+1")
    eq(items[1].sub, "added by Kari")
    eq(items[1].face.rf, "Human")
    eq(items[1].faded, nil)
    assert(empty:find("No nice names"), empty)
    LIB.roster[ME] = { rankIndex = 0 }
    items = GK.NotesItems("names")
    eq(#items, 2)
    eq(items[1].name, "Silly Two", "the newest first")
    eq(items[1].faded, true)
    eq(items[1].sub, "hidden - added by Kari")
    eq(GK.LedgerPages[8].sub(items), "2 nice names in the guild's list")
    eq(#GK.LedgerPages[8].items(), 2)
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

test("a nice name's card: who added it, the vote buttons, and the officer's hide", function()
    local GK, LIB = bootUI()
    W.receive(GK, KARI, msg("M", 1, NICE, B + 1, "", "PRIEST", "Human", "Human", 3, 40))
    local d = GK.NameCard(NICE)
    eq(d.title, "NICE NAME")
    eq(d.name, "Nina Nice")
    eq(d.lines[1], "Added by: Kari")
    eq(d.big, "0")
    eq(d.buttons[1][1], "Vote up")
    eq(d.buttons[2][1], "More...")
    d.buttons[1][2]()
    eq(GK.NameScore(NICE), 1)
    d = GK.NameCard(NICE)
    eq(d.buttons[1][1], "Take back")
    eq(d.big, "+1")
    local root = fakeNode("root")
    GK.NameMenu(root, NICE)
    eq(labels(root), "Vote down|Take back my vote", "no hide: I am no officer")
    LIB.roster[ME] = { rankIndex = 0 }
    root = fakeNode("root")
    GK.NameMenu(root, NICE)
    eq(labels(root), "Vote down|Take back my vote|Hide for everyone")
    kid(root, "Hide for everyone").fn()
    d = GK.NameCard(NICE)
    eq(d.lines[2], "Hidden: an officer hid it from the list.")
    root = fakeNode("root")
    GK.NameMenu(root, NICE)
    assert(kid(root, "Show for everyone"))
    LIB.roster[ME] = { rankIndex = 5 }
    eq(GK.NameCard(NICE), nil, "hidden from a non-officer")
    -- my own: remove, and no vote
    GK.AddNiceName("Mine Funny-Realm")
    d = GK.NameCard("Mine Funny-Realm")
    eq(d.buttons[1][1], "Remove")
    eq(d.buttons[2], nil, "nothing to put in More for my own name when I am no officer")
    d.buttons[1][2]()
    eq(GK.NameCard("Mine Funny-Realm"), nil)
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
    r = P("nice", "Funny Name", KARI, known)
    eq(r.key, "Funny Name-Realm")
    eq(P("nice", "", KARI, known).key, KARI)
    eq(select(1, P("nice", "one", nil, known)), nil)
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
    slash("nice Funny Name")
    assert(GK.Store().names["Funny Name-Realm"], "a nice name")
    slash("nice Funny Name")
    assert(W.printed[#W.printed]:find("already"), W.printed[#W.printed])
    slash("notes")
    eq(W2.opened, 4, "Marked")
    slash("watch")
    eq(W2.opened, 6)
    slash("kudos")
    eq(W2.opened, 7)
    slash("names")
    eq(W2.opened, 8)
    slash("watch Nina Nice")
    eq(W2.opened, 8, "with a name, watch adds")
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

test("the alert style: a raid warning with its sound and a chat line, or the scroll", function()
    local GK = bootUI()
    local W2 = require("wow_mock")
    GK.Warn("Gank is near!", true)
    eq(#W2.raid, 0, "scroll is the default: the original ran")
    eq(#W2.warned, 1, "...the stand-in for Notice.lua")
    GK.db.alertStyle = "raid"
    GK.Warn("Gank is near!", true)
    eq(#W2.warned, 1, "the original is not called")
    eq(#W2.raid, 1)
    eq(W2.raid[1].text, "Gank is near!")
    eq(W2.raid[1].colour, ChatTypeInfo.RAID_WARNING)
    eq(W2.played[1], 8959)
    assert(W.printed[#W.printed]:find(GK.TAG, 1, true) and W.printed[#W.printed]:find("Gank is near!", 1, true))
    GK.db.sound = false
    GK.Warn("again", true)
    eq(#W2.played, 1, "no sound when sounds are off")
    eq(#W2.raid, 2)
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

test("joining the group: Shame warns with the tag, Kudos says one green line, each once", function()
    local GK, LIB = bootUI()
    local W2 = require("wow_mock")
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
    eq(labels(sub), "Add a note|Shame list|Kudos|Add to nice names", "no Their notes: nobody wrote about them")
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
    kid(sub, "Add to nice names").fn()
    assert(GK.Store().names[GANK])
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
    eq(GK.db.kudosGroup, true)
    eq(GK.db.plateNotes, true)
    eq(GK.db.alertStyle, "scroll")
    eq(#GK.OptionSections, 1)
end)

say(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
