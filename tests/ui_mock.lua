-- What NotesUI.lua needs of the files that load before it (Window, Profile, Social, Notice, Letters,
-- Sightings, Options) and of the game's unit and menu API, as stand-ins that record what they are asked
-- to do. wow_mock.boot({ ui = true }) loads it. No frames: the code that builds frames is not run here.
local U = {}

--- Install the stand-ins on GK and the globals, then load NotesUI.lua as the game would.
function U.load(M, GK)
    local env = _G
    M.opened, M.poster, M.card, M.played = nil, nil, nil, {}
    M.warned, M.menus = {}, {}
    M.mobs, M.hostile, M.order, M.tipLine, M.seen = {}, {}, nil, nil, {}
    M.group = { raid = false, size = 0 }

    -- the other files' functions NotesUI calls or wraps
    GK.LedgerPages = { { name = "Kill orders" }, { name = "Leaderboard" }, { name = "Grudges" }, { name = "News" } }
    GK.AddLedgerPage = function(def)        -- as Window.lua's: def.before names the page to sit in front of
        for i, page in ipairs(GK.LedgerPages) do
            if def.before and page.name == def.before then return table.insert(GK.LedgerPages, i, def) end
        end
        table.insert(GK.LedgerPages, def)
    end
    GK.OptionSections = {}
    GK.Ago = function() return "3 days ago" end
    GK.OpenWindow = function(page) M.opened = page end
    GK.OpenOptions = function() M.optionsOpened = true end
    GK.ShowPoster = function(t) M.poster = t end
    GK.ShowCard = function(make) M.card = make end
    GK.MenuKey = function() return M.menuKey end
    GK.OrderOn = function() return M.order end
    GK.Seen = function(key) return M.seen[key] end
    GK.Hostile = function(unit) return M.hostile[unit] == true end
    GK.PlaceNotice = function() end
    local function Copy(list)
        local t = {}
        for i, v in ipairs(list or {}) do t[i] = v end
        return t
    end
    GK.PosterCard = function(t) return { key = t.key, lines = Copy(M.posterLines), buttons = {} } end
    GK.RecordCard = function(key) return { key = key, lines = Copy(M.recordLines), buttons = {} } end
    GK.TooltipLine = function() return M.tipLine end
    GK.Warn = function(text, urgent) table.insert(M.warned, { text = text, urgent = urgent }) end

    -- the game
    env.IsInInstance = function() return false end
    env.SOUNDKIT = { RAID_WARNING = 8959 }
    env.PlaySound = function(id) table.insert(M.played, id) end
    env.UnitExists = function(unit) return M.units[unit] ~= nil end
    env.UnitIsPlayer = function(unit) return M.units[unit] ~= nil and not M.mobs[unit] end
    env.UnitClass = function() return "Rogue", "ROGUE" end
    env.UnitRace = function() return "Orc", "Orc" end
    env.UnitSex = function() return 2 end
    env.UnitLevel = function() return 60 end
    env.UnitGUID = function(unit) return "Player-" .. tostring(M.units[unit]) end
    env.IsInRaid = function() return M.group.raid end
    env.GetNumGroupMembers = function() return M.group.size end
    env.Menu = { ModifyMenu = function(tag, fn) M.menus[tag] = fn end }
    env.GameTooltip = {}

    local chunk = assert(loadfile(M.dir .. "NotesUI.lua"))
    chunk("Grudgekeeper", GK)
end

return U
