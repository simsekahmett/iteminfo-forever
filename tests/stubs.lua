-- Minimal WoW API for the offline harness
NOW = 1000
local frames, timers, events = {}, {}, {}
local function noop() end

local methods = {}
local widgetMeta = { __index = function(_, k) return methods[k] or (type(k) == 'string' and k:match('^%u') and noop) or nil end }
local function widget(kind)
  local w = setmetatable({ kind = kind, scripts = {}, shown = true, text = '', value = 0 }, widgetMeta)
  return w
end
function methods:SetScript(n, f) self.scripts[n] = f end
function methods:GetScript(n) return self.scripts[n] end
function methods:HookScript(n, f) local o = self.scripts[n]; self.scripts[n] = function(...) if o then o(...) end f(...) end end
function methods:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown = false end
function methods:SetShown(s) if s then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetText(t) self.text = t end
function methods:GetText() return self.text end
function methods:CreateTexture() return widget('Texture') end
function methods:CreateFontString() return widget('FontString') end
function methods:RegisterEvent(e) events[e] = events[e] or {}; events[e][self] = true end
function methods:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
function methods:GetWidth() return 140 end
function methods:GetHeight() return 140 end
function methods:GetCenter() return 0, 0 end
function methods:GetEffectiveScale() return 1 end
function methods:IsOwned() return false end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end
function methods:ClearFocus() end
function methods:SetBackdrop() end

function CreateFrame(kind, name, parent, template)
  local f = widget(kind)
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent, Minimap, GameTooltip = widget('Frame'), widget('Frame'), widget('GameTooltip')
BackdropTemplateMixin = {}
UISpecialFrames, SlashCmdList = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHATLOG[#CHATLOG + 1] = m end }
CHATLOG = {}
ITEM_QUALITY_COLORS = {}
for q = 0, 7 do ITEM_QUALITY_COLORS[q] = { hex = '|cff00000' .. q } end

function GetLocale() return TEST_LOCALE or 'enUS' end
function GetBuildInfo() return '1.60.1', '69893', 'Nov 1 2026', 16001 end
function GetTime() return NOW end
function GetServerTime() return math.floor(NOW) + 1700000000 end
function InCombatLockdown() return COMBAT or false end
function IsModifiedClick() return false end
function geterrorhandler() return function(m) error(m, 0) end end
function GetCursorPosition() return 10, 10 end
function GetRealZoneText() return ZONE or 'Testzone' end
function UnitGUID() return 'Creature-0-1-2-3-99999-0000ABCDEF' end
function UnitName() return 'Test Vendor' end
function GetMerchantNumItems() return 2 end
function GetMerchantItemID(i) return ({ 5772, 2605 })[i] end
function GetMerchantItemInfo(i) return 'x', 1, ({ 500, 50 })[i], 1 end
function strsplit(sep, s) local out = {}; for part in (s .. sep):gmatch('(.-)' .. sep) do out[#out + 1] = part end; return unpack(out) end
C_Timer = { After = function(d, f) timers[#timers + 1] = { at = NOW + d, f = f } end }
C_Map = { GetAreaInfo = function(id) return 'Zone' .. id end, GetBestMapForUnit = function() return 1 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end }
local profNames = { [3908] = 'Tailoring', [2550] = 'Cooking' }
C_Spell = { GetSpellName = function(id) return profNames[id] or ('Spell ' .. id) end, GetSpellTexture = function() return 136243 end }

-- A simulated item server: answers late, drops some queries, never answers hidden items
ITEMS, QUERIES = {}, 0
local cached, inflight = {}, {}
local function info(id)
  local i = ITEMS[id]
  return i.name, '|cffffffff|Hitem:' .. id .. '::::::::|h[' .. i.name .. ']|h|r', i.quality or 1, i.ilvl or 10, i.minLevel or 0,
    i.typeName or 'Miscellaneous', i.subName or 'Junk', 20, i.slot or '', 134400, i.price or 0, i.class or 15, i.sub or 0
end
C_Item = {
  GetItemInfoInstant = function(id)
    local i = ITEMS[id]
    if not i then return nil end
    return id, i.typeName or 'Miscellaneous', i.subName or 'Junk', i.slot or '', 134400, i.class or 15, i.sub or 0
  end,
  GetItemInfo = function(id)
    local i = ITEMS[id]
    if not i then return nil end
    if cached[id] then return info(id) end
    if not inflight[id] and not i.hidden then
      QUERIES = QUERIES + 1
      -- about 6% of the queries are dropped by the server
      if (QUERIES * 7919 + id) % 101 >= 6 then inflight[id] = NOW + 0.2 end
    end
    return nil
  end,
}

function FireEvent(e, ...)
  for f in pairs(events[e] or {}) do if f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end
end
function Tick(dt)
  NOW = NOW + dt
  for id, at in pairs(inflight) do
    if at <= NOW then inflight[id] = nil; cached[id] = true; FireEvent('GET_ITEM_INFO_RECEIVED', id, true) end
  end
  for i = #timers, 1, -1 do
    if timers[i].at <= NOW then local t = table.remove(timers, i); t.f() end
  end
  for i = 1, #frames do
    local f = frames[i]
    if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
  end
end

-- Tooltip pipeline
Enum = { TooltipDataType = { Item = 0 } }
TOOLTIP_CALLS = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, f) TOOLTIP_CALLS[#TOOLTIP_CALLS + 1] = f end }
SHIFT = false
function IsShiftKeyDown() return SHIFT end
function UnitFactionGroup() return 'Horde' end
TIP = {}
function GameTooltip:AddLine(text) TIP[#TIP + 1] = text end
function GameTooltip:AddDoubleLine(left, right) TIP[#TIP + 1] = left .. '   [' .. right .. ']' end
function GameTooltip:GetOwner() return TIP_OWNER end
function ShowItemTooltip(id) TIP = {}; for _, f in ipairs(TOOLTIP_CALLS) do f(GameTooltip, { id = id }) end; return TIP end
