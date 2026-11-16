local ADDON, ns = ...

-- Tells the player when a newer version of ItemInfo is out.
--
-- Addons cannot reach the internet, so versions are compared with the other
-- ItemInfo users of the guild and group, over addon messages: each client
-- announces its version on login and when joining a group, and a client with
-- a newer version answers the announcer directly.
--
-- Message: V;<version>

local L = ns.L

local Version = {}
ns.Version = Version

local PREFIX = 'ItemInfo'

-- A group is announced to at most this often, in seconds
local groupInterval = 60

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata

-- Returns the numbers of a release version such as 'v1.2.3', or nil for a
-- development copy or a beta or alpha
local function Parse(version)
  if type(version) ~= 'string' then
    return nil
  end

  local major, minor, patch = version:match('^v?(%d+)%.(%d+)%.?(%d*)$')
  if major == nil then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) or 0 }
end

-- Returns whether version a is newer than version b
local function IsNewer(a, b)
  for index = 1, 3 do
    if a[index] ~= b[index] then
      return a[index] > b[index]
    end
  end

  return false
end

local function Send(message, channel, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, channel, target)
  end
end

------------------------------------------
-- Setup
------------------------------------------

function Version:Init()
  self.text = GetAddOnMetadata and GetAddOnMetadata(ADDON, 'Version') or nil
  self.version = Parse(self.text)
  self.groupAnnouncedAt = -math.huge

  -- A development copy takes no part, its version is not known
  if self.version == nil then
    return
  end

  if not self.isListening then
    self.isListening = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end

    ns.On('CHAT_MSG_ADDON', function(prefix, text, channel, sender)
      if prefix == PREFIX and self.version ~= nil then
        pcall(self._Receive, self, text, channel, sender)
      end
    end)

    ns.On('GROUP_ROSTER_UPDATE', function()
      if self.version ~= nil then
        self:_AnnounceToGroup()
      end
    end)
  end

  -- After the login messages, so the notice is not lost among them
  C_Timer.After(10, function()
    if IsInGuild() then
      self:_Announce('GUILD')
    end

    self:_AnnounceToGroup()
  end)
end

------------------------------------------
-- Messages
------------------------------------------

function Version:_Announce(channel, target)
  -- Addon messages may be refused in combat
  if InCombatLockdown() then
    return
  end

  Send('V;' .. self.text, channel, target)
end

function Version:_AnnounceToGroup()
  if GetTime() - self.groupAnnouncedAt < groupInterval then
    return
  end

  local channel
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    channel = 'INSTANCE_CHAT'
  elseif IsInRaid() then
    channel = 'RAID'
  elseif IsInGroup() then
    channel = 'PARTY'
  end

  if channel ~= nil then
    self.groupAnnouncedAt = GetTime()
    self:_Announce(channel)
  end
end

function Version:_Receive(text, channel, sender)
  if ns.IsSecret(text) or ns.IsSecret(sender) then
    return
  end

  local other = text:match('^V;(.+)$')
  local version = Parse(other)

  if version == nil or Ambiguate(sender, 'none') == UnitName('player') then
    return
  end

  if IsNewer(version, self.version) then
    -- Each newer version is announced once per session
    if self.notified == nil or IsNewer(version, self.notified) then
      self.notified = version
      ns.Print(L['A new version of ItemInfo is available: %s (you have %s).']:format(other, self.text))
    end
  elseif IsNewer(self.version, version) and channel ~= 'WHISPER' then
    -- The announcer is out of date, it is told directly
    self:_Announce('WHISPER', sender)
  end
end
