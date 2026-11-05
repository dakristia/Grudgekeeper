-- Grudgekeeper - a one-time import from Guild Grudge. When both addons are on, the notes, lists, tags,
-- nice names and votes Guild Grudge kept (GuildGrudgeDB) are taken over into the guild's store, once
-- per guild. Its bounties and claims are not (kill orders do that job here). Afterwards the player can
-- turn Guild Grudge off.
-- Whose is what: a note keeps its author, so Guild Grudge's notes by OTHER players land under them
-- and are never sent by us (the wire only sends records whose author is me, Notes.lua); only my own
-- notes, marks, votes and names go on to the guild, and only as other clients ask (a Q). Guild Grudge
-- gave a player one shared list, not one per author, so the list becomes a mark for each author of a
-- live note on them, and for me when there is none. Marked (stored as kos) is what a note alone already means,
-- so only Shame (stored as watch) and Kudos make marks.
-- A note's id here is its time times 100 plus its place among that author's notes of the same second on
-- that player, the notes put in order by text, tag and Guild Grudge's own id (a string, which we can't
-- use): the same data gives the same ids whatever order it is walked in. A vote on someone else's
-- imported note is kept to count, not sent: that id is only ours.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

--- A Guild Grudge name ("First Surname", or "Name-Realm") as one of our player keys.
local function Key(name)
    return GK.KeyOf(GK.Clean(name, 64))
end

--- A time Guild Grudge kept, in a range we accept: whole seconds, not after now.
local function When(v)
    v = tonumber(v)
    if not v or v < 1 then return nil end
    return math.min(math.floor(v), time())
end

