local ns = NS
local function add(id, name, t) t = t or {}; t.name = name; ITEMS[id] = t end
add(5764, 'Green Silk Pack', { quality = 2, class = 1, sub = 0, typeName = 'Container', subName = 'Bag', price = 2000 })
add(5774, 'Pattern: Green Silk Pack', { quality = 2, class = 9, sub = 2, typeName = 'Recipe', subName = 'Tailoring', price = 200 })
add(5772, 'Pattern: Red Woolen Bag', { class = 9, sub = 2, typeName = 'Recipe', subName = 'Tailoring', price = 125 })
add(4305, 'Bolt of Silk Cloth', { class = 7, typeName = 'Trade Goods', subName = 'Cloth', price = 150 })
add(4234, 'Heavy Leather', { class = 7, typeName = 'Trade Goods', subName = 'Leather' })
add(2321, 'Fine Thread', { class = 7, typeName = 'Trade Goods', subName = 'Other' })
add(2605, 'Green Dye', { class = 7, typeName = 'Trade Goods', subName = 'Other', price = 25 })
add(12037, 'Mystery Meat', { class = 7, typeName = 'Trade Goods', subName = 'Meat', price = 87 })
add(7065, 'Green Silk Armor', { quality = 2, class = 4, sub = 1, typeName = 'Armor', subName = 'Cloth', slot = 'INVTYPE_ROBE' })
add(300, 'Monster - Sword', {})
add(301, 'Ünïted GREEN Écu', {})
add(302, 'Зелёный Плащ', {})
for id = 100000, 102999 do add(id, 'Filler ' .. id, { hidden = id % 10 == 0 }) end
add(289560, 'Formula: Enchant Boots - Speed', { class = 9, sub = 8, typeName = 'Recipe', subName = 'Enchanting' })

FireEvent('PLAYER_LOGIN')
assert(SlashCmdList.ITEMINFO, 'slash command missing')
Tick(6)
assert(ns.Scanner:IsScanning(), 'scan did not start')

-- Search whilst scanning
SlashCmdList.ITEMINFO('green')
local n = 0
while ns.Scanner:IsScanning() do
  Tick(0.05); n = n + 1
  assert(n < 20000, 'scan never finished at ' .. ns.Scanner:GetProgress())
end
local expected = 0
for id, i in pairs(ITEMS) do if not i.hidden and id ~= 300 then expected = expected + 1 end end
-- A query dropped on every attempt is left for the daily recheck
assert(ns.Scanner:GetItemCount() >= expected - 2, ns.Scanner:GetItemCount() .. ' ~= ' .. expected)
assert(not ns.Scanner:IsIncomplete() and not ns.Scanner:IsStale(), 'still incomplete')
print('scan: ' .. expected .. ' items in ' .. n .. ' frames, ' .. QUERIES .. ' queries')

local UI, DB = ns.UI, ns.DB
local function dump(title)
  print('--- ' .. title)
  for _, l in ipairs(UI.detailLines) do
    print(string.rep('  ', l.indent or 0) .. (l.text or '') .. (l.right and ('   [' .. tostring(l.right) .. ']') or ''))
  end
end
local function has(refs, ref) for _, r in ipairs(refs) do if r == ref then return true end end end

