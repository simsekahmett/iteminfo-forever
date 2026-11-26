local _, ns = ...

-- The encyclopedia window: a category tree to the left, a search bar above
-- the results, and the details of the selected entry beside them.

local L = ns.L
local DB = ns.DB
local Scanner = ns.Scanner
local List = ns.List
local GetItemInfo = ns.GetItemInfo

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 920, 560
local TREE_WIDTH, RESULTS_WIDTH = 210, 290
local TOP, BOTTOM, PADDING = 62, 30, 10
local ROW_HEIGHT = 18

local GOLD = '|cffffd100'
local GRAY = '|cff909090'
local STAR_TEXTURE = 'Interface\\TargetingFrame\\UI-RaidTargetingIcon_1'

------------------------------------------
-- Details
------------------------------------------

local function AddHeader(lines, text)
  if #lines > 0 then
    lines[#lines + 1] = { static = true }
  end

  lines[#lines + 1] = { text = text, header = true, static = true }
end

local function AddText(lines, text, right, indent)
  lines[#lines + 1] = { text = text, right = right, indent = indent, static = true }
end

-- Adds a line that opens an entry when clicked
local function AddRef(lines, ref, prefix, right, indent)
  lines[#lines + 1] = {
    text = (prefix or '') .. DB:GetColoredName(ref),
    right = right,
    icon = DB:GetIcon(ref),
    indent = indent,
    ref = ref,
  }
end

local function FormatSkill(profession, skill)
  return string.format('%s (%d)', DB:GetProfessionName(profession), skill)
end

-- Returns a character's name in the color of its class
local function ClassColored(name, class)
  local color = _G.RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]

  if color ~= nil and color.colorStr ~= nil then
    return '|c' .. color.colorStr .. name .. '|r'
  end

  return name
end

-- Adds the members of the guild who know a spell, those online first. A
-- click whispers them, or the character that shared an alt.
local function AddGuildCrafters(lines, spellId)
  local crafters = ns.Guild:GetCrafters(spellId)

  if #crafters == 0 then
    return
  end

  AddText(lines, L['Made in your guild by'] .. ':', nil, 1)

  for _, crafter in ipairs(crafters) do
    local whisper = crafter.online and crafter.name or crafter.by or crafter.name
    local right

    if crafter.online then
      right = '|cff40c040' .. (_G.FRIENDS_LIST_ONLINE or L['Online']) .. '|r'
    elseif whisper ~= crafter.name then
      right = GRAY .. whisper .. '|r'
    end

    lines[#lines + 1] = {
      text = crafter.online and ClassColored(crafter.name, crafter.class) or GRAY .. crafter.name .. '|r',
      right = right,
      indent = 2,
      static = true,
      whisper = whisper,
      tooltip = L['Click to whisper %s']:format(whisper),
    }
  end
end

-- Adds how a spell is made: its profession, reagents and recipe. For an
-- item on the wishlist, how many of each reagent the character has.
local function AddSpell(lines, spellId, isWanted)
  local profession, skill, yellow, green, reagents, made = DB:GetSpell(spellId)
  local difficulty

  if yellow > 0 and green > 0 then
    difficulty = GRAY .. L['yellow %d, green %d']:format(yellow, green) .. '|r'
  end

  lines[#lines + 1] = {
    text = GOLD .. FormatSkill(profession, skill) .. '|r',
    right = difficulty,
    icon = DB:GetProfessionIcon(profession),
    static = true,
  }

  if made > 1 then
    AddText(lines, L['Creates %d']:format(made), nil, 1)
  end

  if #reagents > 0 then
    AddText(lines, L['Reagents'] .. ':', nil, 1)

    for index = 1, #reagents, 2 do
      local progress

      if isWanted then
        progress = ns.Wishlist:FormatProgress(ns.Wishlist:CountOf(reagents[index]), reagents[index + 1])
      end

      AddRef(lines, reagents[index], reagents[index + 1] .. 'x ', progress, 2)
    end
  end

  AddText(lines, L['Recipe'] .. ':', nil, 1)

  local recipes = DB:GetRecipeItems(spellId)
  if recipes == nil then
    AddText(lines, GRAY .. L['Taught by trainers'] .. '|r', nil, 2)
  else
    for index = 1, #recipes do
      AddRef(lines, recipes[index], nil, nil, 2)
    end
  end

  AddGuildCrafters(lines, spellId)
end

local function AddNpc(lines, npcId, right, isVendor)
  local name, zone, x, y, friendly = DB:GetNpc(npcId)
  local text = name

  if zone ~= nil and zone ~= '' then
    text = text .. GRAY .. ' - ' .. zone

    if x >= 0 and y >= 0 then
      text = text .. string.format(' (%.1f, %.1f)', x, y)
    end

    text = text .. '|r'
  end

  -- Only vendors are bound to a faction, a hostile NPC drops for either
  if not isVendor then
    friendly = nil
  end

  if friendly == 'A' then
    text = '|cff5c88ff' .. (_G.FACTION_ALLIANCE or 'Alliance') .. '|r  ' .. text
  elseif friendly == 'H' then
    text = '|cffe03a3a' .. (_G.FACTION_HORDE or 'Horde') .. '|r  ' .. text
  end

  lines[#lines + 1] = { text = text, right = right, indent = 1, static = true, tooltip = text }
end

local function AddQuestList(lines, title, quests)
  if quests == nil then
    return
  end

  AddHeader(lines, title .. ' (' .. #quests .. ')')

  for _, questId in ipairs(quests) do
    local name, _, requiredLevel, _, zone, giver = DB:GetQuest(questId)

    if DB:IsOnQuest(questId) then
      zone = '|cff40c040' .. L['In your quest log'] .. '|r'
    end

    lines[#lines + 1] = {
      text = DB:GetColoredQuestName(questId),
      right = zone,
      indent = 1,
      static = true,
      tooltip = name,
    }

    if giver ~= nil then
      local giverName, giverZone, x, y = DB:GetNpc(giver)
      local text = GRAY .. L['Quest giver'] .. ':|r ' .. giverName

      if giverZone ~= nil and x >= 0 and y >= 0 then
        text = text .. GRAY .. string.format(' (%.1f, %.1f)', x, y) .. '|r'
      end

      AddText(lines, text, requiredLevel > 1 and GRAY .. (_G.LEVEL or 'Level') .. ' ' .. requiredLevel .. '|r' or nil, 2)
    end
  end
end

local function AddQuests(lines, itemId)
  AddQuestList(lines, L['Needed for a quest'], DB:GetUsableQuestObjectives(itemId))
  AddQuestList(lines, L['Quest reward'], DB:GetUsableQuestRewards(itemId))
end

local function AddSources(lines, itemId)
  local vendors, prices = DB:GetVendors(itemId)

  if vendors ~= nil then
    AddHeader(lines, L['Sold by'])

    for index = 1, #vendors do
      local price = prices[vendors[index]]
      AddNpc(lines, vendors[index], price and ns.FormatMoney(price) or nil, true)
    end
  end

  local drops, total = DB:GetDrops(itemId)

  if drops ~= nil then
    AddHeader(lines, L['Dropped by'] .. ' (' .. total .. ')')

    -- Only a few are known by name, an item with more drops anywhere
    if total > #drops then
      AddText(lines, L['World drop, from %d different creatures']:format(total), nil, 1)
    else
      for index = 1, #drops do
        local rate = DB:GetDropRate(itemId, drops[index])
        AddNpc(lines, drops[index], rate and DB:FormatDropRate(rate) or nil)
      end
    end
  end
end

local function AddScrolls(lines, title, scrolls)
  if scrolls == nil then
    return
  end

  AddHeader(lines, title .. ' (' .. #scrolls .. ')')

  for _, itemId in ipairs(scrolls) do
    AddRef(lines, itemId, nil, nil, 1)
  end
end

local function BuildItemDetails(lines, itemId)
  local name, _, _, itemLevel, minLevel, typeName, subTypeName, _, equipLoc, _, sellPrice =
    GetItemInfo(itemId)

  lines[#lines + 1] = {
    text = DB:GetColoredName(itemId),
    icon = DB:GetIcon(itemId),
    ref = itemId,
    header = true,
    static = true,
  }

  if name == nil then
    AddText(lines, GRAY .. L['Loading...'] .. '|r')
  else
    local slot = equipLoc ~= nil and equipLoc ~= '' and _G[equipLoc] or nil
    local kind = typeName or ''

    if subTypeName ~= nil and subTypeName ~= '' and subTypeName ~= typeName then
      kind = kind .. ' / ' .. subTypeName
    end

    AddText(lines, kind, type(slot) == 'string' and slot or nil)

    if (itemLevel or 0) > 0 then
      AddText(lines, (_G.ITEM_LEVEL or 'Item Level %d'):format(itemLevel))
    end
    if (minLevel or 0) > 0 then
      AddText(lines, (_G.ITEM_MIN_LEVEL or 'Requires Level %d'):format(minLevel))
    end

    AddText(lines, L['Sell price'] .. ':',
            (sellPrice or 0) > 0 and ns.FormatMoney(sellPrice) or GRAY .. L['Cannot be sold'] .. '|r')
  end

  local buyPrice = DB:GetBuyPrice(itemId)
  if buyPrice ~= nil then
    AddText(lines, L['Buy price'] .. ':', ns.FormatMoney(buyPrice))
  end

  AddText(lines, GRAY .. L['Item ID: %d']:format(itemId) .. '|r')

  local taught = DB:GetTaughtSpell(itemId)
  if taught ~= nil then
    local profession, skill = DB:GetSpell(taught)

    AddHeader(lines, L['Teaches'])
    AddRef(lines, DB:GetSpellRef(taught), nil, FormatSkill(profession, skill), 1)
  end

  local createdBy = DB:GetCreatedBy(itemId)
  if createdBy ~= nil then
    AddHeader(lines, L['Created by'])

    for index = 1, #createdBy do
      AddSpell(lines, createdBy[index], ns.Wishlist:Has(itemId))
    end
  end

  AddScrolls(lines, L['May be deciphered into one of'], DB:GetDecipheredInto(itemId))
  AddScrolls(lines, L['May be deciphered from'], DB:GetDecipheredFrom(itemId))

  local usedIn = DB:GetUsedIn(itemId)
  if usedIn ~= nil then
    AddHeader(lines, L['Used in'] .. ' (' .. #usedIn .. ') ' .. DB:GetProfessionIcons(usedIn))

    for index = 1, #usedIn do
      local profession, skill = DB:GetSpell(usedIn[index])
      AddRef(lines, DB:GetSpellRef(usedIn[index]), nil, FormatSkill(profession, skill), 1)
    end
  end

  AddQuests(lines, itemId)
  AddSources(lines, itemId)
end

local function BuildSpellDetails(lines, spellId)
  lines[#lines + 1] = {
    text = DB:GetColoredName(-spellId),
    icon = DB:GetIcon(-spellId),
    ref = -spellId,
    header = true,
    static = true,
  }

  AddHeader(lines, L['Created by'])
  AddSpell(lines, spellId)
end

------------------------------------------
-- Window
------------------------------------------

function UI:_Create()
  local frame = CreateFrame('Frame', 'ItemInfoFrame', UIParent,
                            _G.BackdropTemplateMixin and 'BackdropTemplate' or nil)
  self.frame = frame

  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint('CENTER')
  frame:SetFrameStrata('HIGH')
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag('LeftButton')
  frame:SetScript('OnDragStart', frame.StartMoving)
  frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
  frame:Hide()

  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
      edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
      tile = true,
      tileSize = 32,
      edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.95)
  else
    local background = frame:CreateTexture(nil, 'BACKGROUND')
    background:SetAllPoints()
    background:SetColorTexture(0.05, 0.05, 0.05, 0.95)
  end

  -- Escape closes the window
  table.insert(UISpecialFrames, 'ItemInfoFrame')

  local logo = frame:CreateTexture(nil, 'ARTWORK')
  logo:SetTexture(ns.LOGO)
  logo:SetSize(26, 26)
  logo:SetPoint('TOPLEFT', PADDING - 2, -PADDING + 5)

  local title = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
  title:SetPoint('LEFT', logo, 'RIGHT', 4, 0)
  title:SetText('ItemInfo')

  local close = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', -2, -2)

  -- Search bar
  local left = PADDING + TREE_WIDTH + PADDING

  local back = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
  back:SetSize(70, 22)
  back:SetPoint('TOPLEFT', left, -34)
  back:SetText(_G.BACK or L['Back'])
  back:SetScript('OnClick', function()
    self:Back()
  end)
  self.backButton = back

  local search = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
  search:SetSize(90, 22)
  search:SetPoint('TOPRIGHT', -PADDING, -34)
  search:SetText(_G.SEARCH or L['Search'])
  search:SetScript('OnClick', function()
    self:Search()
  end)

  local editBox = CreateFrame('EditBox', nil, frame, 'InputBoxTemplate')
  editBox:SetHeight(22)
  editBox:SetPoint('LEFT', back, 'RIGHT', 12, 0)
  editBox:SetPoint('RIGHT', search, 'LEFT', -6, 0)
  editBox:SetAutoFocus(false)
  editBox:SetMaxLetters(60)
  editBox:SetScript('OnEnterPressed', function()
    self:Search()
    editBox:ClearFocus()
  end)
  editBox:SetScript('OnEscapePressed', editBox.ClearFocus)
  editBox:SetScript('OnTextChanged', function(_, isUserInput)
    -- The search follows the typing, after a short pause
    if isUserInput then
      self.searchAt = GetTime() + 0.3
    end
  end)
  self.editBox = editBox

  -- Lists
  local listHeight = math.floor((HEIGHT - TOP - BOTTOM) / ROW_HEIGHT) * ROW_HEIGHT
  local treeHeight = math.floor((HEIGHT - 34 - BOTTOM) / ROW_HEIGHT) * ROW_HEIGHT

  self.tree = List.New(frame, TREE_WIDTH, treeHeight, ROW_HEIGHT, function(entry)
    self:_OnTreeClick(entry)
  end)
  self.tree.frame:SetPoint('TOPLEFT', PADDING, -34)

  self.results = List.New(frame, RESULTS_WIDTH, listHeight, ROW_HEIGHT, function(entry)
    self:Select(entry.ref)
  end)
  self.results.frame:SetPoint('TOPLEFT', left, -TOP)

  local detailsWidth = WIDTH - left - RESULTS_WIDTH - PADDING * 2
  self.details = List.New(frame, detailsWidth, listHeight, ROW_HEIGHT, function(entry)
    self:Select(entry.ref)
  end)
  self.details.frame:SetPoint('TOPLEFT', left + RESULTS_WIDTH + PADDING, -TOP)

  -- Adds the item shown in the details to the wishlist, or removes it
  local star = CreateFrame('Button', nil, self.details.frame)
  star:SetSize(ROW_HEIGHT, ROW_HEIGHT)
  star:SetPoint('TOPRIGHT', -12, 0)
  star:SetFrameLevel(self.details.frame:GetFrameLevel() + 5)
  star.icon = star:CreateTexture(nil, 'OVERLAY')
  star.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
  star.icon:SetPoint('RIGHT')
  star.icon:SetTexture(STAR_TEXTURE)
  -- A star alone is easily missed, the label tells what it does
  star.label = star:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  star.label:SetPoint('RIGHT', star.icon, 'LEFT', -3, 0)
  star:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight', 'ADD')
  star:SetScript('OnClick', function()
    if self.selected ~= nil and self.selected > 0 then
      ns.Wishlist:Toggle(self.selected)
      self:OnWishlistChanged()
    end
  end)
  star:SetScript('OnEnter', function()
    GameTooltip:SetOwner(star, 'ANCHOR_RIGHT')
    GameTooltip:SetText(ns.Wishlist:Has(self.selected or 0) and L['Remove from wishlist'] or L['Add to wishlist'])
    GameTooltip:Show()
  end)
  star:SetScript('OnLeave', function()
    GameTooltip:Hide()
  end)
  star:Hide()
  self.starButton = star

  local status = frame:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  status:SetPoint('BOTTOMLEFT', left, PADDING)
  status:SetPoint('BOTTOMRIGHT', -PADDING, PADDING)
  status:SetJustifyH('LEFT')
  self.status = status

  -- State
  self.expanded = { professions = true }
  self.selectedNode = 'all'
  self.filter = nil
  self.resultRefs = {}
  self.detailLines = {}
  self.history = {}

  frame:SetScript('OnShow', function()
    self:_RefreshTree()
    self:_RefreshStatus()
  end)

  frame:SetScript('OnUpdate', function(_, elapsed)
    self:_OnUpdate(elapsed)
  end)

  -- Names and details arrive from the server as they're asked for
  ns.On('GET_ITEM_INFO_RECEIVED', function()
    self.isDirty = true
  end)

  self:_RefreshTree()
  self:_RefreshResults()
  self:_RefreshDetails()
end

function UI:_OnUpdate(elapsed)
  if self.searchAt ~= nil and GetTime() >= self.searchAt then
    self:Search()
  end

  self.elapsed = (self.elapsed or 0) + elapsed
  if self.elapsed < 0.5 then
    return
  end
  self.elapsed = 0

  if self.isDirty then
    self.isDirty = false
    self.results:Refresh()
    self:_RefreshDetails(true)
  end

  if Scanner:IsScanning() or self.wasScanning then
    self.wasScanning = Scanner:IsScanning()
    self:_RefreshTree()
    self:_RefreshStatus()
  end
end

------------------------------------------
-- Category tree
------------------------------------------

local function ByName(a, b)
  return a.name < b.name
end

function UI:_RefreshTree()
  local nodes = {}
  local classes = {}

  for _, class in pairs(DB:GetCategories()) do
    classes[#classes + 1] = class
  end
  table.sort(classes, ByName)

  nodes[#nodes + 1] = { key = 'all', text = L['All items'], right = Scanner:GetItemCount() }
  nodes[#nodes + 1] = {
    key = 'wishlist',
    text = L['Wishlist'],
    icon = STAR_TEXTURE,
    right = ns.Wishlist:GetCount(),
    filter = { wishlist = true },
  }

  -- The creature whose drops are listed, until another category is picked
  if self.selectedNode == 'npc' and self.filter ~= nil and self.filter.npc ~= nil then
    nodes[#nodes + 1] = { key = 'npc', text = self.creatureName, filter = self.filter, indent = 1 }
  end

  for _, class in ipairs(classes) do
    local subs = {}
    for _, sub in pairs(class.subs) do
      subs[#subs + 1] = sub
    end
    table.sort(subs, ByName)

    local key = 'class' .. class.id
    local isExpandable = #subs > 1

    nodes[#nodes + 1] = {
      key = key,
      text = class.name,
      right = class.count,
      filter = { class = class.id },
      expandable = isExpandable,
    }

    if isExpandable and self.expanded[key] then
      for _, sub in ipairs(subs) do
        nodes[#nodes + 1] = {
          key = key .. ':' .. sub.id,
          text = sub.name,
          right = sub.count,
          indent = 1,
          filter = { class = class.id, sub = sub.id },
        }
      end
    end
  end

  nodes[#nodes + 1] = {
    key = 'professions',
    text = _G.TRADE_SKILLS or L['Professions'],
    expandable = true,
  }

  if self.expanded.professions then
    for _, profession in ipairs(DB:GetProfessions()) do
      nodes[#nodes + 1] = {
        key = 'prof' .. profession,
        text = DB:GetProfessionName(profession),
        icon = DB:GetProfessionIcon(profession),
        indent = 1,
        filter = { prof = profession },
      }
    end
  end

  for _, node in ipairs(nodes) do
    if node.expandable then
      node.text = (self.expanded[node.key] and '- ' or '+ ') .. node.text
    end

    node.selected = node.key == self.selectedNode
  end

  self.nodes = nodes
  self.tree:SetSource(#nodes, function(index)
    return nodes[index]
  end, true)
end

function UI:_OnTreeClick(node)
  if node.expandable then
    -- A click on the selected node, or one without items of its own, toggles it
    if node.filter == nil or node.key == self.selectedNode or not self.expanded[node.key] then
      self.expanded[node.key] = not self.expanded[node.key]
    end
  end

  if node.filter ~= nil or node.key == 'all' then
    -- The details belong to the category they were opened from
    if node.key ~= self.selectedNode then
      self.selected = nil
      self.history = {}
      self:_RefreshDetails()
    end

    self.selectedNode = node.key
    self.filter = node.filter
    self:Search()
  end

  self:_RefreshTree()
end

------------------------------------------
-- Search results
------------------------------------------

-- Searches for the text of the search bar within the selected category
function UI:Search()
  self.searchAt = nil
  self.resultRefs, self.resultSkills = DB:Search(self.editBox:GetText(), self.filter)
  self:_RefreshResults()
  self:_RefreshStatus()
end

function UI:_RefreshResults(keepOffset)
  local refs, skills = self.resultRefs, self.resultSkills

  -- Each row keeps its entry for clicks and tooltips, so every entry must be
  -- a table of its own
  self.results:SetSource(#refs, function(index)
    local ref = refs[index]

    local text = DB:GetColoredName(ref)
    if ref > 0 and ns.Wishlist:Has(ref) then
      text = ns.Wishlist.STAR .. ' ' .. text
    end

    return {
      ref = ref,
      text = text,
      icon = DB:GetIcon(ref),
      right = skills and skills[ref] or nil,
      selected = ref == self.selected,
    }
  end, keepOffset)
end

function UI:_RefreshStatus()
  local text

  if #self.resultRefs == 0 and self.filter == nil and ns.Trim(self.editBox:GetText()) == '' then
    text = L['Type a name to search, or pick a category.']
  elseif self.filter ~= nil and self.filter.wishlist and ns.Wishlist:GetCount() == 0 then
    text = L['Click the star of an item to add it to your wishlist.']
  elseif self.filter ~= nil and self.filter.npc ~= nil then
    text = L['Dropped by %s: %d items']:format(self.creatureName, #self.resultRefs)
  else
    text = L['%d results']:format(#self.resultRefs)
  end

  if Scanner:IsScanning() then
    text = text .. '   ' .. L['Scanning items... %d%%']:format(math.floor(Scanner:GetProgress() * 100))
  end

  self.status:SetText(text)
end

------------------------------------------
-- Selection
------------------------------------------

-- Shows the details of an entry, an item ID or a negated spell ID
function UI:Select(ref, isBack)
  if ref == nil then
    return
  end

  if not isBack and self.selected ~= nil and self.selected ~= ref then
    self.history[#self.history + 1] = self.selected

    if #self.history > 50 then
      table.remove(self.history, 1)
    end
  end

  self.selected = ref
  self:_RefreshDetails()
  self.results:Refresh()
end

function UI:Back()
  local ref = table.remove(self.history)

  if ref ~= nil then
    self:Select(ref, true)
  end
end

function UI:_RefreshDetails(keepOffset)
  local lines = {}

  if self.selected ~= nil then
    if self.selected < 0 then
      BuildSpellDetails(lines, -self.selected)
    else
      BuildItemDetails(lines, self.selected)
    end
  end

  self.detailLines = lines
  self.details:SetSource(#lines, function(index)
    return lines[index]
  end, keepOffset)

  self.backButton:SetEnabled(#self.history > 0)
  self:_RefreshStar()
end

function UI:_RefreshStar()
  local itemId = self.selected

  if itemId == nil or itemId <= 0 then
    self.starButton:Hide()
    return
  end

  local star = self.starButton
  local isWanted = ns.Wishlist:Has(itemId)

  star.icon:SetDesaturated(not isWanted)
  star.icon:SetAlpha(isWanted and 1 or 0.6)
  star.label:SetText(isWanted and L['On your wishlist'] or GRAY .. L['Add to wishlist'] .. '|r')
  star:SetWidth((star.label:GetStringWidth() or 100) + ROW_HEIGHT + 4)
  star:Show()
end

-- Called when an item is added to the wishlist or taken off it
function UI:OnWishlistChanged()
  ns.MapPins:Refresh()

  if self.frame == nil then
    return
  end

  if self.filter ~= nil and self.filter.wishlist then
    self:Search()
  else
    self.results:Refresh()
  end

  self:_RefreshTree()
  self:_RefreshStar()
end

------------------------------------------
-- Public
------------------------------------------

function UI:Show()
  if self.frame == nil then
    self:_Create()
  end

  self.frame:Show()
end

function UI:Toggle()
  if self.frame ~= nil and self.frame:IsShown() then
    self.frame:Hide()
  else
    self:Show()
  end
end

-- Opens the window and searches every item for a text. Should the text be
-- the exact name of a single item, or the search have a single result, its
-- details are shown as well.
function UI:Open(text)
  self:Show()

  self.selectedNode = 'all'
  self.filter = nil
  self.editBox:SetText(text)
  self:Search()
  self:_RefreshTree()

  local ref = DB:FindExact(text)
  if ref == nil and #self.resultRefs == 1 then
    ref = self.resultRefs[1]
  end

  if ref ~= nil then
    self:Select(ref)

    for index = 1, #self.resultRefs do
      if self.resultRefs[index] == ref then
        self.results:ScrollTo(index)
        break
      end
    end
  end
end

-- Opens the window on the wishlist
function UI:ShowWishlist()
  self:Show()
  self.selectedNode = 'wishlist'
  self.filter = { wishlist = true }
  self.editBox:SetText('')
  self:Search()
  self:_RefreshTree()
end

-- Opens the window on every item a creature drops, the most notable first
function UI:ShowCreature(npcId, name)
  self:Show()

  self.creatureName = name or (DB:GetNpc(npcId))
  self.selectedNode = 'npc'
  self.filter = { npc = npcId }
  self.selected = nil
  self.history = {}
  self.editBox:SetText('')
  self:Search()
  self:_RefreshTree()
  self:_RefreshDetails()
end

-- Opens the window with the details of an item
function UI:ShowItem(itemId)
  self:Show()
  self:Select(itemId)
end

-- Opens the window, searches for the name of an item and shows its details,
-- so that items of the same name are listed alongside
function UI:SearchItem(itemId)
  local name = ns.GetItemInfo(itemId) or ns.Scanner:GetName(itemId)

  if name == nil then
    self:ShowItem(itemId)
    return
  end

  self:Open(name)

  if self.selected ~= itemId then
    self:Select(itemId)
  end
end
