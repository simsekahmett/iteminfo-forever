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
  _G.ItemInfoDB = _G.ItemInfoDB or {}
  local saved = _G.ItemInfoDB

  Scanner:Init(saved)
  ns.DB:Init(saved)
  ns.Merchant:Init(saved)
  ns.Tooltip:Init(saved)
  ns.Lookup:Init(saved)
  ns.Version:Init()
  ns.MinimapButton:Init(saved)

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
  -- Used by the key binding
  LookUpHovered = function()
    ns.Lookup:LookUpHovered()
  end,
}
