local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ==================== GUI SETUP ====================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "STK VIP | BY PUTZZDEV",
    Icon = 0,
    LoadingTitle = "Survive The Killer",
    LoadingSubtitle = "VIP Ultimate Script",
    Theme = "Dark",
})

-- ==================== VARIABEL ====================
local highlights = {}
local espItems = {}
local espLines = {}
local noclipConn = nil
local flyConn = nil
local flyBodyVel = nil
local antiDamageEnabled = false
local antiDamageHeartbeat = nil
local antiStunEnabled = false
local antiStunConnections = {}
local autoLootEnabled = false
local autoLootThread = nil
local currentTarget = nil

-- FITUR BARU
local autoExitEnabled = false
local autoExitThread = nil
local autoEscapeEnabled = false
local autoEscapeThread = nil
local escapeDistance = 20 -- jarak aman, jika killer kurang dari ini akan teleport

-- Killer detection
local killerKeywords = {
    ["killer"] = true, ["slasher"] = true, ["stalker"] = true,
    ["jason"] = true, ["michael"] = true, ["ghost"] = true,
    ["werewolf"] = true, ["demon"] = true
}

-- ==================== UTILITY FUNCTIONS ====================
local function createHighlight(target, color)
    if not target or not target.Parent then return nil end
    local h = target:FindFirstChildOfClass("Highlight")
    if h then
        h.FillColor = color
        return h
    end
    h = Instance.new("Highlight")
    h.FillColor = color
    h.OutlineColor = Color3.fromRGB(255,255,255)
    h.Parent = target
    return h
end

local function clearHighlights()
    for _, v in pairs(highlights) do
        if v and v.Parent then v:Destroy() end
    end
    highlights = {}
    for _, v in pairs(espItems) do
        if v and v.Parent then v:Destroy() end
    end
    espItems = {}
end

local function safeTeleportTo(part)
    local char = player.Character
    if not char or not part then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
end

local function getKiller()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl == player then continue end
        local nameLower = string.lower(pl.Name .. pl.DisplayName)
        for _, kw in pairs(killerKeywords) do
            if nameLower:find(kw) then
                return pl
            end
        end
    end
    return nil
end

local function getExitDoor()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local nameLower = string.lower(obj.Name or "")
        if nameLower:find("exit") or nameLower:find("door") or nameLower:find("gate") then
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                return part
            end
        end
    end
    return nil
end

-- ==================== AUTO EXIT ====================
local function checkExitDoorLoop()
    while autoExitEnabled do
        task.wait(1) -- cek tiap detik
        local door = getExitDoor()
        if door then
            -- cek apakah pintu sudah terbuka atau bisa diinteraksi (biasanya ada ProximityPrompt)
            local prompt = door.Parent and door.Parent:FindFirstChildWhichIsA("ProximityPrompt")
            if not prompt then prompt = door:FindFirstChildWhichIsA("ProximityPrompt") end
            if prompt then
                -- pintu sudah ada prompt (biasanya muncul setelah timer 4 menit)
                safeTeleportTo(door)
                Rayfield:Notify({Title = "VIP", Content = "Auto Exit: Teleported to exit!", Duration = 2})
                task.wait(2)
                -- coba interaksi dengan pintu
                pcall(function() prompt:InputHoldBegin() end)
            end
        end
    end
end

-- ==================== AUTO ESCAPE FROM KILLER ====================
local function escapeFromKiller()
    local killer = getKiller()
    if not killer or not killer.Character then return end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local killerHrp = killer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or not killerHrp then return end
    
    local distance = (hrp.Position - killerHrp.Position).Magnitude
    if distance < escapeDistance then
        -- Cari posisi aman: menjauh dari killer
        local direction = (hrp.Position - killerHrp.Position).Unit
        local safePos = hrp.Position + direction * 40
        -- Pastikan tidak keluar map (batasi)
        safePos = Vector3.new(
            math.clamp(safePos.X, -200, 200),
            safePos.Y,
            math.clamp(safePos.Z, -200, 200)
        )
        hrp.CFrame = CFrame.new(safePos)
        Rayfield:Notify({Title = "VIP", Content = "Auto Escape: Teleported away from killer!", Duration = 1})
        task.wait(0.5)
    end
end

local function autoEscapeLoop()
    while autoEscapeEnabled do
        task.wait(0.2) -- cek cepat
        pcall(escapeFromKiller)
    end
end

-- ==================== ITEM DETECTION & LOOT ====================
local itemPriority = {
    ["goldcoin"] = 100,
    ["diamond"] = 95,
    ["ruby"] = 90,
    ["emerald"] = 85,
    ["coin"] = 70,
    ["key"] = 60,
    ["chest"] = 80,
    ["crate"] = 75,
    ["battery"] = 50,
    ["medkit"] = 40,
    ["flashlight"] = 30,
}

