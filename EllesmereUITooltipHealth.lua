local ADDON = "EllesmereUITooltipHealth"

local state = setmetatable({}, { __mode = "k" })
local issecret = _G.issecretvalue

local function isSecret(v)
    return issecret ~= nil and issecret(v)
end

local canaccess = _G.canaccessvalue

local function CanAccess(v)
    if v == nil then return false end
    if isSecret(v) then return false end
    if canaccess then
        local ok, r = pcall(canaccess, v)
        if ok then return r end
    end
    return true
end

EllesmereUITooltipHealthDB = EllesmereUITooltipHealthDB or {}
local db = EllesmereUITooltipHealthDB

local function EnsureDefaults()
    if db.enabled == nil then db.enabled = true end
    if db.showLabel == nil then db.showLabel = false end
    if db.showPercent == nil then db.showPercent = false end
    if db.liveUpdate == nil then db.liveUpdate = true end
    if db.colorByPct == nil then db.colorByPct = true end
    if db.debug == nil then db.debug = false end
end
EnsureDefaults()

local function Log(msg)
    if not db.debug then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff0cd29f[EUI TH]|r " .. tostring(msg))
end

local LABEL = "Health:"
local loc = GetLocale and GetLocale()
if loc == "zhCN" or loc == "zhTW" then LABEL = "生命值:" end

local function fmt(n)
    if isSecret(n) then
        if _G.AbbreviateNumbers then
            local ok, s = pcall(_G.AbbreviateNumbers, n)
            if ok and type(s) == "string" then
                local num = tonumber(s)
                if num and _G.BreakUpLargeNumbers then
                    local okb, b = pcall(_G.BreakUpLargeNumbers, num)
                    if okb and type(b) == "string" then return b end
                end
                Log(string.format("fmt secret: abbrev ok=%s type=%s secret=%s tonumber=%s",
                    tostring(ok), type(s), tostring(isSecret(s)), tostring(type(num))))
                return s
            end
        end
        if _G.BreakUpLargeNumbers then
            local ok, b = pcall(_G.BreakUpLargeNumbers, n)
            if ok and type(b) == "string" then return b end
        end
        local okf, f = pcall(string.format, "%d", n)
        if okf and type(f) == "string" then return f end
        return "??"
    end
    if _G.AbbreviateNumbers then
        local ok, s = pcall(_G.AbbreviateNumbers, n)
        if ok and type(s) == "string" then return s end
    end
    if _G.BreakUpLargeNumbers then
        local ok, s = pcall(_G.BreakUpLargeNumbers, n)
        if ok and type(s) == "string" then return s end
    end
    local s = tostring(math.floor((n or 0) + 0.5))
    return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function ApplyFont(tt, left, right)
    if not (EllesmereUI and EllesmereUI.GetFontPath) then return end
    local ok, fp = pcall(EllesmereUI.GetFontPath, "blizzardSkin")
    if not ok or type(fp) ~= "string" then return end
    local scale = (EllesmereUIDB and EllesmereUIDB.tooltipFontScale) or 1
    local size = math.floor(11 * (scale or 1) + 0.5)
    local ol = ""
    if EllesmereUI.GetFontOutlineFlag then
        local ok2, o = pcall(EllesmereUI.GetFontOutlineFlag, "blizzardSkin")
        if ok2 and type(o) == "string" then ol = o end
    end
    pcall(left.SetFont, left, fp, size, ol)
    if right then pcall(right.SetFont, right, fp, size, ol) end
end

local function ColorForPct(pct)
    if not db.colorByPct then return 1, 1, 1 end
    if pct > 60 then
        return 0.2, 1, 0.2
    elseif pct > 30 then
        return 1, 0.82, 0.2
    end
    return 1, 0.2, 0.2
end

local function RenderLine(ft, hpStr, maxStr, pctStr)
    if not ft then return end
    if db.showPercent then
        ft:SetFormattedText("%s / %s (%s%%)", hpStr, maxStr, pctStr or "??")
    else
        ft:SetFormattedText("%s / %s", hpStr, maxStr)
    end
end

