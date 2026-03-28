-- ============================================
-- SURVIVE THE KILLER | FIXED SCRIPT
-- Fitur: ESP (player, item, exit) + Auto Loot + Auto Escape + Auto Exit
-- Dengan debug untuk membantu pencarian
-- ============================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ==================== GUI (Rayfield) ====================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "STK FIXED",
    Icon = 0,
    LoadingTitle = "Survive The Killer",
    LoadingSubtitle = "Fixed Version",
    Theme = "Dark",
})

-- ==================== UTILITY FUNCTIONS ====================
local function safeTeleportTo(part)
    local char = player.Character
    if not char or not part then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and part then
        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
    end
end

local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

-- ==================== ESP (Menggunakan BillboardGui) ====================
local espObjects = {} -- untuk cleanup

local function createBillboard(part, text, color)
    if not part then return end
    local bill = Instance.new("BillboardGui")
    bill.Name = "STK_ESP"
    bill.Adornee = part
    bill.Size = UDim2.new(0, 100, 0, 30)
    bill.StudsOffset = Vector3.new(0, 2, 0)
    bill.AlwaysOnTop = true
    local frame = Instance.new("Frame", bill)
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = color
    frame.BackgroundTransparency = 0.5
    local textLabel = Instance.new("TextLabel", frame)
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = text
    textLabel.TextColor3 = Color3.new(1,1,1)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold
    bill.Parent = part
    return bill
end

local function clearESP()
    for _, obj in pairs(espObjects) do
        pcall(function() obj:Destroy() end)
    end
    espObjects = {}
end

-- ==================== DETEKSI ITEM ====================
-- Item biasanya memiliki ProximityPrompt atau ClickDetector, dan berada di folder "Items" atau langsung di workspace
local function findItems()
    local items = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        -- Kriteria item: memiliki ProximityPrompt atau ClickDetector, dan bukan bagian dari player
        if obj:IsA("BasePart") or obj:IsA("Model") then
            local hasPrompt = obj:FindFirstChildWhichIsA("ProximityPrompt") or (obj.Parent and obj.Parent:FindFirstChildWhichIsA("ProximityPrompt"))
            local hasClick = obj:FindFirstChildWhichIsA("ClickDetector")
            if hasPrompt or hasClick then
                -- pastikan bukan bagian dari karakter
                local isChar = false
                local current = obj
                while current do
                    if current:IsA("Character") or (current == player.Character) then
                        isChar = true
                        break
                    end
                    current = current.Parent
                end
                if not isChar then
                    local root = obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")) or obj
                    if root then
                        table.insert(items, root)
                    end
                end
            end
        end
    end
    return items
end

-- ==================== DETEKSI PINTU KELUAR ====================
local function findExit()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local name = obj.Name:lower()
        if name:find("exit") or name:find("gate") or name:find("door") then
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then return part end
        end
    end
    return nil
end

-- ==================== DETEKSI KILLER ====================
-- Cari player yang bukan diri sendiri, dan memiliki karakter
local function getKiller()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= player and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
            -- Di game ini killer adalah player dengan tim berbeda? Atau nama tertentu? 
            -- Sebagai fallback, kita anggap semua player selain diri adalah musuh (karena survivor lain tidak terlihat sebagai ancaman)
            -- Tapi jika ingin membedakan, bisa cek atribut
            -- Sementara, kita anggap semua player lain adalah musuh untuk auto escape.
            return pl
        end
    end
    return nil
end

-- ==================== AUTO LOOP ====================
local autoLootEnabled = false
local autoLootThread = nil

local function startAutoLoot()
    if autoLootThread then return end
    autoLootThread = task.spawn(function()
        while autoLootEnabled do
            task.wait(0.3)
            local char = player.Character
            if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end

            local items = findItems()
            if #items == 0 then
                task.wait(1)
                continue
            end

            -- Cari item terdekat
            local nearest = nil
            local nearestDist = math.huge
            for _, item in ipairs(items) do
                if item and item.Parent then
                    local dist = getDistance(hrp.Position, item.Position)
                    if dist < nearestDist then
                        nearestDist = dist
                        nearest = item
                    end
                end
            end

            if nearest then
                if nearestDist > 8 then
                    safeTeleportTo(nearest)
                    task.wait(0.2)
                else
                    -- Interaksi
                    local prompt = nearest:FindFirstChildWhichIsA("ProximityPrompt")
                    if not prompt and nearest.Parent then
                        prompt = nearest.Parent:FindFirstChildWhichIsA("ProximityPrompt")
                    end
                    if prompt then
                        pcall(function() prompt:InputHoldBegin() end)
                    else
                        local click = nearest:FindFirstChildWhichIsA("ClickDetector")
                        if click then
                            pcall(function() click:Click() end)
                        end
                    end
                    task.wait(0.5)
                end
            end
        end
        autoLootThread = nil
    end)