local function getItemValue(item)
    local nameLower = string.lower(item.Name or "")
    for keyword, value in pairs(itemPriority) do
        if nameLower:find(keyword) then
            return value
        end
    end
    return 10
end

local function collectItems()
    local items = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") or obj:IsA("Model") then
            local nameLower = string.lower(obj.Name or "")
            if nameLower:find("coin") or nameLower:find("key") or nameLower:find("chest") or nameLower:find("crate") or nameLower:find("gem") or nameLower:find("battery") or nameLower:find("medkit") or nameLower:find("flashlight") then
                local root = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")) or obj
                if root and root.Parent then
                    table.insert(items, {
                        part = root,
                        value = getItemValue(obj),
                        name = obj.Name
                    })
                end
            end
        end
    end
    table.sort(items, function(a,b) return a.value > b.value end)
    return items
end

local function teleportToItem(itemPart)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and itemPart then
        hrp.CFrame = itemPart.CFrame + Vector3.new(0, 3, 0)
    end
end

-- Auto Loot Loop
local function startAutoLoot()
    if autoLootThread then return end
    autoLootThread = task.spawn(function()
        while autoLootEnabled do
            task.wait(0.3)
            local char = player.Character
            if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            
            local items = collectItems()
            local bestItem = items[1]
            if not bestItem then
                currentTarget = nil
                task.wait(1)
                continue
            end
            
            currentTarget = bestItem.part
            local distance = (hrp.Position - bestItem.part.Position).Magnitude
            
            if distance > 8 then
                teleportToItem(bestItem.part)
                task.wait(0.2)
            else
                local prompt = bestItem.part.Parent and bestItem.part.Parent:FindFirstChildWhichIsA("ProximityPrompt")
                if not prompt then
                    prompt = bestItem.part:FindFirstChildWhichIsA("ProximityPrompt")
                end
                if prompt then
                    pcall(function() prompt:InputHoldBegin() end)
                else
                    local click = bestItem.part:FindFirstChildWhichIsA("ClickDetector")
                    if click then
                        pcall(function() click:Click() end)
                    end
                end
                task.wait(0.5)
            end
        end
        autoLootThread = nil
    end)
end

-- ==================== ESP ITEM ====================
local espItemEnabled = false
local function updateItemESP()
    while espItemEnabled do
        task.wait(0.2)
        for _, v in pairs(espItems) do
            if v and v.Parent then v:Destroy() end
        end
        espItems = {}
        local items = collectItems()
        for _, item in ipairs(items) do
            local color
            if item.value >= 90 then
                color = Color3.fromRGB(255,215,0)
            elseif item.value >= 70 then
                color = Color3.fromRGB(0,255,255)
            else
                color = Color3.fromRGB(255,255,255)
            end
            local h = createHighlight(item.part, color)
            if h then espItems[item.part] = h end
        end
    end
end

-- ==================== ESP PLAYER / KILLER ====================
local espKillerEnabled = false
local espSurvivorEnabled = false
local function updatePlayerESP()
    while espKillerEnabled or espSurvivorEnabled do
        task.wait(0.15)
        for _, v in pairs(highlights) do
            if v and v.Parent then v:Destroy() end
        end
        highlights = {}
        
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl == player or not pl.Character then continue end
            local isKiller = false
            local nameLower = string.lower(pl.Name .. pl.DisplayName)
            for _, kw in pairs(killerKeywords) do
                if nameLower:find(kw) then
                    isKiller = true
                    break
                end
            end
            if isKiller and espKillerEnabled then
                highlights[pl] = createHighlight(pl.Character, Color3.fromRGB(255,0,0))
            elseif not isKiller and espSurvivorEnabled then
                highlights[pl] = createHighlight(pl.Character, Color3.fromRGB(0,150,255))
            end
        end
    end
end

