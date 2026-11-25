local _, ns = ...

-- The professions of the player's characters and the recipes they know, so
-- that a recipe's tooltip tells whether it is worth buying: known already,
-- learnable now, learnable later, or of no use to anyone.
--
-- Skill levels are read from the skill lines, on login and whenever they
-- change. The known recipes are read whenever a profession window is open,
-- that is the only place the game lists them. Characters are kept account
-- wide, by realm, so that the tooltip also tells about the alts.

local DB = ns.DB

-- The game's skill line IDs, with the profession IDs of the recipe data. Unlike
-- the names, they do not depend on the language.
local SKILL_LINES = {
  [129] = 1, [164] = 2, [165] = 3, [171] = 4, [182] = 5, [185] = 6, [186] = 7,
  [197] = 8, [202] = 9, [333] = 10, [356] = 11, [393] = 12, [40] = 13,
}

local Professions = {}
ns.Professions = Professions

------------------------------------------
-- Characters
------------------------------------------

-- Returns the saved entry of the player's character
function Professions:_GetPlayer()
  local realm, name = GetRealmName() or '?', UnitName('player') or '?'
  local characters = self.saved.characters
  characters[realm] = characters[realm] or {}

  local player = characters[realm][name]
  if player == nil then
    player = { skills = {}, known = {} }
    characters[realm][name] = player
  end

  player.class = select(2, UnitClass('player')) or player.class
  return player, name, realm
end

-- Returns the professions known by name, in the player's language
function Professions:_GetNames()
  if self.names == nil then
    local names = {}

    for _, profession in ipairs(DB:GetProfessions()) do
      names[DB:GetProfessionName(profession)] = profession
    end

    self.names = names
  end

  return self.names
end

-- Returns the profession of a skill line or profession window by its name
function Professions:GetByName(name)
  return name ~= nil and self:_GetNames()[name] or nil
end

------------------------------------------
-- Skills
------------------------------------------

-- Returns the number of skill lines, nil if the client doesn't list them.
-- Forever has replaced the globals with C_SkillInfo.
local function GetLineCount()
  if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
    return C_SkillInfo.GetNumSkillLines()
  elseif _G.GetNumSkillLines and _G.GetSkillLineInfo then
    return GetNumSkillLines()
  end
end

-- Returns a skill line's name, whether it is a header, whether that is
-- collapsed, the skill, its maximum and the skill line's ID, if there is one
local function GetLine(index)
  if C_SkillInfo and C_SkillInfo.GetSkillLineInfo then
    local info = C_SkillInfo.GetSkillLineInfo(index)

    if info == nil then
      return nil
    end

    return info.name, info.isHeader, info.isCollapsed, (info.rank or 0) + (info.modifier or 0),
      info.maxRank, info.skillID
  end

  local name, isHeader, isExpanded, rank, _, modifier, maxRank = GetSkillLineInfo(index)
  return name, isHeader, not isExpanded, (rank or 0) + (modifier or 0), maxRank
end

-- Reads the player's profession skills from the skill lines. Lines under a
-- collapsed header are not listed, a profession is only forgotten when every
-- header is open.
function Professions:_ReadSkills()
  local count = GetLineCount()

  -- None at all means that they are not loaded yet
  if count == nil or count == 0 then
    return
  end

  local player = self:_GetPlayer()
  local seen, isComplete = {}, true

  local success = pcall(function()
    for index = 1, count do
      local name, isHeader, isCollapsed, rank, maxRank, skillLine = GetLine(index)

      if isHeader then
        if isCollapsed then
          isComplete = false
        end
      else
        local profession = SKILL_LINES[skillLine or 0] or self:GetByName(name)

        if profession ~= nil then
          seen[profession] = true
          player.skills[profession] = { rank, maxRank or 0 }
        end
      end
    end
  end)

  if success and isComplete then
    for profession in pairs(player.skills) do
      if not seen[profession] then
        player.skills[profession] = nil
        player.known[profession] = nil
      end
    end
  end
end

------------------------------------------
-- Recipes
------------------------------------------

