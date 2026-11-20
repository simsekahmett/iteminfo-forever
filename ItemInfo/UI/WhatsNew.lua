local _, ns = ...

-- A page that tells what a new version brings, shown once after an update.
--
-- Each release with something to tell adds an entry on top of 'NOTES'. The
-- page is shown when the newest entry has not been seen, so it works the same
-- for a release and for a development copy. A fresh install is not shown
-- anything, there's nothing new to someone who never used ItemInfo.

local L = ns.L

local WhatsNew = {}
ns.WhatsNew = WhatsNew

local GOLD = '|cffffd100'
local GRAY = '|cff909090'
local WIDTH, HEIGHT, PADDING = 460, 400, 16

-- The newest first. The texts are keys of the translations.
WhatsNew.NOTES = {
  {
    version = '1.5.4',
    sections = {
      {
        title = 'What a creature drops',
        lines = {
          'Hover or target a creature: its tooltip lists the few items worth knowing that it drops, its own loot first. Hold Shift for more.',
          'The look-up key over a creature, or /iteminfo target, lists everything it drops in the window.',
          'Choose what creature tooltips show with /iteminfo creature.',
        },
      },
      {
        title = 'Wishlist',
        lines = {
          "Click the star beside an item's name in the window to add it to the wishlist of your character.",
          'Stars on the world map show where the creatures that drop them are. Hide them with /iteminfo map.',
          'Targeting a creature that drops one of them, or opening a vendor that sells one, tells you in chat.',
          'Getting one takes it off the list. Turn the alerts off with /iteminfo alerts.',
        },
      },
    },
  },
}

function WhatsNew:_Create()
  local frame = CreateFrame('Frame', 'ItemInfoWhatsNewFrame', UIParent,
                            _G.BackdropTemplateMixin and 'BackdropTemplate' or nil)
  self.frame = frame

  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint('CENTER', 0, 40)
  frame:SetFrameStrata('DIALOG')
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

  -- Escape closes the page
  table.insert(UISpecialFrames, 'ItemInfoWhatsNewFrame')

  local logo = frame:CreateTexture(nil, 'ARTWORK')
  logo:SetTexture(ns.LOGO)
  logo:SetSize(40, 40)
  logo:SetPoint('TOPLEFT', PADDING - 4, -PADDING + 6)

  local title = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
  title:SetPoint('TOPLEFT', logo, 'TOPRIGHT', 6, -4)
  self.title = title

  local subtitle = frame:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  subtitle:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -3)
  subtitle:SetText(L['What is new in this version'])

  local close = CreateFrame('Button', nil, frame, 'UIPanelCloseButton')
  close:SetPoint('TOPRIGHT', -2, -2)

  local done = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
  done:SetSize(110, 22)
  done:SetPoint('BOTTOMRIGHT', -PADDING, PADDING - 4)
  done:SetText(_G.OKAY or L['Got it'])
  done:SetScript('OnClick', function()
    frame:Hide()
  end)

  local footer = frame:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
  footer:SetPoint('BOTTOMLEFT', PADDING, PADDING + 2)
  footer:SetPoint('RIGHT', done, 'LEFT', -8, 0)
  footer:SetJustifyH('LEFT')
  footer:SetText(L['/iteminfo news shows this page again.'])

  self.texts = {}
end

-- Returns a text of the page, creating it when there are not enough
function WhatsNew:_Text(index)
  local text = self.texts[index]

  if text == nil then
    text = self.frame:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
    text:SetJustifyH('LEFT')
    text:SetJustifyV('TOP')
    text:SetWordWrap(true)
    self.texts[index] = text
  end

  return text
end

-- Fills the page with the notes of a version
function WhatsNew:_Fill(notes)
  self.title:SetText(L['ItemInfo %s']:format(notes.version))

  local width = WIDTH - PADDING * 2
  local top = -PADDING - 46
  local count = 0

  local function Add(content, font, indent, gap)
    count = count + 1
    local text = self:_Text(count)

    top = top - gap
    text:SetFontObject(font)
    text:ClearAllPoints()
    text:SetPoint('TOPLEFT', PADDING + indent, top)
    text:SetWidth(width - indent)
    text:SetText(content)
    text:Show()
    top = top - (text:GetStringHeight() or 14)
  end

  for _, section in ipairs(notes.sections) do
    Add(GOLD .. L[section.title] .. '|r', GameFontNormal, 0, count > 0 and 12 or 0)

    for _, line in ipairs(section.lines) do
      Add(GRAY .. '-|r ' .. L[line], GameFontHighlight, 8, 5)
    end
  end

  for index = count + 1, #self.texts do
    self.texts[index]:Hide()
  end

  self.lines = count
end

-- Shows the notes of the newest version
function WhatsNew:Show()
  if self.frame == nil then
    self:_Create()
  end

  self:_Fill(self.NOTES[1])
  self.frame:Show()
end

-- Shows the page if the newest notes are unseen, once the chat has settled
-- after login and never in combat
function WhatsNew:Init(saved, isFirstRun)
  local newest = self.NOTES[1].version

  if isFirstRun then
    saved.whatsNew = newest
  end

  if saved.whatsNew == newest then
    return
  end

  C_Timer.After(4, function()
    if InCombatLockdown() then
      ns.On('PLAYER_REGEN_ENABLED', function()
        if saved.whatsNew ~= newest then
          saved.whatsNew = newest
          self:Show()
        end
      end)
      return
    end

    saved.whatsNew = newest
    self:Show()
  end)
end
