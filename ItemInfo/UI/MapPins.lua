local _, ns = ...

-- Pins on the world map where the creatures that drop the items on the
-- wishlist are. A zone map shows them where they are, a continent map shows
-- them too, so that the zone to go to is found at a glance.
--
-- A zone map has a star at each of the places a creature spawns at, up to
-- ten of them spread over where it roams. A continent map has one per
-- creature, enough to tell which zone to go to.
--
-- The pins are drawn by the game's own map framework: a data provider added
-- to the world map, and a pin template defined in MapPins.xml.

local L = ns.L
local Data = ns.Data
local DB = ns.DB

local MapPins = {}
ns.MapPins = MapPins

local TEMPLATE = 'ItemInfoMapPinTemplate'
local GRAY = '|cff909090'

-- The map types of Enum.UIMapType, for clients without the enum
local MAP_TYPE = (_G.Enum and Enum.UIMapType) or {}
local CONTINENT = MAP_TYPE.Continent or 2
local ZONE = MAP_TYPE.Zone or 3

-- The highest map ID looked at when matching zones to maps
local maxMapId = 5000

------------------------------------------
-- Pin
------------------------------------------

-- The mixin of the pin template, the XML refers to it by name. What the map
-- framework's own mixin brings is added once the world map is there.
local PinMixin = {}
_G.ItemInfoMapPinMixin = PinMixin

function PinMixin:OnLoad()
  if self.UseFrameLevelType then
    self:UseFrameLevelType(MapPins.frameLevelType)
  end

  -- Pins keep a readable size whatever the zoom
  if self.SetScalingLimits then
    pcall(self.SetScalingLimits, self, 1, 1.0, 1.25)
  end
end

-- Lifts the star above the pins of other addons, whenever the map sets its
-- frame level
function PinMixin:Raise()
  local top = MapPins.topLevel

  if top ~= nil and (self:GetFrameLevel() or 0) < top then
    self:SetFrameLevel(top)
  end
end

function PinMixin:ApplyFrameLevel()
  local base = _G.MapCanvasPinMixin and MapCanvasPinMixin.ApplyFrameLevel

  if base ~= nil then
    base(self)
  end

  self:Raise()
end

function PinMixin:OnAcquired(npcId, itemIds, x, y)
  self.npcId, self.itemIds = npcId, itemIds
  self:SetPosition(x, y)
end

function PinMixin:OnMouseEnter()
  local name, zone, x, y = DB:GetNpc(self.npcId)

  GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
  GameTooltip:AddLine(ns.Wishlist.STAR .. ' ' .. name)

  if zone ~= nil and x >= 0 then
    GameTooltip:AddLine(GRAY .. string.format('%s (%.1f, %.1f)', zone, x, y) .. '|r')
  end

  for _, itemId in ipairs(self.itemIds) do
    GameTooltip:AddLine('  ' .. DB:GetColoredName(itemId), 1, 1, 1)
  end

  GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
  GameTooltip:Hide()
end

------------------------------------------
-- Zones
------------------------------------------

-- Returns the map of a zone of the drop data, which knows zones by their
-- area ID. Maps are matched by name, zones first, then other maps.
function MapPins:_GetMapId(areaId)
  if self.byName == nil then
    local byName, typeOf = {}, {}

    for mapId = 1, maxMapId do
      local info = C_Map.GetMapInfo(mapId)

      if info ~= nil and info.name ~= nil and info.name ~= '' then
        local known = byName[info.name]
        local isZone = info.mapType == ZONE

        if known == nil or (isZone and typeOf[known] ~= ZONE) then
          byName[info.name] = mapId
          typeOf[mapId] = info.mapType
        end
      end
    end

    self.byName, self.byArea = byName, {}
  end

  local mapId = self.byArea[areaId]

  if mapId == nil then
    local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaId)
    mapId = name ~= nil and self.byName[name] or false
    self.byArea[areaId] = mapId
  end

  return mapId or nil
end

