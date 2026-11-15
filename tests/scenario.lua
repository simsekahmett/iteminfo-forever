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
assert(ns.Tooltip.folded == GameTooltip)
TIP_OWNER = CreateFrame('Frame'); TIP_OWNER:SetScript('OnEnter', function() ShowItemTooltip(4305) end)
SHIFT = true; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 1)
assert(#TIP > folded, 'shift unfolds the list'); print('unfolded: ' .. #TIP .. ' lines')
SHIFT = false; FireEvent('MODIFIER_STATE_CHANGED', 'LSHIFT', 0); assert(#TIP == folded, 'release folds it again')
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
