local _, ns = ...

-- Lookups over the scanned items and the static recipe & source data.
--
-- Entries are referred to by a single number: an item by its ID, and a spell
-- that creates no item (e.g. an enchant) by its negated spell ID.

local Data = ns.Data
local Scanner = ns.Scanner
local GetItemInfo = ns.GetItemInfo
local GetItemInfoInstant = ns.GetItemInfoInstant

local DB = {}
ns.DB = DB

-- Indices of a spell's fields in 'Data.spells'
local ITEM, PROF, SKILL, YELLOW, GREEN, REAGENTS, MADE = 1, 2, 3, 4, 5, 6, 7

-- The profession IDs used by the recipe data, with the spell that names them
local professions = {
  [1] = { spell = 3273, name = 'First Aid' },
  [2] = { spell = 2018, name = 'Blacksmithing' },
  [3] = { spell = 2108, name = 'Leatherworking' },
  [4] = { spell = 2259, name = 'Alchemy' },
  [5] = { spell = 2366, name = 'Herbalism' },
  [6] = { spell = 2550, name = 'Cooking' },
  [7] = { spell = 2575, name = 'Mining' },
  [8] = { spell = 3908, name = 'Tailoring' },
  [9] = { spell = 4036, name = 'Engineering' },
  [10] = { spell = 7411, name = 'Enchanting' },
  [11] = { spell = 7732, name = 'Fishing' },
  [12] = { spell = 8618, name = 'Skinning' },
  [13] = { spell = 2842, name = 'Poisons' },
}

------------------------------------------
-- Setup
------------------------------------------

