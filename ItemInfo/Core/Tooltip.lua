local _, ns = ...

-- Adds information to item tooltips anywhere in the game: how the item is
-- made, where its recipe comes from, what it is used to make, which quests
-- reward it, who sells it and what drops it.
--
-- Creature tooltips gain the few items worth knowing that the creature drops.

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
-- The number of scrolls listed before the rest is folded away
local scrollLimit = 5
local scrollLimitExpanded = 15
-- The number of guild members listed, and how many on a line
local guildLimit = 4
local guildLimitExpanded = 20
local guildPerLine = 4
-- The number of a creature's drops listed, items on the wishlist aside
local creatureLimit = 3
local creatureLimitExpanded = 15

-- What creature tooltips show: the notable drops, only those on the
-- wishlist, or nothing
Tooltip.CREATURE_MODES = { 'all', 'wishlist', 'off' }

local function FormatSkill(profession, skill)
  return string.format('%s (%d)', DB:GetProfessionName(profession), skill)
end

-- Returns a character's name in the color of its class
local function ClassColored(name, class)
  local color = _G.RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]

  if color ~= nil and color.colorStr ~= nil then
    return '|c' .. color.colorStr .. name .. '|r'
  end

  return name
end

-- Adds the members of the guild who know a spell, those online in the color
-- of their class, the others in gray. Returns whether some were hidden.
local function AddGuildCrafters(tooltip, spellId, title)
  local crafters = ns.Guild:GetCrafters(spellId)

  if #crafters == 0 then
    return false
  end

  local limit = IsShiftKeyDown() and guildLimitExpanded or guildLimit
  local names = {}

  for index = 1, math.min(#crafters, limit) do
    local crafter = crafters[index]
    names[#names + 1] = crafter.online and ClassColored(crafter.name, crafter.class)
      or GRAY .. crafter.name .. '|r'
  end

  local rest = #crafters - #names
  if rest > 0 then
    names[#names + 1] = GRAY .. '+' .. rest .. '|r'
  end

  for first = 1, #names, guildPerLine do
    local line = table.concat(names, ', ', first, math.min(#names, first + guildPerLine - 1))

    if first == 1 then
      line = title .. ': ' .. line
    end

    tooltip:AddLine('  ' .. line, 1, 1, 1)
  end

  return rest > 0 and limit == guildLimit
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

  local vendors = DB:GetUsableVendors(recipe)
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

-- Returns whether some guild members were hidden
local function AddCreatedBy(tooltip, itemId)
  local createdBy = DB:GetCreatedBy(itemId)
  local isFolded = false

  if createdBy == nil then
    return false
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
    isFolded = AddGuildCrafters(tooltip, spellId, L['Made in your guild by']) or isFolded
  end

  return isFolded
end

-- Adds a list of NPCs under a title, those in the player's zone first, the
-- nearest of them first. Returns whether some were hidden.
local function AddNpcList(tooltip, title, npcs, prices, itemId)
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
    local rate = itemId and DB:GetDropRate(itemId, npcId)

    if price ~= nil then
      tooltip:AddDoubleLine(text, ns.FormatMoney(price), 1, 1, 1, 1, 1, 1)
    elseif rate ~= nil then
      tooltip:AddDoubleLine(text, DB:FormatDropRate(rate), 1, 1, 1, 1, 1, 1)
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
  local vendors = DB:GetUsableVendors(itemId)

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

  return AddNpcList(tooltip, L['Dropped by'], drops, nil, itemId)
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

-- Adds the quests that ask for an item, those in the quest log first,
-- returns whether some were hidden
local function AddQuestObjectives(tooltip, itemId)
  local quests = DB:GetUsableQuestObjectives(itemId)

  if quests == nil then
    return false
  end

  local limit = IsShiftKeyDown() and questLimitExpanded or questLimit

  tooltip:AddLine(' ')
  tooltip:AddLine(GOLD .. L['Needed for a quest'] .. ' (' .. #quests .. ')|r')

  for index = 1, math.min(#quests, limit) do
    local questId = quests[index]
    local _, _, _, _, zone = DB:GetQuest(questId)
    local right = zone or ''

    if DB:IsOnQuest(questId) then
      right = '|cff40c040' .. L['In your quest log'] .. '|r'
    end

    tooltip:AddDoubleLine('  ' .. DB:GetColoredQuestName(questId), right, 1, 1, 1, 0.6, 0.6, 0.6)
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

-- Adds a list of scrolls under a title, returns whether some were hidden
local function AddScrollList(tooltip, title, scrolls)
  if scrolls == nil then
    return false
  end

  local limit = IsShiftKeyDown() and scrollLimitExpanded or scrollLimit

  tooltip:AddLine(' ')
  tooltip:AddLine(GOLD .. title .. ' (' .. #scrolls .. ')|r')

  for index = 1, math.min(#scrolls, limit) do
    local icon = DB:GetIcon(scrolls[index])
    local iconText = icon and string.format('|T%s:0|t ', icon) or ''

    tooltip:AddLine('  ' .. iconText .. DB:GetColoredName(scrolls[index]), 1, 1, 1)
  end

  if #scrolls > limit then
    tooltip:AddLine('  ' .. GRAY .. L['Hold Shift for %d more']:format(#scrolls - limit) .. '|r')
    return true
  end

  return false
end

-- Adds what a mage may decipher an item into, or from, returns whether some
-- were hidden
local function AddDeciphered(tooltip, itemId)
  local isFolded = AddScrollList(tooltip, L['May be deciphered into one of'], DB:GetDecipheredInto(itemId))
  return AddScrollList(tooltip, L['May be deciphered from'], DB:GetDecipheredFrom(itemId)) or isFolded
end

-- The colors of where a character stands with a recipe
local STATUS_COLORS = {
  known = GRAY,
  learnable = '|cff40c040',
  later = '|cffff8040',
  none = GRAY,
}

-- Adds whether the player and their other characters know the recipe an
-- item teaches, or can learn it, and who knows it in the guild. Returns
-- whether some guild members were hidden.
local function AddRecipeStatus(tooltip, itemId)
  local spellId = DB:GetTaughtSpell(itemId)
  local Professions = ns.Professions
  if spellId == nil then
    return false
  end

  local status, skill, required = Professions:GetStatus(spellId)
  if status == nil then
    return false
  end

  local profession = DB:GetProfessionName((DB:GetSpell(spellId)))
  local text

  if status == 'known' then
    text = L['You already know this recipe']
  elseif status == 'learnable' then
    text = L['You can learn this recipe']
  elseif status == 'later' then
    text = L['You can learn this recipe at %s %d (you have %d)']:format(profession, required, skill)
  else
    text = L['Not one of your professions (%s %d)']:format(profession, required)
  end

  tooltip:AddLine(' ')
  tooltip:AddLine(STATUS_COLORS[status] .. text .. '|r')

  for _, alt in ipairs(Professions:GetAlts(spellId)) do
    local line

    if alt.status == 'known' then
      line = L['%s knows it']:format(ClassColored(alt.name, alt.class))
    elseif alt.status == 'learnable' then
      line = L['%s can learn it']:format(ClassColored(alt.name, alt.class))
    else
      line = L['%s can learn it at %d (has %d)']:format(ClassColored(alt.name, alt.class), required, alt.skill)
    end

    tooltip:AddLine('  ' .. STATUS_COLORS[alt.status] .. line .. '|r')
  end

  return AddGuildCrafters(tooltip, spellId, L['Known in your guild by'])
end

-- Adds whether an item is on the wishlist, or a reagent of one on it
local function AddWishlist(tooltip, itemId)
  local Wishlist = ns.Wishlist
  local isWanted = Wishlist:Has(itemId)
  local needs, have = Wishlist:GetNeeds(itemId)

  if not isWanted and needs == nil then
    return
  end

  tooltip:AddLine(' ')

  if isWanted then
    tooltip:AddLine(Wishlist.STAR .. ' ' .. GOLD .. L['On your wishlist'] .. '|r')
  end

  for _, need in ipairs(needs or {}) do
    tooltip:AddLine(Wishlist.STAR .. ' ' .. L['Wanted for %s: %s']:format(
                      DB:GetColoredName(need.itemId), Wishlist:FormatProgress(have, need.count)), 1, 1, 1)
  end
end

-- Returns whether ItemInfo adds anything to the tooltip of an item
local function HasInfo(itemId)
  return DB:GetCreatedBy(itemId) ~= nil or DB:GetUsedIn(itemId) ~= nil
    or DB:GetUsableQuestRewards(itemId) ~= nil or DB:GetQuestObjectives(itemId) ~= nil
    or DB:GetVendors(itemId) ~= nil
    or DB:GetDrops(itemId) ~= nil
    or DB:GetDecipheredInto(itemId) ~= nil or DB:GetDecipheredFrom(itemId) ~= nil
end

------------------------------------------
-- Hooks
------------------------------------------

function Tooltip:_OnItem(tooltip, itemId)
  self.folded = nil

  if not self.options.enabled or itemId == nil or ns.IsSecret(itemId) then
    return
  end

  local isFolded = AddRecipeStatus(tooltip, itemId)
  isFolded = AddCreatedBy(tooltip, itemId) or isFolded
  isFolded = AddQuestObjectives(tooltip, itemId) or isFolded
  isFolded = AddDeciphered(tooltip, itemId) or isFolded
  isFolded = AddUsedIn(tooltip, itemId) or isFolded
  isFolded = AddQuestRewards(tooltip, itemId) or isFolded
  isFolded = AddSoldBy(tooltip, itemId) or isFolded
  isFolded = AddDroppedBy(tooltip, itemId) or isFolded

  AddWishlist(tooltip, itemId)

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

-- Adds the notable items a creature drops, returns whether some were hidden
function Tooltip:_OnUnit(tooltip, npcId)
  local mode = self.options.creature

  if not self.options.enabled or mode == 'off' or npcId == nil then
    return false
  end

  local notable, total = ns.Creature:GetNotable(npcId)
  if notable == nil or #notable == 0 then
    return false
  end

  local Wishlist = ns.Wishlist
  local limit = IsShiftKeyDown() and creatureLimitExpanded or creatureLimit
  local shown, others = {}, 0

  -- Items on the wishlist are always listed, on top of the limit
  for _, itemId in ipairs(notable) do
    if Wishlist:Has(itemId) then
      shown[#shown + 1] = itemId
    elseif mode == 'all' and others < limit then
      shown[#shown + 1] = itemId
      others = others + 1
    end
  end

  if #shown == 0 then
    return false
  end

  tooltip:AddLine(' ')
  tooltip:AddLine(GOLD .. L['Drops'] .. ' (' .. total .. ')|r')

  for _, itemId in ipairs(shown) do
    local prefix = Wishlist:Has(itemId) and Wishlist.STAR .. ' ' or ''
    local _, _, _, _, icon = ns.GetItemInfoInstant(itemId)
    local iconText = icon and string.format('|T%s:0|t ', icon) or ''

    local rate = DB:GetDropRate(itemId, npcId)

    if rate ~= nil then
      tooltip:AddDoubleLine('  ' .. prefix .. iconText .. DB:GetColoredName(itemId),
                            DB:FormatDropRate(rate), 1, 1, 1, 1, 1, 1)
    else
      tooltip:AddLine('  ' .. prefix .. iconText .. DB:GetColoredName(itemId), 1, 1, 1)
    end
  end

  if mode ~= 'all' then
    return false
  end

  local hidden = #notable - #shown

  if hidden > 0 and limit == creatureLimit then
    tooltip:AddLine('  ' .. GRAY .. L['Hold Shift for %d more']:format(hidden) .. '|r')
  elseif hidden > 0 then
    tooltip:AddLine('  ' .. GRAY .. '+' .. hidden .. '|r')
  end

  local key = _G.GetBindingKey and GetBindingKey('ITEMINFO_LOOKUP')
  if key ~= nil and total > #shown then
    tooltip:AddLine('  ' .. GRAY .. L['%s: every drop in ItemInfo']:format(key) .. '|r')
  end

  return hidden > 0 and limit == creatureLimit
end

-- Returns the creature ID of the unit a tooltip shows
local function GetTooltipNpcId(tooltip, data)
  local guid = type(data) == 'table' and data.guid or nil

  if guid == nil and tooltip.GetUnit then
    local _, unit = tooltip:GetUnit()
    guid = unit ~= nil and not ns.IsSecret(unit) and UnitGUID(unit) or nil
  end

  return ns.Creature:GetNpcId(guid)
end

-- Returns what the game tooltip shows now, as its fold would record it
local function GetShown()
  local _, link = GameTooltip:GetItem()
  local itemId = link ~= nil and not ns.IsSecret(link) and tonumber(link:match('item:(%d+)')) or nil

  if itemId ~= nil then
    return itemId, nil
  end

  return nil, GetTooltipNpcId(GameTooltip)
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

  -- Only the tooltip that was folded, still showing the same item or creature
  local itemId, npcId = GetShown()

  if GameTooltip:GetOwner() ~= fold.owner or itemId ~= fold.itemId or npcId ~= fold.npcId then
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
  self.options.creature = self.options.creature or 'all'

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
  local function OnUnit(tooltip, data)
    if tooltip ~= GameTooltip then
      return
    end

    -- An item tooltip's fold must not survive into a creature's
    self.folded = nil

    local success, message = pcall(function()
      local npcId = GetTooltipNpcId(tooltip, data)

      if self:_OnUnit(tooltip, npcId) then
        self.folded = { owner = tooltip:GetOwner(), npcId = npcId }
      end
    end)

    if not success then
      geterrorhandler()(message)
    end
  end

  if _G.TooltipDataProcessor and _G.Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)

    if Enum.TooltipDataType.Unit ~= nil then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
    end
  else
    pcall(GameTooltip.HookScript, GameTooltip, 'OnTooltipSetItem', OnItem)
    pcall(GameTooltip.HookScript, GameTooltip, 'OnTooltipSetUnit', OnUnit)
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

-- Sets what creature tooltips show, returns false for an unknown mode
function Tooltip:SetCreatureMode(mode)
  for _, known in ipairs(self.CREATURE_MODES) do
    if mode == known then
      self.options.creature = mode
      return true
    end
  end

  return false
end

function Tooltip:GetCreatureMode()
  return self.options.creature
end

-- Returns the creature mode as shown in chat
function Tooltip:GetCreatureModeText()
  local texts = { all = L['notable drops'], wishlist = L['wishlist only'], off = L['off'] }
  return texts[self.options.creature]
end
