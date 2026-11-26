local _, ns = ...

-- Shares the recipes of the player's characters with the guild, so that a
-- tooltip tells who in the guild knows a recipe or can make an item.
--
-- The ItemInfo users of a guild exchange the recipes their characters know,
-- over addon messages, with the prefix of the version check:
--
--   S1;<name>=<digest>,...   the characters a client shares, each with a
--                            digest of its recipes
--   Q1;<name>,...            asks the owner of characters for their recipes
--   D1;<name>;<digest>;<part>;<parts>;<text>
--                            a character's recipes, to the guild, in parts
--   X1;<name>,...            the owner stopped sharing these characters
--
-- After login, a client announces its characters to the guild, and every
-- other client answers with its own, by whisper. Each side asks only for the
-- characters it has no recipes of, or older ones, so the recipes are sent
-- once, and again only when the character learns a new one.
--
-- A character is shared while it is in the guild the player is in now: the
-- alts of other guilds stay out of it. The recipes received are kept by realm
-- and guild, until the character has not been announced for a month.

local L = ns.L
local DB = ns.DB

local Guild = {}
ns.Guild = Guild

local PREFIX = 'ItemInfo'

-- The characters announced again after a recipe is learnt, at most this
-- often, in seconds
local announceDelay = 30
-- A character's recipes are sent to the guild at most this often
local sendInterval = 30
-- The owner of a character is asked for its recipes at most this often
local askInterval = 120
-- Addon messages are throttled by the game, they are sent one at a time
local messageInterval = 1
-- The length of the recipes in each part, leaving room for the header
local partLength = 200
-- A character's recipes are given up on when parts are still missing after
-- this long, and are not taken in more than this many parts
local partTimeout = 120
local maxParts = 60
-- Characters that have not been announced for this long are forgotten
local maxAge = 30 * 24 * 60 * 60

local DIGITS = '0123456789abcdefghijklmnopqrstuvwxyz'

local function Base36(number)
  if number == 0 then
    return '0'
  end

  local text = ''
  while number > 0 do
    local digit = number % 36
    text = DIGITS:sub(digit + 1, digit + 1) .. text
    number = math.floor(number / 36)
  end

  return text
end

-- Returns a short digest of a text, that changes whenever the text does
local function Digest(text)
  local hash = 5381

  for index = 1, #text do
    hash = (hash * 33 + text:byte(index)) % 4294967291
  end

  return Base36(hash)
end

