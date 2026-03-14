local addonName, FBStorage = ...
local FBI = FBStorage
local FBConstants = FBI.FBConstants

local FL = LibStub("LibFishing-1.0")

local SESSION_TAB = "Session"
local SESSION_INFO = "Shows catch statistics for the current session."
local SESSION_RESET = "Reset Session"
local SESSION_EMPTY = "No fishing data collected in this session yet."

local SessionStats = {}
SessionStats.__index = SessionStats

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %02dm %02ds", hours, minutes, secs)
    end
    return string.format("%dm %02ds", minutes, secs)
end

local function SortedPairsByCount(values)
    local sorted = {}
    for key, count in pairs(values) do
        tinsert(sorted, { key = key, count = count })
    end
    table.sort(sorted, function(a, b)
        if a.count == b.count then
            return a.key < b.key
        end
        return a.count > b.count
    end)
    return sorted
end

function SessionStats:Reset()
    local now = GetTime()
    self.startedAt = now
    self.fishingSince = nil
    self.fishingSeconds = 0
    self.totalCaught = 0
    self.countedCaught = 0
    self.otherCaught = 0
    self.poolCaught = 0
    self.openWaterCaught = 0
    self.uniqueFish = {}
    self.uniqueCounted = {}
    self.fishCounts = {}
    self.zoneCounts = {}
    self.lastCatch = nil
    if FBI.AreWeFishing and FBI:AreWeFishing() then
        self.fishingSince = now
    end
end

function SessionStats:GetFishingSeconds()
    local active = self.fishingSeconds
    if self.fishingSince then
        active = active + (GetTime() - self.fishingSince)
    end
    return active
end

function SessionStats:StartFishing()
    if not self.fishingSince then
        self.fishingSince = GetTime()
    end
end

function SessionStats:StopFishing()
    if self.fishingSince then
        self.fishingSeconds = self.fishingSeconds + (GetTime() - self.fishingSince)
        self.fishingSince = nil
    end
end

function SessionStats:AddCatch(id, name, quantity, mapId, subzone, poolhint)
    quantity = quantity or 1
    self.totalCaught = self.totalCaught + quantity

    local zoneName = FL:GetLocZone(mapId) or UNKNOWN
    local zoneLabel = zoneName
    if subzone and subzone ~= "" and subzone ~= zoneName then
        zoneLabel = zoneName.." / "..subzone
    end
    self.zoneCounts[zoneLabel] = (self.zoneCounts[zoneLabel] or 0) + quantity

    self.uniqueFish[id] = true
    self.fishCounts[id] = (self.fishCounts[id] or 0) + quantity
    self.lastCatch = {
        id = id,
        name = name,
        quantity = quantity,
        zone = zoneLabel,
        at = GetTime(),
    }

    if poolhint then
        self.poolCaught = self.poolCaught + quantity
    else
        self.openWaterCaught = self.openWaterCaught + quantity
    end

    if FBI:IsCountedFish(id) then
        self.countedCaught = self.countedCaught + quantity
        self.uniqueCounted[id] = true
    else
        self.otherCaught = self.otherCaught + quantity
    end
end

function SessionStats:GetSnapshot()
    local unique = 0
    for _ in pairs(self.uniqueFish) do
        unique = unique + 1
    end

    local uniqueCounted = 0
    for _ in pairs(self.uniqueCounted) do
        uniqueCounted = uniqueCounted + 1
    end

    return {
        elapsed = GetTime() - self.startedAt,
        fishingSeconds = self:GetFishingSeconds(),
        totalCaught = self.totalCaught,
        countedCaught = self.countedCaught,
        otherCaught = self.otherCaught,
        poolCaught = self.poolCaught,
        openWaterCaught = self.openWaterCaught,
        unique = unique,
        uniqueCounted = uniqueCounted,
        fishCounts = self.fishCounts,
        zoneCounts = self.zoneCounts,
        lastCatch = self.lastCatch,
    }
end

