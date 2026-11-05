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
-- A note's id here is its time (a later number if that is taken): Guild Grudge's own ids were
-- strings. A vote on someone else's imported note is kept to count, not sent: that id is only ours.
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
    GK.Store()                                  -- sets which guild this character is in
    local guild = LIB.GuildKey()
    if not guild and IsInGuild() then guild = GK.char.guild end
    guild = guild or "-"
    GK.db.importedGG = GK.db.importedGG or {}
    if GK.db.importedGG[guild] and not force then return nil, "done" end

    local Put = GK.NotesPut
    local counts = { notes = 0, marks = 0, names = 0, votes = 0, skipped = 0 }

    for _, e in pairs(type(src.entries) == "table" and src.entries or {}) do
        local key = type(e) == "table" and Key(e.name)
        if key then
            local authors, newest = {}, 0
            for _, n in pairs(type(e.notes) == "table" and e.notes or {}) do
                local author, ts = type(n) == "table" and Key(n.author), type(n) == "table" and When(n.ts)
                local text, tag = type(n) == "table" and GK.Clean(n.text, 200), type(n) == "table" and GK.Clean(n.tag, GK.MAX_TAG)
                if type(n) == "table" and not n.deleted and author and ts and (text or tag) then
                    authors[author] = true
                    newest = math.max(newest, ts)
                    -- the same note from an earlier import is found by its text, and not made twice
                    local id = ts
                    local p = GK.Person(key, false)
                    local byId = p and p.notes[author]
                    while byId and byId[id] and not (byId[id].text == text and byId[id].tag == tag) do id = id + 1 end
                    local kept = byId and byId[id] and true or false
                    if not kept then
                        kept = Put.Note(key, author, id, { text = text, tag = tag, ts = ts, imp = author ~= me })
                        if kept then counts.notes = counts.notes + 1 else counts.skipped = counts.skipped + 1 end
                    end
                    if kept then
                        for voter, vote in pairs(type(n.votes) == "table" and n.votes or {}) do
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
                voter = Key(voter)
                local v, vts = tonumber(vote.v), When(vote.ts)
                if voter and vts and (v == 1 or v == -1) and Put.NameVote(key, voter, v, vts) then
                    counts.votes = counts.votes + 1
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
-- guild's name can be a moment late, so a missing one is waited for once more.
local function AutoImport(retry)
    if IsInGuild() and not LIB.GuildKey() and not retry then
        C_Timer.After(15, function() AutoImport(true) end)
        return
    end
    GK.ImportGuildGrudge(false)
end

LIB.On("PLAYER_LOGIN", function()
    if not (GK.db and GK.char) then return end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("GuildGrudge")
    if loaded and GuildGrudgeDB then C_Timer.After(15, function() AutoImport(false) end) end
end)
