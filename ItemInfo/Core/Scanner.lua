local _, ns = ...

-- Builds the item database by asking the client for every item it knows of.
--
-- The scanning approach (probing the client's item table, pacing the queries
-- to what the server answers, and rechecking unanswered items) is adapted from
-- ItemAutocomplete by Elliott Linder (MIT), see NOTICE.md.

local GetItemInfo = ns.GetItemInfo
local GetItemInfoInstant = ns.GetItemInfoInstant

local Scanner = {}
ns.Scanner = Scanner

local const = {
  -- Local existence checks per frame, these never reach the server
  checksPerFrame = 2000,
  -- The scan ends after this many IDs without an item, but never before
  -- 'minEnd' since the item table has gaps wider than that
  gap = 50000,
  minEnd = 350000,
  -- The server drops item queries when flooded, so those awaiting an answer
  -- are capped. Some are never answered (items hidden until they first drop),
  -- thus a query only counts towards the cap whilst younger than 'liveTime'.
  limitInitial = 20,
  limitMin = 5,
  limitMax = 100,
  pendingMax = 1000,
  liveTime = 1,
  timeout = 5,
  attempts = 3,
  dropShare = 0.1,
  -- Unanswered items are skipped by a scan for a day, unless it's asked to
  -- recheck them. They are revealed as they drop on the server.
  recheckTime = 86400,
  version = 1,
}

-- Names of items left in the client by the developers
local devPatterns = {
  'Monster %-', 'Monster,', 'DEPRECATED', 'Dep[rt][ie]cated', 'DEBUG', '%(old%d?%)',
  '[ %(]test[%) ]', '^test ', 'Test[%u) ]', 'Test$', 'Test_', 'TEST', 'UNUSED',
  '^Unused ', '^zz',
}

local function IsDevItem(name)
  for index = 1, #devPatterns do
    if name:find(devPatterns[index]) then
      return true
    end
  end

  return false
end

------------------------------------------
-- Setup
------------------------------------------

