local ADDON, ns = ...

ns.ADDON = ADDON
ns.LOGO = 'Interface\\AddOns\\' .. ADDON .. '\\Media\\Logo'
ns.Data = {}

-- Missing translations fall back to the English text, which is the key
ns.L = setmetatable({}, {
  __index = function(_, key)
    return key
  end,
})

------------------------------------------
-- API compatibility
------------------------------------------

-- The item and spell APIs live in namespaces on the modern client that Forever
-- is built on, the globals are only kept as fallbacks.
ns.GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
ns.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

function ns.GetSpellName(spellId)
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(spellId)
  end

  return _G.GetSpellInfo and (_G.GetSpellInfo(spellId)) or nil
end

function ns.GetSpellIcon(spellId)
  if C_Spell and C_Spell.GetSpellTexture then
    return (C_Spell.GetSpellTexture(spellId))
  end

  return _G.GetSpellTexture and (_G.GetSpellTexture(spellId)) or nil
end

-- Returns whether a value is a secret, which addons cannot inspect
function ns.IsSecret(value)
  return _G.issecretvalue ~= nil and _G.issecretvalue(value)
end

------------------------------------------
-- Events
------------------------------------------

local listeners = {}
local eventFrame = CreateFrame('Frame')

eventFrame:SetScript('OnEvent', function(_, event, ...)
  local callbacks = listeners[event]

  for index = 1, #callbacks do
    callbacks[index](...)
  end
end)

-- Calls back on an event. Clients differ in the events they know and raise an
-- error for the others, which then simply never fire.
function ns.On(event, callback)
  if listeners[event] == nil then
    listeners[event] = {}
    pcall(eventFrame.RegisterEvent, eventFrame, event)
  end

  table.insert(listeners[event], callback)
end

------------------------------------------
-- Utilities
------------------------------------------

function ns.Print(...)
  local message = string.format('|cFFFFA500[%s]|r: %s', ADDON, table.concat({ ... }, ' '))
  DEFAULT_CHAT_FRAME:AddMessage(message)
end

-- Lowers the second byte of a two byte UTF-8 sequence, for the Latin-1 and
-- Cyrillic blocks. Other scripts either have no case or are left as they are.
local function LowerSequence(lead, trail)
  local leadByte, trailByte = lead:byte(), trail:byte()

  if leadByte == 195 then
    -- À..Þ, except the multiplication sign
    if trailByte >= 128 and trailByte <= 158 and trailByte ~= 151 then
      return lead .. string.char(trailByte + 32)
    end
  elseif leadByte == 208 then
    if trailByte >= 144 and trailByte <= 159 then
      -- А..П
      return lead .. string.char(trailByte + 32)
    elseif trailByte >= 160 and trailByte <= 175 then
      -- Р..Я
      return '\209' .. string.char(trailByte - 32)
    elseif trailByte >= 128 and trailByte <= 143 then
      -- Ѐ..Џ
      return '\209' .. string.char(trailByte + 16)
    end
  end
end

-- Returns a string in lower case, for case-insensitive searches
function ns.Lower(text)
  text = text:lower()

  if text:find('[\195\208]') then
    text = text:gsub('([\195\208])([\128-\191])', LowerSequence)
  end

  return text
end

function ns.Trim(text)
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Returns an amount of copper as text with coin icons
function ns.FormatMoney(copper)
  if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
    return C_CurrencyInfo.GetCoinTextureString(copper)
  elseif _G.GetCoinTextureString then
    return _G.GetCoinTextureString(copper)
  end

  local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
  return string.format('%dg %ds %dc', gold, silver, copper % 100)
end

-- Returns the color code of an item quality
function ns.QualityColor(quality)
  local color = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 1]
  return color and color.hex or '|cffffffff'
end