end

-- ==================== AUTO ESCAPE ====================
local autoEscapeEnabled = false
local escapeDistance = 20
local autoEscapeThread = nil

local function escapeFromKiller()
    local killer = getKiller()
    if not killer or not killer.Character then return end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local killerHrp = killer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or not killerHrp then return end

    local dist = getDistance(hrp.Position, killerHrp.Position)
    if dist < escapeDistance then
        -- Posisi menjauh
        local direction = (hrp.Position - killerHrp.Position).Unit
        local safePos = hrp.Position + direction * 40
        safePos = Vector3.new(
            math.clamp(safePos.X, -250, 250),
            safePos.Y,
            math.clamp(safePos.Z, -250, 250)
        )
        hrp.CFrame = CFrame.new(safePos)
        Rayfield:Notify({Title = "Auto Escape", Content = "Escape from killer!", Duration = 1})
        task.wait(0.5)
    end
end

local function autoEscapeLoop()
    while autoEscapeEnabled do
        task.wait(0.2)
        pcall(escapeFromKiller)
    end
end

-- ==================== AUTO EXIT ====================
local autoExitEnabled = false
local autoExitThread = nil

local function autoExitLoop()
    while autoExitEnabled do
        task.wait(1)
        local exit = findExit()
        if exit then
            -- Cek apakah pintu sudah bisa diinteraksi (ada prompt atau sudah terbuka)
            local prompt = exit:FindFirstChildWhichIsA("ProximityPrompt") or (exit.Parent and exit.Parent:FindFirstChildWhichIsA("ProximityPrompt"))
            if prompt then
                safeTeleportTo(exit)
                Rayfield:Notify({Title = "Auto Exit", Content = "Exit found! Teleported.", Duration = 2})
                task.wait(1)
                pcall(function() prompt:InputHoldBegin() end)
            end
        end
    end
end

-- ==================== ESP BUTTON & FUNGSI ====================
local espPlayerEnabled = false
local espItemEnabled = false
local espExitEnabled = false
local espUpdateThread = nil

local function updateESP()
    while espPlayerEnabled or espItemEnabled or espExitEnabled do
        task.wait(0.2)
        clearESP()

        -- ESP Player (semua player lain)
        if espPlayerEnabled then
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= player and pl.Character then
                    local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local bill = createBillboard(hrp, pl.Name, Color3.fromRGB(255,0,0))
                        if bill then table.insert(espObjects, bill) end
                    end
                end
            end
        end

        -- ESP Item
        if espItemEnabled then
            local items = findItems()
            for _, item in ipairs(items) do
                local bill = createBillboard(item, "ITEM", Color3.fromRGB(0,255,0))
                if bill then table.insert(espObjects, bill) end
            end
        end

        -- ESP Exit
        if espExitEnabled then
            local exit = findExit()
            if exit then
                local bill = createBillboard(exit, "EXIT", Color3.fromRGB(255,255,0))
                if bill then table.insert(espObjects, bill) end
            end
        end
    end
end

-- ==================== GUI TABS ====================
-- Tab: ESP
local ESPTab = Window:CreateTab("👁️ ESP", nil)

ESPTab:CreateToggle({
    Name = "ESP Players (All)",
    CurrentValue = false,
    Callback = function(Value)
        espPlayerEnabled = Value
        if espPlayerEnabled or espItemEnabled or espExitEnabled then
            if not espUpdateThread then
                espUpdateThread = task.spawn(updateESP)
            end
        elseif not espPlayerEnabled and not espItemEnabled and not espExitEnabled then
            if espUpdateThread then task.cancel(espUpdateThread) end
            espUpdateThread = nil
            clearESP()
        end
    end,
})

ESPTab:CreateToggle({
    Name = "ESP Items",
    CurrentValue = false,
    Callback = function(Value)
        espItemEnabled = Value
        if espPlayerEnabled or espItemEnabled or espExitEnabled then
            if not espUpdateThread then
                espUpdateThread = task.spawn(updateESP)
            end
        elseif not espPlayerEnabled and not espItemEnabled and not espExitEnabled then
            if espUpdateThread then task.cancel(espUpdateThread) end
            espUpdateThread = nil
            clearESP()
        end
    end,
})

ESPTab:CreateToggle({
    Name = "ESP Exit",
    CurrentValue = false,
    Callback = function(Value)
        espExitEnabled = Value
        if espPlayerEnabled or espItemEnabled or espExitEnabled then
            if not espUpdateThread then
                espUpdateThread = task.spawn(updateESP)
            end
        elseif not espPlayerEnabled and not espItemEnabled and not espExitEnabled then
            if espUpdateThread then task.cancel(espUpdateThread) end
            espUpdateThread = nil
            clearESP()
        end
    end,
})

