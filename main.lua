-- ============================================
-- VARIABLES & CONFIG
-- ============================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Script state
local isRunning = false
local stats = {
    totalAttempts = 0,
    totalSuccesses = 0,
    totalFailures = 0,
    currentUpgrade = "None",
    lastPayload = "None",
    failureCount = 0
}

-- CONFIG
local CONFIG = {
    RemotePath = "ReplicatedStorage.Network.EventUpgrades.Purchase",
    UpgradeIDs = {
        "TapHeroesEggUpgrade",
        "TapHeroesClickDamage", 
        "TapHeroesPetDamage",
        "TapHeroesCoinBonus"
    },
    MinInterval = 30,
    MaxInterval = 60,
    MimicHumanTyping = true,
    RandomizeOrder = true,
    MaxFailures = 10,
    WebhookURL = "YOUR_DISCORD_WEBHOOK_HERE"
}

-- Forward declaration for UI update function
local UIUpdateStats

-- ============================================
-- RESOLVE REMOTE EVENT
-- ============================================

local RemoteEvent = nil

local function getRemoteEvent()
    if RemoteEvent then return RemoteEvent end
    
    local pathParts = {}
    for part in string.gmatch(CONFIG.RemotePath, "[^%.]+") do
        table.insert(pathParts, part)
    end
    
    local current = game
    for i, part in ipairs(pathParts) do
        if i == 1 and part == "ReplicatedStorage" then
            current = ReplicatedStorage
        else
            current = current and current:FindFirstChild(part)
            if not current then
                return nil
            end
        end
    end
    
    if current and current:IsA("RemoteEvent") then
        RemoteEvent = current
        return current
    end
    return nil
end

-- ============================================
-- WEBHOOK FUNCTION (Delta / Executor Compatible)
-- ============================================

local function sendWebhook(title, description, color, fields)
    if not CONFIG.WebhookURL or CONFIG.WebhookURL == "" or string.find(CONFIG.WebhookURL, "YOUR_") then return end
    
    local embed = {
        title = title or "🔄 Upgrade Update",
        description = description or "No details provided.",
        color = color or 0x00FF00,
        timestamp = os.date("!%Y-%m-%dT%T.000Z"),
        footer = {
            text = "Tap Heroes Assistant"
        },
        fields = fields or {}
    }
    
    local payload = {
        content = "**🔥 TAP HEROES UPGRADE ACTIVITY**",
        embeds = { embed },
        username = "Tap Heroes Manager"
    }
    
    local success, err = pcall(function()
        local reqFunc = syn and syn.request or request
        if reqFunc then
            reqFunc({
                Url = CONFIG.WebhookURL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = HttpService:JSONEncode(payload)
            })
        end
    end)
    
    if not success then
        -- Silent fail to avoid spamming the console
    end
end

-- ============================================
-- PAYLOAD GENERATORS
-- ============================================

local payloadIndex = 1
local PayloadFormats = {
    function(upgradeID) 
        return { upgradeID, LocalPlayer.UserId }
    end,
    function(upgradeID)
        return {
            UpgradeId = upgradeID,
            PlayerId = LocalPlayer.UserId,
            Amount = 999999,
            Timestamp = os.time()
        }
    end,
    function(upgradeID)
        return upgradeID
    end,
    function(upgradeID)
        return {
            Purchase = {
                Type = upgradeID,
                Quantity = 100,
                Cost = 0
            }
        }
    end
}

local function generatePayload(upgradeID)
    local formatFunc = PayloadFormats[payloadIndex]
    if not formatFunc then
        payloadIndex = 1
        formatFunc = PayloadFormats[payloadIndex]
    end
    
    payloadIndex = payloadIndex + 1
    if payloadIndex > #PayloadFormats then
        payloadIndex = 1
    end
    
    return formatFunc(upgradeID)
end

-- ============================================
-- CORE FUNCTION
-- ============================================