local function ValidRaceFile(rf)
    return (type(rf) == "string" and #rf <= 20 and rf:match("^%a+$")) and rf or nil
end

local function ValidSex(sx)
    return (sx == 2 or sx == 3) and sx or nil
end

--- Take over what Guild Grudge kept, once per guild (force: again). Returns { notes, marks, names,
--- votes, skipped }, or nil and why nothing was done.
function GK.ImportGuildGrudge(force)
    local src = GuildGrudgeDB
    if type(src) ~= "table" or not (GK.db and GK.char) then return nil, "nothing to import" end
    local me = LIB.Me()
    if not me then return nil, "not yet" end
    -- The test panel (Debug.lua) puts the stores back when it closes, but not the done marker.
    if GK.testMode then return nil, "test mode" end
    -- In a guild the store and the marker belong to that guild, so wait until the client says which;
    -- the guildless store is only for a character who has none.
    local guild = "-"
    if IsInGuild() then
        guild = LIB.GuildKey()
        if not guild then return nil, "not yet" end
    end
    GK.db.importedGG = GK.db.importedGG or {}
    if GK.db.importedGG[guild] and not force then return nil, "done" end

    local Put = GK.NotesPut
    local counts = { notes = 0, marks = 0, names = 0, votes = 0, skipped = 0 }

    for _, e in pairs(type(src.entries) == "table" and src.entries or {}) do
        local key = type(e) == "table" and Key(e.name)
        if key then
            local authors, newest = {}, 0
            -- The notes that will be taken, in an order of their own: by time, author, text, tag and Guild
            -- Grudge's id for the note, never the order the saved data happens to be walked in.
            local found = {}
            for nid, n in pairs(type(e.notes) == "table" and e.notes or {}) do
                local author, ts = type(n) == "table" and Key(n.author), type(n) == "table" and When(n.ts)
                local text, tag = type(n) == "table" and GK.Clean(n.text, 200), type(n) == "table" and GK.Clean(n.tag, GK.MAX_TAG)
                if type(n) == "table" and not n.deleted and author and ts and (text or tag) then
                    found[#found + 1] = { n = n, author = author, ts = ts, text = text, tag = tag,
                        sid = tostring(n.id ~= nil and n.id or nid) }
                end
            end
            table.sort(found, function(a, b)
                if a.ts ~= b.ts then return a.ts < b.ts end
                if a.author ~= b.author then return a.author < b.author end
                if (a.text or "") ~= (b.text or "") then return (a.text or "") < (b.text or "") end
                if (a.tag or "") ~= (b.tag or "") then return (a.tag or "") < (b.tag or "") end
                return a.sid < b.sid
            end)
            -- An id is the time times 100 plus the note's place among its author's notes of that second:
            -- the same data gives the same ids on every client.
            local placed = {}
            for _, f in ipairs(found) do
                local n, author, ts, text, tag = f.n, f.author, f.ts, f.text, f.tag
                local slot = author .. "\0" .. ts
                local index = placed[slot] or 0
                placed[slot] = index + 1
                authors[author] = true
                newest = math.max(newest, ts)
                local id = ts * 100 + index
                local p = GK.Person(key, false)
                local old = p and p.notes[author] and p.notes[author][id]
                -- the same note from an earlier import has the same id, and is not made twice
                local kept = old ~= nil and old.text == text and old.tag == tag
                if not old and index < 100 then
                    kept = Put.Note(key, author, id, { text = text, tag = tag, ts = ts, imp = author ~= me })
                    if kept then counts.notes = counts.notes + 1 end
                end
                -- a different note already holds this id (or the limits refused it): left out
                if not kept then counts.skipped = counts.skipped + 1 end
                if kept then
                    for voter, vote in pairs(type(n.votes) == "table" and n.votes or {}) do
                        if type(vote) ~= "table" then
                            counts.skipped = counts.skipped + 1
                        else
                            voter = Key(voter)
                            local v, vts = tonumber(vote.v), When(vote.ts)
                            if voter and vts and (v == 1 or v == -1) and Put.Vote(key, author, id, voter, v, vts) then
                                counts.votes = counts.votes + 1
                            end
                        end
                    end
                end
            end
            if e.list == "watch" or e.list == "kudos" then
                if next(authors) == nil then authors[me] = true end
                local ts = When(e.listTs) or (newest > 0 and newest) or time()
                for author in pairs(authors) do
                    if Put.Mark(key, author, { list = e.list, ts = ts }) then counts.marks = counts.marks + 1 end
                end
            end
            GK.LearnPerson(key, { c = e.class, r = e.race, rf = ValidRaceFile(e.raceFile), sx = ValidSex(e.sex),
                l = e.level })
        end
    end

    for _, n in pairs(type(src.names) == "table" and src.names or {}) do
        local key, by, ts = type(n) == "table" and Key(n.name), type(n) == "table" and Key(n.by), type(n) == "table" and When(n.ts)
        if key and by and ts and not n.deleted then
            local rec = { ts = ts, c = GK.ValidClass(n.class), r = GK.Clean(n.race, 20), rf = ValidRaceFile(n.raceFile),
                sx = ValidSex(n.sex), l = GK.ValidLevel(n.level) }
            if Put.Name(key, by, rec) then counts.names = counts.names + 1 end
            for voter, vote in pairs(type(n.votes) == "table" and n.votes or {}) do
                if type(vote) ~= "table" then
                    counts.skipped = counts.skipped + 1
                else
                    voter = Key(voter)
                    local v, vts = tonumber(vote.v), When(vote.ts)
                    if voter and vts and (v == 1 or v == -1) and Put.NameVote(key, voter, v, vts) then
                        counts.votes = counts.votes + 1
                    end
                end
            end
        end
    end

    GK.db.importedGG[guild] = time()
    GK.Changed()
    print(("%s: took over %d notes, %d list marks, %d nice names and %d votes from Guild Grudge."):format(
        GK.TAG, counts.notes, counts.marks, counts.names, counts.votes))
    return counts
end

-- Both addons on: do it once, a little after login, when the client has said which guild this is. The
-- guild's name can be a moment late, so a missing one is waited for a few times and then given up on,
-- quietly and without the done marker: the next login tries again. The test panel being open is waited
-- out the same way, for longer.
local WAIT_GUILD, WAIT_TEST = 4, 20
local function AutoImport(guildTries, testTries)
    local _, why = GK.ImportGuildGrudge(false)
    if why == "not yet" and guildTries < WAIT_GUILD then
        C_Timer.After(15, function() AutoImport(guildTries + 1, testTries) end)
    elseif why == "test mode" and testTries < WAIT_TEST then
        C_Timer.After(30, function() AutoImport(guildTries, testTries + 1) end)
    end
end

LIB.On("PLAYER_LOGIN", function()
    if not (GK.db and GK.char) then return end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("GuildGrudge")
    if loaded and GuildGrudgeDB then C_Timer.After(15, function() AutoImport(0, 0) end) end
end)