function DB:Init(saved)
  saved.soldBy = saved.soldBy or {}
  saved.merchants = saved.merchants or {}
  self.saved = saved

  self.createdBy = {} -- itemId -> { spellId, ... }
  self.usedIn = {} -- itemId -> { spellId, ... }
  self.recipesFor = {} -- spellId -> { recipeItemId, ... }
  self.profSpells = {} -- profession -> { spellId, ... } sorted by skill
  self.lowerNames = {}
  self.itemClass = {}
  self.classes = {}
  self.classifiedCount = 0

  local function append(index, key, value)
    local list = index[key]

    if list == nil then
      list = {}
      index[key] = list
    end

    list[#list + 1] = value
  end

  self.decipheredInto = {} -- itemId -> { itemId, ... }
  self.decipheredFrom = {} -- itemId -> { itemId, ... }

  for _, tier in ipairs(Data.scrollTiers or {}) do
    for _, itemId in ipairs(tier.from) do
      self.decipheredInto[itemId] = tier.into
    end
    for _, itemId in ipairs(tier.into) do
      self.decipheredFrom[itemId] = tier.from
    end
  end

  self.recipeCount = 0

  for spellId, spell in pairs(Data.spells) do
    self.recipeCount = self.recipeCount + 1

    if spell[ITEM] ~= 0 then
      append(self.createdBy, spell[ITEM], spellId)
    end

    local reagents = spell[REAGENTS]
    for index = 1, #reagents, 2 do
      append(self.usedIn, reagents[index], spellId)
    end

    append(self.profSpells, spell[PROF], spellId)
  end

  for itemId, spellId in pairs(Data.recipeItems) do
    append(self.recipesFor, spellId, itemId)
  end

  local function bySkill(a, b)
    local skillA, skillB = Data.spells[a][SKILL], Data.spells[b][SKILL]

    if skillA ~= skillB then
      return skillA < skillB
    end

    return a < b
  end

  for _, list in pairs(self.profSpells) do
    table.sort(list, bySkill)
  end
  for _, list in pairs(self.createdBy) do
    table.sort(list, bySkill)
  end
  for _, list in pairs(self.usedIn) do
    table.sort(list, function(a, b)
      local profA, profB = Data.spells[a][PROF], Data.spells[b][PROF]

      if profA ~= profB then
        return profA < profB
      end

      return bySkill(a, b)
    end)
  end
  for _, list in pairs(self.recipesFor) do
    table.sort(list)
  end
end

------------------------------------------
-- Entries
------------------------------------------

-- Returns the reference of what a spell makes
function DB:GetSpellRef(spellId)
  local item = Data.spells[spellId][ITEM]
  return item ~= 0 and item or -spellId
end

function DB:GetName(ref)
  if ref < 0 then
    return ns.GetSpellName(-ref) or ('Spell #' .. -ref)
  end

  return Scanner:GetName(ref) or (GetItemInfo(ref)) or ('Item #' .. ref)
end

-- Returns an entry's name in its quality color
function DB:GetColoredName(ref)
  if ref < 0 then
    return '|cff71d5ff' .. self:GetName(ref) .. '|r'
  end

  local quality = Scanner:GetQuality(ref)
  if quality == nil then
    quality = select(3, GetItemInfo(ref))
  end

  return ns.QualityColor(quality) .. self:GetName(ref) .. '|r'
end

function DB:GetIcon(ref)
  if ref < 0 then
    return ns.GetSpellIcon(-ref)
  end

  return (select(5, GetItemInfoInstant(ref)))
end

function DB:GetLowerName(ref)
  local lowerName = self.lowerNames[ref]

  if lowerName == nil then
    lowerName = ns.Lower(self:GetName(ref))

    -- Only names that are known for certain are kept
    if ref < 0 or Scanner:GetName(ref) ~= nil then
      self.lowerNames[ref] = lowerName
    end
  end

  return lowerName
end

------------------------------------------
-- Professions
------------------------------------------

function DB:GetProfessionName(profession)
  local info = professions[profession]

  if info == nil then
    return UNKNOWN or '?'
  end

  return ns.GetSpellName(info.spell) or info.name
end

function DB:GetProfessionIcon(profession)
  local info = professions[profession]
  return info and ns.GetSpellIcon(info.spell) or nil
end

-- Returns the icons of the professions of a list of spells, as text that can
-- be embedded in a line. Each profession is listed once.
function DB:GetProfessionIcons(spellIds, size)
  local icons, seen = {}, {}

  for index = 1, #spellIds do
    local profession = Data.spells[spellIds[index]][PROF]

    if not seen[profession] then
      seen[profession] = true

      local icon = self:GetProfessionIcon(profession)
      if icon ~= nil then
        icons[#icons + 1] = string.format('|T%s:%d|t', icon, size or 14)
      end
    end
  end

  return table.concat(icons, ' ')
end

-- Returns the number of recipes known, across every profession
function DB:GetRecipeCount()
  return self.recipeCount
end

-- Returns the professions that have recipes, sorted by name
function DB:GetProfessions()
  local list = {}

  for profession in pairs(self.profSpells) do
    list[#list + 1] = profession
  end

  table.sort(list, function(a, b)
    return self:GetProfessionName(a) < self:GetProfessionName(b)
  end)

  return list
end

-- Returns the spells of a profession, sorted by skill
function DB:GetProfessionSpells(profession)
  return self.profSpells[profession]
end

-- Returns a spell's profession, required skill, the skill at which it turns
-- yellow and green (0 if unknown), its reagents and the number of items made
function DB:GetSpell(spellId)
  local spell = Data.spells[spellId]

  if spell == nil then
    return nil
  end

  return spell[PROF], spell[SKILL], spell[YELLOW], spell[GREEN], spell[REAGENTS], spell[MADE] or 1
end

function DB:GetCreatedBy(itemId)
  return self.createdBy[itemId]
end

function DB:GetUsedIn(itemId)
  return self.usedIn[itemId]
end

-- Returns the recipe items that teach a spell
function DB:GetRecipeItems(spellId)
  return self.recipesFor[spellId]
end

-- Returns the spell taught by a recipe item
function DB:GetTaughtSpell(itemId)
  return Data.recipeItems[itemId]
end

-- Returns the scrolls an undeciphered scroll may turn into, any one of them
function DB:GetDecipheredInto(itemId)
  return self.decipheredInto[itemId]
end

-- Returns the undeciphered scrolls that may turn into a scroll
function DB:GetDecipheredFrom(itemId)
  return self.decipheredFrom[itemId]
end

------------------------------------------
-- Sources
------------------------------------------

local function GetZoneName(areaId)
  if areaId ~= nil and areaId > 0 and C_Map and C_Map.GetAreaInfo then
    return C_Map.GetAreaInfo(areaId)
  end
end

-- Returns an NPC's name, zone, coordinates (-1 if unknown) and the factions
-- it's friendly to ('A', 'H' or 'AH')
function DB:GetNpc(npcId)
  local npc = Data.npcs[npcId]
  local seen = self.saved.merchants[npcId]

  if npc == nil then
    if seen == nil then
      return 'NPC #' .. npcId, nil, -1, -1, ''
    end

    return seen.name, seen.zone, seen.x or -1, seen.y or -1, ''
  end

  local name = (Data.npcNames and Data.npcNames[npcId]) or (seen and seen.name) or npc[1]
  return name, GetZoneName(npc[2]), npc[3], npc[4], npc[5]
end

-- Returns the NPCs that sell an item, and the price seen at each of them
function DB:GetVendors(itemId)
  local seen = self.saved.soldBy[itemId]
  local static = Data.vendors[itemId]

  if seen == nil and static == nil then
    return nil
  end

  local vendors, prices, known = {}, seen or {}, {}

  if static ~= nil then
    for index = 1, #static do
      vendors[index] = static[index]
      known[static[index]] = true
    end
  end

  if seen ~= nil then
    for npcId in pairs(seen) do
      if not known[npcId] then
        vendors[#vendors + 1] = npcId
      end
    end
  end

  return vendors, prices
end

-- Returns the price an item was last seen sold for by a vendor
function DB:GetBuyPrice(itemId)
  local seen = self.saved.soldBy[itemId]

  if seen ~= nil then
    local _, price = next(seen)
    return price
  end
end

-- Returns the NPCs known to drop a recipe item, and how many there are in all
function DB:GetDrops(itemId)
  local drops = Data.drops[itemId]

  if drops == nil then
    return nil
  end

  local npcs = {}
  for index = 2, #drops do
    npcs[#npcs + 1] = drops[index]
  end

  return npcs, drops[1]
end

-- Returns the chance in percent of a creature dropping an item, nil if not
-- known. Only the bosses of dungeons and raids have one.
function DB:GetDropRate(itemId, npcId)
  local rates = Data.dropRates and Data.dropRates[itemId]

  if rates == nil then
    return nil
  end

  for index = 1, #rates - 1, 2 do
    if rates[index] == npcId then
      return rates[index + 1]
    end
  end
end

-- Returns a drop rate as text
function DB:FormatDropRate(rate)
  if rate >= 10 then
    return string.format('%.0f%%', rate)
  elseif rate >= 1 then
    return string.format('%.1f%%', rate)
  end

  return string.format('%.2f%%', rate)
end

------------------------------------------
-- Quests
------------------------------------------

-- Returns the quests that reward an item
function DB:GetQuestRewards(itemId)
  return Data.questRewards and Data.questRewards[itemId] or nil
end

-- Returns a quest's name, level, required level, faction ('A', 'H' or ''),
-- zone, and the NPC who gives it (nil if none)
function DB:GetQuest(questId)
  local quest = Data.quests[questId]

  if quest == nil then
    return nil
  end

  local name = (Data.questNames and Data.questNames[questId]) or quest[1]
  local zone = quest[5] > 0 and GetZoneName(quest[5]) or nil

  return name, quest[2], quest[3], quest[4], zone, quest[6] > 0 and quest[6] or nil
end

-- Returns the quests that ask for an item
function DB:GetQuestObjectives(itemId)
  return Data.questObjectives and Data.questObjectives[itemId] or nil
end

-- Returns whether the player is on a quest
function DB:IsOnQuest(questId)
  if C_QuestLog and C_QuestLog.IsOnQuest then
    local success, isOn = pcall(C_QuestLog.IsOnQuest, questId)
    return success and isOn == true
  end

  if _G.GetQuestLogIndexByID then
    local index = GetQuestLogIndexByID(questId)
    return index ~= nil and index > 0
  end

  return false
end

-- Returns the quests that the player's faction can do, or all of them if
-- none can, sorted by level
local function GetUsable(self, quests)
  if quests == nil then
    return nil
  end

  local faction = UnitFactionGroup('player') == 'Horde' and 'H' or 'A'
  local usable = {}

  for _, questId in ipairs(quests) do
    local _, _, _, questFaction = self:GetQuest(questId)

    if questFaction == '' or questFaction == faction then
      usable[#usable + 1] = questId
    end
  end

  if #usable == 0 then
    usable = { unpack(quests) }
  end

  table.sort(usable, function(a, b)
    local levelA, levelB = Data.quests[a][2], Data.quests[b][2]

    if levelA ~= levelB then
      return levelA < levelB
    end

    return a < b
  end)

  return usable
end

-- Returns the quests rewarding an item that the player's faction can do, or
-- all of them if none can, sorted by level
function DB:GetUsableQuestRewards(itemId)
  return GetUsable(self, self:GetQuestRewards(itemId))
end

-- Returns the quests asking for an item that the player's faction can do,
-- or all of them if none can, those in the quest log first, then by level
function DB:GetUsableQuestObjectives(itemId)
  local quests = GetUsable(self, self:GetQuestObjectives(itemId))

  if quests == nil then
    return nil
  end

  local active, others = {}, {}

  for _, questId in ipairs(quests) do
    table.insert(self:IsOnQuest(questId) and active or others, questId)
  end

  for _, questId in ipairs(others) do
    active[#active + 1] = questId
  end

  return active
end

-- Returns a quest's name colored by its difficulty for the player
function DB:GetColoredQuestName(questId)
  local name, level = self:GetQuest(questId)
  local color = '|cffffd100'

  if level > 0 and _G.GetQuestDifficultyColor then
    local ok, difficulty = pcall(_G.GetQuestDifficultyColor, level)

    if ok and type(difficulty) == 'table' and difficulty.r ~= nil then
      color = string.format('|cff%02x%02x%02x', difficulty.r * 255, difficulty.g * 255, difficulty.b * 255)
    end
  end

  if level > 0 then
    return color .. '[' .. level .. '] ' .. name .. '|r'
  end

  return color .. name .. '|r'
end

------------------------------------------
-- Categories
------------------------------------------

-- Sorts scanned items into their class and subclass, which the client knows
-- of without asking the server. Only items added since the last call are
-- processed.
function DB:GetCategories()
  local itemIds = Scanner:GetItems()
  local classes = self.classes

  for index = self.classifiedCount + 1, #itemIds do
    local itemId = itemIds[index]
    local _, typeName, subTypeName, _, _, classId, subClassId = GetItemInfoInstant(itemId)

    if classId ~= nil then
      subClassId = subClassId or 0
      self.itemClass[itemId] = classId * 1000 + subClassId

      local class = classes[classId]
      if class == nil then
        class = { id = classId, name = typeName or ('#' .. classId), count = 0, subs = {} }
        classes[classId] = class
      end

      local sub = class.subs[subClassId]
      if sub == nil then
        sub = { id = subClassId, name = subTypeName or ('#' .. subClassId), count = 0 }
        class.subs[subClassId] = sub
      end

      class.count = class.count + 1
      sub.count = sub.count + 1
    end
  end

  self.classifiedCount = #itemIds
  return classes
end

------------------------------------------
-- Search
------------------------------------------

local sortLimit = 5000

-- Returns the entries whose name contains a text, as a list of references.
--
-- The filter narrows the search to an item class ('class' and optionally
-- 'sub'), to the recipes of a profession ('prof'), to the wishlist
-- ('wishlist') or to what a creature drops ('npc'). For a profession, the
-- second return value holds the skill required for each entry. The wishlist
-- and a creature's drops keep their own order.
function DB:Search(text, filter)
  local query = ns.Lower(ns.Trim(text or ''))
  local hasQuery = query ~= ''
  local results = {}

  if filter ~= nil and (filter.wishlist or filter.npc ~= nil) then
    local refs = filter.wishlist and ns.Wishlist:GetItems() or ns.Creature:GetRanked(filter.npc)

    for _, ref in ipairs(refs) do
      if not hasQuery or self:GetLowerName(ref):find(query, 1, true) ~= nil then
        results[#results + 1] = ref
      end
    end

    return results
  end

  if filter ~= nil and filter.prof ~= nil then
    local skills = {}

    for _, spellId in ipairs(self.profSpells[filter.prof] or {}) do
      local ref = self:GetSpellRef(spellId)

      if skills[ref] == nil and
        (not hasQuery or self:GetLowerName(ref):find(query, 1, true) ~= nil) then
        results[#results + 1] = ref
        skills[ref] = Data.spells[spellId][SKILL]
      end
    end

    return results, skills
  end

  local itemIds, names = Scanner:GetItems()

  if filter ~= nil and filter.class ~= nil then
    self:GetCategories()

    local itemClass = self.itemClass
    local low = filter.class * 1000 + (filter.sub or 0)
    local high = filter.sub ~= nil and low or low + 999

    for index = 1, #itemIds do
      local itemId = itemIds[index]
      local class = itemClass[itemId]

      if class ~= nil and class >= low and class <= high and
        (not hasQuery or self:GetLowerName(itemId):find(query, 1, true) ~= nil) then
        results[#results + 1] = itemId
      end
    end
  elseif hasQuery then
    for index = 1, #itemIds do
      local itemId = itemIds[index]

      if self:GetLowerName(itemId):find(query, 1, true) ~= nil then
        results[#results + 1] = itemId
      end
    end

    -- Recipes that make no item, e.g. enchants
    for spellId, spell in pairs(Data.spells) do
      if spell[ITEM] == 0 and self:GetLowerName(-spellId):find(query, 1, true) ~= nil then
        results[#results + 1] = -spellId
      end
    end
  end

  if #results <= sortLimit then
    table.sort(results, function(a, b)
      local nameA, nameB = self:GetLowerName(a), self:GetLowerName(b)

      if nameA ~= nameB then
        return nameA < nameB
      end

      return a < b
    end)
  end

  return results
end

-- Returns the item whose name is exactly a text, if there's only one
function DB:FindExact(text)
  local query = ns.Lower(ns.Trim(text or ''))
  local itemIds = Scanner:GetItems()
  local found

  for index = 1, #itemIds do
    if self:GetLowerName(itemIds[index]) == query then
      if found ~= nil then
        return nil
      end

      found = itemIds[index]
    end
  end

  return found
end
