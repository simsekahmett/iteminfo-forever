local _, ns = ...

-- Looks an item up in the window without typing its name:
--   - a click with a modifier (Alt by default) on an item anywhere in the
--     game: bags, bank, loot, vendors, the auction house, chat links,
--   - a key binding that looks up the item under the mouse,
--   - a shift-click on an item while the window's search box has focus,
--     which fills it as it does the auction house's.
--
-- The game's functions are only ever hooked with hooksecurefunc, which runs
-- after them and never taints the buttons that call them.

local L = ns.L

local Lookup = {}
ns.Lookup = Lookup

-- The modifiers a look-up click can use, in the order they are offered
Lookup.MODIFIERS = { 'alt', 'ctrl-alt', 'shift-alt', 'off' }

local KEYS = {
  alt = { alt = true },
  ['ctrl-alt'] = { ctrl = true, alt = true },
  ['shift-alt'] = { shift = true, alt = true },
}

local LABELS = {
  alt = 'Alt',
  ['ctrl-alt'] = 'Ctrl-Alt',
  ['shift-alt'] = 'Shift-Alt',
}

local function GetItemId(link)
  if type(link) ~= 'string' or ns.IsSecret(link) then
    return nil
  end

  return tonumber(link:match('item:(%d+)'))
end

-- Returns whether exactly the keys of a modifier are held, so that another
-- modified click, a shift-click that links the item say, is left alone
local function IsHeld(modifier)
  local keys = KEYS[modifier]

  if keys == nil then
    return false
  end

  return IsAltKeyDown() == (keys.alt == true)
    and IsControlKeyDown() == (keys.ctrl == true)
    and IsShiftKeyDown() == (keys.shift == true)
end

-- Returns the modifier a look-up click uses
function Lookup:GetModifier()
  return self.options.modifier
end

-- Sets the modifier of a look-up click, returns false for an unknown one
function Lookup:SetModifier(modifier)
  if KEYS[modifier] == nil and modifier ~= 'off' then
    return false
  end

  self.options.modifier = modifier
  return true
end

-- Returns the line that tells how to look up an item, if a click can
function Lookup:GetHint()
  local label = LABELS[self.options.modifier]
  return label and L['%s-click to look up in ItemInfo']:format(label) or nil
end

-- Returns the modifier as shown in chat
function Lookup:GetModifierText()
  return LABELS[self.options.modifier] or L['off']
end

-- Called after the game handles a modified click on an item
function Lookup:_OnModifiedClick(link)
  -- A right-click with the modifier uses or equips the item, as usual
  local button = _G.GetMouseButtonClicked and GetMouseButtonClicked()
  if button ~= nil and button ~= 'LeftButton' then
    return
  end

  local itemId = GetItemId(link)
  if itemId ~= nil and IsHeld(self.options.modifier) then
    ns.UI:SearchItem(itemId)
  end
end

-- Called after the game inserts a link into the chat, which a shift-click on
-- an item does
function Lookup:_OnInsertLink(link)
  local editBox = ns.UI.editBox
  if editBox == nil or not editBox:IsVisible() or not editBox:HasFocus() then
    return
  end

  local itemId = GetItemId(link)

  -- The game may pass the same link through two of its functions
  if itemId == nil or (itemId == self.lastInserted and GetTime() == self.lastInsertedAt) then
    return
  end

  self.lastInserted, self.lastInsertedAt = itemId, GetTime()
  ns.UI:SearchItem(itemId)
end

-- Looks up the item whose tooltip is shown, lists what the creature under
-- the mouse drops, or opens and closes the window when there is neither.
-- Bound to a key in the game's key bindings.
function Lookup:LookUpHovered()
  local itemId

  if GameTooltip:IsVisible() and GameTooltip.GetItem then
    local _, link = GameTooltip:GetItem()
    itemId = GetItemId(link)
  end

  if itemId ~= nil then
    ns.UI:SearchItem(itemId)
    return
  end

  local npcId = ns.Creature:GetUnitNpcId('mouseover')
  if npcId ~= nil and ns.Creature:GetDrops(npcId) ~= nil then
    ns.UI:ShowCreature(npcId, UnitName('mouseover'))
  else
    ns.UI:Toggle()
  end
end

function Lookup:Init(saved)
  saved.lookup = saved.lookup or {}
  self.options = saved.lookup

  if KEYS[self.options.modifier] == nil and self.options.modifier ~= 'off' then
    self.options.modifier = 'alt'
  end

  if _G.HandleModifiedItemClick then
    hooksecurefunc('HandleModifiedItemClick', function(link)
      self:_OnModifiedClick(link)
    end)
  end

  local function OnInsertLink(link)
    self:_OnInsertLink(link)
  end

  if _G.ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, 'InsertLink', OnInsertLink)
  end

  if _G.ChatEdit_InsertLink then
    hooksecurefunc('ChatEdit_InsertLink', OnInsertLink)
  end
end

-- The texts of the key binding, in the game's key bindings window
_G.BINDING_HEADER_ITEMINFO = 'ItemInfo'
_G.BINDING_NAME_ITEMINFO_LOOKUP = L['Look up the item under the mouse']
