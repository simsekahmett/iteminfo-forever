local _, ns = ...

-- The items a character is after, and the alerts that help find them:
--   - targeting a creature that drops one of them,
--   - opening a vendor that sells one of them,
--   - one of them entering the bags, which also takes it off the list.
--
-- The list belongs to the character, each one has goals of its own.

local L = ns.L
local DB = ns.DB

local Wishlist = {}
ns.Wishlist = Wishlist

Wishlist.STAR = '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t'

-- A creature is announced once in this many seconds, retargeting is common
local alertInterval = 300

local function GetItemCount(itemId)
  local getCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
  return getCount and getCount(itemId) or 0
end

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

function Wishlist:GetCount()
  local count = 0

  for _ in pairs(self.items) do
    count = count + 1
  end

  return count
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
end
