local ADDON, ns = ...

local L = ns.L
local Scanner = ns.Scanner

-- Scans for items in the background. An update only queries the items that
-- are missing, a rebuild discards the database first.
local function StartScan(rebuild, recheck)
  local isStarted = Scanner:Start(rebuild, function(itemCount)
    ns.Print(L['The item database has been updated (%d items).']:format(itemCount))
  end, recheck)

  if isStarted then
    ns.Print(L['Scanning items in the background, those found so far can be searched meanwhile.'])
  else
    ns.Print(L['Scanning items... %d%%']:format(math.floor(Scanner:GetProgress() * 100)))
  end
end

-- Handles '/iteminfo', followed by nothing, an item's name, link or ID, or a
-- command
local function OnSlashCommand(message)
  local text = ns.Trim(message or '')
  local command = text:lower()

  if text == '' then
    ns.UI:Toggle()
  elseif command == 'update' or command == 'scan' then
    StartScan(false, true)
  elseif command == 'rebuild' then
    StartScan(true)
  elseif command == 'minimap' then
    ns.MinimapButton:Toggle()
  elseif command == 'tooltip' then
    ns.Print(ns.Tooltip:Toggle() and L['Item tooltips: on'] or L['Item tooltips: off'])
  elseif command == 'creature' or command:match('^creature%s') then
    local mode = ns.Trim(command:sub(9))

    if mode ~= '' and not ns.Tooltip:SetCreatureMode(mode) then
      ns.Print('/iteminfo creature ' .. table.concat(ns.Tooltip.CREATURE_MODES, '|'))
    else
      ns.Print(L['Creature tooltips: %s']:format(ns.Tooltip:GetCreatureModeText()))
    end
  elseif command == 'wishlist' then
    ns.UI:ShowWishlist()
  elseif command == 'map' then
    ns.Print(ns.MapPins:Toggle() and L['Wishlist pins on the map: on'] or L['Wishlist pins on the map: off'])
  elseif command == 'news' then
    ns.WhatsNew:Show()
  elseif command == 'alerts' then
    ns.Print(ns.Wishlist:ToggleAlerts() and L['Wishlist alerts: on'] or L['Wishlist alerts: off'])
  elseif command == 'target' then
    local npcId = ns.Creature:GetUnitNpcId('target')

    if npcId ~= nil and ns.Creature:GetDrops(npcId) ~= nil then
      ns.UI:ShowCreature(npcId, UnitName('target'))
    else
      ns.Print(L['Nothing is known to drop from your target.'])
    end
  elseif command == 'click' or command:match('^click%s') then
    local modifier = ns.Trim(command:sub(6))

    if modifier ~= '' and not ns.Lookup:SetModifier(modifier) then
      ns.Print('/iteminfo click ' .. table.concat(ns.Lookup.MODIFIERS, '|'))
    else
      ns.Print(L['Look-up click: %s']:format(ns.Lookup:GetModifierText()))
    end
  elseif command == 'help' or command == '?' then
    ns.Print('/iteminfo - ' .. L['open or close the window'])
    ns.Print('/iteminfo <' .. L['name, link or ID'] .. '> - ' .. L['look up an item'])
    ns.Print('/iteminfo update - ' .. L['look for new items'])
    ns.Print('/iteminfo rebuild - ' .. L['rebuild the item database'])
    ns.Print('/iteminfo minimap - ' .. L['show or hide the minimap button'])
    ns.Print('/iteminfo tooltip - ' .. L['show or hide crafting info in item tooltips'])
    ns.Print('/iteminfo click ' .. table.concat(ns.Lookup.MODIFIERS, '|') .. ' - ' ..
               L['the click that looks up an item'])
    ns.Print('/iteminfo creature ' .. table.concat(ns.Tooltip.CREATURE_MODES, '|') .. ' - ' ..
               L['what creature tooltips show of their drops'])
    ns.Print('/iteminfo target - ' .. L['list what your target drops'])
    ns.Print('/iteminfo wishlist - ' .. L['open your wishlist'])
    ns.Print('/iteminfo alerts - ' .. L['turn the wishlist alerts on or off'])
    ns.Print('/iteminfo map - ' .. L['show or hide wishlist pins on the world map'])
    ns.Print('/iteminfo news - ' .. L['what is new in this version'])
  else
    -- An item link, as inserted by a shift-click, or a bare item ID
    local itemId = tonumber(text:match('item:(%d+)') or text:match('^%d+$'))

    if itemId ~= nil and ns.GetItemInfoInstant(itemId) ~= nil then
      ns.UI:ShowItem(itemId)
    else
      ns.UI:Open(text)
    end
  end
end

-- The bootstrap waits for login, by then the saved variables are loaded
ns.On('PLAYER_LOGIN', function()
  -- Nothing saved yet means a fresh install, rather than an update
  local isFirstRun = _G.ItemInfoDB == nil or next(_G.ItemInfoDB) == nil

  _G.ItemInfoDB = _G.ItemInfoDB or {}
  _G.ItemInfoCharDB = _G.ItemInfoCharDB or {}
  local saved = _G.ItemInfoDB

  Scanner:Init(saved)
  ns.DB:Init(saved)
  ns.Merchant:Init(saved)
  ns.Wishlist:Init(_G.ItemInfoCharDB)
  ns.Tooltip:Init(saved)
  ns.Lookup:Init(saved)
  ns.Version:Init()
  ns.MinimapButton:Init(saved)
  ns.MapPins:Init(saved)
  ns.WhatsNew:Init(saved, isFirstRun)

  _G.SLASH_ITEMINFO1 = '/iteminfo'
  _G.SLASH_ITEMINFO2 = '/ii'
  _G.SlashCmdList.ITEMINFO = OnSlashCommand

  -- The database is only scanned on its own when it's empty, to finish a
  -- scan that was interrupted, or after a patch, which may have added items.
  -- Otherwise it's updated on request.
  -- Either way, the state of the database is reported once the chat has
  -- settled after login.
  local needsScan = Scanner:IsIncomplete() or Scanner:IsStale()

  C_Timer.After(5, function()
    if needsScan then
      StartScan(false)
    else
      ns.Print(L['The item database is up to date (%d items, %d recipes).']:format(
                 Scanner:GetItemCount(), ns.DB:GetRecipeCount()))
    end
  end)
end)

-- Lets other addons and macros open the encyclopedia
_G.ItemInfo = {
  Toggle = function()
    ns.UI:Toggle()
  end,
  Search = function(text)
    ns.UI:Open(text)
  end,
  ShowItem = function(itemId)
    ns.UI:ShowItem(itemId)
  end,
  ShowWishlist = function()
    ns.UI:ShowWishlist()
  end,
  -- Adds an item to the wishlist or removes it, returns whether it's on it
  ToggleWishlist = function(itemId)
    local isWanted = ns.Wishlist:Toggle(itemId)
    ns.UI:OnWishlistChanged()
    return isWanted
  end,
  -- Used by the key binding
  LookUpHovered = function()
    ns.Lookup:LookUpHovered()
  end,
}