local function firePurchase(upgradeID)
    if not RemoteEvent then
        RemoteEvent = getRemoteEvent()
        if not RemoteEvent then return false end
    end
    
    stats.currentUpgrade = upgradeID
    local payload = generatePayload(upgradeID)
    
    local success, json = pcall(HttpService.JSONEncode, HttpService, payload)
    stats.lastPayload = success and json or tostring(payload)
    
    if CONFIG.MimicHumanTyping then
        task.wait(math.random(50, 300) / 1000)
    end
    
    local success2, err = pcall(function()
        RemoteEvent:FireServer(payload)
    end)
    
    stats.totalAttempts = stats.totalAttempts + 1
    
    if success2 then
        stats.totalSuccesses = stats.totalSuccesses + 1
        stats.failureCount = 0
        
        if UIUpdateStats then UIUpdateStats() end
        
        if stats.totalSuccesses % 5 == 0 then
            sendWebhook(
                "✅ UPGRADE SUCCESSFUL",
                "**" .. upgradeID .. "** processed successfully",
                0x00FF00,
                {
                    { name = "🎯 Upgrade", value = upgradeID, inline = true },
                    { name = "📊 Attempts", value = tostring(stats.totalAttempts), inline = true },
                    { name = "✅ Successes", value = tostring(stats.totalSuccesses), inline = true },
                    { name = "📈 Rate", value = string.format("%.1f%%", (stats.totalSuccesses/stats.totalAttempts)*100), inline = true }
                }
            )
        end
        
        return true
    else
        stats.totalFailures = stats.totalFailures + 1
        stats.failureCount = stats.failureCount + 1
        
        if UIUpdateStats then UIUpdateStats() end
        
        return false
    end
end

-- ============================================
-- MAIN LOOP
-- ============================================

local function spamLoop()
    if not RemoteEvent then
        RemoteEvent = getRemoteEvent()
        if not RemoteEvent then
            warn("[ERROR] RemoteEvent not found!")
            return
        end
    end
    
    sendWebhook(
        "🔥 MODULE STARTED",
        "Sequence is now **LIVE**",
        0x9B59B6,
        {
            { name = "🎯 Upgrades", value = table.concat(CONFIG.UpgradeIDs, ", "), inline = false },
            { name = "👤 Player", value = LocalPlayer.Name, inline = true },
            { name = "⏱️ Interval", value = CONFIG.MinInterval .. "-" .. CONFIG.MaxInterval .. "s", inline = true }
        }
    )
    
    while isRunning do
        -- Create a shallow copy to prevent permanently scrambling the config order
        local upgradeList = {}
        for i, v in ipairs(CONFIG.UpgradeIDs) do
            upgradeList[i] = v
        end

        if CONFIG.RandomizeOrder then
            for i = #upgradeList, 2, -1 do
                local j = math.random(1, i)
                upgradeList[i], upgradeList[j] = upgradeList[j], upgradeList[i]
            end
        end
        
        for _, upgradeID in ipairs(upgradeList) do
            if not isRunning then break end
            
            firePurchase(upgradeID)
            
            if #upgradeList > 1 then
                task.wait(math.random(1, 3))
            end
            
            if stats.failureCount >= CONFIG.MaxFailures then
                warn("[PAUSING] Too many consecutive failures. Waiting 60s...")
                local pauseEnd = os.time() + 60
                while isRunning and os.time() < pauseEnd do
                    task.wait(1)
                end
                stats.failureCount = 0
            end
        end
        
        if UIUpdateStats then UIUpdateStats() end
        
        local interval = math.random(CONFIG.MinInterval * 10, CONFIG.MaxInterval * 10) / 10
        local waitStart = os.time()
        while isRunning and os.time() - waitStart < interval do
            task.wait(0.5)
        end
    end
end

-- ============================================
-- CREATE UI (Pure Lua)
-- ============================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TapHeroesSpammer"
screenGui.ResetOnSpawn = false
screenGui.Parent = PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 450, 0, 600)
mainFrame.Position = UDim2.new(0.5, -225, 0.5, -300)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
mainFrame.BackgroundTransparency = 0.1
mainFrame.BorderSizePixel = 2
mainFrame.BorderColor3 = Color3.fromRGB(100, 50, 200)
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 40)
title.Position = UDim2.new(0, 0, 0, 0)
title.BackgroundColor3 = Color3.fromRGB(100, 50, 200)
title.BackgroundTransparency = 0.3
title.Text = "🔥 TAP HEROES UTILITY v4.0"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = mainFrame

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -35, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextScaled = true
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = mainFrame
closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
    if isRunning then
        isRunning = false
    end
