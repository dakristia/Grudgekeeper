-- Grudgekeeper - the quiet ways in: one line on a tooltip, one badge beside the guild window.
-- Neither ever opens anything or makes a sound; they are only there when you are already looking.
--   Tooltip   mouse over an enemy player you have a history with, and one line says it:
--             "Grudge: killed you 24 - you got them 3 - kill order 20s". Nobody you've never met gets one.
--   Guild     a small round badge on the guild window's right edge, opening the leaderboard. Outside
--             the window, not in its button row: Guildhall's button already lives along the bottom,
--             and two addons each placing theirs beside "the leftmost button" would anchor to each
--             other in a loop.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local Secret = GK.Secret

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"

-- ---------------------------------------------------------------------------
-- The tooltip line
-- ---------------------------------------------------------------------------
--- The line for an enemy player, from what we know of them: our record, the guild's, an order. nil
--- when there is nothing to say - most enemies, most of the time. Exposed for the smoke test.
function GK.TooltipLine(key, guid)
    if not key then return nil end
    local parts = {}
    local f = GK.char.foes[key]
    if f and (f.d or 0) > 0 then parts[#parts + 1] = ("killed you %d"):format(f.d) end
    if f and (f.k or 0) > 0 then parts[#parts + 1] = ("you got them %d"):format(f.k) end
    if f and (f.a or 0) > 0 then parts[#parts + 1] = ("you helped %d"):format(f.a) end
    local w = GK.Store().wanted[key]
    if w then
        local total, others = 0, 0
        for who, n in pairs(w.victims) do
            total = total + n
            if who ~= LIB.Me() then others = others + n end
        end
        if others > 0 then parts[#parts + 1] = ("killed the guild %d"):format(total) end
    end
    local o = GK.OrderOn(key, guid)
    if o then
        local pot = GK.Pot(o)
        parts[#parts + 1] = pot > 0 and ("kill order %s"):format(GK.MoneyText(pot)) or "kill order"
    end
    if #parts == 0 then return nil end
    return "|cffc8281eGrudge|r  " .. table.concat(parts, "  -  ")
end

-- A tooltip is drawn again and again while the mouse rests on someone: the line is worked out once
-- and kept until the data changes (GK.version) or the mouse finds somebody else.
local memoKey, memoGuid, memoVersion, memoLine

local function OnUnitTip(tooltip)
    if tooltip ~= GameTooltip or not (GK.db and GK.db.tooltip) or not GK.InWorld() then return end
    if not tooltip.GetUnit then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok or type(unit) ~= "string" or Secret(unit) then return end
    local key, guid = GK.UnitIdentity(unit)
    if not key then return end
    if key ~= memoKey or guid ~= memoGuid or GK.version ~= memoVersion then
        memoKey, memoGuid, memoVersion = key, guid, GK.version
        memoLine = GK.TooltipLine(key, guid)
    end
    if not memoLine then return end
    tooltip:AddLine(memoLine, 0.85, 0.75, 0.6)
    tooltip:Show()
end

-- ---------------------------------------------------------------------------
-- The guild window badge
-- ---------------------------------------------------------------------------
local badge

local function Attach()
    if badge then return end
    local parent = _G.CommunitiesFrame
    if not (parent and parent.GetObjectType) then return end
    badge = CreateFrame("Button", nil, parent)
    badge:SetSize(34, 34)
    badge:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 36)
    local tex = badge:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(MEDIA .. "minimap")
    local hi = badge:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture(MEDIA .. "glow")
    hi:SetBlendMode("ADD")
    hi:SetVertexColor(1, 0.8, 0.35, 0.6)
    badge:SetScript("OnClick", function() GK.OpenWindow(2) end)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(GK.TAG)
        local rank, of = GK.MyRank()
        GameTooltip:AddLine(("The guild's leaderboard - you're #%d of %d"):format(rank, of), 1, 1, 1)
        local open = #GK.OpenOrders()
        if open > 0 then GameTooltip:AddLine(("%d open kill order%s"):format(open, open == 1 and "" or "s"), 1, 0.5, 0.4) end
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge:SetShown(GK.db.guildButton and IsInGuild())
end

function GK.RefreshGuildBadge()
    Attach()
    if badge then badge:SetShown(GK.db.guildButton and IsInGuild()) end
end

function GK.StartSocial()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTip)
    end
    -- The guild window loads on demand: it may be there already, or come later.
    Attach()
    LIB.On("ADDON_LOADED", function(name)
        if name == "Blizzard_Communities" then Attach() end
    end)
end