-- Returns the recipes of a character as text: its class, then the spells
-- it knows in base 36, in order, so that the same recipes give the same text
local function Serialize(character)
  local spells = {}

  for _, known in pairs(character.known or {}) do
    for spellId in pairs(known) do
      spells[#spells + 1] = spellId
    end
  end

  table.sort(spells)

  for index, spellId in ipairs(spells) do
    spells[index] = Base36(spellId)
  end

  return (character.class or '') .. ':' .. table.concat(spells, ','), #spells
end

-- Returns the class and the known spells of a character's text, nil if it
-- is not one. Spells the recipe data doesn't list are left out.
local function Parse(text)
  local class, list = text:match('^(%u*):([%w,]*)$')
  if class == nil then
    return nil
  end

  local known = {}

  for code in list:gmatch('[^,]+') do
    local spellId = tonumber(code, 36)

    if spellId ~= nil and ns.Data.spells[spellId] ~= nil then
      known[spellId] = true
    end
  end

  return class ~= '' and class or nil, known
end

local function Send(message, channel, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, channel, target)
  end
end

local function GetGuildName()
  if not IsInGuild() then
    return nil
  end

  return _G.GetGuildInfo and (GetGuildInfo('player')) or nil
end

------------------------------------------
-- Characters
------------------------------------------

-- Returns the player's characters on the realm, by name
function Guild:_GetOwn()
  local _, _, realm = ns.Professions:_GetPlayer()
  return ns.Professions.saved.characters[realm], realm
end

-- Records the guild the player is in, and returns it. The name is not known
-- until the game has loaded the guild, which takes a while after login.
function Guild:_ReadGuild()
  local player = ns.Professions:_GetPlayer()
  local name = GetGuildName()

  if name ~= nil then
    player.guild = name
  elseif not IsInGuild() then
    player.guild = nil
  end

  self.guildName = name
  return name
end

-- Returns the characters of the player that are shared with the guild, by
-- name, with their text and digest: { text, digest }
function Guild:_GetShared()
  local shared = {}

  if not self.saved.share or self.guildName == nil then
    return shared
  end

  for name, character in pairs(self:_GetOwn()) do
    if character.guild == self.guildName then
      local text, count = Serialize(character)

      if count > 0 then
        shared[name] = { text = text, digest = Digest(text) }
      end
    end
  end

  return shared
end

-- Returns the recipes received from the guild the player is in, by name
function Guild:_GetStore()
  if self.guildName == nil then
    return nil
  end

  local _, realm = self:_GetOwn()
  local guilds = self.saved.guilds
  guilds[realm] = guilds[realm] or {}
  guilds[realm][self.guildName] = guilds[realm][self.guildName] or {}

  return guilds[realm][self.guildName]
end

-- Forgets the characters that have not been announced for a long time
function Guild:_Prune()
  local now = time()

  for realm, guilds in pairs(self.saved.guilds) do
    for guildName, characters in pairs(guilds) do
      for name, character in pairs(characters) do
        if now - (character.seen or 0) > maxAge then
          characters[name] = nil
        end
      end

      if next(characters) == nil then
        guilds[guildName] = nil
      end
    end

    if next(guilds) == nil then
      self.saved.guilds[realm] = nil
    end
  end
end

-- Reads which members of the guild are online
function Guild:_ReadRoster()
  local count = _G.GetNumGuildMembers and GetNumGuildMembers() or 0
  if count == 0 or _G.GetGuildRosterInfo == nil then
    return
  end

  local online = {}

  for index = 1, count do
    local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(index)

    if name ~= nil and isOnline then
      online[Ambiguate(name, 'none')] = true
    end
  end

  self.online = online
end

------------------------------------------
-- Messages
------------------------------------------

-- Sends the queued messages one at a time, and none in combat, when addon
-- messages may be refused
function Guild:_Pump()
  if self.isPumping then
    return
  end

  self.isPumping = true

  local function Step()
    if InCombatLockdown() then
      C_Timer.After(2, Step)
      return
    end

    local message = table.remove(self.queue, 1)
    if message ~= nil then
      Send(message[1], message[2], message[3])
    end

    if #self.queue > 0 then
      C_Timer.After(messageInterval, Step)
    else
      self.isPumping = false
    end
  end

  Step()
end

function Guild:_Queue(message, channel, target)
  self.queue[#self.queue + 1] = { message, channel, target }
  self:_Pump()
end

-- Sends a list in as few messages as it fits in
function Guild:_QueueList(kind, items, channel, target)
  local line = ''

  for _, item in ipairs(items) do
    if line ~= '' and #line + #item > 240 then
      self:_Queue(kind .. ';' .. line, channel, target)
      line = ''
    end

    line = line == '' and item or line .. ',' .. item
  end

  if line ~= '' or #items == 0 then
    self:_Queue(kind .. ';' .. line, channel, target)
  end
end

-- Returns the shared characters with their digests, in order
function Guild:_GetAnnouncement()
  local items = {}

  for name, character in pairs(self:_GetShared()) do
    items[#items + 1] = name .. '=' .. character.digest
  end

  table.sort(items)
  return items
end

-- Announces the shared characters and their digests. An empty announcement
-- to the guild still asks the others for theirs.
function Guild:_Announce(channel, target)
  local items = self:_GetAnnouncement()
  local text = table.concat(items, ',')

  -- The same announcement to the guild is not repeated so soon
  if channel == 'GUILD' then
    if text == self.announced and GetTime() - self.announcedAt < announceDelay then
      return
    end

    self.announced, self.announcedAt = text, GetTime()
  end

  self:_QueueList('S1', items, channel, target)
end

-- Sends a character's recipes to the guild, in parts
function Guild:_SendRecipes(name)
  local character = self:_GetShared()[name]
  if character == nil or GetTime() - (self.sentAt[name] or -math.huge) < sendInterval then
    return
  end

  self.sentAt[name] = GetTime()

  local text = character.text
  local parts = math.max(1, math.ceil(#text / partLength))

  for part = 1, parts do
    local slice = text:sub((part - 1) * partLength + 1, part * partLength)
    self:_Queue(string.format('D1;%s;%s;%d;%d;%s', name, character.digest, part, parts, slice), 'GUILD')
  end
end

-- Announces the characters again once a recipe has been learnt, if their
-- recipes have changed
function Guild:_QueueCheck()
  if self.isCheckQueued or self.guildName == nil then
    return
  end

  self.isCheckQueued = true
  C_Timer.After(announceDelay, function()
    self.isCheckQueued = false

    if self.announced ~= nil and table.concat(self:_GetAnnouncement(), ',') ~= self.announced then
      self:_Announce('GUILD')
    end
  end)
end

function Guild:_OnAnnounce(list, channel, sender)
  local store, own = self:_GetStore(), self:_GetOwn()
  if store == nil then
    return
  end

  local wanted = {}

  for name, digest in list:gmatch('([^,=]+)=([%w]+)') do
    if own[name] == nil then
      local character = store[name]

      if character ~= nil and character.digest == digest then
        character.seen = time()
      elseif GetTime() - (self.askedAt[name] or -math.huge) >= askInterval then
        self.askedAt[name] = GetTime()
        wanted[#wanted + 1] = name
      end
    end
  end

  if #wanted > 0 then
    self:_QueueList('Q1', wanted, 'WHISPER', sender)
  end

  -- A client that just logged in is told about the characters shared here,
  -- whispers are not answered, or two clients would answer each other
  if channel == 'GUILD' and next(self:_GetShared()) ~= nil then
    self:_Announce('WHISPER', sender)
  end
end

function Guild:_OnRequest(list)
  for name in list:gmatch('[^,]+') do
    self:_SendRecipes(name)
  end
end

function Guild:_OnRecipes(name, digest, part, parts, text, sender)
  local store = self:_GetStore()
  if store == nil or self:_GetOwn()[name] ~= nil then
    return
  end

  if store[name] ~= nil and store[name].digest == digest then
    store[name].seen = time()
    return
  end

  if parts < 1 or parts > maxParts or part < 1 or part > parts then
    return
  end

  local key = sender .. ';' .. name .. ';' .. digest
  local buffer = self.buffers[key]

  if buffer == nil or GetTime() - buffer.startedAt > partTimeout then
    buffer = { startedAt = GetTime(), parts = {}, count = 0 }
    self.buffers[key] = buffer
  end

  if buffer.parts[part] == nil then
    buffer.parts[part] = text
    buffer.count = buffer.count + 1
  end

  if buffer.count < parts then
    return
  end

  self.buffers[key] = nil
  local whole = table.concat(buffer.parts, '', 1, parts)

  if Digest(whole) ~= digest then
    return
  end

  local class, known = Parse(whole)
  if known ~= nil then
    store[name] = { class = class, by = sender, digest = digest, seen = time(), known = known }
  end
end

function Guild:_OnWithdraw(list, sender)
  local store = self:_GetStore()
  if store == nil then
    return
  end

  for name in list:gmatch('[^,]+') do
    if store[name] ~= nil and store[name].by == sender then
      store[name] = nil
    end
  end
end

function Guild:_Receive(text, channel, sender)
  if ns.IsSecret(text) or ns.IsSecret(sender) or type(text) ~= 'string' or type(sender) ~= 'string' then
    return
  end

  local kind, rest = text:match('^(%u1);(.*)$')
  if kind == nil then
    return
  end

  local name = Ambiguate(sender, 'none')
  if name == UnitName('player') then
    return
  end

  -- The guild name may not have been known yet at login
  if self.guildName == nil then
    self:_ReadGuild()
  end

  self.online[name] = true

  if kind == 'S1' then
    self:_OnAnnounce(rest, channel, sender)
  elseif kind == 'Q1' and channel == 'WHISPER' then
    self:_OnRequest(rest)
  elseif kind == 'D1' and channel == 'GUILD' then
    local character, digest, part, parts, slice = rest:match('^([^;]+);(%w+);(%d+);(%d+);(.*)$')

    if character ~= nil then
      self:_OnRecipes(character, digest, tonumber(part), tonumber(parts), slice, name)
    end
  elseif kind == 'X1' and channel == 'GUILD' then
    self:_OnWithdraw(rest, name)
  end
end

------------------------------------------
-- Public
------------------------------------------

-- Returns the guild's characters that know a spell, but the player's own,
-- those online first, then by name: { name, class, online, by }
function Guild:GetCrafters(spellId)
  local store = self:_GetStore()
  local crafters = {}

  if store == nil then
    return crafters
  end

  local own = self:_GetOwn()

  for name, character in pairs(store) do
    if own[name] == nil and character.known ~= nil and character.known[spellId] then
      crafters[#crafters + 1] = {
        name = name,
        class = character.class,
        online = self.online[name] == true,
        -- An alt is reached through the character that shared it
        by = character.by,
      }
    end
  end

  table.sort(crafters, function(a, b)
    if a.online ~= b.online then
      return a.online
    end

    return a.name < b.name
  end)

  return crafters
end

-- Turns sharing on or off, returns whether it is on. Turning it off tells
-- the guild to forget the characters shared so far.
function Guild:ToggleSharing()
  if self.saved.share then
    local names = {}
    for name in pairs(self:_GetShared()) do
      names[#names + 1] = name
    end

    table.sort(names)
    if #names > 0 then
      self:_QueueList('X1', names, 'GUILD')
    end

    self.saved.share = false
    self.announced = nil
  else
    self.saved.share = true

    if self.guildName ~= nil then
      self:_Announce('GUILD')
    end
  end

  return self.saved.share
end

function Guild:Init(saved)
  saved.guildShare = saved.guildShare or { share = true, guilds = {} }
  self.saved = saved.guildShare
  self.saved.guilds = self.saved.guilds or {}

  self.queue = self.queue or {}
  self.online = self.online or {}
  self.sentAt, self.askedAt, self.buffers = {}, {}, {}
  self.announcedAt = -math.huge

  self:_Prune()
  self:_ReadGuild()

  if not self.isListening then
    self.isListening = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end

    ns.On('CHAT_MSG_ADDON', function(prefix, text, channel, sender)
      if prefix == PREFIX then
        pcall(self._Receive, self, text, channel, sender)
      end
    end)

    ns.On('PLAYER_GUILD_UPDATE', function()
      local before = self.guildName

      if self:_ReadGuild() ~= nil and before ~= self.guildName then
        self:_Announce('GUILD')
      end
    end)

    ns.On('GUILD_ROSTER_UPDATE', function()
      if self.guildName == nil then
        self:_ReadGuild()
      end

      self:_ReadRoster()
    end)

    -- The recipes may have changed
    for _, event in ipairs({ 'TRADE_SKILL_CLOSE', 'CRAFT_CLOSE', 'NEW_RECIPE_LEARNED', 'CHAT_MSG_SYSTEM' }) do
      ns.On(event, function()
        self:_QueueCheck()
      end)
    end
  end

  -- After the login messages, once the guild is loaded
  C_Timer.After(15, function()
    if not IsInGuild() then
      return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
      C_GuildInfo.GuildRoster()
    elseif _G.GuildRoster then
      _G.GuildRoster()
    end

    if self:_ReadGuild() ~= nil then
      self:_Announce('GUILD')
    end
  end)
end