local function AddOrUpdate(tt, guid, token)
    if not token then
        Log("AddOrUpdate: no token")
        return "no-token"
    end
    if not UnitExists(token) then
        Log("AddOrUpdate: unit not exists: " .. tostring(token))
        return "no-unit"
    end
    local hp, max = UnitHealth(token), UnitHealthMax(token)
    local hpSec, maxSec = isSecret(hp), isSecret(max)

    local pctNum, pctStr
    if hpSec or maxSec then
        Log("AddOrUpdate: hp/max secret -> SetText render path")
        if _G.UnitHealthPercent then
            local okp, p = pcall(UnitHealthPercent, token, true)
            if okp and p ~= nil then
                if isSecret(p) then
                    local oks, ps = pcall(string.format, "%d", p)
                    if oks and type(ps) == "string" then
                        pctStr = ps
                    end
                elseif type(p) == "number" then
                    pctNum = math.floor(p + 0.5)
                    pctStr = tostring(pctNum)
                end
            end
        end
    else
        hp, max = hp or 0, max or 0
        if max <= 0 then
            Log("AddOrUpdate: max<=0 (" .. tostring(max) .. ")")
            return "max-zero"
        end
        if hp < 0 then return "neg-hp" end
        if hp > max then hp = max end
        pctNum = math.floor((hp / max) * 100 + 0.5)
        pctStr = tostring(pctNum)
    end

    local hpStr, maxStr = fmt(hp), fmt(max)
    local label = db.showLabel and LABEL or nil
    local r, g, b
    if pctNum then
        r, g, b = ColorForPct(pctNum)
    else
        r, g, b = 1, 1, 1
    end

    local row = state[tt]
    if row and row.lastLabel ~= (label or false) then
        if row.left then pcall(row.left.SetText, row.left, "") end
        if row.right then pcall(row.right.SetText, row.right, "") end
        row = nil
    end

    local target = (label and row and row.right) or (not label and row and row.left)
    if target then
        RenderLine(target, hpStr, maxStr, pctStr)
        target:SetTextColor(r, g, b)
        row.guid, row.token = guid, token
        return "updated"
    end

    if label then
        tt:AddDoubleLine(label, " ", 1, 1, 1, 1, 1, 1)
    else
        tt:AddLine(" ")
    end

    local n2 = tt.NumLines and tt:NumLines() or 0
    local newLeft = _G["GameTooltipTextLeft" .. n2]
    local newRight = _G["GameTooltipTextRight" .. n2]
    local addTarget = (label and newRight) or newLeft
    if addTarget then
        RenderLine(addTarget, hpStr, maxStr, pctStr)
        addTarget:SetTextColor(r, g, b)
    end
    ApplyFont(tt, newLeft, newRight)
    state[tt] = { guid = guid, token = token, lastLabel = label or false, left = newLeft, right = newRight }
    return "added"
end

local function GroupTokenForGUID(guid)
    if not guid then return nil end
    local pg = UnitGUID("player")
    if pg and not isSecret(pg) and pg == guid then return "player" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local tk = "raid" .. i
            local tg = UnitGUID(tk)
            if tg and not isSecret(tg) and tg == guid then return tk end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local tk = "party" .. i
            local tg = UnitGUID(tk)
            if tg and not isSecret(tg) and tg == guid then return tk end
        end
    end
    return nil
end

local function ResolveUnit(tt, data)
    local guid
    if data and CanAccess(data) then
        local g = data.guid
        if g and CanAccess(g) then guid = g end
    end
    if not guid and data and CanAccess(data) then
        local hg = data.healthGUID
        if hg and CanAccess(hg) then guid = hg end
    end

    local token
    if data and data.lines and CanAccess(data.lines) then
        for _, line in ipairs(data.lines) do
            local u = line.unitToken
            if u and CanAccess(u) and UnitExists(u) then
                token = u
                break
            end
        end
    end

    if not token then
        local ok, name, unit, g = pcall(tt.GetUnit, tt)
        if ok and unit and CanAccess(unit) and UnitExists(unit) then
            if not guid and g and CanAccess(g) then guid = g end
            token = unit
        end
    end

    if guid and not token and _G.UnitTokenFromGUID then
        local tu = _G.UnitTokenFromGUID(guid)
        if tu and CanAccess(tu) and UnitExists(tu) then token = tu end
    end

    if guid and not token and UnitExists("mouseover") then
        local mg = UnitGUID("mouseover")
        if mg and CanAccess(mg) and mg == guid then token = "mouseover" end
    end

    if guid and not token then
        token = GroupTokenForGUID(guid)
    end

    if not token and UnitExists("mouseover") then
        token = "mouseover"
    end

    if token and not guid then
        local g = UnitGUID(token)
        if g and CanAccess(g) then guid = g end
    end

    return guid, token
end

local function Handler(tt, data, source)
    local ok, err = pcall(function()
        if not db.enabled then return end
        if tt ~= GameTooltip then
            Log("skip: not GameTooltip (" .. tostring(tt and tt.GetName and tt:GetName() or "?") .. ")")
            return
        end
        if tt:IsForbidden() then
            Log("skip: tooltip forbidden")
            return
        end
        local guid, token = ResolveUnit(tt, data)
        Log(string.format("resolve [%s] type=%s guid=%s token=%s",
            source or "?", tostring(data and data.type), tostring(guid), tostring(token)))
        if not token then return end
        local status = AddOrUpdate(tt, guid, token)
        Log("AddOrUpdate: " .. tostring(status))
    end)
    if not ok then
        Log("ERROR: " .. tostring(err))
    end
