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
assert(CHATLOG[#CHATLOG]:find('2460') and #CHATLOG == chatCount + 1, 'state reported on login')
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
assert(header and lines[header]:find('(11)', 1, true), 'creatures listed: ' .. tostring(header and lines[header]))
for index = header, header + 4 do print('drops> ' .. (lines[index] or '')) end
local worldDrop
for itemId, drop in pairs(ns.Data.drops) do if #drop == 1 then worldDrop = itemId break end end
ITEMS[worldDrop] = { name = 'Some World Drop', class = 4 }
local summary
for _, line in ipairs(ShowItemTooltip(worldDrop)) do
  if line:find(ns.L['Dropped by'], 1, true) then summary = line end
end
assert(summary and summary:find('%d'), 'world drop summary'); print('world> ' .. summary)