-- Returns the spells of a profession by name, a name may stand for more
-- than one
function Professions:_GetSpellsByName(profession)
  self.spellNames = self.spellNames or {}
  local byName = self.spellNames[profession]

  if byName == nil then
    byName = {}

    for _, spellId in ipairs(DB:GetProfessionSpells(profession) or {}) do
      local name = ns.GetSpellName(spellId)

      if name ~= nil and name ~= '' then
        byName[name] = byName[name] or {}
        table.insert(byName[name], spellId)
      end
    end

    self.spellNames[profession] = byName
  end

  return byName
end

-- Marks the spells of a recipe of a profession window as known
local function MarkKnown(known, byName, name, link)
  local spellId = link ~= nil and tonumber(link:match('enchant:(%d+)')) or nil

  if spellId ~= nil and ns.Data.spells[spellId] ~= nil then
    known[spellId] = true
    return
  end

  for _, id in ipairs(byName[name] or {}) do
    known[id] = true
  end
end

-- Reads the recipes of the open profession window on the modern client, which
-- lists all of them and tells which ones are learnt
function Professions:_ReadModernWindow()
  local api = C_TradeSkillUI

  -- Not the window of another player, the guild or an NPC
  for _, name in ipairs({ 'IsTradeSkillLinked', 'IsTradeSkillGuild', 'IsTradeSkillGuildMember', 'IsNPCCrafting' }) do
    if api[name] and api[name]() then
      return
    end
  end

  if api.IsTradeSkillReady and not api.IsTradeSkillReady() then
    return
  end

  local info = api.GetBaseProfessionInfo()
  local profession = info and (SKILL_LINES[info.professionID or 0] or self:GetByName(info.professionName))
  if profession == nil then
    return
  end

  local player = self:_GetPlayer()
  local known = player.known[profession] or {}
  player.known[profession] = known

  local byName = self:_GetSpellsByName(profession)

  for _, recipeId in ipairs(api.GetAllRecipeIDs() or {}) do
    local recipe = api.GetRecipeInfo(recipeId)

    if recipe ~= nil and recipe.learned then
      MarkKnown(known, byName, recipe.name, 'enchant:' .. recipeId)
    end
  end
end

-- Marks a recipe as known when the game tells that it was learnt
function Professions:_OnRecipeLearned(recipeId)
  local profession = ns.Data.spells[recipeId] ~= nil and DB:GetSpell(recipeId) or nil

  if profession ~= nil then
    local player = self:_GetPlayer()
    player.known[profession] = player.known[profession] or {}
    player.known[profession][recipeId] = true
  end
end

-- Reads the window once for a burst of updates, they come with every craft
function Professions:_QueueWindow()
  if self.isQueued then
    return
  end

  self.isQueued = true
  C_Timer.After(0.5, function()
    self.isQueued = false
    self:_ReadWindow(false)
  end)
end

-- Reads the recipes of the open profession window. Recipes hidden by a
-- collapsed header or a filter are not listed, so known recipes are added
-- and never taken away, recipes can't be unlearnt.
function Professions:_ReadWindow(isCraft)
  if not isCraft and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs
    and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetBaseProfessionInfo then
    self:_ReadModernWindow()
    return
  end

  local skillName, rank, maxRank
  local count, GetInfo, GetLink

  if isCraft then
    if _G.GetCraftDisplaySkillLine == nil or _G.GetNumCrafts == nil then
      return
    end

    skillName, rank, maxRank = GetCraftDisplaySkillLine()
    count, GetInfo = GetNumCrafts(), GetCraftInfo
    GetLink = _G.GetCraftRecipeLink or _G.GetCraftItemLink
  else
    if _G.GetTradeSkillLine == nil or _G.GetNumTradeSkills == nil then
      return
    end

    skillName, rank, maxRank = GetTradeSkillLine()
    count, GetInfo = GetNumTradeSkills(), GetTradeSkillInfo
    GetLink = _G.GetTradeSkillRecipeLink
  end

  local profession = self:GetByName(skillName)
  if profession == nil then
    return
  end

  local player = self:_GetPlayer()
  local known = player.known[profession] or {}
  player.known[profession] = known

  if rank ~= nil and rank > 0 then
    player.skills[profession] = { rank, maxRank or 0 }
  end

  local byName = self:_GetSpellsByName(profession)

  for index = 1, count or 0 do
    local name, kind
    if isCraft then
      name, _, kind = GetInfo(index)
    else
      name, kind = GetInfo(index)
    end

    if name ~= nil and kind ~= 'header' and kind ~= 'subheader' then
      local link = GetLink and GetLink(index) or nil
      MarkKnown(known, byName, name, link)
    end
  end