end)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 30)
statusLabel.Position = UDim2.new(0, 10, 0, 50)
statusLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
statusLabel.BackgroundTransparency = 0.5
statusLabel.Text = "🔴 Status: STOPPED"
statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Parent = mainFrame

local statsLabel = Instance.new("TextLabel")
statsLabel.Size = UDim2.new(1, -20, 0, 60)
statsLabel.Position = UDim2.new(0, 10, 0, 85)
statsLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
statsLabel.BackgroundTransparency = 0.5
statsLabel.Text = "📈 Attempts: 0\n✅ Success: 0 | ❌ Failed: 0"
statsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statsLabel.TextScaled = true
statsLabel.Font = Enum.Font.Gotham
statsLabel.Parent = mainFrame

local rateLabel = Instance.new("TextLabel")
rateLabel.Size = UDim2.new(1, -20, 0, 30)
rateLabel.Position = UDim2.new(0, 10, 0, 150)
rateLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
rateLabel.BackgroundTransparency = 0.5
rateLabel.Text = "📊 Success Rate: 0%"
rateLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
rateLabel.TextScaled = true
rateLabel.Font = Enum.Font.Gotham
rateLabel.Parent = mainFrame

local currentLabel = Instance.new("TextLabel")
currentLabel.Size = UDim2.new(1, -20, 0, 30)
currentLabel.Position = UDim2.new(0, 10, 0, 185)
currentLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
currentLabel.BackgroundTransparency = 0.5
currentLabel.Text = "🎯 Current: None"
currentLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
currentLabel.TextScaled = true
currentLabel.Font = Enum.Font.Gotham
currentLabel.Parent = mainFrame

local payloadLabel = Instance.new("TextLabel")
payloadLabel.Size = UDim2.new(1, -20, 0, 30)
payloadLabel.Position = UDim2.new(0, 10, 0, 220)
payloadLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
payloadLabel.BackgroundTransparency = 0.5
payloadLabel.Text = "📦 Last Payload: None"
payloadLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
payloadLabel.TextScaled = true
payloadLabel.Font = Enum.Font.Gotham
payloadLabel.Parent = mainFrame

local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.new(0.45, -10, 0, 40)
startBtn.Position = UDim2.new(0.025, 0, 0, 270)
startBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
startBtn.Text = "🚀 START LOOP"
startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
startBtn.TextScaled = true
startBtn.Font = Enum.Font.GothamBold
startBtn.Parent = mainFrame

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(0.45, -10, 0, 40)
resetBtn.Position = UDim2.new(0.525, 0, 0, 270)
resetBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 0)
resetBtn.Text = "🔄 RESET STATS"
resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
resetBtn.TextScaled = true
resetBtn.Font = Enum.Font.GothamBold
resetBtn.Parent = mainFrame

local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(1, -20, 0, 220)
settingsFrame.Position = UDim2.new(0, 10, 0, 320)
settingsFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
settingsFrame.BackgroundTransparency = 0.3
settingsFrame.BorderSizePixel = 1
settingsFrame.BorderColor3 = Color3.fromRGB(100, 50, 200)
settingsFrame.Parent = mainFrame

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, 0, 0, 25)
settingsTitle.Position = UDim2.new(0, 0, 0, 0)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "⚙️ SETTINGS"
settingsTitle.TextColor3 = Color3.fromRGB(150, 100, 255)
settingsTitle.TextScaled = true
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.Parent = settingsFrame

local minLabel = Instance.new("TextLabel")
minLabel.Size = UDim2.new(0.4, 0, 0, 25)
minLabel.Position = UDim2.new(0, 0, 0, 30)
minLabel.BackgroundTransparency = 1
minLabel.Text = "Min Interval: 30s"
minLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
minLabel.TextScaled = true
minLabel.Font = Enum.Font.Gotham
minLabel.Parent = settingsFrame

local minSlider = Instance.new("TextBox")
minSlider.Size = UDim2.new(0.5, 0, 0, 25)
minSlider.Position = UDim2.new(0.45, 0, 0, 30)
minSlider.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
minSlider.Text = "30"
minSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
minSlider.TextScaled = true
minSlider.Font = Enum.Font.Gotham
minSlider.Parent = settingsFrame
minSlider.FocusLost:Connect(function()
    local val = tonumber(minSlider.Text)
    if val and val >= 5 and val <= 120 then
        CONFIG.MinInterval = math.floor(val)
        minLabel.Text = "Min Interval: " .. CONFIG.MinInterval .. "s"
    else
        minSlider.Text = tostring(CONFIG.MinInterval)
    end
end)