end

local function Install()
    local ok, err = pcall(function()
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
            and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
                Handler(tt, data, "postcall")
            end)
            Log("installed TooltipDataProcessor post-call")
        else
            Log("TooltipDataProcessor unavailable")
        end
    end)
    if not ok then
        Log("Install ERROR: " .. tostring(err))
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("UNIT_MAXHEALTH")
ev:SetScript("OnEvent", function(self, event, unitToken)
    if not db.liveUpdate or not db.enabled then return end
    if not GameTooltip or not GameTooltip:IsShown() then return end
    if not unitToken or isSecret(unitToken) then return end
    local row = state[GameTooltip]
    if not row or not row.token then return end
    local matches = unitToken == row.token
    if not matches and row.guid then
        local ug = UnitGUID(unitToken)
        if ug and not isSecret(ug) and ug == row.guid then matches = true end
    end
    if not matches then return end
    pcall(AddOrUpdate, GameTooltip, row.guid, row.token)
end)

if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnHide", function(self)
        state[self] = nil
    end)
    GameTooltip:HookScript("OnTooltipCleared", function(self)
        state[self] = nil
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == ADDON then
            EnsureDefaults()
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        Install()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff0cd29f[EUI Tooltip Health]|r " .. msg)
end

local function PrintStatus()
    Print("血量显示: |cff00ff00" .. (db.enabled and "开" or "关") .. "|r | " ..
        "百分比: |cff00ff00" .. (db.showPercent and "开" or "关") .. "|r | " ..
        "标签: |cff00ff00" .. (db.showLabel and "开" or "关") .. "|r | " ..
        "实时刷新: |cff00ff00" .. (db.liveUpdate and "开" or "关") .. "|r | " ..
        "血量着色: |cff00ff00" .. (db.colorByPct and "开" or "关") .. "|r | " ..
        "调试: |cff00ff00" .. (db.debug and "开" or "关") .. "|r")
    Print("用法: /euhp [on|off] / percent [on|off] / label [on|off] / live [on|off] / color [on|off] / debug [on|off] / reset / help")
end

local function ParseBool(s)
    s = (s or ""):lower()
    if s == "" or s == "on" or s == "true" or s == "1" or s == "yes" then return true end
    if s == "off" or s == "false" or s == "0" or s == "no" then return false end
    return nil
end

local function RefreshShown()
    if GameTooltip and GameTooltip:IsShown() then
        local guid, token = ResolveUnit(GameTooltip, {})
        if token then AddOrUpdate(GameTooltip, guid, token) end
    end
end

local function Trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

SlashCmdList["ELLESMEREUITOOLTIPHEALTH"] = function(msg)
    msg = Trim(msg):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "help" then
        PrintStatus()
        return
    end
    if cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        Print("血量显示: " .. (db.enabled and "开" or "关"))
        RefreshShown()
        return
    end
    if cmd == "percent" or cmd == "pct" then
        local v = ParseBool(arg)
        if v == nil then Print("用法: /euhp percent on|off") return end
        db.showPercent = v
        Print("百分比: " .. (db.showPercent and "开" or "关"))
        RefreshShown()
        return
    end
    if cmd == "label" then
        local v = ParseBool(arg)
        if v == nil then Print("用法: /euhp label on|off") return end
        db.showLabel = v
        Print("标签: " .. (db.showLabel and "开" or "关"))
        RefreshShown()
        return
    end
    if cmd == "live" then
        local v = ParseBool(arg)
        if v == nil then Print("用法: /euhp live on|off") return end
        db.liveUpdate = v
        Print("实时刷新: " .. (db.liveUpdate and "开" or "关"))
        return
    end
    if cmd == "color" then
        local v = ParseBool(arg)
        if v == nil then Print("用法: /euhp color on|off") return end
        db.colorByPct = v
        Print("血量着色: " .. (db.colorByPct and "开" or "关"))
        RefreshShown()
        return
    end
    if cmd == "debug" then
        local v = ParseBool(arg)
        if v == nil then Print("用法: /euhp debug on|off") return end
        db.debug = v
        Print("调试模式: " .. (db.debug and "开" or "关"))
        return
    end
    if cmd == "reset" then
        db.enabled = true
        db.showLabel = false
        db.showPercent = false
        db.liveUpdate = true
        db.colorByPct = true
        db.debug = false
        Print("已恢复默认设置")
        RefreshShown()
        return
    end
    PrintStatus()
end
SLASH_ELLESMEREUITOOLTIPHEALTH1 = "/euhp"
SLASH_ELLESMEREUITOOLTIPHEALTH2 = "/ellhp"