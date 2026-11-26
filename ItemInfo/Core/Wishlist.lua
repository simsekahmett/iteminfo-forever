local _, ns = ...

-- The items a character is after, and the alerts that help find them:
--   - targeting a creature that drops one of them,
--   - opening a vendor that sells one of them,
--   - one of them entering the bags, which also takes it off the list,
--   - a reagent of one that is crafted entering the bags.
--
-- The list belongs to the character, each one has goals of its own.

local L = ns.L
local DB = ns.DB

local Wishlist = {}
ns.Wishlist = Wishlist

Wishlist.STAR = '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t'

-- A creature is announced once in this many seconds, retargeting is common
local alertInterval = 300

local function GetItemCount(itemId, includeBank)
  local getCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
  return getCount and getCount(itemId, includeBank) or 0
end

local GREEN = '|cff40c040'
local ORANGE = '|cffff8040'

local function PlayAlert()
  if _G.PlaySound and _G.SOUNDKIT and SOUNDKIT.MAP_PING then
    pcall(PlaySound, SOUNDKIT.MAP_PING)
  end
end

-- Returns an item's link, which can be hovered in the chat, or its name
-- while the client doesn't know the item
local function GetLink(itemId)
  local _, link = ns.GetItemInfo(itemId)
  return link or DB:GetColoredName(itemId)
end

local function JoinNames(itemIds)
  local names = {}

  for index, itemId in ipairs(itemIds) do
    names[index] = DB:GetColoredName(itemId)
  end

  return table.concat(names, ', ')
end

function Wishlist:Has(itemId)
  return self.items ~= nil and self.items[itemId] ~= nil
end

-- Adds an item, how many of it the bags hold is remembered so that getting
-- another one counts, even if the character already has some
function Wishlist:Add(itemId)
  if itemId == nil or itemId <= 0 or self:Has(itemId) then
    return
  end

  self.items[itemId] = { added = time(), count = GetItemCount(itemId) }

  -- What the bags hold of its reagents already is not news
  if self.reagentCounts ~= nil then
    for reagentId in pairs(self:GetReagents()) do
      self.reagentCounts[reagentId] = GetItemCount(reagentId, true)
    end
  end
  ns.Print(self.STAR .. ' ' .. L['%s added to your wishlist.']:format(GetLink(itemId)))
end

function Wishlist:Remove(itemId)
  if not self:Has(itemId) then
    return
  end

  self.items[itemId] = nil
  ns.Print(L['%s removed from your wishlist.']:format(GetLink(itemId)))
end

-- Adds or removes an item, returns whether it's on the list
function Wishlist:Toggle(itemId)
  if self:Has(itemId) then
    self:Remove(itemId)
    return false
  end

  self:Add(itemId)
  return true
end