local maxLabel = Instance.new("TextLabel")
maxLabel.Size = UDim2.new(0.4, 0, 0, 25)
maxLabel.Position = UDim2.new(0, 0, 0, 60)
maxLabel.BackgroundTransparency = 1
maxLabel.Text = "Max Interval: 60s"
maxLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
maxLabel.TextScaled = true
maxLabel.Font = Enum.Font.Gotham
maxLabel.Parent = settingsFrame

local maxSlider = Instance.new("TextBox")
maxSlider.Size = UDim2.new(0.5, 0, 0, 25)
maxSlider.Position = UDim2.new(0.45, 0, 0, 60)
maxSlider.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
maxSlider.Text = "60"
maxSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
maxSlider.TextScaled = true
maxSlider.Font = Enum.Font.Gotham
maxSlider.Parent = settingsFrame
maxSlider.FocusLost:Connect(function()
    local val = tonumber(maxSlider.Text)
    if val and val >= 5 and val <= 120 then
        CONFIG.MaxInterval = math.floor(val)
        maxLabel.Text = "Max Interval: " .. CONFIG.MaxInterval .. "s"
    else
        maxSlider.Text = tostring(CONFIG.MaxInterval)
    end
end)

local humanToggle = Instance.new("TextButton")
humanToggle.Size = UDim2.new(0.45, 0, 0, 30)
humanToggle.Position = UDim2.new(0, 0, 0, 95)
humanToggle.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
humanToggle.Text = "✅ Mimic Typing: ON"
humanToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
humanToggle.TextScaled = true
humanToggle.Font = Enum.Font.Gotham
humanToggle.Parent = settingsFrame
humanToggle.MouseButton1Click:Connect(function()
    CONFIG.MimicHumanTyping = not CONFIG.MimicHumanTyping
    humanToggle.Text = CONFIG.MimicHumanTyping and "✅ Mimic Typing: ON" or "❌ Mimic Typing: OFF"
    humanToggle.BackgroundColor3 = CONFIG.MimicHumanTyping and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(200, 0, 0)
end)

local randomToggle = Instance.new("TextButton")
randomToggle.Size = UDim2.new(0.45, 0, 0, 30)
randomToggle.Position = UDim2.new(0.52, 0, 0, 95)
randomToggle.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
randomToggle.Text = "✅ Random Order: ON"
randomToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
randomToggle.TextScaled = true
randomToggle.Font = Enum.Font.Gotham
randomToggle.Parent = settingsFrame
randomToggle.MouseButton1Click:Connect(function()
    CONFIG.RandomizeOrder = not CONFIG.RandomizeOrder
    randomToggle.Text = CONFIG.RandomizeOrder and "✅ Random Order: ON" or "❌ Random Order: OFF"
    randomToggle.BackgroundColor3 = CONFIG.RandomizeOrder and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(200, 0, 0)
end)

local webhookLabel = Instance.new("TextLabel")
webhookLabel.Size = UDim2.new(0.3, 0, 0, 25)
webhookLabel.Position = UDim2.new(0, 0, 0, 135)
webhookLabel.BackgroundTransparency = 1
webhookLabel.Text = "Webhook:"
webhookLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
webhookLabel.TextScaled = true
webhookLabel.Font = Enum.Font.Gotham
webhookLabel.Parent = settingsFrame

local webhookInput = Instance.new("TextBox")
webhookInput.Size = UDim2.new(0.65, 0, 0, 25)
webhookInput.Position = UDim2.new(0.32, 0, 0, 135)
webhookInput.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
webhookInput.Text = CONFIG.WebhookURL
webhookInput.TextColor3 = Color3.fromRGB(200, 200, 200)
webhookInput.TextScaled = true
webhookInput.Font = Enum.Font.Gotham
webhookInput.Parent = settingsFrame
webhookInput.FocusLost:Connect(function()
    CONFIG.WebhookURL = webhookInput.Text
end)