-- Item names differ by locale, so each locale has a database of its own
function Scanner:Init(saved)
  saved.items = saved.items or {}

  local locale = GetLocale()
  local db = saved.items[locale]

  if db == nil or db.version ~= const.version then
    db = { version = const.version }
    saved.items[locale] = db
  end

  db.names = db.names or {}
  db.quality = db.quality or {}
  db.price = db.price or {}
  db.unavailable = db.unavailable or {}

  self.db = db
  self.build = tonumber((select(2, GetBuildInfo()))) or 0
  self.itemIds = {}
  self.listeners = {}

  for itemId in pairs(db.names) do
    self.itemIds[#self.itemIds + 1] = itemId
  end
  table.sort(self.itemIds)

  -- A patch may make items available, only dev items (0) stay excluded
  if db.build ~= nil and db.build ~= self.build then
    for itemId, since in pairs(db.unavailable) do
      if since ~= 0 then
        db.unavailable[itemId] = nil
      end
    end
  end

  self:_Reset()

  self.frame = CreateFrame('Frame')
  self.frame:Hide()
  self.frame:SetScript('OnUpdate', function()
    self:_OnUpdate()
  end)

  ns.On('GET_ITEM_INFO_RECEIVED', function(itemId, success)
    self:_OnItemInfoReceived(itemId, success)
  end)
end

-- Registers a function called with the ID of every item added
function Scanner:OnItemAdded(callback)
  self.listeners[#self.listeners + 1] = callback
end

------------------------------------------
-- Queries
------------------------------------------

function Scanner:GetName(itemId)
  return self.db.names[itemId]
end

function Scanner:GetQuality(itemId)
  return self.db.quality[itemId]
end

-- Returns the price a vendor pays for an item, or nil if it cannot be sold
function Scanner:GetSellPrice(itemId)
  return self.db.price[itemId]
end

-- Returns the sorted list of item IDs and their names, the list is only ever
-- appended to
function Scanner:GetItems()
  return self.itemIds, self.db.names
end

function Scanner:GetItemCount()
  return #self.itemIds
end

function Scanner:IsScanning()
  return self.thread ~= nil
end

-- Returns whether the database is empty, or a scan was left unfinished
function Scanner:IsIncomplete()
  return next(self.db.names) == nil or self.db.scan ~= nil
end

-- Returns whether the client was patched since the database was last updated
function Scanner:IsStale()
  return self.db.build ~= nil and self.db.build ~= self.build
end

-- Returns how far the scan has come, between 0 and 1
function Scanner:GetProgress()
  local scan = self.db.scan

  if scan == nil then
    return 1
  end

  local total = self:_GetEnd(scan)
  self.progress = math.max(self.progress or 0, math.min(1, scan.nextId / total))
  return self.progress
end

------------------------------------------
-- Scanning
------------------------------------------

-- Adds an item whose info the client has, returns whether it was added
function Scanner:Add(itemId)
  local name, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemId)

  if name == nil or name == '' then
    return false
  end

  local db = self.db

  if IsDevItem(name) then
    db.unavailable[itemId] = 0
    return false
  end

  local isNew = db.names[itemId] == nil

  db.names[itemId] = name
  db.quality[itemId] = quality
  db.price[itemId] = (sellPrice or 0) > 0 and sellPrice or nil
  db.unavailable[itemId] = nil

  if isNew then
    self.itemIds[#self.itemIds + 1] = itemId

    for index = 1, #self.listeners do
      self.listeners[index](itemId)
    end
  end

  return true
end

-- Starts scanning in the background. Only items missing from the database
-- are queried, unless it's rebuilt. With 'recheck', items the server did not
-- answer before are queried again regardless of when they last were.
function Scanner:Start(rebuild, onFinish, recheck)
  if self:IsScanning() then
    return false
  end

  local db = self.db

  if recheck then
    for itemId, since in pairs(db.unavailable) do
      if since ~= 0 then
        db.unavailable[itemId] = nil
      end
    end
  end

  if rebuild then
    -- Fresh tables are used since a search may be traversing the current ones
    db.names, db.quality, db.price, db.unavailable = {}, {}, {}, {}
    db.scan = nil
    self.itemIds = {}
  end

  db.scan = db.scan or { unresolved = {} }

  -- A scan interrupted by a patch starts over, known items are not queried
  local scan = db.scan
  if scan.build ~= self.build then
    scan.build = self.build
    scan.nextId = 1
    scan.highestId = 0
  end

  -- Requests left unanswered by a previous session are sent again
  self:_Reset()
  for itemId, attempts in pairs(scan.unresolved) do
    if attempts >= const.attempts then
      db.unavailable[itemId] = GetServerTime()
      scan.unresolved[itemId] = nil
    else
      self.attempts[itemId] = attempts
      self.retries[#self.retries + 1] = itemId
    end
  end

  self.onFinish = onFinish
  self.thread = coroutine.create(function()
    self:_Run()
  end)
  self.frame:Show()

  return true
end

function Scanner:_Reset()
  self.pending = {}
  self.pendingCount = 0
  self.live = {}
  self.liveCount = 0
  self.attempts = {}
  self.retries = {}
  self.retried = {}
  self.limit = const.limitInitial
  self.window = { startedAt = GetTime(), answered = 0, retriesAnswered = 0 }
  self.progress = nil
end

function Scanner:_GetEnd(scan)
  return math.max(math.max(scan.highestId, self.db.highestId or 0) + const.gap, const.minEnd)
end

function Scanner:_OnUpdate()
  local thread = self.thread

  if thread == nil then
    self.frame:Hide()
    return
  end

  local success, message = coroutine.resume(thread)

  if coroutine.status(thread) == 'dead' then
    self.thread = nil
    self.frame:Hide()

    if not success then
      geterrorhandler()(message)
    elseif self.onFinish ~= nil then
      self.onFinish(self:GetItemCount())
    end
  end
end

function Scanner:_EndLive(itemId)
  if self.live[itemId] then
    self.live[itemId] = nil
    self.liveCount = self.liveCount - 1
  end
end

function Scanner:_Complete(itemId)
  self:_EndLive(itemId)
  self.pending[itemId] = nil
  self.pendingCount = self.pendingCount - 1
  self.attempts[itemId] = nil
  self.retried[itemId] = nil
end

function Scanner:_Resolve(itemId)
  local scan = self.db.scan

  if scan ~= nil then
    scan.unresolved[itemId] = nil
  end
end

function Scanner:_IsUnavailable(itemId)
  local since = self.db.unavailable[itemId]

  if since == nil then
    return false
  end

  return since == 0 or GetServerTime() - since < const.recheckTime
end

function Scanner:_OnItemInfoReceived(itemId, success)
  if self.pending[itemId] == nil then
    -- The client also receives the info of items encountered in the world
    if success then
      self:Add(itemId)
    end
    return
  end

  -- The info may arrive before it can be read, the request then times out and
  -- is sent again.
  if success and not self:Add(itemId) and not self.db.unavailable[itemId] then
    return
  end

  -- The server refuses to return the item, or it does not exist
  if not success then
    self.db.unavailable[itemId] = GetServerTime()
  end

  local window = self.window
  window.answered = window.answered + 1
  if self.retried[itemId] then
    window.retriesAnswered = window.retriesAnswered + 1
  end

  self:_Complete(itemId)
  self:_Resolve(itemId)
  self.limit = math.min(const.limitMax, self.limit + 1 / self.limit)
end

function Scanner:_Expire()
  local now = GetTime()

  for itemId, requestedAt in pairs(self.pending) do
    local age = now - requestedAt

    if age > const.timeout then
      local attempts = self.attempts[itemId]
      self:_Complete(itemId)

      if attempts < const.attempts then
        self.attempts[itemId] = attempts
        self.retries[#self.retries + 1] = itemId
      else
        -- The server won't answer, e.g. an item that is still hidden
        self.db.unavailable[itemId] = GetServerTime()
        self:_Resolve(itemId)
      end
    elseif age > const.liveTime then
      self:_EndLive(itemId)
    end
  end

  -- Dropped queries are answered on retry, a timeout later, so the cap is
  -- lowered at most once per timeout.
  local window = self.window
  if now - window.startedAt > const.timeout then
    if window.retriesAnswered > const.dropShare * window.answered then
      self.limit = math.max(const.limitMin, self.limit / 2)
    end

    self.window = { startedAt = now, answered = 0, retriesAnswered = 0 }
  end
end

-- Requests an item from the server if it's missing, returns whether it was
function Scanner:_Request(itemId, scan)
  local db = self.db
  local isKnown = db.names[itemId] ~= nil or self:_IsUnavailable(itemId)

  if not isKnown and GetItemInfoInstant(itemId) == nil then
    self:_Resolve(itemId)
    return false
  end

  -- Known items count as well, otherwise a scan would end prematurely
  scan.highestId = math.max(scan.highestId, itemId)

  if self.pending[itemId] ~= nil then
    return false
  end

  if isKnown then
    self:_Resolve(itemId)
    return false
  end

  -- An item due for a recheck is only queried once, most are still hidden
  if db.unavailable[itemId] ~= nil and self.attempts[itemId] == nil then
    self.attempts[itemId] = const.attempts - 1
  end

  db.unavailable[itemId] = nil

  if self:Add(itemId) or db.unavailable[itemId] then
    self:_Resolve(itemId)
    return false
  end

  self.pending[itemId] = GetTime()
  self.pendingCount = self.pendingCount + 1
  self.live[itemId] = true
  self.liveCount = self.liveCount + 1
  self.attempts[itemId] = (self.attempts[itemId] or 0) + 1
  scan.unresolved[itemId] = self.attempts[itemId]
  return true
end

function Scanner:_Run()
  local db = self.db
  local scan = db.scan
  local isExhausted = false

  while not isExhausted or self.pendingCount > 0 or #self.retries > 0 do
    self:_Expire()

    -- Item queries are held back during combat
    if not InCombatLockdown() then
      local checks = 0

      while checks < const.checksPerFrame and self.liveCount < math.floor(self.limit) and
        self.pendingCount < const.pendingMax do
        local retryId = table.remove(self.retries)
        local itemId = retryId

        if itemId == nil and scan.nextId <= self:_GetEnd(scan) then
          itemId = scan.nextId
          scan.nextId = itemId + 1
        end

        if itemId == nil then
          isExhausted = true
          break
        end

        if self:_Request(itemId, scan) and retryId ~= nil then
          self.retried[itemId] = true
        end

        checks = checks + 1
      end
    end

    coroutine.yield()
  end

  db.scan = nil
  db.checkedAt = GetServerTime()
  db.highestId = scan.highestId
  db.build = self.build
end