-- ==================== ANTI STUN & DAMAGE ====================
local function setupAntiStun()
    for _, conn in pairs(antiStunConnections) do pcall(function() conn:Disconnect() end) end
    antiStunConnections = {}
    
    local function onStateChanged(_, newState)
        if not antiStunEnabled then return end
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if newState == Enum.HumanoidStateType.PlatformStanding or
               newState == Enum.HumanoidStateType.Physics or
               newState == Enum.HumanoidStateType.Stunned or
               newState == Enum.HumanoidStateType.GettingUp or
               newState == Enum.HumanoidStateType.FallingDown then
                hum:ChangeState(Enum.HumanoidStateType.Running)
                hum.Sit = false
                hum.PlatformStand = false
            end
        end
    end
    
    local stateConn = nil
    local function attachState()
        if player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                if stateConn then stateConn:Disconnect() end
                stateConn = hum.StateChanged:Connect(onStateChanged)
                table.insert(antiStunConnections, stateConn)
            end
        end
    end
    attachState()
    player.CharacterAdded:Connect(attachState)
    
    local loopConn = RunService.Heartbeat:Connect(function()
        if not antiStunEnabled then return end
        pcall(function()
            local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                local state = hum:GetState()
                if state == Enum.HumanoidStateType.PlatformStanding or
                   state == Enum.HumanoidStateType.Physics or
                   state == Enum.HumanoidStateType.Stunned or
                   state == Enum.HumanoidStateType.GettingUp or
                   state == Enum.HumanoidStateType.FallingDown then
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                    hum.Sit = false
                    hum.PlatformStand = false
                end
                for _, joint in ipairs(player.Character:GetDescendants()) do
                    if joint:IsA("HingeConstraint") or joint:IsA("RodConstraint") or joint:IsA("RopeConstraint") then
                        joint:Destroy()
                    end
                end
            end
        end)
    end)
    table.insert(antiStunConnections, loopConn)
end

local function disableAntiStun()
    antiStunEnabled = false
    for _, conn in pairs(antiStunConnections) do pcall(function() conn:Disconnect() end) end
    antiStunConnections = {}
end

local function setupAntiDamage()
    if antiDamageHeartbeat then antiDamageHeartbeat:Disconnect() end
    antiDamageHeartbeat = RunService.Heartbeat:Connect(function()
        if not antiDamageEnabled then return end
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health < hum.MaxHealth then
            hum.Health = hum.MaxHealth
        end
    end)
end

local function disableAntiDamage()
    if antiDamageHeartbeat then antiDamageHeartbeat:Disconnect() end
    antiDamageHeartbeat = nil
end

-- ==================== MOVEMENT ====================
local function toggleNoclip(state)
    if state then
        if noclipConn then return end
        noclipConn = RunService.Stepped:Connect(function()
            if player.Character then
                for _, part in ipairs(player.Character:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end)
    else
        if noclipConn then noclipConn:Disconnect() end
        noclipConn = nil
    end
end

local flyEnabled = false
local function toggleFly(state)
    flyEnabled = state
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if flyEnabled then
        if not hrp or not hum then return end
        flyBodyVel = Instance.new("BodyVelocity")
        flyBodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        flyBodyVel.Velocity = Vector3.new(0,0,0)
        flyBodyVel.Parent = hrp
        hum.PlatformStand = true
        flyConn = RunService.RenderStepped:Connect(function()
            if not flyEnabled or not flyBodyVel.Parent then return end
            local moveDir = Vector3.new(0,0,0)
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                moveDir = moveDir + camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                moveDir = moveDir - camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                moveDir = moveDir - camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                moveDir = moveDir + camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                moveDir = moveDir + Vector3.new(0,1,0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                moveDir = moveDir - Vector3.new(0,1,0)
            end
            if moveDir.Magnitude > 0 then
                flyBodyVel.Velocity = moveDir.Unit * 70
            else
                flyBodyVel.Velocity = Vector3.new(0,0,0)
            end
        end)
    else
        if flyBodyVel then flyBodyVel:Destroy() end
        if flyConn then flyConn:Disconnect() end
        if hum then hum.PlatformStand = false end
        flyBodyVel = nil
        flyConn = nil
    end
end

-- ==================== GUI TABS ====================
-- Tab: AUTO LOOT
local LootTab = Window:CreateTab(" AUTO LOOT", nil)

LootTab:CreateToggle({
    Name = "Auto Loot (VIP)",
    CurrentValue = false,
    Callback = function(Value)
        autoLootEnabled = Value
        if Value then
            startAutoLoot()
        else
            if autoLootThread then
                task.cancel(autoLootThread)
                autoLootThread = nil
            end
            currentTarget = nil
        end
    end,
})

LootTab:CreateButton({
    Name = "Teleport to Best Item",
    Callback = function()
        local items = collectItems()
        if #items > 0 then
            teleportToItem(items[1].part)
            Rayfield:Notify({Title = "VIP", Content = "Teleported to " .. items[1].name, Duration = 2})
        else
            Rayfield:Notify({Title = "VIP", Content = "No items found!", Duration = 2})
        end
    end,
})

-- Tab: ESCAPE (BARU)
local EscapeTab = Window:CreateTab("ESCAPE", nil)

EscapeTab:CreateToggle({
    Name = "Auto Teleport to Exit (when opens)",
    CurrentValue = false,
    Callback = function(Value)
        autoExitEnabled = Value
        if Value then
            if autoExitThread then task.cancel(autoExitThread) end
            autoExitThread = task.spawn(checkExitDoorLoop)
        else
            if autoExitThread then task.cancel(autoExitThread) end
            autoExitThread = nil
        end
    end,
})

EscapeTab:CreateToggle({
    Name = "Auto Escape from Killer",
    CurrentValue = false,
    Callback = function(Value)
        autoEscapeEnabled = Value
        if Value then
            if autoEscapeThread then task.cancel(autoEscapeThread) end
            autoEscapeThread = task.spawn(autoEscapeLoop)
        else
            if autoEscapeThread then task.cancel(autoEscapeThread) end
            autoEscapeThread = nil
        end
    end,
})

EscapeTab:CreateSlider({
    Name = "Escape Distance (studs)",
    Range = {10, 50},
    Increment = 1,
    Suffix = "studs",
    CurrentValue = escapeDistance,
    Callback = function(Value)
        escapeDistance = Value
    end,
})

-- Tab: ESP
local ESPTab = Window:CreateTab(" ESP", nil)

ESPTab:CreateToggle({
    Name = "ESP Items (Value Color)",
    CurrentValue = false,
    Callback = function(Value)
        espItemEnabled = Value
        if Value then
            coroutine.wrap(updateItemESP)()
        else
            for _, v in pairs(espItems) do if v and v.Parent then v:Destroy() end end
            espItems = {}
        end
    end,
})

ESPTab:CreateToggle({
    Name = "ESP Killer",
    CurrentValue = false,
    Callback = function(Value)
        espKillerEnabled = Value
        if espKillerEnabled or espSurvivorEnabled then
            coroutine.wrap(updatePlayerESP)()
        end
    end,
})

ESPTab:CreateToggle({
    Name = "ESP Survivor",
    CurrentValue = false,
    Callback = function(Value)
        espSurvivorEnabled = Value
        if espKillerEnabled or espSurvivorEnabled then
            coroutine.wrap(updatePlayerESP)()
        end
    end,
})

-- Tab: MOVEMENT
local MoveTab = Window:CreateTab(" MOVEMENT", nil)

MoveTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 350},
    Increment = 1,
    Suffix = "Studs/s",
    CurrentValue = 16,
    Callback = function(Value)
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = Value end
    end,
})

MoveTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Callback = function(Value) toggleNoclip(Value) end,
})

MoveTab:CreateToggle({
    Name = "Fly",
    CurrentValue = false,
    Callback = function(Value) toggleFly(Value) end,
})

-- Tab: ANTI
local AntiTab = Window:CreateTab("ANTI", nil)

AntiTab:CreateToggle({
    Name = "Anti Stun / Grab",
    CurrentValue = false,
    Callback = function(Value)
        antiStunEnabled = Value
        if Value then
            setupAntiStun()
        else
            disableAntiStun()
        end
    end,
})

AntiTab:CreateToggle({
    Name = "Anti Damage (God Mode)",
    CurrentValue = false,
    Callback = function(Value)
        antiDamageEnabled = Value
        if Value then
            setupAntiDamage()
        else
            disableAntiDamage()
        end
    end,
})

AntiTab:CreateButton({
    Name = "Heal Full",
    Callback = function()
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.Health = hum.MaxHealth end
        Rayfield:Notify({Title = "VIP", Content = "Healed!", Duration = 2})
    end,
})

-- Tab: UTILITY
local UtilTab = Window:CreateTab(" UTILITY", nil)

UtilTab:CreateButton({
    Name = "Teleport to Safe Zone",
    Callback = function()
        local door = getExitDoor()
        if door then
            safeTeleportTo(door)
            Rayfield:Notify({Title = "VIP", Content = "Teleported to safe zone!", Duration = 2})
        else
            Rayfield:Notify({Title = "VIP", Content = "Safe zone not found!", Duration = 2})
        end
    end,
})

UtilTab:CreateButton({
    Name = "Rejoin Game",
    Callback = function() TeleportService:Teleport(game.PlaceId) end,
})

UtilTab:CreateButton({
    Name = "Server Hop",
    Callback = function()
        local Http = game:GetService("HttpService")
        pcall(function()
            local response = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100")
            local data = Http:JSONDecode(response)
            local servers = {}
            for _, server in pairs(data.data) do
                if server.playing < server.maxPlayers then
                    table.insert(servers, server.id)
                end
            end
            if #servers > 0 then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1,#servers)])
            end
        end)
    end,
})

-- Notifikasi siap
Rayfield:Notify({
    Title = "STK VIP",
    Content = "Script By Putzx",
    Duration = 4,
})

print("STK VIP Script Loaded - by Putzzdev")