end

-- Marks a recipe as known when the chat tells it was learnt
function Professions:_OnSystemMessage(message)
  if self.learnPatterns == nil then
    self.learnPatterns = {}

    for _, format in ipairs({ _G.ERR_LEARN_RECIPE_S, _G.ERR_LEARN_SPELL_S }) do
      if type(format) == 'string' then
        local pattern = format:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1'):gsub('%%%%s', '(.+)')
        self.learnPatterns[#self.learnPatterns + 1] = '^' .. pattern .. '$'
      end
    end
  end

  for _, pattern in ipairs(self.learnPatterns) do
    local name = message:match(pattern)

    if name ~= nil then
      local player = self:_GetPlayer()

      for profession in pairs(player.skills) do
        local known = player.known[profession] or {}
        player.known[profession] = known
        MarkKnown(known, self:_GetSpellsByName(profession), name)
      end
      return
    end
  end
end

------------------------------------------
-- Public
------------------------------------------

-- Returns where a character stands with a spell: 'known', 'learnable',
-- 'later' (the skill is too low) or 'none' (not its profession). Also
-- returns the character's skill and the skill the spell requires.
local function GetStatus(character, spellId, isPlayer)
  local profession, required = DB:GetSpell(spellId)
  if profession == nil then
    return nil
  end

  local skill = character.skills[profession]
  if skill == nil then
    return 'none', nil, required
  end

  local known = character.known[profession]
  if (known ~= nil and known[spellId])
    or (isPlayer and _G.IsPlayerSpell ~= nil and IsPlayerSpell(spellId)) then
    return 'known', skill[1], required
  end

  return skill[1] >= required and 'learnable' or 'later', skill[1], required
end

-- Returns where the player stands with a spell, see GetStatus
function Professions:GetStatus(spellId)
  return GetStatus(self:_GetPlayer(), spellId, true)
end

-- Returns the player's other characters on the realm that have the
-- profession of a spell, sorted by name: { name, class, status, skill }
function Professions:GetAlts(spellId)
  local _, playerName, realm = self:_GetPlayer()
  local alts = {}

  for name, character in pairs(self.saved.characters[realm]) do
    if name ~= playerName then
      local status, skill = GetStatus(character, spellId, false)

      if status ~= nil and status ~= 'none' then
        alts[#alts + 1] = { name = name, class = character.class, status = status, skill = skill }
      end
    end
  end

  table.sort(alts, function(a, b)
    return a.name < b.name
  end)

  return alts
end

function Professions:Init(saved)
  saved.characters = saved.characters or {}
  self.saved = saved

  self:_ReadSkills()

  ns.On('SKILL_LINES_CHANGED', function()
    self:_ReadSkills()
  end)

  for _, event in ipairs({ 'TRADE_SKILL_SHOW', 'TRADE_SKILL_UPDATE' }) do
    ns.On(event, function()
      self:_ReadWindow(false)
    end)
  end

  for _, event in ipairs({ 'CRAFT_SHOW', 'CRAFT_UPDATE' }) do
    ns.On(event, function()
      self:_ReadWindow(true)
    end)
  end

  ns.On('TRADE_SKILL_LIST_UPDATE', function()
    self:_QueueWindow()
  end)

  ns.On('NEW_RECIPE_LEARNED', function(recipeId)
    self:_OnRecipeLearned(recipeId)
  end)

  ns.On('CHAT_MSG_SYSTEM', function(message)
    if type(message) == 'string' and not ns.IsSecret(message) then
      self:_OnSystemMessage(message)
    end
  end)
end