ESPTab:CreateButton({
    Name = "Debug: List Items in Console",
    Callback = function()
        local items = findItems()
        print("=== ITEMS FOUND ===")
        for i, item in ipairs(items) do
            print(i, item.Name, item.Parent and item.Parent.Name)
        end
        local exit = findExit()
        print("Exit found:", exit and exit.Name or "none")
        print("===================")
        Rayfield:Notify({Title = "Debug", Content = "Check F9 console for details", Duration = 3})
    end,
})

-- Tab: AUTO LOOT
local LootTab = Window:CreateTab("💰 AUTO LOOT", nil)

LootTab:CreateToggle({
    Name = "Auto Loot (Teleport & Pickup)",
    CurrentValue = false,
    Callback = function(Value)
        autoLootEnabled = Value
        if Value then
            startAutoLoot()
        else
            if autoLootThread then task.cancel(autoLootThread) end
            autoLootThread = nil
        end
    end,
})

LootTab:CreateButton({
    Name = "Teleport to Nearest Item",
    Callback = function()
        local items = findItems()
        if #items == 0 then
            Rayfield:Notify({Title = "Error", Content = "No items found", Duration = 2})
            return
        end
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local nearest = nil
        local nearestDist = math.huge
        for _, item in ipairs(items) do
            local dist = getDistance(hrp.Position, item.Position)
            if dist < nearestDist then
                nearestDist = dist
                nearest = item
            end
        end
        if nearest then
            safeTeleportTo(nearest)
            Rayfield:Notify({Title = "Teleport", Content = "Teleported to item", Duration = 2})
        end
    end,
})

-- Tab: ESCAPE
local EscapeTab = Window:CreateTab("🏃 ESCAPE", nil)

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
    Name = "Escape Distance",
    Range = {10, 50},
    Increment = 1,
    Suffix = "studs",
    CurrentValue = escapeDistance,
    Callback = function(Value)
        escapeDistance = Value
    end,
})

EscapeTab:CreateToggle({
    Name = "Auto Exit (when exit opens)",
    CurrentValue = false,
    Callback = function(Value)
        autoExitEnabled = Value
        if Value then
            if autoExitThread then task.cancel(autoExitThread) end
            autoExitThread = task.spawn(autoExitLoop)
        else
            if autoExitThread then task.cancel(autoExitThread) end
            autoExitThread = nil
        end
    end,
})

-- Tab: MOVEMENT
local MoveTab = Window:CreateTab("🏃 MOVEMENT", nil)

MoveTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 350},
    Increment = 1,
    Suffix = "studs/s",
    CurrentValue = 16,
    Callback = function(Value)
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = Value end
    end,
})

local noclipConn = nil
MoveTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Callback = function(Value)
        if Value then
            if noclipConn then return end
            noclipConn = RunService.Stepped:Connect(function()
                if player.Character then
                    for _, p in ipairs(player.Character:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end
            end)
        else
            if noclipConn then noclipConn:Disconnect() end
            noclipConn = nil
        end
    end,
})

local flyEnabled = false
local flyBodyVel, flyConn
MoveTab:CreateToggle({
    Name = "Fly",
    CurrentValue = false,
    Callback = function(Value)
        flyEnabled = Value
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
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camera.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camera.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camera.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camera.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0,1,0) end
                if moveDir.Magnitude > 0 then flyBodyVel.Velocity = moveDir.Unit * 70 else flyBodyVel.Velocity = Vector3.new(0,0,0) end
            end)
        else
            if flyBodyVel then flyBodyVel:Destroy() end
            if flyConn then flyConn:Disconnect() end
            if hum then hum.PlatformStand = false end
            flyBodyVel = nil
            flyConn = nil
        end
    end,
})

-- Tab: UTILITY
local UtilTab = Window:CreateTab("⚙️ UTILITY", nil)

UtilTab:CreateButton({
    Name = "Teleport to Exit",
    Callback = function()
        local exit = findExit()
        if exit then
            safeTeleportTo(exit)
            Rayfield:Notify({Title = "Teleport", Content = "To exit", Duration = 2})
        else
            Rayfield:Notify({Title = "Error", Content = "Exit not found", Duration = 2})
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

-- Notifikasi
Rayfield:Notify({
    Title = "STK FIXED",
    Content = "Script loaded! Use Debug button to check objects.",
    Duration = 5,
})

print("STK Fixed Script Loaded. Use 'Debug: List Items' to see what objects are detected.")