local upgradeLabel = Instance.new("TextLabel")
upgradeLabel.Size = UDim2.new(1, 0, 0, 50)
upgradeLabel.Position = UDim2.new(0, 0, 0, 170)
upgradeLabel.BackgroundTransparency = 1
upgradeLabel.Text = "🎯 " .. table.concat(CONFIG.UpgradeIDs, " | ")
upgradeLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
upgradeLabel.TextScaled = true
upgradeLabel.Font = Enum.Font.Gotham
upgradeLabel.Parent = settingsFrame

-- ============================================
-- UI UPDATE FUNCTION
-- ============================================

function UIUpdateStats()
    local rate = stats.totalAttempts > 0 and (stats.totalSuccesses/stats.totalAttempts)*100 or 0
    statsLabel.Text = string.format("📈 Attempts: %d\n✅ Success: %d | ❌ Failed: %d", 
        stats.totalAttempts, stats.totalSuccesses, stats.totalFailures)
    rateLabel.Text = string.format("📊 Success Rate: %.1f%%", rate)
    currentLabel.Text = "🎯 Current: " .. stats.currentUpgrade
    payloadLabel.Text = "📦 Last Payload: " .. string.sub(stats.lastPayload, 1, 50) .. (string.len(stats.lastPayload) > 50 and "..." or "")
end

-- ============================================
-- BUTTON FUNCTIONS
-- ============================================

startBtn.MouseButton1Click:Connect(function()
    if isRunning then
        isRunning = false
        statusLabel.Text = "🔴 Status: STOPPED"
        statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        startBtn.Text = "🚀 START LOOP"
        startBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
        sendWebhook("⏹️ LOOP STOPPED", "Manual stop by user", 0xFFA500, {})
        return
    end
    
    local remote = getRemoteEvent()
    if not remote then
        warn("[ERROR] RemoteEvent not found!")
        statusLabel.Text = "🔴 ERROR: Remote Not Found"
        statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
        return
    end
    
    isRunning = true
    statusLabel.Text = "🟢 Status: RUNNING"
    statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    startBtn.Text = "⏹️ STOP LOOP"
    startBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    
    sendWebhook("🚀 LOOP STARTED", "User initiated loop", 0x00FF00, {})
    
    task.spawn(function()
        local ok, err = pcall(spamLoop)
        if not ok then
            warn("[CRITICAL] Loop crashed: " .. tostring(err))
            isRunning = false
            statusLabel.Text = "🔴 Status: CRASHED"
            statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
            startBtn.Text = "🚀 START LOOP"
            startBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
            sendWebhook("💀 CRASH", "Loop crashed: " .. tostring(err), 0xFF0000, {})
        end
    end)
end)

resetBtn.MouseButton1Click:Connect(function()
    stats.totalAttempts = 0
    stats.totalSuccesses = 0
    stats.totalFailures = 0
    stats.failureCount = 0
    stats.currentUpgrade = "None"
    stats.lastPayload = "None"
    UIUpdateStats()
    sendWebhook("🔄 STATS RESET", "Statistics have been reset", 0x3498DB, {})
end)

-- ============================================
-- KEYBIND
-- ============================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        screenGui.Enabled = not screenGui.Enabled
    end
end)

-- ============================================
-- INITIALIZATION
-- ============================================

print("==========================================")
print("🔥 TAP HEROES UTILITY v4.0")
print("💻 PURE LUA UI - NO LIBRARIES")
print("📡 UI Loaded Successfully")
print("🎯 Press Right Shift to toggle UI")
print("==========================================")

local remote = getRemoteEvent()
if remote then
    print("[SUCCESS] RemoteEvent found: " .. remote:GetFullName())
else
    warn("[WARNING] RemoteEvent not found. Will retry on start.")
end

UIUpdateStats()

sendWebhook(
    "🖥️ UI LOADED",
    "Interface is ready",
    0x9B59B6,
    {
        { name = "🎯 Upgrades", value = table.concat(CONFIG.UpgradeIDs, ", "), inline = false },
        { name = "👤 Player", value = LocalPlayer.Name, inline = true },
        { name = "⏱️ Interval", value = CONFIG.MinInterval .. "-" .. CONFIG.MaxInterval .. "s", inline = true }
    }
)

print("[OK] UI Loaded. Press Right Shift to toggle visibility.")

```
