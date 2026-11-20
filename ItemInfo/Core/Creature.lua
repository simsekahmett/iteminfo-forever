local _, ns = ...

-- What a creature drops: the reverse of the drop data, which lists the
-- creatures of an item. A creature may drop over a hundred items, so they are
-- ranked to tell the few worth showing from the rest:
--   - items on the wishlist first, always,
--   - items few other creatures drop, which are this creature's own loot,
--   - better quality,
--   - recipes of the player's professions, armor the player can wear.
--
-- Poor and common items are not notable unless they are recipes, they only
-- appear in the full list of the window.

local Data = ns.Data
local DB = ns.DB
local Scanner = ns.Scanner

local Creature = {}
ns.Creature = Creature

local RECIPE_CLASS, ARMOR_CLASS = 9, 4

-- The heaviest armor each class wears: cloth 1, leather 2, mail 3, plate 4
local armorOf = {
  WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
  HUNTER = 3, SHAMAN = 3,
  ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
  MAGE = 1, PRIEST = 1, WARLOCK = 1,
}

-- Builds the index on first use, it's only needed once a creature is seen
function Creature:_Index()
  if self.drops ~= nil then
    return self.drops
  end

  local drops = {}

  for itemId, entry in pairs(Data.drops) do
    for index = 2, #entry do
      local npcId = entry[index]
      local list = drops[npcId]

      if list == nil then
        list = {}
        drops[npcId] = list
      end

      list[#list + 1] = itemId
    end
  end

  for _, list in pairs(drops) do
    table.sort(list)
  end

  self.drops = drops
  return drops
end

-- Returns the creature ID of a GUID, nil for players, pets and objects
function Creature:GetNpcId(guid)
  if type(guid) ~= 'string' or ns.IsSecret(guid) then
    return nil
  end

  local unitType, _, _, _, _, npcId = strsplit('-', guid)
  if unitType ~= 'Creature' and unitType ~= 'Vehicle' then
    return nil
  end

  return tonumber(npcId)
end

-- Returns the creature ID of a unit, 'target' or 'mouseover' say
function Creature:GetUnitNpcId(unit)
  return self:GetNpcId(UnitGUID(unit))
end

-- Returns every item a creature drops, sorted by ID
function Creature:GetDrops(npcId)
  return npcId ~= nil and self:_Index()[npcId] or nil
end

-- Returns the professions the player knows, by the IDs of the recipe data
function Creature:_GetProfessions()
  local now = GetTime()

  if self.professions ~= nil and now - self.professionsAt < 10 then
    return self.professions
  end

  local known, names = {}, {}

  for _, profession in ipairs(DB:GetProfessions()) do
    names[DB:GetProfessionName(profession)] = profession
  end

  if _G.GetNumSkillLines and _G.GetSkillLineInfo then
    pcall(function()
      for index = 1, GetNumSkillLines() do
        local name, isHeader = GetSkillLineInfo(index)

        if not isHeader and name ~= nil and names[name] ~= nil then
          known[names[name]] = true
        end
      end
    end)
  end

  self.professions, self.professionsAt = known, now
  return known
end

-- Returns an item's quality, nil while the client doesn't know it
local function GetQuality(itemId)
  local quality = Scanner:GetQuality(itemId)

  if quality == nil then
    quality = select(3, ns.GetItemInfo(itemId))
  end

  return quality
end

-- Returns how worth showing an item is, nil if it isn't notable
function Creature:_Score(itemId, total)
  local isWanted = ns.Wishlist:Has(itemId)
  local quality = GetQuality(itemId)
  local _, _, _, _, _, classId, subClassId = ns.GetItemInfoInstant(itemId)
  local isRecipe = classId == RECIPE_CLASS

  if not isWanted and not isRecipe and (quality or 0) < 2 then
    return nil
  end

  local score = (quality or 1) * 2

  if isWanted then
    score = score + 1000
  end

  -- An item few creatures drop belongs to this one
  if total <= 1 then
    score = score + 6
  elseif total <= 3 then
    score = score + 4
  elseif total <= 8 then
    score = score + 2
  end

  if isRecipe then
    local spellId = DB:GetTaughtSpell(itemId)
    local profession = spellId and DB:GetSpell(spellId)

    if profession ~= nil and self:_GetProfessions()[profession] then
      score = score + 5
    end
  elseif classId == ARMOR_CLASS and subClassId ~= nil and subClassId >= 1 and subClassId <= 4 then
    local _, class = UnitClass('player')
    local heaviest = armorOf[class or '']

    if heaviest ~= nil and subClassId > heaviest then
      score = score - 8
    end
  end

  return score
end

-- Returns the notable items a creature drops, the most worth showing first,
-- and the number of items it drops in all
function Creature:GetNotable(npcId)
  local drops = self:GetDrops(npcId)

  if drops == nil then
    return nil, 0
  end

  local notable, scores = {}, {}

  for _, itemId in ipairs(drops) do
    local score = self:_Score(itemId, Data.drops[itemId][1])

    if score ~= nil then
      notable[#notable + 1] = itemId
      scores[itemId] = score
    end
  end

  table.sort(notable, function(a, b)
    if scores[a] ~= scores[b] then
      return scores[a] > scores[b]
    end

    return a < b
  end)

  return notable, #drops
end

-- Returns every item a creature drops: the notable ones in their order, then
-- the rest by quality and name. Used by the window.
function Creature:GetRanked(npcId)
  local drops = self:GetDrops(npcId)

  if drops == nil then
    return {}
  end

  local ranked = self:GetNotable(npcId)
  local seen, rest = {}, {}

  for _, itemId in ipairs(ranked) do
    seen[itemId] = true
  end

  for _, itemId in ipairs(drops) do
    if not seen[itemId] then
      rest[#rest + 1] = itemId
    end
  end

  table.sort(rest, function(a, b)
    local qualityA, qualityB = GetQuality(a) or 0, GetQuality(b) or 0

    if qualityA ~= qualityB then
      return qualityA > qualityB
    end

    local nameA, nameB = DB:GetLowerName(a), DB:GetLowerName(b)
    if nameA ~= nameB then
      return nameA < nameB
    end

    return a < b
  end)

  for _, itemId in ipairs(rest) do
    ranked[#ranked + 1] = itemId
  end

  return ranked
end

-- Returns the items on the wishlist that a creature drops
function Creature:GetWanted(npcId)
  local drops = self:GetDrops(npcId)
  local wanted = {}

  if drops ~= nil then
    for _, itemId in ipairs(drops) do
      if ns.Wishlist:Has(itemId) then
        wanted[#wanted + 1] = itemId
      end
    end
  end

  return wanted
end