-- Returns the creatures to pin: for each, its map, position (0 to 1) and the
-- wanted items it drops
function MapPins:_GetCreatures()
  local creatures = {}

  for _, itemId in ipairs(ns.Wishlist:GetItems()) do
    local drops = DB:GetDrops(itemId)

    for _, npcId in ipairs(drops or {}) do
      local npc = Data.npcs[npcId]

      if npc ~= nil and npc[2] > 0 and npc[3] >= 0 and npc[4] >= 0 then
        local creature = creatures[npcId]

        if creature == nil then
          local mapId = self:_GetMapId(npc[2])

          if mapId ~= nil then
            local points = { { npc[3] / 100, npc[4] / 100 } }
            local spawns = Data.spawns and Data.spawns[npcId]

            if spawns ~= nil then
              points = {}

              for index = 1, #spawns - 1, 2 do
                points[#points + 1] = { spawns[index] / 100, spawns[index + 1] / 100 }
              end
            end

            creature = { mapId = mapId, points = points, itemIds = {} }
            creatures[npcId] = creature
          end
        end

        if creature ~= nil then
          creature.itemIds[#creature.itemIds + 1] = itemId
        end
      end
    end
  end

  return creatures
end

-- Returns where a point of a zone lies on the map shown, if it shows there:
-- on the zone's own map, or on the continent around it
local function Place(creature, point, mapId)
  local x, y = point[1], point[2]

  if creature.mapId == mapId then
    return x, y
  end

  local info = C_Map.GetMapInfo(mapId)
  if info == nil or info.mapType == nil or info.mapType > CONTINENT or not C_Map.GetMapRectOnMap then
    return nil
  end

  local left, right, top, bottom = C_Map.GetMapRectOnMap(creature.mapId, mapId)
  if left == nil or right == nil or right <= left or bottom <= top then
    return nil
  end

  return left + x * (right - left), top + y * (bottom - top)
end

------------------------------------------
-- Data provider
------------------------------------------

local Provider = {}

function Provider:RemoveAllData()
  self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function Provider:RefreshAllData()
  self:RemoveAllData()

  if not MapPins.options.enabled then
    return
  end

  local map = self:GetMap()
  local mapId = map:GetMapID()
  if mapId == nil then
    return
  end

  MapPins:_FindTopLevel(map)

  local creatures = MapPins:_GetCreatures()
  local npcIds = {}

  for npcId in pairs(creatures) do
    npcIds[#npcIds + 1] = npcId
  end
  table.sort(npcIds)

  -- One star failing must not take the others with it
  local pins = {}

  for _, npcId in ipairs(npcIds) do
    local creature = creatures[npcId]
    -- Away from its zone, a single star tells where the creature is
    local count = creature.mapId == mapId and #creature.points or 1

    for index = 1, count do
      local x, y = Place(creature, creature.points[index], mapId)

      if x ~= nil then
        local success, result = pcall(map.AcquirePin, map, TEMPLATE, npcId, creature.itemIds, x, y)

        if success and result ~= nil then
          result:Raise()
          pins[#pins + 1] = result
        elseif not success and not MapPins.hasFailed then
          MapPins.hasFailed = true
          geterrorhandler()(result)
        end
      end
    end
  end

  -- Other addons may draw their pins right after the map opens, the stars
  -- are lifted above those once they are there
  if #pins > 0 then
    C_Timer.After(0.2, function()
      MapPins:_FindTopLevel(map)

      for _, pin in ipairs(pins) do
        if pin:IsShown() and pin.npcId ~= nil then
          pin:Raise()
        end
      end
    end)
  end
end

-- Finds the highest frame level of the other pins on the map, and their
-- icons a level below, which the stars go just above
function MapPins:_FindTopLevel(map)
  self.topLevel = nil

  if map.GetCanvas == nil then
    return
  end

  local top = 0

  local function Visit(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
      if child.npcId == nil and child.GetFrameLevel ~= nil then
        top = math.max(top, child:GetFrameLevel() or 0)

        if depth < 2 then
          Visit(child, depth + 1)
        end
      end
    end
  end

  Visit(map:GetCanvas(), 1)
  self.topLevel = top > 0 and math.min(top + 1, 9999) or nil
end

------------------------------------------
-- Public
------------------------------------------

-- Redraws the pins, after the wishlist changed say
function MapPins:Refresh()
  if self.isAdded and WorldMapFrame:IsShown() then
    local success, message = pcall(Provider.RefreshAllData, Provider)
    if not success then
      geterrorhandler()(message)
    end
  end
end

-- Turns the pins on or off, returns whether they're on
function MapPins:Toggle()
  self.options.enabled = not self.options.enabled
  self:Refresh()
  return self.options.enabled
end

function MapPins:_Add()
  if self.isAdded or _G.WorldMapFrame == nil or WorldMapFrame.AddDataProvider == nil
    or _G.MapCanvasDataProviderMixin == nil then
    return
  end

  -- Inherits from the framework's mixins, keeping what ItemInfo defines
  local function Inherit(target, base)
    for key, value in pairs(base or {}) do
      if target[key] == nil then
        target[key] = value
      end
    end
  end

  Inherit(Provider, MapCanvasDataProviderMixin)
  Inherit(PinMixin, _G.MapCanvasPinMixin)

  -- Stars go above every other pin, those of other addons such as Questie's
  -- creature icons included, which would hide them. A map that doesn't know
  -- the topmost level gets the one of the zones' points of interest.
  self.frameLevelType = 'PIN_FRAME_LEVEL_AREA_POI'

  local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
  if manager ~= nil and manager.GetValidFrameLevel ~= nil then
    local isKnown, level = pcall(manager.GetValidFrameLevel, manager, 'PIN_FRAME_LEVEL_TOPMOST')

    if isKnown and type(level) == 'number' then
      self.frameLevelType = 'PIN_FRAME_LEVEL_TOPMOST'
    end
  end

  self.isAdded = true
  WorldMapFrame:AddDataProvider(Provider)
end

function MapPins:Init(saved)
  saved.mapPins = saved.mapPins or { enabled = true }
  self.options = saved.mapPins
  self.provider = Provider

  self:_Add()

  -- The world map may load after ItemInfo
  if not self.isAdded then
    ns.On('ADDON_LOADED', function(name)
      if name == 'Blizzard_WorldMap' then
        self:_Add()
      end
    end)
  end
end