SlashCmdList.ITEMINFO('green')
assert(has(UI.resultRefs, 5764) and has(UI.resultRefs, 2605) and has(UI.resultRefs, 301), 'substring search')
assert(not has(UI.resultRefs, 4305))
print('"green": ' .. #UI.resultRefs .. ' results')
SlashCmdList.ITEMINFO('ÉCU'); assert(has(UI.resultRefs, 301), 'latin-1 case')
SlashCmdList.ITEMINFO('ЗЕЛЁНЫЙ'); assert(has(UI.resultRefs, 302), 'cyrillic case')

SlashCmdList.ITEMINFO('Green Silk Pack'); assert(UI.selected == 5764); dump('Green Silk Pack')
SlashCmdList.ITEMINFO('|cffffffff|Hitem:12037::::::::|h[Mystery Meat]|h|r'); assert(UI.selected == 12037); dump('Mystery Meat')
SlashCmdList.ITEMINFO('5774'); assert(UI.selected == 5774); dump('Pattern: Green Silk Pack')
FireEvent('MERCHANT_SHOW')
SlashCmdList.ITEMINFO('5772'); dump('Pattern: Red Woolen Bag (after visiting a vendor)')
SlashCmdList.ITEMINFO('Spell 1328948'); assert(UI.selected == -1328948, tostring(UI.selected)); dump('Enchant (spell)')
UI:Back(); assert(UI.selected == 5772); UI:Back(); UI:Back(); UI:Back(); UI:Back(); UI:Back()

-- Every tree node, twice (expand & collapse)
UI.editBox:SetText('')
for pass = 1, 2 do
  local i = 1
  while i <= #UI.nodes do
    local node = UI.nodes[i]
    UI:_OnTreeClick(node)
    if node.filter and node.filter.prof == 8 then
      assert(has(UI.resultRefs, 5764), 'tailoring list'); assert(UI.resultSkills[5764] == 175)
    end
    i = i + 1
  end
end
print('tree nodes: ' .. #UI.nodes)
UI.editBox:SetText('silk'); UI.selectedNode = 'prof8'; UI.filter = { prof = 8 }; UI:Search()
print('tailoring + "silk": ' .. #UI.resultRefs .. ' results')

-- Clicking a result selects that result, not the last one rendered
UI.editBox:SetText('green'); UI.selectedNode = 'all'; UI.filter = nil; UI:Search()
assert(#UI.resultRefs >= 3)
local first = UI.results.rows[1]
first.scripts.OnClick(first); assert(UI.selected == UI.resultRefs[1], 'row click selects its own entry')

-- Rows: render, hover and click
for _, list in ipairs({ UI.tree, UI.results, UI.details }) do
  list:SetOffset(3); list:ScrollTo(1)
  for _, row in ipairs(list.rows) do
    if row.entry then row.scripts.OnEnter(row); row.scripts.OnLeave(row); row.scripts.OnClick(row) end
  end
  list.frame.scripts.OnMouseWheel(list.frame, -1)
end
UI.editBox.scripts.OnTextChanged(UI.editBox, true); Tick(1); Tick(1)
ItemInfoMinimapButton.scripts.OnDragStart(); ItemInfoMinimapButton.scripts.OnUpdate(); ItemInfoMinimapButton.scripts.OnDragStop()
ItemInfoMinimapButton.scripts.OnEnter(); ItemInfoMinimapButton.scripts.OnClick(); ItemInfoMinimapButton.scripts.OnClick()
-- A category change clears the details, the same category keeps them
UI:Select(5764); UI:Select(4305)
for _, node in ipairs(UI.nodes) do if node.key == UI.selectedNode then UI:_OnTreeClick(node) end end
assert(UI.selected == 4305, 'same category keeps the details')
for _, node in ipairs(UI.nodes) do if node.filter and node.key ~= UI.selectedNode then UI:_OnTreeClick(node) break end end
assert(UI.selected == nil and #UI.detailLines == 0 and #UI.history == 0, 'category change clears the details')

-- An update finds what's new without discarding the database
add(250000, 'Brand New Item', {}); local before = ns.Scanner:GetItemCount()
SlashCmdList.ITEMINFO('update'); assert(ns.Scanner:IsScanning()); n = 0
while ns.Scanner:IsScanning() do Tick(0.05); n = n + 1; assert(n < 20000) end
assert(ns.Scanner:GetName(250000) == 'Brand New Item' and ns.Scanner:GetItemCount() >= before + 1, 'update')
expected = expected + 1
for _, c in ipairs({ '', '', 'help', 'minimap', 'minimap', 'rebuild', 'rebuild', 'nothing matches this' }) do SlashCmdList.ITEMINFO(c) end
assert(ns.Scanner:IsScanning()); n = 0
while ns.Scanner:IsScanning() do Tick(0.05); n = n + 1; assert(n < 20000) end
assert(ns.Scanner:GetItemCount() >= expected - 2, 'rebuild count')
for _, m in ipairs(CHATLOG) do print('chat> ' .. m) end

-- A patch makes the database stale, which a login then scans for
ns.Scanner.db.build = ns.Scanner.db.build - 1
assert(ns.Scanner:IsStale() and not ns.Scanner:IsIncomplete(), 'stale after a patch')

-- Item tooltips
local function tip(title, id)
  print('--- tooltip: ' .. title)
  for _, line in ipairs(ShowItemTooltip(id)) do print(line) end
  return #TIP
end
assert(tip('Green Silk Pack', 5764) > 5)
local folded = tip('Bolt of Silk Cloth (folded)', 4305)
assert(ns.Tooltip.folded ~= nil and ns.Tooltip.folded.itemId == 4305)
TIP_OWNER = CreateFrame('Frame')
-- The owner's OnEnter must never be called, it would taint action buttons
local entered = 0
TIP_OWNER:SetScript('OnEnter', function() entered = entered + 1 end)
ShowItemTooltip(4305)
SHIFT = true; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 1)
assert(#TIP > folded, 'shift unfolds the list'); print('unfolded: ' .. #TIP .. ' lines')
SHIFT = false; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 0); assert(#TIP == folded, 'release folds it again')
assert(entered == 0, 'the owner is not entered again')
-- Shift over another tooltip, after a folded one, refreshes nothing
local refreshes = REFRESHES
ShowItemTooltip(4305); TIP_ITEM = nil
SHIFT = true; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 1); SHIFT = false
assert(REFRESHES == refreshes and entered == 0, 'stale fold is ignored')
ShowItemTooltip(4305); TIP_OWNER = CreateFrame('Frame')
SHIFT = true; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 1); SHIFT = false
assert(REFRESHES == refreshes, 'another owner is ignored')
-- Hiding the tooltip forgets the fold
ShowItemTooltip(4305); GameTooltip.scripts.OnHide(GameTooltip)
assert(ns.Tooltip.folded == nil, 'fold forgotten on hide')
assert(tip('Filler (nothing to add)', 100001) == 0)
SlashCmdList.ITEMINFO('tooltip'); assert(#ShowItemTooltip(5764) == 0, 'tooltips off')
SlashCmdList.ITEMINFO('tooltip'); assert(#ShowItemTooltip(5764) > 5, 'tooltips on')

-- A login with a complete database reports its state instead of scanning
ns.Scanner.db.build = ns.Scanner.build
local chatCount = #CHATLOG
FireEvent('PLAYER_LOGIN'); Tick(6)
assert(not ns.Scanner:IsScanning(), 'no scan when up to date')
assert(CHATLOG[#CHATLOG]:find(tostring(ns.DB:GetRecipeCount())) and #CHATLOG == chatCount + 1, 'state reported on login')
print('login> ' .. CHATLOG[#CHATLOG])

-- The professions an item is used by are shown as icons, once each
ShowItemTooltip(4305)
local header
for _, line in ipairs(TIP) do if line:find(ns.L['Used in'], 1, true) then header = line end end
local _, iconCount = header:gsub('|T', '')
assert(iconCount >= 2 and iconCount <= 10, 'profession icons: ' .. header)
print('header> ' .. header)

-- Vendors of any item, nearest first, folded beyond three
ShowItemTooltip(6256)
ITEMS[6256] = { name = 'Fishing Pole', class = 2, sub = 20 }
local lines = ShowItemTooltip(6256)
local header, firstVendor
for index, line in ipairs(lines) do
  if line:find(ns.L['Sold by'] .. ' (', 1, true) then header = index end
end
-- Only vendors serving the player's faction (Horde in the tests) are listed
local shown = tonumber(lines[header]:match('%((%d+)%)'))
assert(shown > 3 and shown < 77, 'faction filtered vendor count: ' .. lines[header])
local zoneOf
for _, npcId in ipairs(ns.Data.vendors[6256]) do
  local _, zone, x, _, friendly = ns.DB:GetNpc(npcId)
  if zone and x >= 0 and friendly == 'H' then zoneOf = zone end
end
ZONE = zoneOf
lines = ShowItemTooltip(6256)
for index, line in ipairs(lines) do
  if line:find(ns.L['Sold by'] .. ' (', 1, true) then firstVendor = lines[index + 1] end
end
assert(firstVendor:find(zoneOf, 1, true) and firstVendor:find('%(%d+, %d+%)'), 'nearest vendor first: ' .. firstVendor)
assert(ns.Tooltip.folded ~= nil, 'long vendor list folds')
print('fishing pole> ' .. firstVendor)
ZONE = nil

-- Quest rewards: only quests of the player's faction (Horde), lowest level first
ITEMS[118] = { name = 'Minor Healing Potion', class = 0 }
local lines = ShowItemTooltip(118)
local header
for index, line in ipairs(lines) do
  if line:find(ns.L['Quest reward'] .. ' (', 1, true) then header = index end
end
assert(header and lines[header]:find('(3)', 1, true), 'faction filtered quests: ' .. tostring(header and lines[header]))
for index = header + 1, header + 3 do print('quest> ' .. lines[index]) end
local quests = ns.DB:GetUsableQuestRewards(118)
for _, questId in ipairs(quests) do assert(select(4, ns.DB:GetQuest(questId)) ~= 'A', 'no Alliance quests') end
-- An item rewarded only by quests of the other faction still lists them
ITEMS[60] = { name = 'Layered Tunic', class = 4 }
assert(#ns.DB:GetUsableQuestRewards(60) == 1, 'fallback to all quests')
-- The window lists the quest and its giver
NS.UI:ShowItem(60)
local found
for _, line in ipairs(NS.UI.detailLines) do
  if (line.text or ''):find(ns.L['Quest giver'], 1, true) then found = line.text end
end
assert(found, 'quest giver in the window'); print('giver> ' .. found)

-- Version check: announced to the guild after login
SENT = {}
Tick(11)
local announced
for _, m in ipairs(SENT) do if m[2] == 'V;v1.1.1' and m[3] == 'GUILD' then announced = true end end
assert(announced, 'version announced to the guild')
local function receive(text, channel, sender)
  FireEvent('CHAT_MSG_ADDON', 'ItemInfo', text, channel or 'GUILD', sender or 'Friend-Realm')
end
-- An older client is answered by whisper, nothing is printed
SENT = {}; local chats = #CHATLOG
receive('V;v1.0.0')
assert(#SENT == 1 and SENT[1][3] == 'WHISPER' and SENT[1][4] == 'Friend-Realm', 'older client answered')
assert(#CHATLOG == chats, 'nothing printed for an older version')
-- A newer version is printed once
receive('V;v1.2.0'); receive('V;v1.2.0', 'WHISPER'); receive('V;1.2.0')
assert(#CHATLOG == chats + 1 and CHATLOG[#CHATLOG]:find('v1.2.0', 1, true), 'newer version printed once')
print('notice> ' .. CHATLOG[#CHATLOG])
receive('V;v1.3.0'); assert(#CHATLOG == chats + 2, 'an even newer version is printed')
-- Betas, development copies and junk are ignored, and whispers are not answered
SENT = {}
for _, text in ipairs({ 'V;v9.0.0-beta1', 'V;@project-version@', 'V;', 'V;1', 'V;v1.0.0.0', 'Z;1' }) do receive(text) end
receive('V;v1.0.0', 'WHISPER')
assert(#CHATLOG == chats + 2 and #SENT == 0, 'ignored')
-- A development copy takes no part
ADDON_VERSION = '@project-version@'; SENT = {}
ns.Version:Init(); Tick(11)
for _, m in ipairs(SENT) do assert(not m[2]:find('^V;'), 'development copy announced') end
ADDON_VERSION = 'v1.1.1'

-- Drops of any item: listed creatures, nearest first, or a world drop summary
ITEMS[287013] = { name = "Krol'dok Warplate Legplates", class = 4, sub = 4 }
local lines = ShowItemTooltip(287013)
local header
for index, line in ipairs(lines) do if line:find(ns.L['Dropped by'] .. ' (', 1, true) then header = index end end
assert(header and lines[header]:find('(' .. #ns.DB:GetDrops(287013) .. ')', 1, true), 'creatures listed: ' .. tostring(header and lines[header]))
for index = header, header + 4 do print('drops> ' .. (lines[index] or '')) end
local worldDrop
for itemId, drop in pairs(ns.Data.drops) do if #drop == 1 then worldDrop = itemId break end end
ITEMS[worldDrop] = { name = 'Some World Drop', class = 4 }
local summary
for _, line in ipairs(ShowItemTooltip(worldDrop)) do
  if line:find(ns.L['Dropped by'], 1, true) then summary = line end
end
assert(summary and summary:find('%d'), 'world drop summary'); print('world> ' .. summary)

-- Look-up clicks: Alt by default, exactly those keys, left button only
local function link(id) return '|cffffffff|Hitem:' .. id .. '::::::::|h[' .. ITEMS[id].name .. ']|h|r' end
UI.frame:Hide(); UI:Select(5764)
ALT = true; HandleModifiedItemClick(link(4305)); ALT = false
assert(UI.frame:IsShown() and UI.selected == 4305 and UI.editBox:GetText() == 'Bolt of Silk Cloth', 'alt-click looks up')
assert(has(UI.resultRefs, 4305), 'alt-click searches the name')
ALT, CTRL = true, true; HandleModifiedItemClick(link(2605)); ALT, CTRL = false, false
assert(UI.selected == 4305, 'ctrl-alt is not alt')
ALT, MOUSE_BUTTON = true, 'RightButton'; HandleModifiedItemClick(link(2605)); ALT, MOUSE_BUTTON = false, 'LeftButton'
assert(UI.selected == 4305, 'a right-click is left alone')
HandleModifiedItemClick(link(2605)); assert(UI.selected == 4305, 'a plain click is left alone')
-- The modifier is configurable and saved
SlashCmdList.ITEMINFO('click ctrl-alt'); assert(ItemInfoDB.lookup.modifier == 'ctrl-alt')
ALT = true; HandleModifiedItemClick(link(2605)); ALT = false
assert(UI.selected == 4305, 'alt no longer looks up')
ALT, CTRL = true, true; HandleModifiedItemClick(link(2605)); ALT, CTRL = false, false
assert(UI.selected == 2605, 'ctrl-alt looks up')
SlashCmdList.ITEMINFO('click nonsense'); assert(ItemInfoDB.lookup.modifier == 'ctrl-alt', 'unknown modifier ignored')
print('click> ' .. CHATLOG[#CHATLOG])
-- The tooltip tells which click to use, and nothing when it's off
local function hint() for _, line in ipairs(ShowItemTooltip(4305)) do if line:find('ItemInfo', 1, true) then return line end end end
assert(hint() and hint():find('Ctrl-Alt', 1, true), 'hint names the modifier'); print('hint> ' .. hint())
assert(#ShowItemTooltip(100001) == 0, 'no hint where there is nothing else')
SlashCmdList.ITEMINFO('click off'); assert(hint() == nil, 'no hint when off')
ALT, CTRL = true, true; HandleModifiedItemClick(link(5764)); ALT = true; CTRL = false; HandleModifiedItemClick(link(5764)); ALT = false
assert(UI.selected == 2605, 'off looks nothing up')
SlashCmdList.ITEMINFO('click'); SlashCmdList.ITEMINFO('click alt'); assert(ItemInfoDB.lookup.modifier == 'alt')

-- A shift-click fills the search box only while it has focus
SHIFT = true; HandleModifiedItemClick(link(5764)); SHIFT = false
assert(UI.selected == 2605 and #INSERTED == 1, 'a shift-click links in chat as usual')
UI.editBox:SetFocus()
SHIFT = true; HandleModifiedItemClick(link(5764)); SHIFT = false
assert(UI.selected == 5764 and UI.editBox:GetText() == 'Green Silk Pack', 'shift-click fills the search box')
local history = #UI.history
Tick(1); SHIFT = true; HandleModifiedItemClick(link(5764)); SHIFT = false
assert(#UI.history == history, 'the same link twice changes nothing')
FOCUS = nil

-- The key binding looks up the hovered item, or toggles the window
TIP_ITEM = 12037; ItemInfo.LookUpHovered(); assert(UI.selected == 12037, 'binding looks up the hovered item')
TIP_ITEM = nil; local shown = UI.frame:IsShown(); ItemInfo.LookUpHovered()
assert(UI.frame:IsShown() ~= shown, 'binding toggles the window with nothing hovered')
assert(BINDING_NAME_ITEMINFO_LOOKUP and BINDING_HEADER_ITEMINFO == 'ItemInfo')

-- Creature tooltips: the notable drops, the creature's own loot first
local Creature, Wishlist = ns.Creature, ns.Wishlist
-- The second login above registered the tooltip hooks again, as the game never does
UNIT_CALLS = { UNIT_CALLS[#UNIT_CALLS] }
local busyNpc, busyCount = nil, 0
for npcId, drops in pairs(Creature:_Index()) do
  if #drops > busyCount or (#drops == busyCount and npcId < busyNpc) then busyNpc, busyCount = npcId, #drops end
end
assert(busyCount > 20, 'a creature with many drops: ' .. busyCount)
local guid = 'Creature-0-1-2-3-' .. busyNpc .. '-0000ABCDEF'
-- Its drops become known items of mixed quality: plate, cloth and junk
local drops = Creature:GetDrops(busyNpc)
for index, itemId in ipairs(drops) do
  local kind = index % 4
  ITEMS[itemId] = { name = 'Drop ' .. itemId, class = kind == 0 and 15 or 4, sub = kind == 1 and 4 or 1 }
  ns.Scanner.db.quality[itemId] = kind == 0 and 0 or (index % 3) + 2
end
local notable, total = Creature:GetNotable(busyNpc)
assert(total == busyCount and #notable > 3 and #notable < busyCount, 'junk is not notable: ' .. #notable .. '/' .. total)
-- Plate is pushed down for a mage, below cloth of the same quality and rarity
local plateRank, clothRank = {}, {}
for rank, itemId in ipairs(notable) do
  local key = ns.Scanner.db.quality[itemId] .. ':' .. ns.Data.drops[itemId][1]
  if ITEMS[itemId].sub == 4 then plateRank[key] = plateRank[key] or rank else clothRank[key] = clothRank[key] or rank end
end
for key, rank in pairs(plateRank) do assert(clothRank[key] == nil or clothRank[key] < rank, 'cloth before plate ' .. key) end

local function lineWith(lines, text) for index, line in ipairs(lines) do if line:find(text, 1, true) then return index, line end end end
local lines = ShowUnitTooltip(guid)
local header = lineWith(lines, ns.L['Drops'] .. ' (' .. busyCount .. ')')
assert(header, 'drops header')
for index = header, #lines do print('creature> ' .. lines[index]) end
assert(#lines == header + 4 and lines[header + 4]:find(ns.L['Hold Shift for %d more']:format(#notable - 3), 1, true), 'three drops, then a fold')
assert(lines[header + 1]:find(ns.DB:GetName(notable[1]), 1, true), 'the best drop first')
-- Shift unfolds, release folds again
TIP_OWNER = CreateFrame('Frame'); ShowUnitTooltip(guid)
SHIFT = true; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 1)
assert(#TIP == header + math.min(#notable, 15) + (#notable > 15 and 1 or 0), 'shift unfolds the drops: ' .. #TIP)
SHIFT = false; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 0)
assert(#TIP == header + 4, 'release folds the drops')
-- The key binding is named when one is set
BINDING_KEY = 'F5'; lines = ShowUnitTooltip(guid); BINDING_KEY = nil
assert(lines[#lines]:find('F5', 1, true), 'binding hint')
-- Players, objects and creatures with no known drops add nothing
assert(#ShowUnitTooltip('Player-1-0ABC') == 0 and #ShowUnitTooltip('Creature-0-1-2-3-1-0000') == 0, 'nothing to add')

-- The wishlist: always shown, starred, whatever the rank
local wanted = notable[#notable]
Wishlist:Toggle(wanted)
lines = ShowUnitTooltip(guid)
assert(lines[header + 1]:find(Wishlist.STAR, 1, true) and lines[header + 1]:find(ns.DB:GetName(wanted), 1, true), 'wishlist first')
assert(#lines == header + 5, 'wishlist on top of the three')
SlashCmdList.ITEMINFO('creature wishlist'); lines = ShowUnitTooltip(guid)
assert(#lines == header + 1 and lines[#lines]:find(Wishlist.STAR, 1, true), 'wishlist only')
SlashCmdList.ITEMINFO('creature off'); assert(#ShowUnitTooltip(guid) == 0, 'creature tooltips off')
SlashCmdList.ITEMINFO('creature nonsense'); assert(ns.Tooltip:GetCreatureMode() == 'off', 'unknown mode ignored')
SlashCmdList.ITEMINFO('creature all'); print('mode> ' .. CHATLOG[#CHATLOG])
SlashCmdList.ITEMINFO('tooltip'); assert(#ShowUnitTooltip(guid) == 0, 'tooltips off hides creatures too')
SlashCmdList.ITEMINFO('tooltip')
-- Item tooltips tell an item is on the wishlist
assert(lineWith(ShowItemTooltip(wanted), ns.L['On your wishlist']), 'wishlist line in item tooltip')

-- Alerts: targeting a creature that drops a wanted item, once in a while
local chats = #CHATLOG
UNIT_GUIDS.target = guid; FireEvent('PLAYER_TARGET_CHANGED')
assert(#CHATLOG == chats + 1 and CHATLOG[#CHATLOG]:find(ns.DB:GetName(wanted), 1, true), 'target alert')
print('alert> ' .. CHATLOG[#CHATLOG])
FireEvent('PLAYER_TARGET_CHANGED'); assert(#CHATLOG == chats + 1, 'not twice in a row')
NOW = NOW + 301; FireEvent('PLAYER_TARGET_CHANGED'); assert(#CHATLOG == chats + 2, 'again after a while')
SlashCmdList.ITEMINFO('alerts'); NOW = NOW + 301; chats = #CHATLOG
FireEvent('PLAYER_TARGET_CHANGED'); assert(#CHATLOG == chats, 'alerts off')
SlashCmdList.ITEMINFO('alerts'); chats = #CHATLOG
-- A vendor that sells a wanted item
Wishlist:Add(5772); UNIT_GUIDS.npc = nil
FireEvent('MERCHANT_SHOW'); assert(CHATLOG[#CHATLOG]:find('Pattern: Red Woolen Bag', 1, true), 'vendor alert')
print('alert> ' .. CHATLOG[#CHATLOG])
-- Getting one takes it off the list, having had some before counts the next
ITEM_COUNTS[2605] = 3; Wishlist:Add(2605); FireEvent('BAG_UPDATE_DELAYED')
assert(Wishlist:Has(2605) and Wishlist:Has(5772), 'nothing obtained yet')
ITEM_COUNTS[5772] = 1; ITEM_COUNTS[2605] = 4; FireEvent('BAG_UPDATE_DELAYED')
assert(not Wishlist:Has(5772) and not Wishlist:Has(2605) and Wishlist:Has(wanted), 'obtained items are off the list')
print('alert> ' .. CHATLOG[#CHATLOG])

-- The window: the wishlist category, the star and a creature's full loot
SlashCmdList.ITEMINFO('wishlist')
assert(UI.selectedNode == 'wishlist' and #UI.resultRefs == 1 and UI.resultRefs[1] == wanted, 'wishlist category')
UI:Select(4305); assert(UI.starButton:IsShown(), 'star for an item')
NOW = NOW + 1; UI.starButton.scripts.OnClick(UI.starButton)
assert(Wishlist:Has(4305) and #UI.resultRefs == 2 and UI.resultRefs[1] == 4305, 'star adds, newest first')
UI.starButton.scripts.OnEnter(UI.starButton)
UI.starButton.scripts.OnClick(UI.starButton); assert(not Wishlist:Has(4305) and #UI.resultRefs == 1, 'star removes')
UI:Select(-1328948); assert(not UI.starButton:IsShown(), 'no star for a spell')
assert(ItemInfo.ToggleWishlist(2605) == true and ItemInfoCharDB.wishlist[2605], 'API and per-character storage')
ItemInfo.ToggleWishlist(2605)
-- The key binding over a creature lists all it drops, the notable first
TIP_ITEM = nil; UNIT_GUIDS.mouseover = guid; ItemInfo.LookUpHovered()
assert(UI.filter.npc == busyNpc and #UI.resultRefs == busyCount and UI.resultRefs[1] == wanted, 'creature loot in the window')
local npcNode; for _, node in ipairs(UI.nodes) do if node.key == 'npc' then npcNode = node end end
assert(npcNode and npcNode.selected, 'creature node'); print('status> ' .. UI.status:GetText())
UI.editBox:SetText(ns.DB:GetName(wanted)); UI:Search()
assert(#UI.resultRefs == 1 and UI.resultRefs[1] == wanted and UI.filter.npc == busyNpc, 'search within the loot')
UNIT_GUIDS.mouseover = 'Player-1-0ABC'; local shown = UI.frame:IsShown(); ItemInfo.LookUpHovered()
assert(UI.frame:IsShown() ~= shown, 'a player toggles the window')
UNIT_GUIDS.target = 'Player-1-0ABC'; SlashCmdList.ITEMINFO('target')
assert(CHATLOG[#CHATLOG]:find(ns.L['Nothing is known to drop from your target.'], 1, true), 'nothing for a player')
UNIT_GUIDS.target = guid; SlashCmdList.ITEMINFO('target'); assert(UI.filter.npc == busyNpc, '/ii target')
for _, node in ipairs(UI.nodes) do if node.key == 'all' then UI:_OnTreeClick(node) end end
for _, node in ipairs(UI.nodes) do assert(node.key ~= 'npc', 'the creature node leaves with another category') end

-- What's new: never on a fresh install, once after an update, not in combat
local WhatsNew = ns.WhatsNew
local newest = WhatsNew.NOTES[1].version
assert(ItemInfoWhatsNewFrame == nil and ItemInfoDB.whatsNew == newest, 'a fresh install shows nothing')
ItemInfoDB.whatsNew = '1.4.0'
FireEvent('PLAYER_LOGIN'); Tick(2)
assert(ItemInfoWhatsNewFrame == nil, 'not before the chat settles')
Tick(3)
assert(ItemInfoWhatsNewFrame and ItemInfoWhatsNewFrame:IsShown() and ItemInfoDB.whatsNew == newest, 'shown after an update')
assert(WhatsNew.title:GetText():find(newest, 1, true) and WhatsNew.lines >= 3, 'title and notes')
for index = 1, WhatsNew.lines do print('news> ' .. WhatsNew.texts[index]:GetText()) end
ItemInfoWhatsNewFrame:Hide()
FireEvent('PLAYER_LOGIN'); Tick(5)
assert(not ItemInfoWhatsNewFrame:IsShown(), 'only once')
-- An update noticed in combat waits for it to end
ItemInfoDB.whatsNew = '1.4.0'; COMBAT = true
FireEvent('PLAYER_LOGIN'); Tick(5)
assert(not ItemInfoWhatsNewFrame:IsShown() and ItemInfoDB.whatsNew == '1.4.0', 'not in combat')
COMBAT = false; FireEvent('PLAYER_REGEN_ENABLED')
assert(ItemInfoWhatsNewFrame:IsShown() and ItemInfoDB.whatsNew == newest, 'after combat')
ItemInfoWhatsNewFrame:Hide(); FireEvent('PLAYER_REGEN_ENABLED')
assert(not ItemInfoWhatsNewFrame:IsShown(), 'once after combat too')
-- Asked for, it shows again
SlashCmdList.ITEMINFO('news'); assert(ItemInfoWhatsNewFrame:IsShown(), '/iteminfo news')
-- Every note has a translation in every language
for _, notes in ipairs(WhatsNew.NOTES) do
  for _, section in ipairs(notes.sections) do
    assert(ns.L[section.title] ~= nil)
    for _, line in ipairs(section.lines) do assert(TEST_LOCALE == 'enUS' or ns.L[line] ~= line, 'untranslated: ' .. line) end
  end
end

-- Texture paths keep their backslashes, a lone one is eaten by Lua
UI:Select(4305)
assert(UI.starButton:IsShown() and UI.starButton.label:GetText():find(ns.L['Add to wishlist'], 1, true), 'labeled star')
for _, node in ipairs(UI.nodes) do if node.key == 'wishlist' then assert(node.icon:find('TargetingFrame\\UI', 1, true), 'star texture path: ' .. node.icon) end end

-- Adding and removing tell so in chat, with the item's link
local chats = #CHATLOG
UI.starButton.scripts.OnClick(UI.starButton)
assert(#CHATLOG == chats + 1 and CHATLOG[#CHATLOG]:find(ns.L['%s added to your wishlist.']:format(select(2, ns.GetItemInfo(4305))), 1, true), 'added in chat')
print('chat> ' .. CHATLOG[#CHATLOG])
UI.starButton.scripts.OnClick(UI.starButton)
assert(#CHATLOG == chats + 2 and CHATLOG[#CHATLOG]:find('Bolt of Silk Cloth', 1, true), 'removed in chat')
print('chat> ' .. CHATLOG[#CHATLOG])
ns.Wishlist:Remove(4305); assert(#CHATLOG == chats + 2, 'nothing to remove, nothing said')

-- Map pins: a world map that loads after ItemInfo, as the game's map framework draws them
MapCanvasDataProviderMixin = {
  OnAdded = function(self, map) self.owningMap = map end,
  GetMap = function(self) return self.owningMap end,
}
MapCanvasPinMixin = {
  SetPosition = function(self, x, y) self.px, self.py = x, y end,
  UseFrameLevelType = function(self, levelType) self.levelType = levelType end,
}
WorldMapFrame = CreateFrame('Frame'); WorldMapFrame.pins = {}
-- The map knows the topmost level of pins
function WorldMapFrame:GetPinFrameLevelsManager()
  return { GetValidFrameLevel = function(_, levelType) return levelType == 'PIN_FRAME_LEVEL_TOPMOST' and 900 or nil end }
end
function WorldMapFrame:AddDataProvider(provider) self.provider = provider; provider:OnAdded(self) end
function WorldMapFrame:GetMapID() return MAP_ID end
function WorldMapFrame:RemoveAllPinsByTemplate(template) assert(template == 'ItemInfoMapPinTemplate'); self.pins = {} end
-- Another addon's pin, with an icon a level up, as Questie draws creatures
local function leveled(level, children)
  local frame = CreateFrame('Frame'); frame.level = level
  function frame:GetFrameLevel() return self.level end
  function frame:SetFrameLevel(level) self.level = level end
  function frame:GetChildren() return unpack(children or {}) end
  return frame
end
local questieIcon = leveled(950)
local canvasChildren = { leveled(800, { questieIcon }), leveled(20) }
local canvas = CreateFrame('Frame')
function canvas:GetChildren() local all = { unpack(canvasChildren) }; for _, pin in ipairs(WorldMapFrame.pins) do all[#all + 1] = pin end; return unpack(all) end
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:AcquirePin(template, ...)
  local pin = leveled(500)
  for key, value in pairs(ItemInfoMapPinMixin) do pin[key] = value end
  pin:OnLoad(); pin:OnAcquired(...)
  self.pins[#self.pins + 1] = pin
  return pin
end
-- Every map ID is a zone named as the area of the same ID, 9000 is a continent
C_Map.GetMapInfo = function(id)
  if id == 9000 then return { name = 'Continent', mapType = 2 } end
  if id <= 5000 then return { name = 'Zone' .. id, mapType = 3 } end
end
C_Map.GetMapRectOnMap = function() return 0.2, 0.6, 0.1, 0.5 end

local MapPins = ns.MapPins
FireEvent('ADDON_LOADED', 'Blizzard_WorldMap')
assert(MapPins.isAdded and WorldMapFrame.provider ~= nil, 'added once the world map loads')
local wantedNpcs = {}
for _, npcId in ipairs(ns.DB:GetDrops(wanted)) do
  local npc = ns.Data.npcs[npcId]
  if npc and npc[2] > 0 and npc[2] <= 5000 and npc[3] >= 0 then wantedNpcs[#wantedNpcs + 1] = npcId end
end
assert(#wantedNpcs > 0, 'creatures with a position')
local npc = ns.Data.npcs[wantedNpcs[1]]
MAP_ID = npc[2]
WorldMapFrame.provider:RefreshAllData()
-- A zone map has a star at each place a creature spawns at
local function spawnCount(npcId) local spawns = ns.Data.spawns[npcId]; return spawns and #spawns / 2 or 1 end
local inZone = 0
for _, npcId in ipairs(wantedNpcs) do if ns.Data.npcs[npcId][2] == MAP_ID then inZone = inZone + spawnCount(npcId) end end
assert(#WorldMapFrame.pins == inZone, 'the zone map pins its creatures: ' .. #WorldMapFrame.pins .. '/' .. inZone)
local pin
for _, p in ipairs(WorldMapFrame.pins) do if p.npcId == wantedNpcs[1] then pin = pin or p end end
assert(pin and math.abs(pin.px - npc[3] / 100) < 1e-9 and math.abs(pin.py - npc[4] / 100) < 1e-9, 'pinned where the creature is')
assert(pin.itemIds[1] == wanted, 'the pin knows the items')
assert(pin.levelType == 'PIN_FRAME_LEVEL_TOPMOST', 'the topmost level of the map')
assert(pin.level == 951, 'stars above the icons of other addons: ' .. pin.level)
-- Icons drawn right after the map opened are covered a moment later
questieIcon.level = 1200; Tick(0.3)
assert(pin.level == 1201, 'lifted above icons drawn later: ' .. pin.level)
-- One star failing leaves the others
local acquire = WorldMapFrame.AcquirePin
local calls = 0
WorldMapFrame.AcquirePin = function(self, ...) calls = calls + 1; if calls == 1 then error('boom') end; return acquire(self, ...) end
local handled = geterrorhandler
local reported
geterrorhandler = function() return function(message) reported = message end end
WorldMapFrame.provider:RefreshAllData()
assert(reported and reported:find('boom') and #WorldMapFrame.pins == inZone - 1, 'the other stars stay: ' .. #WorldMapFrame.pins)
WorldMapFrame.AcquirePin, geterrorhandler = acquire, handled
WorldMapFrame.provider:RefreshAllData(); assert(#WorldMapFrame.pins == inZone, 'all back')
TIP = {}; pin:OnMouseEnter(); pin:OnMouseLeave()
print('pin> ' .. table.concat(TIP, ' | '))
-- A continent map shows every creature, placed within its zone
MAP_ID = 9000; WorldMapFrame.provider:RefreshAllData()
assert(#WorldMapFrame.pins == #wantedNpcs, 'continent pins: ' .. #WorldMapFrame.pins)
for _, p in ipairs(WorldMapFrame.pins) do
  local n = ns.Data.npcs[p.npcId]
  assert(math.abs(p.px - (0.2 + n[3] / 100 * 0.4)) < 1e-9 and math.abs(p.py - (0.1 + n[4] / 100 * 0.4)) < 1e-9, 'placed in the zone')
end
-- Another zone shows none of them
MAP_ID = MAP_ID == 4999 and 4998 or 4999
local other = 0
for _, npcId in ipairs(wantedNpcs) do if ns.Data.npcs[npcId][2] == MAP_ID then other = other + spawnCount(npcId) end end
WorldMapFrame.provider:RefreshAllData(); assert(#WorldMapFrame.pins == other, 'other zone')
-- The pins follow the wishlist and the option, while the map is open
MAP_ID = 9000; WorldMapFrame:Show(); WorldMapFrame.provider:RefreshAllData()
SlashCmdList.ITEMINFO('map'); assert(#WorldMapFrame.pins == 0 and not ItemInfoDB.mapPins.enabled, 'map pins off')
print('map> ' .. CHATLOG[#CHATLOG])
SlashCmdList.ITEMINFO('map'); assert(#WorldMapFrame.pins == #wantedNpcs, 'map pins on')
ItemInfo.ToggleWishlist(wanted); assert(#WorldMapFrame.pins < #wantedNpcs or #wantedNpcs == 0, 'removed from the wishlist, off the map')
ItemInfo.ToggleWishlist(wanted); assert(#WorldMapFrame.pins == #wantedNpcs, 'back on the map')

-- A creature that roams has a star at each of its places, the first where it is known to be
local roamer, roamerSpawns
for npcId, spawns in pairs(ns.Data.spawns) do
  local npc = ns.Data.npcs[npcId]
  if npc and npc[2] > 0 and npc[2] <= 5000 and #spawns >= 6 and (roamer == nil or npcId < roamer) then roamer, roamerSpawns = npcId, spawns end
end
assert(roamer and #roamerSpawns <= 20, 'creatures with up to ten spawns')
local roamerNpc = ns.Data.npcs[roamer]
assert(roamerSpawns[1] == roamerNpc[3] and roamerSpawns[2] == roamerNpc[4], 'the first spawn is the known one')
local roamerItem
for itemId, drop in pairs(ns.Data.drops) do
  for index = 2, #drop do if drop[index] == roamer then roamerItem = roamerItem or itemId end end
end
for itemId in pairs(Wishlist.items) do Wishlist.items[itemId] = nil end
Wishlist:Add(roamerItem); MAP_ID = roamerNpc[2]; WorldMapFrame.provider:RefreshAllData()
local roamerPins = 0
for _, p in ipairs(WorldMapFrame.pins) do if p.npcId == roamer then roamerPins = roamerPins + 1 end end
assert(roamerPins == #roamerSpawns / 2, 'a star per spawn: ' .. roamerPins)
MAP_ID = 9000; WorldMapFrame.provider:RefreshAllData()
roamerPins = 0
for _, p in ipairs(WorldMapFrame.pins) do if p.npcId == roamer then roamerPins = roamerPins + 1 end end
assert(roamerPins == 1, 'one star on the continent')
Wishlist:Remove(roamerItem)

-- Recipes: whether the player and the other characters know them or can learn them
local L, Professions = ns.L, ns.Professions
-- The logins above registered the item tooltip hook again, as the game never does
TOOLTIP_CALLS = { TOOLTIP_CALLS[#TOOLTIP_CALLS] }
local function tipText(itemId) return table.concat(ShowItemTooltip(itemId), '\n') end
SKILL_LINES = { { 'Professions', header = true, expanded = true }, { 'Tailoring', 150, 225 } }
FireEvent('SKILL_LINES_CHANGED')
-- Pattern: Green Silk Pack needs Tailoring 175, Pattern: Red Woolen Bag 115
assert(Professions:GetStatus(6693) == 'later' and Professions:GetStatus(6688) == 'learnable', 'by skill')
local text = tipText(5774)
assert(text:find(L['You can learn this recipe at %s %d (you have %d)']:format('Tailoring', 175, 150), 1, true), text)
assert(tipText(5772):find(L['You can learn this recipe'], 1, true), 'learnable')
-- The profession window lists what is known, by name or by the recipe's link
TRADE = { { 'Tailoring', 'header' }, { 'Spell 6688', 'optimal' }, { 'Something else', 'easy', '|Henchant:3757|h' } }
FireEvent('TRADE_SKILL_SHOW')
assert(Professions:GetStatus(6688) == 'known' and Professions:GetStatus(3757) == 'known', 'known from the window')
assert(tipText(5772):find(L['You already know this recipe'], 1, true), 'known in the tooltip')
-- Learning a recipe, as the chat tells
SKILL_LINES[2][2] = 180; FireEvent('SKILL_LINES_CHANGED')
assert(Professions:GetStatus(6693) == 'learnable', 'skill raised')
FireEvent('CHAT_MSG_SYSTEM', ERR_LEARN_RECIPE_S:format('Spell 6693'))
assert(Professions:GetStatus(6693) == 'known', 'learnt')
-- Other characters of the realm with the profession
ItemInfoDB.characters.Testrealm.Alty = { class = 'PRIEST', skills = { [8] = { 120, 150 } }, known = {} }
ItemInfoDB.characters.Testrealm.Brewer = { class = 'WARRIOR', skills = { [6] = { 50, 75 } }, known = {} }
ItemInfoDB.characters.Otherrealm = { Faraway = { skills = { [8] = { 300, 300 } }, known = {} } }
local alts = Professions:GetAlts(6688)
assert(#alts == 1 and alts[1].name == 'Alty' and alts[1].status == 'learnable', 'alts of the realm with the profession')
text = tipText(5774)
assert(text:find(L['%s can learn it at %d (has %d)']:format('Alty', 175, 120), 1, true), text)
print('recipe> ' .. (text:gsub('\n', ' | ')))
-- A collapsed header hides lines, a profession is only forgotten once all are shown
SKILL_LINES = { { 'Professions', header = true, expanded = false } }; FireEvent('SKILL_LINES_CHANGED')
assert(Professions:GetStatus(6693) == 'known', 'kept under a collapsed header')
SKILL_LINES = { { 'Professions', header = true, expanded = true } }; FireEvent('SKILL_LINES_CHANGED')
assert(Professions:GetStatus(6693) == 'none', 'profession dropped')
assert(tipText(5774):find(L['Not one of your professions (%s %d)']:format('Tailoring', 175), 1, true), 'not a profession')
-- The same on the modern client, where C_SkillInfo and C_TradeSkillUI replace the globals
do
  local legacy = { GetNumSkillLines, GetSkillLineInfo, GetNumTradeSkills, GetTradeSkillLine }
  GetNumSkillLines, GetSkillLineInfo, GetNumTradeSkills, GetTradeSkillLine = nil, nil, nil, nil
  -- By ID, the name is in another language
  local lines = { { name = 'Berufe', isHeader = true, isCollapsed = false },
    { name = 'Schneiderei', skillID = 197, rank = 150, maxRank = 225 } }
  C_SkillInfo = { GetNumSkillLines = function() return #lines end, GetSkillLineInfo = function(i) return lines[i] end }
  FireEvent('SKILL_LINES_CHANGED')
  assert(Professions:GetStatus(6693) == 'later' and Professions:GetStatus(6688) == 'learnable', 'modern skill')
  local linked, ready, learned = true, true, { [6688] = true }
  C_TradeSkillUI = { IsTradeSkillLinked = function() return linked end, IsTradeSkillReady = function() return ready end,
    GetBaseProfessionInfo = function() return { professionID = 197 } end,
    GetAllRecipeIDs = function() return { 6688, 3757 } end,
    GetRecipeInfo = function(id) return { recipeID = id, name = 'Recipe ' .. id, learned = learned[id] or false } end }
  FireEvent('TRADE_SKILL_SHOW')
  assert(Professions:GetStatus(6688) == 'learnable', 'not from a linked window')
  linked, ready = false, false; FireEvent('TRADE_SKILL_SHOW')
  assert(Professions:GetStatus(6688) == 'learnable', 'not before it is ready')
  ready = true; FireEvent('TRADE_SKILL_LIST_UPDATE'); Tick(1)
  assert(Professions:GetStatus(6688) == 'known', 'modern window')
  assert(Professions:GetStatus(3757) ~= 'known', 'listed but not learnt')
  FireEvent('NEW_RECIPE_LEARNED', 3757); assert(Professions:GetStatus(3757) == 'known', 'modern learnt')
  FireEvent('NEW_RECIPE_LEARNED', 999999999)
  local saved = lines
  lines = {}; FireEvent('SKILL_LINES_CHANGED'); assert(Professions:GetStatus(6688) == 'known', 'lines not loaded')
  lines = { { name = 'Berufe', isHeader = true, isCollapsed = true } }; FireEvent('SKILL_LINES_CHANGED')
  assert(Professions:GetStatus(6688) == 'known', 'modern collapsed')
  lines = { saved[1] }; FireEvent('SKILL_LINES_CHANGED'); assert(Professions:GetStatus(6688) == 'none', 'modern dropped')
  C_SkillInfo, C_TradeSkillUI = nil, nil
  GetNumSkillLines, GetSkillLineInfo, GetNumTradeSkills, GetTradeSkillLine = unpack(legacy, 1, 4)
end
-- Items that teach nothing are left alone
assert(not tipText(5764):find(L['You can learn this recipe'], 1, true))

-- Reagents of the crafted items on the wishlist
local W = ns.Wishlist
for itemId in pairs(W.items) do W.items[itemId] = nil end
W.reagentCounts = nil; ITEM_COUNTS[4305], ITEM_COUNTS[4234], ITEM_COUNTS[2321], ITEM_COUNTS[2605] = 2, 0, 0, 0
FireEvent('BAG_UPDATE_DELAYED')
local chatCount = #CHATLOG
FireEvent('BAG_UPDATE_DELAYED'); assert(#CHATLOG == chatCount, 'nothing new in the bags')
W:Add(5764); assert(#CHATLOG == chatCount + 1, 'what the bags hold already is not news')
text = tipText(4305)
assert(text:find(L['Wanted for %s: %s']:format(DB:GetColoredName(5764), W:FormatProgress(2, 4)), 1, true), text)
print('reagent> ' .. (text:gsub('\n', ' | ')))
-- Looting one tells how many there are now
ITEM_COUNTS[4305] = 3; FireEvent('BAG_UPDATE_DELAYED')
assert(#CHATLOG == chatCount + 2 and CHATLOG[#CHATLOG]:find(W:FormatProgress(3, 4), 1, true), CHATLOG[#CHATLOG])
print('reagent chat> ' .. CHATLOG[#CHATLOG])
ITEM_COUNTS[4305] = 4; FireEvent('BAG_UPDATE_DELAYED'); assert(#CHATLOG == chatCount + 3)
-- Beyond what is needed is not news
ITEM_COUNTS[4305] = 6; FireEvent('BAG_UPDATE_DELAYED'); assert(#CHATLOG == chatCount + 3, 'enough already')
-- The last reagents: their progress, then that every one is there
ITEM_COUNTS[4234], ITEM_COUNTS[2321], ITEM_COUNTS[2605] = 3, 3, 1; FireEvent('BAG_UPDATE_DELAYED')
assert(#CHATLOG == chatCount + 7, 'three reagents and the craft: ' .. (#CHATLOG - chatCount))
local _, packLink = ns.GetItemInfo(5764)
assert(CHATLOG[#CHATLOG]:find(L['You have every reagent for %s.']:format(packLink or DB:GetColoredName(5764)), 1, true), CHATLOG[#CHATLOG])
print('reagent chat> ' .. CHATLOG[#CHATLOG])
-- The window shows how many of each reagent there are
SlashCmdList.ITEMINFO('5764')
local progressLines = 0
for _, line in ipairs(UI.detailLines) do if line.right == W:FormatProgress(6, 4) or line.right == W:FormatProgress(3, 3) then progressLines = progressLines + 1 end end
assert(progressLines >= 3, 'reagent progress in the window: ' .. progressLines)
-- With the alerts off, the chat is left alone
SlashCmdList.ITEMINFO('alerts'); chatCount = #CHATLOG
ITEM_COUNTS[4305] = 1; FireEvent('BAG_UPDATE_DELAYED'); ITEM_COUNTS[4305] = 2; FireEvent('BAG_UPDATE_DELAYED')
assert(#CHATLOG == chatCount, 'alerts off')
SlashCmdList.ITEMINFO('alerts')
-- Crafting it takes it off the list, and its reagents off the tooltips
ITEM_COUNTS[5764] = 1; FireEvent('BAG_UPDATE_DELAYED')
assert(not W:Has(5764) and not tipText(4305):find(L['Wanted for %s: %s']:format(DB:GetColoredName(5764), ''), 1, true), 'crafted')

-- Quest items: the quests asking for them, those in the log first
local questItem, questIds
for itemId, quests in pairs(ns.Data.questObjectives) do
  local usable = 0
  for _, questId in ipairs(quests) do local q = ns.Data.quests[questId]; if q and q[4] ~= 'A' then usable = usable + 1 end end
  if usable >= 2 and ns.Data.drops[itemId] and #ns.Data.drops[itemId] > 1 and (questItem == nil or itemId < questItem) then questItem, questIds = itemId, quests end
end
assert(questItem, 'an item two quests ask for, dropped by known creatures')
ITEMS[questItem] = { name = 'Quest Thing', class = 12 }
ns.Scanner.db.quality[questItem] = 1
local usable = ns.DB:GetUsableQuestObjectives(questItem)
local last = usable[#usable]
ACTIVE_QUESTS[last] = true
usable = ns.DB:GetUsableQuestObjectives(questItem)
assert(usable[1] == last, 'the quest in the log first')
text = tipText(questItem)
assert(text:find(L['Needed for a quest'], 1, true) and text:find(L['In your quest log'], 1, true), text)
print('quest> ' .. (text:gsub('\n', ' | ')))
-- A creature that drops it lists it while the quest is in the log, even if it's a common item
local dropper = ns.Data.drops[questItem][2]
local notable = Creature:GetNotable(dropper)
assert(notable[1] == questItem, 'quest item first: ' .. tostring(notable[1]))
ACTIVE_QUESTS[last] = nil
notable = Creature:GetNotable(dropper)
for _, itemId in ipairs(notable) do assert(itemId ~= questItem, 'a common item without the quest is not notable') end

-- Drop rates of the bosses
local ratedItem, ratedNpc, rate
for itemId, rates in pairs(ns.Data.dropRates) do
  local drop = ns.Data.drops[itemId]
  if drop and #drop == 2 and drop[2] == rates[1] and (ratedItem == nil or itemId < ratedItem) then ratedItem, ratedNpc, rate = itemId, rates[1], rates[2] end
end
assert(ratedItem, 'an item a single boss drops, with its rate')
assert(ns.DB:GetDropRate(ratedItem, ratedNpc) == rate and ns.DB:GetDropRate(ratedItem, ratedNpc + 1) == nil)
assert(ns.DB:FormatDropRate(56.07) == '56%' and ns.DB:FormatDropRate(3.91) == '3.9%' and ns.DB:FormatDropRate(0.25) == '0.25%')
ITEMS[ratedItem] = { name = 'Boss Loot', class = 4, sub = 1 }
text = tipText(ratedItem)
assert(text:find('[' .. ns.DB:FormatDropRate(rate) .. ']', 1, true), text)
print('rate> ' .. (text:gsub('\n', ' | ')))
ns.Scanner.db.quality[ratedItem] = 4
local unitLines = table.concat(ShowUnitTooltip('Creature-0-1-2-3-' .. ratedNpc .. '-0000ABCDEF'), ' | ')
assert(unitLines:find('[' .. ns.DB:FormatDropRate(rate) .. ']', 1, true), unitLines)
-- The window too
SlashCmdList.ITEMINFO(tostring(ratedItem))
local rated = false
for _, line in ipairs(UI.detailLines) do if line.right == ns.DB:FormatDropRate(rate) then rated = true end end
assert(rated, 'the rate in the window')

-- Mage scrolls: what an undeciphered one may turn into, and the other way around
local scrollSeen = {}
for _, tier in ipairs(ns.Data.scrollTiers) do
  for _, list in ipairs({ tier.from, tier.into }) do
    for _, id in ipairs(list) do
      assert(not scrollSeen[id], 'scroll listed twice: ' .. id)
      scrollSeen[id] = true
      ITEMS[id] = { name = 'Scroll ' .. id, class = 0 }
      ns.Scanner.db.quality[id] = 1
    end
  end
end
local intoTitle, fromTitle = L['May be deciphered into one of'], L['May be deciphered from']
text = tipText(211787)
assert(text:find(intoTitle .. ' (5)', 1, true) and not text:find(fromTitle, 1, true), text)
text = tipText(277490)
assert(text:find(fromTitle .. ' (4)', 1, true) and not text:find(intoTitle, 1, true), text)
-- A long list folds
assert(tipText(213543):find(L['Hold Shift for %d more']:format(5), 1, true), 'folded scrolls')
assert(ns.Tooltip.folded and ns.Tooltip.folded.itemId == 213543, 'can be unfolded')
assert(not tipText(4234):find(intoTitle, 1, true), 'no scroll')
-- The window links them
SlashCmdList.ITEMINFO('211787')
local links = 0
for _, line in ipairs(UI.detailLines) do if line.ref and DB:GetDecipheredFrom(line.ref) and not line.static then links = links + 1 end end
assert(links == 5, 'scroll links: ' .. links)

-- Guild crafters: the ItemInfo users of a guild share the recipes of their characters
do
  local Guild = ns.Guild
  local function sent(pattern, channel)
    local found = {}
    for _, m in ipairs(SENT) do
      if m[2]:find(pattern) and (channel == nil or m[3] == channel) then found[#found + 1] = m end
    end
    return found
  end
  local function hear(text, channel, sender)
    FireEvent('CHAT_MSG_ADDON', 'ItemInfo', text, channel or 'GUILD', sender or 'Friend-Realm')
  end
  function GetGuildInfo() return 'Testguild' end
  local roster = { { 'Friend-Realm', true }, { 'Offline-Realm', false } }
  function GetNumGuildMembers() return #roster end
  function GetGuildRosterInfo(i) return roster[i][1], nil, nil, nil, nil, nil, nil, nil, roster[i][2] end
  FireEvent('GUILD_ROSTER_UPDATE')

  -- Many recipes, so that they are sent in parts
  local spells = {}
  for spellId in pairs(ns.Data.spells) do spells[#spells + 1] = spellId end
  table.sort(spells)
  local many = { [6688] = true, [6693] = true }
  for index = 1, 80 do many[spells[index]] = true end
  local chars = ItemInfoDB.characters.Testrealm
  chars['Test Vendor'].known = { [8] = { [6693] = true } }
  chars.Alty.known = { [8] = many }; chars.Alty.guild = 'Testguild'
  -- An alt of another guild is not shared
  chars.Brewer.known = { [6] = { [2550] = true } }; chars.Brewer.guild = 'Otherguild'

  -- After login, the characters in the guild are announced to it, once
  SENT = {}
  Tick(20); FireEvent('PLAYER_GUILD_UPDATE'); Tick(5)
  local announce = sent('^S1;', 'GUILD')
  assert(#announce == 1 and announce[1][2]:find('^S1;Alty=%w+,Test Vendor=%w+$'), 'announced: ' .. tostring(announce[1] and announce[1][2]))
  print('guild> ' .. announce[1][2])

  -- Another client's announcement: its characters are asked for, it is told about ours
  SENT = {}
  hear('S1;Friend=abc,Test Vendor=zzz')
  Tick(3)
  local asked = sent('^Q1;', 'WHISPER')
  assert(#asked == 1 and asked[1][2] == 'Q1;Friend' and asked[1][4] == 'Friend-Realm', 'asked for its characters')
  assert(#sent('^S1;Alty=', 'WHISPER') == 1, 'answered with ours')
  -- A whisper is not answered, nor asked for again so soon
  SENT = {}
  hear('S1;Friend=abc', 'WHISPER'); Tick(3)
  assert(#SENT == 0, 'whisper not answered')

  -- Asked for a character, its recipes go to the guild in parts, and only once in a while
  SENT = {}
  hear('Q1;Alty,Brewer,Nobody', 'WHISPER'); Tick(10)
  local parts = sent('^D1;', 'GUILD')
  assert(#parts >= 2, 'recipes in parts: ' .. #parts)
  for _, m in ipairs(parts) do assert(m[2]:find('^D1;Alty;'), 'only the shared character: ' .. m[2]) end
  SENT = {}
  hear('Q1;Alty', 'WHISPER'); Tick(10)
  assert(#sent('^D1;') == 0, 'not again so soon')

  -- The same recipes from another member, the parts in any order
  for index = #parts, 1, -1 do hear((parts[index][2]:gsub('^D1;Alty;', 'D1;Friend;'))) end
  local crafters = Guild:GetCrafters(6693)
  assert(#crafters == 1 and crafters[1].name == 'Friend' and crafters[1].class == 'PRIEST' and crafters[1].online, 'received')
  -- An alt shared by Friend, offline
  for _, m in ipairs(parts) do hear((m[2]:gsub('^D1;Alty;', 'D1;Offline;'))) end
  -- A broken part is thrown away
  local broken = parts[1][2]:gsub('^D1;Alty;', 'D1;Broken;'):gsub(';(%d+);(%d+);', ';1;1;', 1)
  hear(broken)
  -- So are recipes of a character of our own
  for _, m in ipairs(parts) do hear((m[2]:gsub('^D1;Alty;', 'D1;Brewer;'))) end
  crafters = Guild:GetCrafters(6693)
  assert(#crafters == 2 and crafters[1].name == 'Friend' and crafters[2].name == 'Offline' and not crafters[2].online
    and crafters[2].by == 'Friend', 'online first')

  -- The tooltips of the recipe and of the item it makes
  local text = tipText(5774)
  assert(text:find(L['Known in your guild by'] .. ': Friend, |cff909090Offline|r', 1, true), text)
  print('guild recipe> ' .. (text:gsub('\n', ' | ')))
  text = tipText(5764)
  assert(text:find(L['Made in your guild by'] .. ': Friend, |cff909090Offline|r', 1, true), text)
  -- The window, a click whispers them, or the owner of an alt
  SlashCmdList.ITEMINFO('5764')
  local whispers = {}
  for _, line in ipairs(UI.detailLines) do if line.whisper then whispers[#whispers + 1] = line.whisper end end
  assert(#whispers == 2 and whispers[1] == 'Friend' and whispers[2] == 'Friend', 'window: ' .. #whispers)

  -- The same digest is not asked for again, a new one is
  SENT = {}; NOW = NOW + 200
  local digest = parts[1][2]:match('^D1;Alty;(%w+);')
  hear('S1;Friend=' .. digest); Tick(3)
  assert(#sent('^Q1;') == 0, 'known already')
  hear('S1;Friend=other'); Tick(3)
  assert(#sent('^Q1;Friend') == 1, 'asked for the new recipes')

  -- Many crafters fold, Shift unfolds them
  for _, name in ipairs({ 'Aa', 'Bb', 'Cc', 'Dd' }) do
    for _, m in ipairs(parts) do hear((m[2]:gsub('^D1;Alty;', 'D1;' .. name .. ';'))) end
  end
  text = tipText(5764)
  assert(text:find('|cff909090+2|r', 1, true) and ns.Tooltip.folded, 'folded: ' .. text)
  SHIFT = true; text = tipText(5764); SHIFT = false
  assert(not text:find('+2', 1, true), 'unfolded')

  -- A member that stops sharing: only its own characters are forgotten
  hear('X1;Offline', 'GUILD', 'Aa-Realm')
  assert(#Guild:GetCrafters(6693) == 6, 'not by another member')
  hear('X1;Offline,Aa')
  assert(#Guild:GetCrafters(6693) == 4, 'withdrawn')

  -- Learning a recipe announces the characters again
  SENT = {}
  chars.Alty.known[8][spells[81]] = true
  FireEvent('NEW_RECIPE_LEARNED', spells[81]); Tick(31)
  assert(#sent('^S1;Alty=', 'GUILD') == 1, 'announced after learning')
  SENT = {}
  FireEvent('NEW_RECIPE_LEARNED', spells[81]); Tick(31)
  assert(#sent('^S1;') == 0, 'nothing new')

  -- Sharing off: the guild is told to forget ours, and nothing is sent any more
  SENT = {}
  SlashCmdList.ITEMINFO('guild'); Tick(3)
  assert(#sent('^X1;Alty,Test Vendor$', 'GUILD') == 1, 'withdrawn from the guild')
  SENT = {}
  NOW = NOW + 100
  hear('Q1;Alty', 'WHISPER'); hear('S1;Friend=' .. digest); Tick(10)
  assert(#sent('^D1;') == 0 and #sent('^S1;') == 0, 'nothing shared')
  assert(#Guild:GetCrafters(6693) == 4, 'still shown')
  SlashCmdList.ITEMINFO('guild'); Tick(3)
  assert(#sent('^S1;Alty=', 'GUILD') == 1, 'sharing again')

  -- Forgotten after a month without being announced
  NOW = NOW + 31 * 24 * 60 * 60
  Guild:Init(ItemInfoDB)
  assert(#Guild:GetCrafters(6693) == 0, 'pruned')
  GetGuildInfo = nil
end

-- The wishlist grouped by zone, the player's zone first
do
  local W = ns.Wishlist
  -- An item a vendor of a known zone sells
  local sold, soldZone
  for itemId, vendors in pairs(ns.Data.vendors) do
    local zone = select(2, DB:GetNpc(vendors[1]))
    if zone ~= nil and not DB:GetCreatedBy(itemId) and not DB:GetDrops(itemId) and (sold == nil or itemId < sold) then
      sold, soldZone = itemId, zone
    end
  end
  assert(sold, 'an item sold in a known zone')
  for itemId in pairs(W.items) do W.items[itemId] = nil end
  W:Add(sold); W:Add(5764); W:Add(5774)
  local zones = W:GetZones(sold)
  assert(#zones >= 1 and zones[1] == soldZone, 'zones of a sold item')

  ZONE = 'Elsewhere'
  UI:ShowWishlist()
  local function headers()
    local found = {}
    for index, row in ipairs(UI.resultRows) do if type(row) == 'table' then found[#found + 1] = { index, row.header } end end
    return found
  end
  local groups = headers()
  local function find(title) for _, h in ipairs(groups) do if h[2]:find(title, 1, true) == 1 then return h end end end
  assert(find(soldZone) and find(L['Crafted']) and find(L['World drop']), 'groups: ' .. #groups)
  assert(UI.resultRows[find(soldZone)[1] + 1] == sold, 'the item under its zone')
  assert(not groups[1][2]:find(L['You are here'], 1, true), 'not here')
  -- The crafted and world drop groups come after the zones
  assert(find(L['Crafted'])[1] > find(soldZone)[1] and find(L['World drop'])[1] > find(L['Crafted'])[1], 'order')
  assert(#UI.resultRefs == 3 and UI.status:GetText():find('3', 1, true), 'counted once: ' .. UI.status:GetText())
  -- Header rows are not entries to click
  local entry = UI.results.GetEntry and UI.results:GetEntry(groups[1][1]) or nil
  if entry then assert(entry.header and entry.static, 'header row') end

  -- Arriving in the zone puts it first
  ZONE = soldZone; FireEvent('ZONE_CHANGED_NEW_AREA')
  groups = headers()
  assert(groups[1][2]:find(soldZone, 1, true) == 1 and groups[1][2]:find(L['You are here'], 1, true), 'here first: ' .. groups[1][2])
  print('wishlist> ' .. groups[1][2] .. ' | ' .. groups[#groups][2])
  -- A search within the wishlist keeps the groups
  UI.editBox:SetText(DB:GetName(sold)); UI:Search()
  assert(#UI.resultRefs == 1 and #headers() >= 1, 'searched')
  UI.editBox:SetText('')
  for itemId in pairs(W.items) do W.items[itemId] = nil end
  UI:Search()
  assert(UI.resultRows == nil and #UI.resultRefs == 0, 'empty')
  ZONE = nil
end