-- Returns the items on the list, the latest added first
function Wishlist:GetItems()
  local list = {}

  for itemId in pairs(self.items) do
    list[#list + 1] = itemId
  end

  table.sort(list, function(a, b)
    local addedA, addedB = self.items[a].added or 0, self.items[b].added or 0

    if addedA ~= addedB then
      return addedA > addedB
    end

    return a < b
  end)

  return list
end

-- Returns the zones where an item can be got: those of its vendors, of the
-- creatures that drop it and of the quests that reward it, each once
function Wishlist:GetZones(itemId)
  local zones, seen = {}, {}

  local function Add(zone)
    if zone ~= nil and zone ~= '' and not seen[zone] then
      seen[zone] = true
      zones[#zones + 1] = zone
    end
  end

  for _, npcId in ipairs(DB:GetUsableVendors(itemId) or {}) do
    Add((select(2, DB:GetNpc(npcId))))
  end

  for _, npcId in ipairs((DB:GetDrops(itemId)) or {}) do
    Add((select(2, DB:GetNpc(npcId))))
  end

  for _, questId in ipairs(DB:GetUsableQuestRewards(itemId) or {}) do
    Add((select(5, DB:GetQuest(questId))))
  end

  return zones
end

-- Groups items by where they can be got: { title, items, isHere }. An item
-- is listed under each of its zones, the player's zone first, then the
-- zones with the most items. Then come the crafted items, the world drops
-- and those of no known source.
function Wishlist:GroupByZone(itemIds)
  local byZone, zones = {}, {}
  local crafted, worldDrops, other = {}, {}, {}
  local here = GetRealZoneText and GetRealZoneText() or nil

  for _, itemId in ipairs(itemIds) do
    local itemZones = self:GetZones(itemId)

    for _, zone in ipairs(itemZones) do
      if byZone[zone] == nil then
        byZone[zone] = { title = zone, items = {}, isHere = zone == here }
        zones[#zones + 1] = byZone[zone]
      end

      table.insert(byZone[zone].items, itemId)
    end

    local drops = DB:GetDrops(itemId)
    local isCrafted = DB:GetCreatedBy(itemId) ~= nil
    local isWorldDrop = drops ~= nil and #drops == 0

    if isCrafted then
      crafted[#crafted + 1] = itemId
    end
    if isWorldDrop then
      worldDrops[#worldDrops + 1] = itemId
    end
    if #itemZones == 0 and not isCrafted and not isWorldDrop then
      other[#other + 1] = itemId
    end
  end

  table.sort(zones, function(a, b)
    if a.isHere ~= b.isHere then
      return a.isHere
    end
    if #a.items ~= #b.items then
      return #a.items > #b.items
    end

    return a.title < b.title
  end)

  for _, group in ipairs({
    { title = L['Crafted'], items = crafted },
    { title = L['World drop'], items = worldDrops },
    { title = L['Other sources'], items = other },
  }) do
    if #group.items > 0 then
      zones[#zones + 1] = group
    end
  end

  return zones
end

function Wishlist:GetCount()
  local count = 0

  for _ in pairs(self.items) do
    count = count + 1
  end

  return count
end

------------------------------------------
-- Reagents
------------------------------------------

-- Returns the spell that makes an item, the one of the player's professions
-- if there are several
local function GetCraft(itemId)
  local createdBy = DB:GetCreatedBy(itemId)

  if createdBy == nil then
    return nil
  end

  for _, spellId in ipairs(createdBy) do
    local status = ns.Professions and ns.Professions:GetStatus(spellId)

    if status ~= nil and status ~= 'none' then
      return spellId
    end
  end

  return createdBy[1]
end

-- Returns the reagents the crafted items on the list need:
-- reagentId -> { { itemId = wanted item, count = needed }, ... }
function Wishlist:GetReagents()
  local reagents = {}

  for _, itemId in ipairs(self:GetItems()) do
    local spellId = GetCraft(itemId)

    if spellId ~= nil then
      local _, _, _, _, list = DB:GetSpell(spellId)

      for index = 1, #list, 2 do
        local reagentId = list[index]
        reagents[reagentId] = reagents[reagentId] or {}
        table.insert(reagents[reagentId], { itemId = itemId, count = list[index + 1] })
      end
    end
  end

  return reagents
end

-- Returns the items on the list a reagent is needed for, how many each
-- needs, and how many the character has, the bank included
function Wishlist:GetNeeds(reagentId)
  local needs = self:GetReagents()[reagentId]

  if needs == nil then
    return nil
  end

  return needs, self:CountOf(reagentId)
end

-- Returns how many of an item the character has, the bank included
function Wishlist:CountOf(itemId)
  return GetItemCount(itemId, true)
end

-- Returns how many of a reagent the character has, out of how many, as text
function Wishlist:FormatProgress(have, need)
  local color = have >= need and GREEN or ORANGE
  return color .. math.min(have, need) .. '/' .. need .. '|r'
end

-- Tells about reagents of the crafted items on the list that entered the
-- bags: how many there are now, and when an item has every reagent
function Wishlist:_OnReagents()
  local reagents = self:GetReagents()
  local counts = self.reagentCounts
  local isFirst = counts == nil

  counts = counts or {}
  self.reagentCounts = counts

  local gained = {}

  for reagentId in pairs(reagents) do
    local count = GetItemCount(reagentId, true)
    local before = counts[reagentId]
    counts[reagentId] = count

    -- The bags are only known after the first update, nothing is new then
    if not isFirst and before ~= nil and count > before then
      gained[reagentId] = before
    end
  end

  if next(gained) == nil or not self.options.enabled then
    return
  end

  -- The reagents that were short, in the order of the list
  local reported, completed = {}, {}

  for _, itemId in ipairs(self:GetItems()) do
    local spellId = GetCraft(itemId)
    local isGaining, wasComplete, isComplete = false, true, true

    if spellId ~= nil then
      local _, _, _, _, list = DB:GetSpell(spellId)

      for index = 1, #list, 2 do
        local reagentId, need = list[index], list[index + 1]
        local count = counts[reagentId] or 0
        local before = gained[reagentId] or count

        wasComplete = wasComplete and before >= need
        isComplete = isComplete and count >= need

        if gained[reagentId] ~= nil and before < need and not reported[reagentId .. ':' .. itemId] then
          reported[reagentId .. ':' .. itemId] = true
          isGaining = true
          ns.Print(self.STAR .. ' ' .. L['%s %s for %s']:format(
                     GetLink(reagentId), self:FormatProgress(count, need), DB:GetColoredName(itemId)))
        end
      end

      if isGaining and isComplete and not wasComplete then
        completed[#completed + 1] = itemId
      end
    end
  end

  for _, itemId in ipairs(completed) do
    ns.Print(self.STAR .. ' ' .. L['You have every reagent for %s.']:format(GetLink(itemId)))
  end

  if #completed > 0 then
    PlayAlert()
  end
end

-- Turns the alerts on or off, returns whether they're on
function Wishlist:ToggleAlerts()
  self.options.enabled = not self.options.enabled
  return self.options.enabled
end

------------------------------------------
-- Alerts
------------------------------------------

function Wishlist:_OnTarget()
  if not self.options.enabled or next(self.items) == nil then
    return
  end

  local npcId = ns.Creature:GetUnitNpcId('target')
  if npcId == nil then
    return
  end

  local now = GetTime()
  if self.alerted[npcId] ~= nil and now - self.alerted[npcId] < alertInterval then
    return
  end

  local wanted = ns.Creature:GetWanted(npcId)
  if #wanted == 0 then
    return
  end

  self.alerted[npcId] = now
  ns.Print(self.STAR .. ' ' .. L['%s drops from your wishlist: %s']:format(
             UnitName('target') or DB:GetNpc(npcId), JoinNames(wanted)))
  PlayAlert()
end

function Wishlist:_OnMerchant()
  if not self.options.enabled or next(self.items) == nil then
    return
  end

  local wanted = {}

  for index = 1, GetMerchantNumItems() do
    local itemId = GetMerchantItemID(index)

    if itemId ~= nil and self:Has(itemId) then
      wanted[#wanted + 1] = itemId
    end
  end

  if #wanted > 0 then
    ns.Print(self.STAR .. ' ' .. L['This vendor sells from your wishlist: %s']:format(JoinNames(wanted)))
    PlayAlert()
  end
end

-- An item is obtained once the bags hold more of it than when it was added
function Wishlist:_OnBags()
  for itemId, entry in pairs(self.items) do
    local count = GetItemCount(itemId)

    if count > (entry.count or 0) then
      self.items[itemId] = nil
      ns.Print(self.STAR .. ' ' .. L['Obtained %s, it is off your wishlist.']:format(DB:GetColoredName(itemId)))

      if ns.UI.OnWishlistChanged then
        ns.UI:OnWishlistChanged()
      end
    elseif count < (entry.count or 0) then
      -- Some were sold or used, the next one counts again
      entry.count = count
    end
  end
end

function Wishlist:Init(saved)
  saved.wishlist = saved.wishlist or {}
  saved.alerts = saved.alerts or { enabled = true }
  self.items = saved.wishlist
  self.options = saved.alerts
  self.alerted = {}

  -- A second login, as the tests run, must not alert twice
  if self.isHooked then
    return
  end
  self.isHooked = true

  local function Safely(method)
    return function()
      local success, message = pcall(method, self)
      if not success then
        geterrorhandler()(message)
      end
    end
  end

  ns.On('PLAYER_TARGET_CHANGED', Safely(self._OnTarget))
  ns.On('MERCHANT_SHOW', Safely(self._OnMerchant))
  ns.On('BAG_UPDATE_DELAYED', Safely(self._OnBags))
  ns.On('BAG_UPDATE_DELAYED', Safely(self._OnReagents))
end
