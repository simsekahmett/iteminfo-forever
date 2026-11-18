local _, ns = ...

-- Adds information to item tooltips anywhere in the game: how the item is
-- made, where its recipe comes from, what it is used to make, which quests
-- reward it, who sells it and what drops it.

local L = ns.L
local DB = ns.DB

local Tooltip = {}
ns.Tooltip = Tooltip

local GOLD = '|cffffd100'
local GRAY = '|cff909090'

-- The number of recipes listed before the rest is folded away
local usedInLimit = 5
local usedInLimitExpanded = 40
local vendorLimit = 2
-- The number of quests listed before the rest is folded away
local questLimit = 3
local questLimitExpanded = 15
-- The number of vendors or creatures listed before the rest is folded away
local npcLimit = 3
local npcLimitExpanded = 20

local function FormatSkill(profession, skill)
  return string.format('%s (%d)', DB:GetProfessionName(profession), skill)
end

-- Returns the vendors of an item that deal with the player's faction, or all
-- of them if none do
local function GetUsableVendors(itemId)
  local vendors = DB:GetVendors(itemId)

  if vendors == nil then
    return nil
  end

  local faction = UnitFactionGroup('player') == 'Horde' and 'H' or 'A'
  local usable = {}

  for index = 1, #vendors do
    local _, _, _, _, friendly = DB:GetNpc(vendors[index])

    if friendly == nil or friendly == '' or friendly:find(faction, 1, true) then
      usable[#usable + 1] = vendors[index]
    end
  end

  return #usable > 0 and usable or vendors
end

-- Returns the player's zone and position in percent, if known
local function GetPlayerPosition()
  local zone = GetRealZoneText()
  local map = C_Map.GetBestMapForUnit('player')
  local position = map and C_Map.GetPlayerMapPosition(map, 'player')

  if position == nil then
    return zone
  end

  local x, y = position:GetXY()
  if x == nil or ns.IsSecret(x) then
    return zone
  end

  return zone, x * 100, y * 100
end

-- Sorts vendors so that those in the player's zone come first, the nearest
-- of them first
local function SortByDistance(vendors)
  local zone, playerX, playerY = GetPlayerPosition()
  local distances = {}

  for _, npcId in ipairs(vendors) do
    local _, npcZone, x, y = DB:GetNpc(npcId)
    local distance = math.huge

    if zone ~= nil and npcZone == zone then
      distance = 1e6

      if playerX ~= nil and x >= 0 and y >= 0 then
        distance = (x - playerX) ^ 2 + (y - playerY) ^ 2
      end
    end

    distances[npcId] = distance
  end

  table.sort(vendors, function(a, b)
    if distances[a] ~= distances[b] then
      return distances[a] < distances[b]
    end

    return a < b
  end)

  return distances
end

local function FormatNpc(npcId)
  local name, zone = DB:GetNpc(npcId)

  if zone ~= nil and zone ~= '' then
    return name .. GRAY .. ' - ' .. zone .. '|r'
  end

  return name
end

-- Adds where the recipe of a spell comes from
local function AddRecipeSource(tooltip, spellId)
  local recipes = DB:GetRecipeItems(spellId)

  if recipes == nil then
    tooltip:AddLine('  ' .. L['Recipe'] .. ': ' .. GRAY .. L['Taught by trainers'] .. '|r', 1, 1, 1)
    return
  end

  local recipe = recipes[1]
  tooltip:AddLine('  ' .. L['Recipe'] .. ': ' .. DB:GetColoredName(recipe), 1, 1, 1)

  local vendors = GetUsableVendors(recipe)
  if vendors ~= nil then
    for index = 1, math.min(#vendors, vendorLimit) do
      tooltip:AddLine('    ' .. L['Sold by'] .. ': ' .. FormatNpc(vendors[index]), 1, 1, 1)
    end

    if #vendors > vendorLimit then
      tooltip:AddLine('    ' .. GRAY .. '+' .. (#vendors - vendorLimit) .. '|r', 1, 1, 1)
    end
    return
  end

  local drops, total = DB:GetDrops(recipe)
  if drops ~= nil then
    if total > #drops then
      tooltip:AddLine('    ' .. GRAY ..
                        L['World drop, from %d different creatures']:format(total) .. '|r', 1, 1, 1)
    else
      tooltip:AddLine('    ' .. L['Dropped by'] .. ': ' .. FormatNpc(drops[1]), 1, 1, 1)
    end
  end
end

local function AddCreatedBy(tooltip, itemId)
  local createdBy = DB:GetCreatedBy(itemId)

  if createdBy == nil then
    return
  end

  for _, spellId in ipairs(createdBy) do
    local profession, skill, _, _, reagents, made = DB:GetSpell(spellId)
    local title = GOLD .. FormatSkill(profession, skill) .. '|r'

    if made > 1 then
      title = title .. GRAY .. ' x' .. made .. '|r'
    end

    tooltip:AddLine(' ')
    tooltip:AddLine(title)

    for index = 1, #reagents, 2 do
      tooltip:AddLine('  ' .. reagents[index + 1] .. 'x ' .. DB:GetColoredName(reagents[index]), 1, 1, 1)
    end

    AddRecipeSource(tooltip, spellId)
  end
end

-- Adds a list of NPCs under a title, those in the player's zone first, the
-- nearest of them first. Returns whether some were hidden.
local function AddNpcList(tooltip, title, npcs, prices)
  local distances = SortByDistance(npcs)
  local limit = IsShiftKeyDown() and npcLimitExpanded or npcLimit

  tooltip:AddLine(' ')
  tooltip:AddLine(GOLD .. title .. ' (' .. #npcs .. ')|r')

  for index = 1, math.min(#npcs, limit) do
    local npcId = npcs[index]
    local name, zone, x, y = DB:GetNpc(npcId)
    local text = '  ' .. name

    if zone ~= nil and zone ~= '' then
      text = text .. GRAY .. ' - ' .. zone

      -- Coordinates only help in the zone the player is in
      if distances[npcId] < 1e6 then
        text = text .. string.format(' (%.0f, %.0f)', x, y)
      end

      text = text .. '|r'
    end

    local price = prices and prices[npcId]
    if price ~= nil then
      tooltip:AddDoubleLine(text, ns.FormatMoney(price), 1, 1, 1, 1, 1, 1)
    else
      tooltip:AddLine(text, 1, 1, 1)
    end
  end

  if #npcs > limit then
    if limit == npcLimit then
      tooltip:AddLine('  ' .. GRAY .. L['Hold Shift for %d more']:format(#npcs - limit) .. '|r')
      return true
    end

    tooltip:AddLine('  ' .. GRAY .. '+' .. (#npcs - limit) .. '|r')
  end

  return false
end

-- Adds the vendors that sell an item, returns whether some were hidden
local function AddSoldBy(tooltip, itemId)
  local vendors = GetUsableVendors(itemId)

  if vendors == nil then
    return false
  end

  local _, prices = DB:GetVendors(itemId)
  return AddNpcList(tooltip, L['Sold by'], vendors, prices)
end

-- Adds the creatures that drop an item, returns whether some were hidden
local function AddDroppedBy(tooltip, itemId)
  local drops, total = DB:GetDrops(itemId)

  if drops == nil then
    return false
  end

  -- Those dropped by many creatures only get a summary
  if #drops == 0 then
    tooltip:AddLine(' ')
    tooltip:AddLine(GOLD .. L['Dropped by'] .. ':|r ' .. GRAY ..
                      L['World drop, from %d different creatures']:format(total) .. '|r')
    return false
  end

  return AddNpcList(tooltip, L['Dropped by'], drops)
end

-- Adds the quests that reward an item, returns whether some were hidden
local function AddQuestRewards(tooltip, itemId)
  local quests = DB:GetUsableQuestRewards(itemId)

  if quests == nil then
    return false
  end

  local limit = IsShiftKeyDown() and questLimitExpanded or questLimit

  tooltip:AddLine(' ')
  tooltip:AddLine(GOLD .. L['Quest reward'] .. ' (' .. #quests .. ')|r')

  for index = 1, math.min(#quests, limit) do
    local _, _, _, _, zone = DB:GetQuest(quests[index])
    tooltip:AddDoubleLine('  ' .. DB:GetColoredQuestName(quests[index]), zone or '', 1, 1, 1, 0.6, 0.6, 0.6)
  end

  if #quests > limit then
    if limit == questLimit then
      tooltip:AddLine('  ' .. GRAY .. L['Hold Shift for %d more']:format(#quests - limit) .. '|r')
      return true
    end

    tooltip:AddLine('  ' .. GRAY .. '+' .. (#quests - limit) .. '|r')
  end

  return false
end

-- Adds the recipes an item is a reagent of, returns whether some were hidden
local function AddUsedIn(tooltip, itemId)
  local usedIn = DB:GetUsedIn(itemId)

  if usedIn == nil then
    return false
  end

  local limit = IsShiftKeyDown() and usedInLimitExpanded or usedInLimit

  tooltip:AddLine(' ')
  tooltip:AddLine(GOLD .. L['Used in'] .. ' (' .. #usedIn .. ')|r ' .. DB:GetProfessionIcons(usedIn))

  for index = 1, math.min(#usedIn, limit) do
    local profession, skill = DB:GetSpell(usedIn[index])

    tooltip:AddDoubleLine('  ' .. DB:GetColoredName(DB:GetSpellRef(usedIn[index])),
                          FormatSkill(profession, skill), 1, 1, 1, 0.6, 0.6, 0.6)
  end

  if #usedIn > limit then
    if limit == usedInLimit then
      tooltip:AddLine('  ' .. GRAY .. L['Hold Shift for %d more']:format(#usedIn - limit) .. '|r')
      return true
    end

    tooltip:AddLine('  ' .. GRAY .. '+' .. (#usedIn - limit) .. '|r')
  end

  return false
end

-- Returns whether ItemInfo adds anything to the tooltip of an item
local function HasInfo(itemId)
  return DB:GetCreatedBy(itemId) ~= nil or DB:GetUsedIn(itemId) ~= nil
    or DB:GetUsableQuestRewards(itemId) ~= nil or DB:GetVendors(itemId) ~= nil
    or DB:GetDrops(itemId) ~= nil
end

------------------------------------------
-- Hooks
------------------------------------------

function Tooltip:_OnItem(tooltip, itemId)
  self.folded = nil

  if not self.options.enabled or itemId == nil or ns.IsSecret(itemId) then
    return
  end

  AddCreatedBy(tooltip, itemId)

  local isFolded = AddUsedIn(tooltip, itemId)
  isFolded = AddQuestRewards(tooltip, itemId) or isFolded
  isFolded = AddSoldBy(tooltip, itemId) or isFolded
  isFolded = AddDroppedBy(tooltip, itemId) or isFolded

  -- The click that opens the item in the window, under what was added
  local hint = ns.Lookup:GetHint()
  if hint ~= nil and HasInfo(itemId) then
    tooltip:AddLine(' ')
    tooltip:AddLine(GRAY .. hint .. '|r')
  end

  if isFolded and tooltip == GameTooltip then
    self.folded = { owner = tooltip:GetOwner(), itemId = itemId }
  end
end

-- A displayed tooltip does not rebuild by itself, so when Shift is pressed it
-- is asked to fetch its data again, which unfolds the lists.
--
-- The frame that owns the tooltip is never asked to show it again by calling
-- its OnEnter script: for an action button, that taints it, and the game then
-- blocks the button's next use (a macro's /use, say) and blames ItemInfo.
function Tooltip:_OnModifier(key)
  if key ~= 'LSHIFT' and key ~= 'RSHIFT' then
    return
  end

  local fold = self.folded or self.unfolded
  if fold == nil then
    return
  end

  if InCombatLockdown() or not GameTooltip:IsShown() or not GameTooltip.RefreshData then
    self.unfolded = nil
    return
  end

  -- Only the tooltip that was folded, still showing the same item
  local _, link = GameTooltip:GetItem()
  local itemId = link ~= nil and not ns.IsSecret(link) and tonumber(link:match('item:(%d+)')) or nil

  if GameTooltip:GetOwner() ~= fold.owner or itemId ~= fold.itemId then
    self.folded, self.unfolded = nil, nil
    return
  end

  -- The list folds again once the key is released
  self.unfolded = IsShiftKeyDown() and fold or nil
  pcall(GameTooltip.RefreshData, GameTooltip)
end

function Tooltip:Init(saved)
  saved.tooltip = saved.tooltip or { enabled = true }
  self.options = saved.tooltip

  local function OnItem(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= _G.ItemRefTooltip then
      return
    end

    local itemId = type(data) == 'table' and data.id or nil

    if itemId == nil and tooltip.GetItem then
      local _, link = tooltip:GetItem()
      itemId = link and tonumber(link:match('item:(%d+)'))
    end

    -- A failure here must never break the game's tooltips
    local success, message = pcall(self._OnItem, self, tooltip, itemId)
    if not success then
      geterrorhandler()(message)
    end
  end

  -- The modern client builds tooltips from data, the legacy script hook is
  -- only there for clients without it
  if _G.TooltipDataProcessor and _G.Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
  else
    pcall(GameTooltip.HookScript, GameTooltip, 'OnTooltipSetItem', OnItem)
  end

  ns.On('MODIFIER_STATE_CHANGED', function(key)
    self:_OnModifier(key)
  end)

  GameTooltip:HookScript('OnHide', function()
    self.folded, self.unfolded = nil, nil
  end)
end

-- Turns the tooltip information on or off, returns whether it's on
function Tooltip:Toggle()
  self.options.enabled = not self.options.enabled
  return self.options.enabled
end
