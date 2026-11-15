local _, ns = ...

-- Records what vendors sell, and for how much, whenever one is visited. The
-- static data knows who sells an item but not its price.

local Merchant = {}
ns.Merchant = Merchant

local function GetNpcId()
  local guid = UnitGUID('npc')

  if guid == nil or ns.IsSecret(guid) then
    return nil
  end

  local unitType, _, _, _, _, npcId = strsplit('-', guid)
  if unitType ~= 'Creature' and unitType ~= 'Vehicle' then
    return nil
  end

  return tonumber(npcId)
end

local function GetItemPrice(index)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(index)
    return info and info.price, info and info.stackCount
  end

  local _, _, price, stackCount = GetMerchantItemInfo(index)
  return price, stackCount
end

local function Record(saved)
  local npcId = GetNpcId()

  if npcId == nil then
    return
  end

  local merchant = saved.merchants[npcId] or {}
  saved.merchants[npcId] = merchant
  merchant.name = UnitName('npc') or merchant.name

  -- The zone and position are only kept for vendors the static data lacks
  if ns.Data.npcs[npcId] == nil then
    merchant.zone = GetRealZoneText()

    local map = C_Map.GetBestMapForUnit('player')
    local position = map and C_Map.GetPlayerMapPosition(map, 'player')
    if position ~= nil then
      local x, y = position:GetXY()
      merchant.x, merchant.y = math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
    end
  end

  for index = 1, GetMerchantNumItems() do
    local itemId = GetMerchantItemID(index)
    local price, stackCount = GetItemPrice(index)

    if itemId ~= nil and price ~= nil and not ns.IsSecret(price) then
      saved.soldBy[itemId] = saved.soldBy[itemId] or {}
      -- The price is per purchase, which may be a stack
      saved.soldBy[itemId][npcId] = math.floor(price / math.max(1, stackCount or 1) + 0.5)
    end
  end
end

function Merchant:Init(saved)
  ns.On('MERCHANT_SHOW', function()
    -- The merchant API differs between clients, a failure must not surface
    pcall(Record, saved)
  end)
end
