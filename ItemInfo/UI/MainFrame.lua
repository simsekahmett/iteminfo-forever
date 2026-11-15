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

-- Adds how a spell is made: its profession, reagents and recipe
local function AddSpell(lines, spellId)
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
      AddRef(lines, reagents[index], reagents[index + 1] .. 'x ', nil, 2)
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
    AddHeader(lines, L['Dropped by'])

    -- Only a few are known by name, an item with more drops anywhere
    if total > #drops then
      AddText(lines, L['World drop, from %d different creatures']:format(total), nil, 1)
    else
      for index = 1, #drops do
        AddNpc(lines, drops[index])
      end
    end
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
      AddSpell(lines, createdBy[index])
    end
  end

  local usedIn = DB:GetUsedIn(itemId)
  if usedIn ~= nil then
    AddHeader(lines, L['Used in'] .. ' (' .. #usedIn .. ') ' .. DB:GetProfessionIcons(usedIn))

    for index = 1, #usedIn do
      local profession, skill = DB:GetSpell(usedIn[index])
      AddRef(lines, DB:GetSpellRef(usedIn[index]), nil, FormatSkill(profession, skill), 1)
    end
  end

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

    return {
      ref = ref,
      text = DB:GetColoredName(ref),
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

-- Opens the window with the details of an item
function UI:ShowItem(itemId)
  self:Show()
  self:Select(itemId)
end
