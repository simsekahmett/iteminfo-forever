local _, ns = ...

-- A scrolling list that only creates the rows that fit on screen.
--
-- Its entries are provided on demand by a function, as tables with the fields:
--   text, right  The texts displayed to the left and the right
--   icon         An optional texture
--   indent       The indentation level
--   ref          An item ID, or a negated spell ID, shown as a tooltip
--   tooltip      A text shown as a tooltip, in place of 'ref'
--   header       Whether the entry is a section header
--   selected     Whether the entry is highlighted
--   static       Whether the entry ignores clicks
--   whisper      A character a click opens a whisper to

local List = {}
List.__index = List
ns.List = List

local function InsertLink(link)
  if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink then
    return _G.ChatFrameUtil.InsertLink(link)
  elseif _G.ChatEdit_InsertLink then
    return _G.ChatEdit_InsertLink(link)
  end
end

local function ShowTooltip(row)
  local entry = row.entry

  if entry == nil or (entry.ref == nil and entry.tooltip == nil) then
    return
  end

  GameTooltip:SetOwner(row, 'ANCHOR_RIGHT')

  if entry.ref == nil then
    GameTooltip:SetText(entry.tooltip, 1, 1, 1, 1, true)
  elseif entry.ref < 0 then
    if GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(-entry.ref)
    else
      GameTooltip:SetHyperlink('spell:' .. -entry.ref)
    end
  elseif GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(entry.ref)
  else
    GameTooltip:SetHyperlink('item:' .. entry.ref)
  end

  GameTooltip:Show()
end

-- Creates a list of a fixed size, 'onClick' is called with the entry clicked
function List.New(parent, width, height, rowHeight, onClick)
  local self = setmetatable({}, List)

  self.count = 0
  self.offset = 0
  self.rowHeight = rowHeight
  self.rows = {}
  self.visible = math.floor(height / rowHeight)
  self.onClick = onClick

  local frame = CreateFrame('Frame', nil, parent)
  frame:SetSize(width, height)
  frame:EnableMouseWheel(true)
  frame:SetScript('OnMouseWheel', function(_, delta)
    self:SetOffset(self.offset - delta * 3)
  end)
  self.frame = frame

  local background = frame:CreateTexture(nil, 'BACKGROUND')
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.35)

  local slider = CreateFrame('Slider', nil, frame)
  slider:SetOrientation('VERTICAL')
  slider:SetPoint('TOPRIGHT', -1, -1)
  slider:SetPoint('BOTTOMRIGHT', -1, 1)
  slider:SetWidth(8)
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  slider:SetValue(0)

  local track = slider:CreateTexture(nil, 'BACKGROUND')
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.05)

  local thumb = slider:CreateTexture(nil, 'OVERLAY')
  thumb:SetColorTexture(0.8, 0.7, 0.4, 0.8)
  thumb:SetSize(8, 32)
  slider:SetThumbTexture(thumb)

  slider:SetScript('OnValueChanged', function(_, value)
    self:SetOffset(math.floor(value + 0.5), true)
  end)
  slider:Hide()
  self.slider = slider

  for index = 1, self.visible do
    self.rows[index] = self:_CreateRow(index, width - 12)
  end

  return self
end

function List:_CreateRow(index, width)
  local row = CreateFrame('Button', nil, self.frame)
  row:SetSize(width, self.rowHeight)
  row:SetPoint('TOPLEFT', 2, -(index - 1) * self.rowHeight)
  row:RegisterForClicks('LeftButtonUp')

  local highlight = row:CreateTexture(nil, 'HIGHLIGHT')
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.12)

  row.selection = row:CreateTexture(nil, 'BACKGROUND')
  row.selection:SetAllPoints()
  row.selection:SetColorTexture(0.9, 0.7, 0.2, 0.25)
  row.selection:Hide()

  row.icon = row:CreateTexture(nil, 'ARTWORK')
  row.icon:SetSize(self.rowHeight - 2, self.rowHeight - 2)

  row.right = row:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  row.right:SetPoint('RIGHT', -2, 0)
  row.right:SetJustifyH('RIGHT')

  row.text = row:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
  row.text:SetJustifyH('LEFT')
  row.text:SetWordWrap(false)

  row:SetScript('OnEnter', ShowTooltip)
  row:SetScript('OnLeave', function()
    GameTooltip:Hide()
  end)
  row:SetScript('OnClick', function()
    local entry = row.entry

    if entry == nil then
      return
    end

    -- A shift-click links the item in the chat, as elsewhere in the game
    if IsModifiedClick('CHATLINK') and entry.ref ~= nil and entry.ref > 0 then
      local _, link = ns.GetItemInfo(entry.ref)
      if link ~= nil and InsertLink(link) then
        return
      end
    end

    if entry.whisper ~= nil then
      local SendTell = (_G.ChatFrameUtil and _G.ChatFrameUtil.SendTell) or _G.ChatFrame_SendTell
      if SendTell ~= nil then
        SendTell(entry.whisper)
      end
      return
    end

    if not entry.static and self.onClick ~= nil then
      self.onClick(entry)
    end
  end)

  return row
end

-- Sets the number of entries and the function that returns the entry of an
-- index. The scroll position is kept if 'keepOffset' is set.
function List:SetSource(count, getEntry, keepOffset)
  self.count = count
  self.getEntry = getEntry

  local maxOffset = math.max(0, count - self.visible)
  self.slider:SetMinMaxValues(0, maxOffset)
  self.slider:SetShown(maxOffset > 0)
  self:SetOffset(keepOffset and self.offset or 0)
end

function List:SetOffset(offset, fromSlider)
  offset = math.max(0, math.min(offset, math.max(0, self.count - self.visible)))
  self.offset = offset

  if not fromSlider then
    self.slider:SetValue(offset)
  end

  self:Refresh()
end

-- Scrolls as little as needed to make an entry visible
function List:ScrollTo(index)
  if index <= self.offset then
    self:SetOffset(index - 1)
  elseif index > self.offset + self.visible then
    self:SetOffset(index - self.visible)
  end
end

function List:Refresh()
  for index = 1, self.visible do
    local row = self.rows[index]
    local entryIndex = self.offset + index
    local entry = entryIndex <= self.count and self.getEntry(entryIndex) or nil

    row.entry = entry

    if entry == nil then
      row:Hide()
    else
      local left = 2 + (entry.indent or 0) * 14

      if entry.icon ~= nil then
        row.icon:SetTexture(entry.icon)
        row.icon:SetPoint('LEFT', left, 0)
        row.icon:Show()
        left = left + self.rowHeight + 2
      else
        row.icon:Hide()
      end

      row.right:SetText(entry.right or '')
      row.text:ClearAllPoints()
      row.text:SetPoint('LEFT', left, 0)
      row.text:SetPoint('RIGHT', row.right, 'LEFT', -4, 0)
      row.text:SetFontObject(entry.header and GameFontNormal or GameFontHighlightSmall)
      row.text:SetText(entry.text or '')
      row.selection:SetShown(entry.selected == true)
      row:Show()

      if GameTooltip:IsOwned(row) then
        ShowTooltip(row)
      end
    end
  end
end
