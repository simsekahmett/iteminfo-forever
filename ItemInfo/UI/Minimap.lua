local ADDON, ns = ...

-- A button on the minimap's edge that opens the window, it can be dragged
-- around the minimap.

local L = ns.L

local MinimapButton = {}
ns.MinimapButton = MinimapButton

function MinimapButton:Init(saved)
  saved.minimap = saved.minimap or { angle = 200, hide = false }
  self.options = saved.minimap

  local button = CreateFrame('Button', 'ItemInfoMinimapButton', Minimap)
  self.button = button

  button:SetSize(31, 31)
  button:SetFrameStrata('MEDIUM')
  button:SetFrameLevel(8)
  button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  button:RegisterForDrag('LeftButton')
  button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')

  local icon = button:CreateTexture(nil, 'BACKGROUND')
  icon:SetTexture('Interface\\Icons\\INV_Misc_Book_09')
  icon:SetSize(20, 20)
  icon:SetPoint('CENTER', 0, 1)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local border = button:CreateTexture(nil, 'OVERLAY')
  border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  border:SetSize(53, 53)
  border:SetPoint('TOPLEFT')

  button:SetScript('OnClick', function()
    ns.UI:Toggle()
  end)

  button:SetScript('OnEnter', function()
    GameTooltip:SetOwner(button, 'ANCHOR_LEFT')
    GameTooltip:SetText(ADDON)
    GameTooltip:AddLine(L['Click to open, drag to move.'], 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript('OnLeave', function()
    GameTooltip:Hide()
  end)

  -- Whilst dragged, the button follows the cursor around the minimap
  button:SetScript('OnDragStart', function()
    button:SetScript('OnUpdate', function()
      local centerX, centerY = Minimap:GetCenter()
      local cursorX, cursorY = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()

      self.options.angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
      self:_Update()
    end)
  end)
  button:SetScript('OnDragStop', function()
    button:SetScript('OnUpdate', nil)
  end)

  self:_Update()
end

function MinimapButton:_Update()
  local angle = math.rad(self.options.angle)
  local radius = Minimap:GetWidth() / 2 + 5

  self.button:ClearAllPoints()
  self.button:SetPoint('CENTER', Minimap, 'CENTER', math.cos(angle) * radius, math.sin(angle) * radius)
  self.button:SetShown(not self.options.hide)
end

-- Shows or hides the button, returns whether it's shown
function MinimapButton:Toggle()
  self.options.hide = not self.options.hide
  self:_Update()
  return not self.options.hide
end