local tracker = setmetatable({}, SessionStats)
tracker:Reset()
FBI.SessionStats = tracker

local function CreateLabel(parent, anchorTo, x, y, text, template, r, g, b)
    local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    label:SetJustifyH("LEFT")
    label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", x or 0, y or 0)
    if r then
        label:SetTextColor(r, g, b)
    end
    label:SetText(text or "")
    return label
end

local function CreateValue(parent, anchorTo, offsetX)
    local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetJustifyH("LEFT")
    value:SetPoint("LEFT", anchorTo, "RIGHT", offsetX or 8, 0)
    value:SetText("")
    return value
end

local function UpdateSessionFrame()
    local frame = FishingSessionFrame
    if not frame then
        return
    end

    local snapshot = tracker:GetSnapshot()
    local fishingSeconds = snapshot.fishingSeconds
    local hours = fishingSeconds / 3600
    local catchesPerHour = 0
    if hours > 0 then
        catchesPerHour = snapshot.totalCaught / hours
    end

    frame.summaryValues.sessionTime:SetText(FormatDuration(snapshot.elapsed))
    frame.summaryValues.activeFishing:SetText(FormatDuration(fishingSeconds))
    frame.summaryValues.totalCaught:SetText(snapshot.totalCaught)
    frame.summaryValues.countedCaught:SetText(snapshot.countedCaught)
    frame.summaryValues.otherCaught:SetText(snapshot.otherCaught)
    frame.summaryValues.uniqueFish:SetText(string.format("%d total / %d counted", snapshot.unique, snapshot.uniqueCounted))
    frame.summaryValues.catchRate:SetText(string.format("%.1f / hr", catchesPerHour))
    frame.summaryValues.waterType:SetText(string.format("%d pool / %d open water", snapshot.poolCaught, snapshot.openWaterCaught))

    if snapshot.lastCatch then
        local lastName = snapshot.lastCatch.name
        if not lastName then
            local _, _, _, _, _, fallbackName = FBI:GetFishieRaw(snapshot.lastCatch.id)
            lastName = fallbackName or UNKNOWN
        end
        frame.lastCatchValue:SetText(string.format("%s x%d [%s]", lastName, snapshot.lastCatch.quantity, snapshot.lastCatch.zone))
    else
        frame.lastCatchValue:SetText(SESSION_EMPTY)
    end

    local sortedFish = SortedPairsByCount(snapshot.fishCounts)
    for index, line in ipairs(frame.topFishLines) do
        local info = sortedFish[index]
        if info then
            local _, _, _, _, _, name = FBI:GetFishieRaw(info.key)
            line:SetText(string.format("%d. %s x%d", index, name or UNKNOWN, info.count))
        else
            line:SetText("")
        end
    end

    local sortedZones = SortedPairsByCount(snapshot.zoneCounts)
    for index, line in ipairs(frame.topZoneLines) do
        local info = sortedZones[index]
        if info then
            line:SetText(string.format("%d. %s x%d", index, info.key, info.count))
        else
            line:SetText("")
        end
    end
end

local function ResetSessionStats()
    tracker:Reset()
    UpdateSessionFrame()
end

local function CreateSessionFrame()
    if FishingSessionFrame then
        return FishingSessionFrame
    end

    local frame = CreateFrame("Frame", "FishingSessionFrame", FishingBuddyFrame)
    frame:SetAllPoints()
    frame:SetScript("OnShow", function()
        UpdateSessionFrame()
    end)
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 1 then
            self.elapsed = 0
            if self:IsShown() then
                UpdateSessionFrame()
            end
        end
    end)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -24)
    title:SetText(SESSION_TAB)

    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText(SESSION_INFO)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(120, 22)
    reset:SetPoint("TOPRIGHT", -24, -24)
    reset:SetText(SESSION_RESET)
    reset:SetScript("OnClick", ResetSessionStats)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 16)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(520, 900)
    scrollFrame:SetScrollChild(content)

    frame.scrollFrame = scrollFrame
    frame.content = content

    local summaryHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    summaryHeader:SetJustifyH("LEFT")
    summaryHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    summaryHeader:SetText("Summary")
    local summaryLabels = {}
    local summaryValues = {}
    local entries = {
        { key = "sessionTime", text = "Session time" },
        { key = "activeFishing", text = "Active fishing" },
        { key = "totalCaught", text = "Total catches" },
        { key = "countedCaught", text = "Counted fish" },
        { key = "otherCaught", text = "Other catches" },
        { key = "uniqueFish", text = "Unique catches" },
        { key = "catchRate", text = "Catch rate" },
        { key = "waterType", text = "Water type split" },
    }

    local anchor = summaryHeader
    for index, info in ipairs(entries) do
        local y = index == 1 and -12 or -8
        local label = CreateLabel(frame, anchor, 0, y, info.text..":", "GameFontHighlightSmall")
        local value = CreateValue(frame, label, 12)
        summaryLabels[info.key] = label
        summaryValues[info.key] = value
        anchor = label
    end

    frame.summaryLabels = summaryLabels
    frame.summaryValues = summaryValues

    local lastCatchLabel = CreateLabel(content, anchor, 0, -16, "Last catch:", "GameFontHighlightSmall")
    local lastCatchValue = CreateLabel(content, lastCatchLabel, 0, -8, "", "GameFontHighlight")
    lastCatchValue:SetWidth(500)
    lastCatchValue:SetJustifyH("LEFT")
    frame.lastCatchValue = lastCatchValue

    local topFishHeader = CreateLabel(content, lastCatchValue, 0, -18, "Top catches", "GameFontNormal")

    frame.topFishLines = {}
    frame.topZoneLines = {}

    anchor = topFishHeader
    for index = 1, 8 do
        local line = CreateLabel(content, anchor, 0, -10, "", "GameFontHighlightSmall")
        line:SetWidth(500)
        frame.topFishLines[index] = line
        anchor = line
    end

    local topZoneHeader = CreateLabel(content, anchor, 0, -18, "Top zones", "GameFontNormal")

    anchor = topZoneHeader
    for index = 1, 8 do
        local line = CreateLabel(content, anchor, 0, -10, "", "GameFontHighlightSmall")
        line:SetWidth(500)
        frame.topZoneLines[index] = line
        anchor = line
    end

    content:SetHeight(720)

    frame:SetScript("OnSizeChanged", function(self, width, height)
        local contentWidth = math.max(320, width - 70)
        content:SetWidth(contentWidth)
        lastCatchValue:SetWidth(contentWidth - 20)
        for _, line in ipairs(frame.topFishLines) do
            line:SetWidth(contentWidth - 20)
        end
        for _, line in ipairs(frame.topZoneLines) do
            line:SetWidth(contentWidth - 20)
        end
    end)

    return frame
end

local SessionEvents = {}

SessionEvents["VARIABLES_LOADED"] = function()
    CreateSessionFrame()
    local groups = {
        {
            ["name"] = SESSION_TAB,
            ["icon"] = "Interface\\Icons\\INV_Misc_PocketWatch_01",
            ["frame"] = "FishingSessionFrame",
        },
    }
    FBI:CreateManagedFrameGroup(SESSION_TAB, SESSION_INFO, "_SES", groups)
    UpdateSessionFrame()
end

SessionEvents[FBConstants.ADD_FISHIE_EVT] = function(id, name, mapId, subzone, texture, quantity, quality, level, idx, poolhint)
    tracker:AddCatch(id, name, quantity, mapId, subzone, poolhint)
    UpdateSessionFrame()
end

SessionEvents[FBConstants.FISHING_ENABLED_EVT] = function()
    tracker:StartFishing()
    UpdateSessionFrame()
end

SessionEvents[FBConstants.FISHING_DISABLED_EVT] = function()
    tracker:StopFishing()
    UpdateSessionFrame()
end

FBI:RegisterHandlers(SessionEvents)
