--// ========================================================= //--
--//                    AUTO FARM SCRIPT                        //--
--// ========================================================= //--

local Library = loadstring(game:HttpGet("https://pastebin.com/raw/7UKF8MKf"))()
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local localPlayer = Players.LocalPlayer

--// ---------- Global State ---------- //--

local State = {
    Running = true,
    FarmSettings = {},
    NoPromptDelay = false,
    SavedDelays = {},
    AntiAfk = false,
}

--// ---------- Global Farm Lock ---------- //--

local FarmLock = { owner = nil }

local function acquireLock(ownerName)
    while State.Running do
        if FarmLock.owner == nil then
            FarmLock.owner = ownerName
            return true
        elseif FarmLock.owner == ownerName then
            return true
        end
        task.wait(0.05)
    end
    return false
end

local function releaseLock(ownerName)
    if FarmLock.owner == ownerName then
        FarmLock.owner = nil
    end
end

--// ---------- Helpers ---------- //--

local function getCharacter()
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    return character, character:WaitForChild("HumanoidRootPart")
end

local function teleportTo(cframe)
    if not State.Running then return end
    local _, rootPart = getCharacter()
    rootPart.CFrame = cframe
end

local function getPromptPosition(prompt)
    local holder = prompt.Parent
    if holder then
        if holder:IsA("Attachment") then
            return holder.WorldCFrame
        elseif holder:IsA("BasePart") then
            return holder.CFrame
        end
    end
    local part = prompt:FindFirstAncestorWhichIsA("BasePart")
    if part then return part.CFrame end
    local model = prompt:FindFirstAncestorWhichIsA("Model")
    if model then return model:GetPivot() end
    return CFrame.new()
end

local firePromptFunc = fireproximityprompt
if not firePromptFunc and getconnections then
    firePromptFunc = function(prompt)
        for _, conn in ipairs(getconnections(prompt.Triggered)) do
            pcall(function() conn:Fire(localPlayer) end)
        end
    end
end

local function firePrompt(prompt)
    if prompt and prompt.Enabled and prompt.Parent and State.Running and firePromptFunc then
        pcall(firePromptFunc, prompt)
    end
end

local function unequipTools()
    pcall(function()
        local character = localPlayer.Character
        if character and character:FindFirstChildOfClass("Humanoid") then
            character:FindFirstChildOfClass("Humanoid"):UnequipTools()
        end
    end)
end

local function equipTool(tool)
    pcall(function()
        local character = localPlayer.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:EquipTool(tool) end
        end
    end)
end

local function notify(title, text)
    print("[autofarm] " .. tostring(title) .. ": " .. tostring(text))
end

--// ---------- Color serialization helpers ---------- //--

local function colorToTable(c)
    return { r = math.floor(c.R * 255 + 0.5), g = math.floor(c.G * 255 + 0.5), b = math.floor(c.B * 255 + 0.5) }
end

local function tableToColor(t)
    if type(t) ~= "table" then return nil end
    local r = tonumber(t.r); local g = tonumber(t.g); local b = tonumber(t.b)
    if r == nil or g == nil or b == nil then return nil end
    return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
end

--// ---------- Lighting originals (for fullbright / force day) ---------- //--

local origBrightness = Lighting.Brightness
local origAmbient = Lighting.Ambient
local origOutdoor = Lighting.OutdoorAmbient
local origClockTime = Lighting.ClockTime
local origFogEnd = Lighting.FogEnd
local origFogStart = Lighting.FogStart
local origShadows = Lighting.GlobalShadows
local origExposure = Lighting.ExposureCompensation
local origCSTop = Lighting.ColorShift_Top
local origCSBottom = Lighting.ColorShift_Bottom
local lightingFx = {}
for _, fx in ipairs(Lighting:GetChildren()) do
    lightingFx[#lightingFx + 1] = fx
end

--// ---------- No Prompt Delay ---------- //--

local function setNoPromptDelay(enabled)
    State.NoPromptDelay = enabled

    if enabled then
        for _, prompt in ipairs(game:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") then
                State.SavedDelays[prompt] = prompt.HoldDuration
                pcall(function() prompt.HoldDuration = 0 end)
            end
        end
    else
        for prompt, oldDuration in pairs(State.SavedDelays) do
            pcall(function()
                if prompt.Parent then
                    prompt.HoldDuration = oldDuration
                end
            end)
        end
        for k in pairs(State.SavedDelays) do
            State.SavedDelays[k] = nil
        end
    end
end

--// ---------- Anti Idle / AFK ---------- //--

local antiAfkCon = nil

local function setAntiAfk(enabled)
    State.AntiAfk = enabled

    if antiAfkCon then
        pcall(function() antiAfkCon:Disconnect() end)
        antiAfkCon = nil
    end

    if enabled then
        if getconnections then
            for _, c in ipairs(getconnections(localPlayer.Idled)) do
                pcall(function() c:Disable() end)
                pcall(function() c:Disconnect() end)
            end
        end

        antiAfkCon = localPlayer.Idled:Connect(function()
            if VirtualUser then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end
        end)
    end
end

--// ========================================================= //--
--//              GENERIC VEHICLE MOD SYSTEM                    //--
--// ========================================================= //--

local function createModSystem(opts)
    local M = {}
    M.Enabled = false
    M.current = nil
    M.originals = nil
    M.connections = {}
    M.defaults = opts.defaults
    M.values = {}
    M.sliderRefs = {}
    for key, value in pairs(opts.defaults) do
        M.values[key] = value
    end

    function M:snapshotOriginals()
        if not self.current or not self.current.Parent then return false end
        if self.originals then return true end

        local snapshot = {}
        for key, _ in pairs(self.values) do
            local ok, val = pcall(opts.readValue, self.current, key)
            if not ok or val == nil then
                return false
            end
            snapshot[key] = val
        end
        self.originals = snapshot
        return true
    end

    function M:apply()
        if not self.Enabled or not self.current or not self.current.Parent then return end
        if not self.originals then
            self:snapshotOriginals()
        end
        for key, value in pairs(self.values) do
            pcall(opts.writeValue, self.current, key, value)
        end
    end

    function M:revert()
        if not self.current or not self.current.Parent then return end
        if not self.originals then return end
        for key, original in pairs(self.originals) do
            pcall(opts.writeValue, self.current, key, original)
        end
    end

    function M:onFound(target)
        if self.current == target then return end

        self.current = target
        self.originals = nil

        if self.Enabled then
            task.spawn(function()
                for _ = 1, 10 do
                    if not State.Running or not target.Parent then return end
                    if self.current ~= target then return end
                    if self:snapshotOriginals() then break end
                    task.wait(0.3)
                end
                if self.Enabled and self.current == target then
                    self:apply()
                end
            end)
        end
    end

    function M:onLost()
        self.current = nil
        self.originals = nil
    end

    function M:setEnabled(enabled)
        self.Enabled = enabled
        if enabled then
            self:apply()
        else
            self:revert()
        end
    end

    function M:resetToDefaults()
        for key, value in pairs(self.defaults) do
            self.values[key] = value
        end
        for key, slider in pairs(self.sliderRefs) do
            pcall(function() slider:SetValue(self.defaults[key]) end)
        end
    end

    function M:start()
        task.spawn(function()
            opts.watch(self, function(target) self:onFound(target) end, function() self:onLost() end)
        end)

        task.spawn(function()
            while State.Running do
                local ok, target = pcall(opts.findTarget)
                if ok and target then
                    if self.current ~= target then
                        self:onFound(target)
                    end
                elseif self.current then
                    local valid = false
                    pcall(function() valid = opts.isValid(self.current) end)
                    if not valid then
                        self:onLost()
                    end
                end
                task.wait(0.5)
            end
        end)
    end

    function M:shutdown()
        self:revert()
        for _, conn in ipairs(self.connections) do
            if conn.Connected then conn:Disconnect() end
        end
        for k in pairs(self.connections) do
            self.connections[k] = nil
        end
        self.current = nil
        self.originals = nil
    end

    return M
end

--// ========================================================= //--
--//                       CAR MODS                            //--
--// ========================================================= //--

local function myCarName()
    return localPlayer.Name .. "'s Car"
end

local CarMods = createModSystem({
    defaults = {
        acceleration = 35,
        deceleration = 35,
        braking = 105,
        handBrakeTorque = 9000,
        forwardMaxSpeed = 70,
        reverseMaxSpeed = 30,
    },

    findTarget = function()
        local folder = workspace:FindFirstChild("CivCars")
        if not folder then return nil end
        return folder:FindFirstChild(myCarName())
    end,

    isValid = function(car)
        return car.Parent ~= nil and car.Parent.Name == "CivCars"
    end,

    readValue = function(car, key)
        local engine = car:FindFirstChild("Engine")
        if not engine then return nil end
        return engine:GetAttribute(key)
    end,

    writeValue = function(car, key, value)
        local engine = car:FindFirstChild("Engine")
        if engine then
            engine:SetAttribute(key, value)
        end
    end,

    watch = function(M, onFound, onLost)
        task.spawn(function()
            while State.Running and not workspace:FindFirstChild("CivCars") do
                task.wait(0.5)
            end
            local folder = workspace:FindFirstChild("CivCars")
            if not folder then return end

            local added = folder.ChildAdded:Connect(function(child)
                if State.Running and child.Name == myCarName() then
                    onFound(child)
                end
            end)
            local removed = folder.ChildRemoved:Connect(function(child)
                if child == M.current then
                    onLost()
                end
            end)
            table.insert(M.connections, added)
            table.insert(M.connections, removed)
        end)
    end,
})

CarMods:start()

--// ========================================================= //--
--//                    SCOOTER MODS                           //--
--// ========================================================= //--

local function isScooterMine(scooter)
    local owner = scooter:FindFirstChild("Owner")
    return owner ~= nil and owner:IsA("StringValue") and owner.Value == localPlayer.Name
end

local ScooterMods = createModSystem({
    defaults = {
        ["Forwards Speed"] = 35,
        ["Reverse Speed"] = 35,
    },

    findTarget = function()
        for _, inst in ipairs(workspace:GetChildren()) do
            if inst.Name == "Electric Scooter" and isScooterMine(inst) then
                return inst
            end
        end
        return nil
    end,

    isValid = function(scooter)
        return scooter.Parent ~= nil and isScooterMine(scooter)
    end,

    readValue = function(scooter, key)
        local cfg = scooter:FindFirstChild("Configuration")
        if not cfg then return nil end
        local nv = cfg:FindFirstChild(key)
        if nv and nv:IsA("NumberValue") then
            return nv.Value
        end
        return nil
    end,

    writeValue = function(scooter, key, value)
        local cfg = scooter:FindFirstChild("Configuration")
        if not cfg then return end
        local nv = cfg:FindFirstChild(key)
        if nv and nv:IsA("NumberValue") then
            nv.Value = value
        end
    end,

    watch = function(M, onFound, onLost)
        local added = workspace.ChildAdded:Connect(function(child)
            if not State.Running or child.Name ~= "Electric Scooter" then return end
            task.spawn(function()
                for _ = 1, 10 do
                    if not child.Parent or not State.Running then return end
                    if isScooterMine(child) then
                        onFound(child)
                        return
                    end
                    task.wait(0.3)
                end
            end)
        end)
        local removed = workspace.ChildRemoved:Connect(function(child)
            if child == M.current then
                onLost()
            end
        end)
        table.insert(M.connections, added)
        table.insert(M.connections, removed)
    end,
})

ScooterMods:start()

--// ========================================================= //--
--//                 CLIENT FEATURES                           //--
--// ========================================================= //--

local Camera = Workspace.CurrentCamera

local clientConnections = {}
local function keepConn(conn)
    if conn then
        clientConnections[#clientConnections + 1] = conn
    end
    return conn
end

keepConn(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local newCam = Workspace.CurrentCamera
    if newCam and newCam ~= Camera then
        Camera = newCam
    end
end))

local OKGui = (gethui and gethui()) or game:GetService("CoreGui")

local function newLine(thickness, color)
    local l = Drawing.new("Line")
    l.Visible = false
    l.From, l.To = Vector2.zero, Vector2.zero
    l.Color = color
    l.Thickness = thickness
    l.Transparency = 1
    return l
end

--// ---------- fps tracking (for General & Stats tab) ---------- //--

local scriptStartClock = os.clock()
local fpsSmooth = 60

RunService.RenderStepped:Connect(function(dt)
    if dt > 0 then
        fpsSmooth = fpsSmooth * 0.95 + (1 / dt) * 0.05
    end
end)

--// ---------- Zoom ---------- //--

local Client = {
    bulletTracers = false,
    tracerColor = Color3.fromRGB(0, 170, 255),
    tracerTime = 3,
    tracerMax = 50,
    zoomFov = 10,
    zoomKey = Enum.KeyCode.Z,
    flySpeed = 40,
    slowSpeed = 8,
    fullbright = false,
    forceDay = false,
}

local zoomHolding = false
local zoomSavedFov = Camera.FieldOfView

local function setZoomHolding(held)
    if zoomHolding == held then return end
    zoomHolding = held
    pcall(function()
        if held then
            zoomSavedFov = Camera.FieldOfView
            Camera.FieldOfView = Client.zoomFov
        else
            Camera.FieldOfView = zoomSavedFov
        end
    end)
end

keepConn(UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Client.zoomKey then
        setZoomHolding(true)
    end
end))
keepConn(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Client.zoomKey then
        setZoomHolding(false)
    end
end))
keepConn(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    zoomHolding = false
end))

--// ---------- Fullbright / Force Day ---------- //--

local white3 = Color3.new(1, 1, 1)

local function applyFullbright(enabled)
    Client.fullbright = enabled
    if not enabled then
        pcall(function()
            Lighting.Brightness = origBrightness
            Lighting.Ambient = origAmbient
            Lighting.OutdoorAmbient = origOutdoor
            Lighting.FogEnd = origFogEnd
            Lighting.FogStart = origFogStart
            Lighting.GlobalShadows = origShadows
            Lighting.ExposureCompensation = origExposure
            Lighting.ColorShift_Top = origCSTop
            Lighting.ColorShift_Bottom = origCSBottom
        end)
    end
end

local function applyForceDay(enabled)
    Client.forceDay = enabled
    if not enabled then
        pcall(function() Lighting.ClockTime = origClockTime end)
    end
end

--// ---------- Freecam ---------- //--

local freecamActive = false
local camYaw, camPitch = 0, 0
local camPos = Vector3.new(0, 0, 0)
local hiddenGuis = {}
local SlowLabel, PosLabel
local ACCENT = Color3.fromRGB(0, 195, 255)
local ACCENT_DARK = Color3.fromRGB(0, 95, 160)

local HUD = Instance.new("ScreenGui")
HUD.Name = "chicagolife_FreecamHUD"
HUD.ResetOnSpawn = false
HUD.IgnoreGuiInset = true
HUD.Enabled = false
HUD.DisplayOrder = 2000
HUD.Parent = OKGui

do
    local function HN(class, props, parent)
        local inst = Instance.new(class)
        for k, v in pairs(props) do inst[k] = v end
        inst.Parent = parent
        return inst
    end
    HN("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(22, 1), BackgroundColor3 = ACCENT, BackgroundTransparency = 0.25, BorderSizePixel = 0}, HUD)
    HN("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(1, 22), BackgroundColor3 = ACCENT, BackgroundTransparency = 0.25, BorderSizePixel = 0}, HUD)
    local Banner = HN("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(210, 22), BackgroundColor3 = Color3.fromRGB(13, 16, 28),
        BackgroundTransparency = 0.15, BorderSizePixel = 0}, HUD)
    HN("UICorner", {CornerRadius = UDim.new(0, 4)}, Banner)
    HN("TextLabel", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.Code,
        TextSize = 13, TextColor3 = ACCENT, Text = "chicagolife // FREECAM"}, Banner)
    local Panel = HN("Frame", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
        Size = UDim2.fromOffset(268, 76), BackgroundColor3 = Color3.fromRGB(8, 10, 18),
        BackgroundTransparency = 0.15, BorderSizePixel = 0}, HUD)
    HN("UICorner", {CornerRadius = UDim.new(0, 5)}, Panel)
    HN("TextLabel", {Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 14), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 12, TextColor3 = Color3.fromRGB(200, 215, 235),
        TextXAlignment = Enum.TextXAlignment.Left, Text = "[WASD] fly   [Q] down   [E] up"}, Panel)
    HN("TextLabel", {Position = UDim2.fromOffset(8, 23), Size = UDim2.new(1, -16, 0, 14), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 12, TextColor3 = Color3.fromRGB(200, 215, 235),
        TextXAlignment = Enum.TextXAlignment.Left, Text = "[SHIFT] slow: OFF", Name = "SlowLabel"}, Panel)
    HN("TextLabel", {Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 0, 14), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 12, TextColor3 = Color3.fromRGB(200, 215, 235),
        TextXAlignment = Enum.TextXAlignment.Left, Text = "[V] exit"}, Panel)
    HN("TextLabel", {Position = UDim2.fromOffset(8, 53), Size = UDim2.new(1, -16, 0, 14), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 10, TextColor3 = ACCENT_DARK,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "pos: 0,0,0", Name = "PosLabel"}, Panel)
end

local function setFreecamBodyFrozen(frozen)
    local char = localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function() hrp.Anchored = frozen end)
end

local function toggleFreecam()
    if not freecamActive then
        local look = Camera.CFrame.LookVector
        camPitch = math.asin(math.clamp(look.Y, -1, 1))
        camYaw = math.atan2(-look.X, -look.Z)
        local char = localPlayer.Character
        local head = char and char:FindFirstChild("Head")
        camPos = (head and head.Parent and head.Position) or Camera.CFrame.Position
        freecamActive = true
        setFreecamBodyFrozen(true)
        hiddenGuis = {}
        local containers = { OKGui, localPlayer:FindFirstChildOfClass("PlayerGui") }
        for _, container in ipairs(containers) do
            if container then
                for _, g in ipairs(container:GetChildren()) do
                    if g:IsA("ScreenGui") and g.Enabled and g ~= HUD then
                        hiddenGuis[#hiddenGuis + 1] = g
                        g.Enabled = false
                    end
                end
            end
        end
        HUD.Enabled = true
        UserInputService.MouseIconEnabled = false
        Camera.CameraType = Enum.CameraType.Scriptable
        Camera.CFrame = CFrame.new(camPos) * CFrame.fromEulerAnglesYXZ(camPitch, camYaw, 0)
    else
        freecamActive = false
        setFreecamBodyFrozen(false)
        for _, g in ipairs(hiddenGuis) do pcall(function() g.Enabled = true end) end
        hiddenGuis = {}
        HUD.Enabled = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
        Camera.CameraType = Enum.CameraType.Custom
    end
end

--// ========================================================= //--
--//        BULLET TRACERS (per-shot Lighting Blur watcher)     //--
--// ========================================================= //--

local tracerEntries = {}

local function removeTracer(i)
    local e = tracerEntries[i]
    if e then
        pcall(function() e.lineO:Remove() end)
        pcall(function() e.line:Remove() end)
    end
    table.remove(tracerEntries, i)
end

local function getCrosshairPosition()
    local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    local gunGUI = pg:FindFirstChild("GunGUI")
    if not gunGUI then return nil end
    local crosshair = gunGUI:FindFirstChild("Crosshair")
    if not crosshair then return nil end
    return crosshair.AbsolutePosition
end

local function getMuzzlePosition()
    local char = localPlayer.Character
    local head = char and char:FindFirstChild("Head")
    local vm = Workspace:FindFirstChild("Camera")

    if head and vm then
        local dist = (Camera.CFrame.Position - head.Position).Magnitude
        if dist <= 2.5 then
            for _, d in ipairs(vm:GetDescendants()) do
                if d:IsA("Attachment") and d.Name:find("^GunFirePoint") then
                    return d.WorldPosition
                end
            end
        end
    end

    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            for _, d in ipairs(tool:GetDescendants()) do
                if d:IsA("Attachment") and d.Name:find("^GunFirePoint") then
                    return d.WorldPosition
                end
            end
        end
    end
    return nil
end

local tracerRayParams = RaycastParams.new()
tracerRayParams.FilterType = Enum.RaycastFilterType.Exclude
tracerRayParams.IgnoreWater = true

local function getShotEndpoint()
    local char = localPlayer.Character
    local filter = { Camera }
    if char then
        filter[#filter + 1] = char
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then filter[#filter + 1] = tool end
    end
    local vm = Workspace:FindFirstChild("Camera")
    if vm then filter[#filter + 1] = vm end
    tracerRayParams.FilterDescendantsInstances = filter

    local screenPos = getCrosshairPosition()

    local ray
    if screenPos then
        ray = Camera:ScreenPointToRay(screenPos.X, screenPos.Y)
    else
        local mouse = UserInputService:GetMouseLocation()
        ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
    end

    local result = Workspace:Raycast(ray.Origin, ray.Direction * 5000, tracerRayParams)
    if result then
        return result.Position
    end
    return ray.Origin + ray.Direction * 5000
end

local function addTracerFromShot()
    local muzzle = getMuzzlePosition()
    if not muzzle then return end
    local endpoint = getShotEndpoint()

    if #tracerEntries >= Client.tracerMax then
        removeTracer(1)
    end

    tracerEntries[#tracerEntries + 1] = {
        origin = muzzle,
        target = endpoint,
        bornAt = os.clock(),
        lineO = newLine(2, Color3.fromRGB(0, 0, 0)),
        line = newLine(1, Client.tracerColor),
    }
end

local function updateTracers(now)
    if not Client.bulletTracers then
        for i = #tracerEntries, 1, -1 do
            removeTracer(i)
        end
        return
    end
    for i = #tracerEntries, 1, -1 do
        local e = tracerEntries[i]
        local age = now - e.bornAt
        if age >= Client.tracerTime then
            removeTracer(i)
        else
            local va = Camera:WorldToViewportPoint(e.origin)
            local vb = Camera:WorldToViewportPoint(e.target)
            if va.Z > 0 and vb.Z > 0 then
                local fade = 1 - (age / Client.tracerTime)
                e.lineO.From = Vector2.new(va.X, va.Y); e.lineO.To = Vector2.new(vb.X, vb.Y)
                e.line.From = Vector2.new(va.X, va.Y);   e.line.To = Vector2.new(vb.X, vb.Y)
                e.lineO.Color = Color3.fromRGB(0, 0, 0)
                e.line.Color = Client.tracerColor
                e.lineO.Transparency = fade
                e.line.Transparency = fade
                e.lineO.Visible = true
                e.line.Visible = true
            else
                e.lineO.Visible = false
                e.line.Visible = false
            end
        end
    end
end

--// ========================================================= //--
--//                     PLAYER ESP                            //--
--// ========================================================= //--

local ESP = {
    enabled = false,
    boxes = false,
    names = false,
    dist = false,
    health = false,
    held = false,
    skel = false,
    highlight = false,
    viewcheck = true,
    espThickness = 1,
    renderDist = 5000,
    boxStyle = "Bounding Box",
    textFont = "Plex [2]",
    textSize = 11,
    visCol = Color3.fromRGB(255, 255, 0),
    hidCol = Color3.fromRGB(255, 255, 255),
    frndCol = Color3.fromRGB(0, 255, 0),
}

local FONT_INDICES = { ["UI [0]"] = 0, ["System [1]"] = 1, ["Plex [2]"] = 2, ["Monospace [3]"] = 3 }
local function espFontIndex()
    return FONT_INDICES[ESP.textFont] or 2
end

local function newQuad(t, c)
    local q = Drawing.new("Quad")
    q.Visible = false
    q.PointA, q.PointB, q.PointC, q.PointD = Vector2.zero, Vector2.zero, Vector2.zero, Vector2.zero
    q.Color = c
    q.Filled = false
    q.Thickness = t
    q.Transparency = 1
    return q
end

local function newText(s, c)
    local t = Drawing.new("Text")
    t.Visible = false
    t.Center = true
    t.Outline = true
    t.Font = 2
    t.Color = c
    t.Size = s
    return t
end

local HP_COLORS = {}
for i = 0, 100 do
    local pct = i / 100
    HP_COLORS[i] = Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(255 * pct), 0)
end
local function hpColor(pct)
    return HP_COLORS[math.clamp(math.floor(pct * 100 + 0.5), 0, 100)]
end

local function hideESPBoxSegs(d)
    if d.segs then
        for i = 1, 8 do d.segs[i].Visible = false end
    end
end

local function drawESPBox(d, minX, minY, maxX, maxY, col, thick)
    if ESP.boxStyle == "Bounding Box" then
        d.box.PointA = Vector2.new(maxX, minY); d.box.PointB = Vector2.new(minX, minY)
        d.box.PointC = Vector2.new(minX, maxY); d.box.PointD = Vector2.new(maxX, maxY)
        d.box.Color = col; d.box.Thickness = thick; d.box.Visible = true
        d.blackbox.PointA = Vector2.new(maxX, minY); d.blackbox.PointB = Vector2.new(minX, minY)
        d.blackbox.PointC = Vector2.new(minX, maxY); d.blackbox.PointD = Vector2.new(maxX, maxY)
        d.blackbox.Thickness = thick + 1; d.blackbox.Visible = true
        hideESPBoxSegs(d)
    else
        d.box.Visible = false; d.blackbox.Visible = false
        local w = maxX - minX
        local h = maxY - minY
        local L = math.min(w, h) * 0.25

        if ESP.boxStyle == "Corner Brackets" then
            d.segs[1].From = Vector2.new(minX, minY); d.segs[1].To = Vector2.new(minX + L, minY)
            d.segs[2].From = Vector2.new(minX, minY); d.segs[2].To = Vector2.new(minX, minY + L)
            d.segs[3].From = Vector2.new(maxX, minY); d.segs[3].To = Vector2.new(maxX - L, minY)
            d.segs[4].From = Vector2.new(maxX, minY); d.segs[4].To = Vector2.new(maxX, minY + L)
            d.segs[5].From = Vector2.new(minX, maxY); d.segs[5].To = Vector2.new(minX + L, maxY)
            d.segs[6].From = Vector2.new(minX, maxY); d.segs[6].To = Vector2.new(minX, maxY - L)
            d.segs[7].From = Vector2.new(maxX, maxY); d.segs[7].To = Vector2.new(maxX - L, maxY)
            d.segs[8].From = Vector2.new(maxX, maxY); d.segs[8].To = Vector2.new(maxX, maxY - L)
        else
            local C = math.min(w, h) * 0.18
            d.segs[1].From = Vector2.new(minX, minY); d.segs[1].To = Vector2.new(minX + L, minY)
            d.segs[2].From = Vector2.new(minX, minY); d.segs[2].To = Vector2.new(minX + C, minY + C)
            d.segs[3].From = Vector2.new(maxX, minY); d.segs[3].To = Vector2.new(maxX - L, minY)
            d.segs[4].From = Vector2.new(maxX, minY); d.segs[4].To = Vector2.new(maxX - C, minY + C)
            d.segs[5].From = Vector2.new(minX, maxY); d.segs[5].To = Vector2.new(minX + L, maxY)
            d.segs[6].From = Vector2.new(minX, maxY); d.segs[6].To = Vector2.new(minX + C, maxY - C)
            d.segs[7].From = Vector2.new(maxX, maxY); d.segs[7].To = Vector2.new(maxX + C, maxY - C)
            d.segs[8].From = Vector2.new(maxX, maxY); d.segs[8].To = Vector2.new(maxX - C, maxY - C)
        end

        for i = 1, 8 do
            local seg = d.segs[i]
            seg.Color = col
            seg.Thickness = thick
            seg.Visible = true
        end
    end
end

local function hideEntry(e)
    if e.hiddenFlag then return end
    e.hiddenFlag = true
    e.blackbox.Visible = false; e.box.Visible = false
    e.name.Visible = false; e.dist.Visible = false
    e.item.Visible = false
    e.hpbg.Visible = false; e.hpfill.Visible = false
    hideESPBoxSegs(e)
    if e.highlightRef then pcall(function() e.highlightRef:Destroy() end); e.highlightRef = nil end
    if e.bones then
        for _, bl in pairs(e.bones) do bl.o.Visible = false; bl.l.Visible = false end
    end
end

local function makeEntry()
    return {
        hiddenFlag = true,
        blackbox = newQuad(2, Color3.fromRGB(0, 0, 0)),
        box = newQuad(1, Color3.fromRGB(255, 255, 255)),
        name = newText(11, Color3.fromRGB(255, 255, 255)),
        dist = newText(11, Color3.fromRGB(255, 255, 255)),
        item = newText(11, Color3.fromRGB(255, 210, 90)),
        hpbg = newLine(4, Color3.fromRGB(0, 0, 0)),
        hpfill = newLine(2, Color3.fromRGB(0, 255, 0)),
        segs = {
            newLine(2, Color3.fromRGB(0, 0, 0)), newLine(1, Color3.fromRGB(255, 255, 255)),
            newLine(2, Color3.fromRGB(0, 0, 0)), newLine(1, Color3.fromRGB(255, 255, 255)),
            newLine(2, Color3.fromRGB(0, 0, 0)), newLine(1, Color3.fromRGB(255, 255, 255)),
            newLine(2, Color3.fromRGB(0, 0, 0)), newLine(1, Color3.fromRGB(255, 255, 255)),
        },
        highlightRef = nil,
        bones = nil,
        visFrame = 0,
        isVisible = false,
    }
end

local function destroyEntry(e)
    pcall(function() e.blackbox:Remove() end); pcall(function() e.box:Remove() end)
    pcall(function() e.name:Remove() end); pcall(function() e.dist:Remove() end)
    pcall(function() e.item:Remove() end)
    pcall(function() e.hpbg:Remove() end); pcall(function() e.hpfill:Remove() end)
    for _, seg in ipairs(e.segs) do
        pcall(function() seg:Remove() end)
    end
    if e.highlightRef then pcall(function() e.highlightRef:Destroy() end) end
    if e.bones then
        for _, bl in pairs(e.bones) do
            pcall(function() bl.o:Remove() end); pcall(function() bl.l:Remove() end)
        end
    end
end

local PlayerDrawings = {}

local function buildPlayerDraw(player)
    if PlayerDrawings[player] then return end
    PlayerDrawings[player] = makeEntry()
end

local function clearPlayer(player)
    local e = PlayerDrawings[player]
    if e then
        destroyEntry(e)
        PlayerDrawings[player] = nil
    end
end

keepConn(Players.PlayerAdded:Connect(buildPlayerDraw))
keepConn(Players.PlayerRemoving:Connect(clearPlayer))
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= localPlayer then buildPlayerDraw(p) end
end

--// ---------- whitelist ---------- //--

local Whitelist = {}
keepConn(Players.PlayerRemoving:Connect(function(p)
    if Whitelist[p.Name] then Whitelist[p.Name] = nil end
end))

local function isFriendly(plr)
    if plr == localPlayer then return true end
    if Whitelist[plr.Name] then return true end
    if localPlayer.Team ~= nil and plr.Team ~= nil and plr.Team == localPlayer.Team then
        return true
    end
    return false
end

local espVisParams = RaycastParams.new()
espVisParams.FilterType = Enum.RaycastFilterType.Exclude
espVisParams.IgnoreWater = true

local function isVisibleCharESP(char, lc, lHead)
    local th = char:FindFirstChild("Head")
    if not th or not lHead then return false end
    espVisParams.FilterDescendantsInstances = { lc, Camera }
    local hit = Workspace:Raycast(lHead.Position, th.Position - lHead.Position, espVisParams)
    return not hit or hit.Instance:IsDescendantOf(char)
end

--// skeleton //--

local BONE_KEYS = {
    "Head_Torso", "Torso_LTorso",
    "Shoulder_R", "Shoulder_L",
    "Torso_RUA", "RUA_RLA",
    "Torso_LUA", "LUA_LLA",
    "Hip_R", "Hip_L",
    "LTorso_RUL", "RUL_RLL",
    "LTorso_LUL", "LUL_LLL",
}

local _bones, _thick, _col, _cam = nil, 1, Color3.new(1, 1, 1), Camera

local function drawBone(key, fp, tp)
    local bl = _bones[key]; if not bl then return end
    local va = _cam:WorldToViewportPoint(fp)
    local vb = _cam:WorldToViewportPoint(tp)
    if va.Z <= 0 or vb.Z <= 0 then bl.o.Visible = false; bl.l.Visible = false; return end
    local f, t2 = Vector2.new(va.X, va.Y), Vector2.new(vb.X, vb.Y)
    bl.o.From = f; bl.o.To = t2; bl.o.Thickness = _thick + 1; bl.o.Color = Color3.new(0, 0, 0); bl.o.Visible = true
    bl.l.From = f; bl.l.To = t2; bl.l.Thickness = _thick; bl.l.Color = _col; bl.l.Visible = true
end

local function getPos(obj, name)
    local p = obj:FindFirstChild(name); return p and p.Position or nil
end

local function drawSkeletonR6(char, head)
    local torso = char:FindFirstChild("Torso"); if not torso then return end
    local cf = torso.CFrame
    local top = (cf * CFrame.new(0, 1, 0)).Position
    local bot = (cf * CFrame.new(0, -1, 0)).Position
    local rSh = (cf * CFrame.new(1.5, 1, 0)).Position
    local lSh = (cf * CFrame.new(-1.5, 1, 0)).Position
    local rHip = (cf * CFrame.new(0.5, -1, 0)).Position
    local lHip = (cf * CFrame.new(-0.5, -1, 0)).Position

    drawBone("Head_Torso", head and head.Position or top, top)
    drawBone("Torso_LTorso", top, bot)

    local function drawLimb(jointKey, limbKey, joint, partName)
        local part = char:FindFirstChild(partName)
        if not part then
            for _, k in ipairs({ jointKey, limbKey }) do
                local bl = _bones[k]; if bl then bl.o.Visible = false; bl.l.Visible = false end
            end
            return
        end
        drawBone(jointKey, joint, part.Position)
        drawBone(limbKey, part.Position, part.Position + part.CFrame.UpVector * -(part.Size.Y / 2))
    end

    drawLimb("Shoulder_R", "Torso_RUA", rSh, "Right Arm")
    drawLimb("Shoulder_L", "Torso_LUA", lSh, "Left Arm")
    drawLimb("Hip_R", "LTorso_RUL", rHip, "Right Leg")
    drawLimb("Hip_L", "LTorso_LUL", lHip, "Left Leg")

    for _, k in ipairs({ "RUA_RLA", "LUA_LLA", "RUL_RLL", "LUL_LLL" }) do
        local bl = _bones[k]; if bl then bl.o.Visible = false; bl.l.Visible = false end
    end
end

local function drawSkeletonR15(obj, head)
    local ut = getPos(obj, "UpperTorso"); local lt = getPos(obj, "LowerTorso")
    local rua = getPos(obj, "RightUpperArm"); local rla = getPos(obj, "RightLowerArm"); local rha = getPos(obj, "RightHand")
    local lua = getPos(obj, "LeftUpperArm"); local lla = getPos(obj, "LeftLowerArm"); local lha = getPos(obj, "LeftHand")
    local rul = getPos(obj, "RightUpperLeg"); local rll = getPos(obj, "RightLowerLeg"); local rf = getPos(obj, "RightFoot")
    local lul = getPos(obj, "LeftUpperLeg"); local lll = getPos(obj, "LeftLowerLeg"); local lf = getPos(obj, "LeftFoot")
    local hp = head and head.Position
    if hp and ut then drawBone("Head_Torso", hp, ut) end
    if ut and lt then drawBone("Torso_LTorso", ut, lt) end
    if ut and rua then drawBone("Shoulder_R", ut, rua) end
    if ut and lua then drawBone("Shoulder_L", ut, lua) end
    if rua and rla then drawBone("Torso_RUA", rua, rla) end
    if rla and rha then drawBone("RUA_RLA", rla, rha) end
    if lua and lla then drawBone("Torso_LUA", lua, lla) end
    if lla and lha then drawBone("LUA_LLA", lla, lha) end
    if lt and rul then drawBone("Hip_R", lt, rul) end
    if lt and lul then drawBone("Hip_L", lt, lul) end
    if rul and rll then drawBone("LTorso_RUL", rul, rll) end
    if rll and rf then drawBone("RUL_RLL", rll, rf) end
    if lul and lll then drawBone("LTorso_LUL", lul, lll) end
    if lll and lf then drawBone("LUL_LLL", lll, lf) end
end

--// ESP render loop //--

local VIS_INTERVAL = 6
local espFrame = 0

RunService.RenderStepped:Connect(function()
    if not State.Running then return end
    espFrame += 1

    if not ESP.enabled then
        for _, e in pairs(PlayerDrawings) do hideEntry(e) end
        return
    end

    local lc = localPlayer.Character
    local lRoot = lc and lc:FindFirstChild("HumanoidRootPart")
    local lHead = lc and lc:FindFirstChild("Head")

    local boxesOn = ESP.boxes
    local namesOn = ESP.names
    local distOn = ESP.dist
    local healthOn = ESP.health
    local skelOn = ESP.skel
    local hlOn = ESP.highlight
    local viewcheckOn = ESP.viewcheck
    local thick = ESP.espThickness
    local maxDist = ESP.renderDist
    local fontIdx = espFontIndex()
    local txtSz = ESP.textSize

    for player, e in pairs(PlayerDrawings) do
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")

        if not char or not hum or not root or not head or hum.Health <= 0 then
            hideEntry(e)
        elseif lRoot then
            local rd = (root.Position - lRoot.Position).Magnitude
            if rd > maxDist then
                hideEntry(e)
            else
                local rv = Camera:WorldToViewportPoint(root.Position)
                if rv.Z <= 0 then
                    hideEntry(e)
                else
                    e.hiddenFlag = false

                    local cx, cy = rv.X, rv.Y
                    local hv = Camera:WorldToViewportPoint(head.Position)
                    local dy = math.clamp((Vector2.new(hv.X, hv.Y) - Vector2.new(cx, cy)).Magnitude, 2, 1e9)
                    local hw, hh = dy * 0.9, dy * 1.9
                    local bL, bR = cx - hw, cx + hw
                    local bT, bB = cy - hh, cy + hh

                    if espFrame - e.visFrame >= VIS_INTERVAL then
                        e.visFrame = espFrame
                        if viewcheckOn and lHead then
                            e.isVisible = isVisibleCharESP(char, lc, lHead)
                        else
                            e.isVisible = false
                        end
                    end

                    local col = (isFriendly(player) and ESP.frndCol) or (e.isVisible and ESP.visCol or ESP.hidCol)

                    if hlOn then
                        if not e.highlightRef or e.highlightRef.Parent ~= char then
                            if e.highlightRef then e.highlightRef:Destroy() end
                            local h = Instance.new("Highlight")
                            h.Name = "chicagolife_ESP"
                            h.FillTransparency = 0.5
                            h.OutlineTransparency = 0
                            h.Parent = char
                            e.highlightRef = h
                        end
                        e.highlightRef.FillColor = col
                        e.highlightRef.OutlineColor = ESP.visCol
                    else
                        if e.highlightRef then e.highlightRef:Destroy(); e.highlightRef = nil end
                    end

                    if boxesOn then
                        drawESPBox(e, bL, bT, bR, bB, col, thick)
                    else
                        e.box.Visible = false; e.blackbox.Visible = false
                        hideESPBoxSegs(e)
                    end

                    if namesOn then
                        e.name.Position = Vector2.new(cx, bT - 14); e.name.Text = player.Name
                        e.name.Color = col; e.name.Font = fontIdx; e.name.Size = txtSz; e.name.Visible = true
                    else e.name.Visible = false end

                    if distOn then
                        local d = math.round((lRoot.Position - root.Position).Magnitude)
                        e.dist.Position = Vector2.new(cx, bB + 4); e.dist.Text = d .. "m"
                        e.dist.Color = col; e.dist.Font = fontIdx; e.dist.Size = txtSz; e.dist.Visible = true
                    else e.dist.Visible = false end

                    if healthOn then
                        local maxHP = hum.MaxHealth > 0 and hum.MaxHealth or 100
                        local pct = math.clamp(hum.Health / maxHP, 0, 1)
                        local barX = bL - 5
                        e.hpbg.From = Vector2.new(barX, bT); e.hpbg.To = Vector2.new(barX, bB); e.hpbg.Visible = true
                        e.hpfill.From = Vector2.new(barX, bB - (hh * 2 * pct)); e.hpfill.To = Vector2.new(barX, bB)
                        e.hpfill.Color = hpColor(pct); e.hpfill.Visible = true
                    else e.hpbg.Visible = false; e.hpfill.Visible = false end

                    if ESP.held then
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool then
                            local iy = distOn and (bB + 18) or (bB + 4)
                            e.item.Position = Vector2.new(cx, iy); e.item.Text = tool.Name
                            e.item.Color = col; e.item.Font = fontIdx; e.item.Size = txtSz; e.item.Visible = true
                        else e.item.Visible = false end
                    else e.item.Visible = false end

                    if skelOn then
                        if not e.bones then
                            e.bones = {}
                            for _, k in ipairs(BONE_KEYS) do
                                e.bones[k] = { o = newLine(3, Color3.new(0, 0, 0)), l = newLine(1, Color3.new(1, 1, 1)) }
                            end
                        end
                        _bones = e.bones; _thick = thick; _col = col; _cam = Camera
                        if char:FindFirstChild("Torso") then
                            pcall(drawSkeletonR6, char, head)
                        elseif char:FindFirstChild("UpperTorso") then
                            pcall(drawSkeletonR15, char, head)
                        else
                            for _, bl in pairs(e.bones) do bl.o.Visible = false; bl.l.Visible = false end
                        end
                    elseif e.bones then
                        for _, bl in pairs(e.bones) do bl.o.Visible = false; bl.l.Visible = false end
                    end
                end
            end
        else
            hideEntry(e)
        end
    end
end)

local function espShutdown()
    ESP.enabled = false
    for player in pairs(PlayerDrawings) do
        clearPlayer(player)
    end
end

--// ========================================================= //--
--//                     COMBAT MODULES                        //--
--// ========================================================= //--

local Combat = {
    silentAim = false,
    wallCheck = false,
    triggerbot = false,
    noRecoil = false,
    noSpread = false,
    tbMaxDist = 1000,
    targetPart = "HumanoidRootPart",
    fovVisible = false,
    fovRadius = 100,
    fovThickness = 1,
    fovColor = Color3.fromRGB(255, 255, 255),
    tracer = false,
    fireRateEnabled = false,
    fireRate = 0.115,
    debugHud = false,
}

local CurrentTarget = nil -- { player, part, root, aimPoint }

local Diag = {
    simHookInstalled = false,
    remoteHookMethod = "none",
    remoteLookups = 0,
    directInflicts = 0,
    redirectHits = 0,
}

--// ---------- weapon Setting module access ---------- //--

local cachedToolRef = nil
local cachedSettingTables = nil

local function getSettingTables(tool)
    if tool == cachedToolRef then
        return cachedSettingTables
    end
    cachedToolRef = tool
    cachedSettingTables = {}

    if tool then
        local settingFolder = tool:FindFirstChild("Setting")
        if settingFolder then
            for _, child in ipairs(settingFolder:GetChildren()) do
                if child:IsA("ModuleScript") then
                    local ok, t = pcall(require, child)
                    if ok and type(t) == "table" then
                        table.insert(cachedSettingTables, t)
                    end
                end
            end
        end
    end
    return cachedSettingTables
end

local function getBallistics()
    local char = localPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local tabs = getSettingTables(tool)
    if tabs and tabs[1] then
        return tabs[1]
    end
    return nil
end

--// ---------- weapon edits (idempotent, with backups) ---------- //--

local editBackups = {} -- [settingTable] = { [key] = original }

local function backupKey(tab, key, val)
    local b = editBackups[tab]
    if not b then
        b = {}
        editBackups[tab] = b
    end
    if b[key] == nil then
        b[key] = val
    end
end

local RECOIL_EDITS = {
    { "Recoil", 0 },
    { "CameraRecoilingEnabled", false },
}
local SPREAD_EDITS = {
    { "Spread", 0 },
}

local function applyEdits(tool, edits, on)
    if not tool then return end
    local tabs = getSettingTables(tool)
    for _, st in ipairs(tabs) do
        for _, e in ipairs(edits) do
            local key, val = e[1], e[2]
            if st[key] ~= nil then
                backupKey(st, key, st[key])
                st[key] = on and val or editBackups[st][key]
            end
        end
    end
end

local function applyFireRate(tool, on)
    if not tool then return end
    local tabs = getSettingTables(tool)
    for _, st in ipairs(tabs) do
        if st.FireRate ~= nil then
            backupKey(st, "FireRate", st.FireRate)
            st.FireRate = on and Combat.fireRate or editBackups[st]["FireRate"]
        end
        if type(st.FireRates) == "table" then
            backupKey(st, "FireRates", st.FireRates)
            local b = editBackups[st]
            if type(b.FireRates) ~= "table" then
                local copy = {}
                for i, v in ipairs(st.FireRates) do copy[i] = v end
                b.FireRates = copy
            end
            for i = 1, #st.FireRates do
                st.FireRates[i] = on and Combat.fireRate or b.FireRates[i]
            end
        end
    end
end

local weaponToolRef = nil

local function refreshWeaponEdits()
    local char = localPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")

    if tool ~= weaponToolRef then
        if weaponToolRef then
            applyEdits(weaponToolRef, RECOIL_EDITS, false)
            applyEdits(weaponToolRef, SPREAD_EDITS, false)
            applyFireRate(weaponToolRef, false)
        end
        weaponToolRef = tool
    end

    if tool then
        applyEdits(tool, RECOIL_EDITS, Combat.noRecoil)
        applyEdits(tool, SPREAD_EDITS, Combat.noSpread)
        applyFireRate(tool, Combat.fireRateEnabled)
    end
end

local function restoreAllWeapons()
    if weaponToolRef then
        applyEdits(weaponToolRef, RECOIL_EDITS, false)
        applyEdits(weaponToolRef, SPREAD_EDITS, false)
        applyFireRate(weaponToolRef, false)
    end
end

--// ---------- predictive aim ---------- //--

local function computeAimPoint(origin, targetPart, targetRoot)
    local point = targetPart.Position
    local s = getBallistics()
    if not s then return point end

    local speed = typeof(s.BulletSpeed) == "number" and s.BulletSpeed or nil
    if not speed or speed <= 0 then return point end

    local acc = typeof(s.BulletAcceleration) == "Vector3" and s.BulletAcceleration or Vector3.zero
    local vel = targetRoot and targetRoot.AssemblyLinearVelocity or Vector3.zero

    local aim = point
    for _ = 1, 5 do
        local t = (aim - origin).Magnitude / speed
        aim = point + vel * t + 0.5 * acc * t * t
    end
    return aim
end

--// ---------- target picking (FOV circle based) ---------- //--

local pickRayParams = RaycastParams.new()
pickRayParams.FilterType = Enum.RaycastFilterType.Exclude
pickRayParams.IgnoreWater = true

local function pickTarget()
    local fovR = Combat.fovRadius
    local targetPartName = Combat.targetPart
    local wallCheck = Combat.wallCheck
    local mouse = UserInputService:GetMouseLocation()

    local best, bestPart, bestRoot, bestDist = nil, nil, nil, fovR
    local myChar = localPlayer.Character
    local camCF = Camera.CFrame

    for _, plr in ipairs(Players:GetPlayers()) do
        if not isFriendly(plr) then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if char and hum and hum.Health > 0 and root then
                local parts
                if targetPartName == "Find Closest Part" then
                    parts = char:GetDescendants()
                else
                    parts = {}
                    local p = char:FindFirstChild(targetPartName)
                        or char:FindFirstChild("Head")
                        or root
                    if p then parts[1] = p end
                end

                for _, desc in ipairs(parts) do
                    if desc:IsA("BasePart") and desc.Parent then
                        local sp, on = Camera:WorldToViewportPoint(desc.Position)
                        if on then
                            local dist = (Vector2.new(mouse.X, mouse.Y) - Vector2.new(sp.X, sp.Y)).Magnitude
                            if dist <= fovR and dist < bestDist then
                                local passes = true
                                if wallCheck and myChar then
                                    pickRayParams.FilterDescendantsInstances = { myChar, char }
                                    local dir = desc.Position - camCF.Position
                                    local hit = Workspace:Raycast(camCF.Position, dir, pickRayParams)
                                    passes = (not hit) or hit.Instance:IsDescendantOf(char)
                                end
                                if passes then
                                    best, bestPart, bestRoot, bestDist = plr, desc, root, dist
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestPart, bestRoot
end

--// ========================================================= //--
--//   SILENT AIM - METHOD 1: SimulateProjectile direction      //--
--// ========================================================= //--

task.spawn(function()
    while State.Running do
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local phModule = modules and modules:FindFirstChild("ProjectileHandler")
        if phModule then
            local ok, handler = pcall(require, phModule)
            if ok and type(handler) == "table" and type(handler.SimulateProjectile) == "function" then
                local oldSim = handler.SimulateProjectile
                handler.SimulateProjectile = function(...)
                    if State.Running and Combat.silentAim and CurrentTarget and CurrentTarget.aimPoint then
                        local args = {...}
                        local origin = nil
                        for _, a in ipairs(args) do
                            if typeof(a) == "Instance" and a:IsA("Attachment")
                                and a.Name:find("GunFirePoint") then
                                origin = a.WorldPosition
                                break
                            end
                        end
                        if origin then
                            local delta = CurrentTarget.aimPoint - origin
                            if delta.Magnitude > 0.1 then
                                local newDir = delta.Unit
                                for _, a in ipairs(args) do
                                    if type(a) == "table" then
                                        local hasVec = false
                                        for _, v in ipairs(a) do
                                            if typeof(v) == "Vector3" then hasVec = true; break end
                                        end
                                        if hasVec then
                                            for j, v in ipairs(a) do
                                                if typeof(v) == "Vector3" then
                                                    a[j] = newDir
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    return oldSim(...)
                end
                Diag.simHookInstalled = true
                return
            end
        end
        task.wait(1)
    end
end)

--// ========================================================= //--
--//   SILENT AIM - METHOD 2: direct InflictTarget replication  //--
--// ========================================================= //--

local InflictTargetRemote = nil
local VisualizeBulletRemote = nil

task.spawn(function()
    while State.Running do
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        InflictTargetRemote = remotes and remotes:FindFirstChild("InflictTarget")
        VisualizeBulletRemote = remotes and remotes:FindFirstChild("VisualizeBullet")
        if InflictTargetRemote and VisualizeBulletRemote then break end
        task.wait(1)
    end
end)

local function getFxTable()
    local miscs = ReplicatedStorage:FindFirstChild("Miscs")
    local gv = miscs and miscs:FindFirstChild("GunVisualEffects")
    local common = gv and gv:FindFirstChild("Common")
    if not common then return nil end
    return {
        ChargeLevel = 0,
        HitEffectFolder = common:FindFirstChild("HitEffect"),
        MuzzleFolder = common:FindFirstChild("MuzzleEffect"),
        BloodEffectFolder = common:FindFirstChild("BloodEffect"),
        ExplosionEffectFolder = common:FindFirstChild("ExplosionEffect"),
        GoreEffect = common:FindFirstChild("GoreEffect"),
    }
end

local function sendDirectInflict()
    Diag.remoteLookups += 1
    if not (Combat.silentAim and CurrentTarget and InflictTargetRemote) then return end

    local char = localPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end

    local tabs = getSettingTables(tool)
    local st = tabs and tabs[1]
    if not st then return end

    local c = CurrentTarget.player.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local hrp = c:FindFirstChild("HumanoidRootPart")
    local hd = c:FindFirstChild("Head")
    if not (hum and hrp and hd) or hum.Health <= 0 then return end

    local fx = getFxTable()
    if not fx then return end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    local dist = myRoot and (hrp.Position - myRoot.Position).Magnitude or 50
    if dist > 999 then dist = 999 end

    local ok = pcall(function()
        InflictTargetRemote:InvokeServer("Gun", tool, st, hum, hrp, hd, fx, dist)
    end)
    if ok then
        Diag.directInflicts += 1
    end
end

--// ============================================================ //--
--//   THE PER-SHOT SIGNAL: Fire() clones a Blur into Lighting on   //--
--//   every single shot, in every fire mode. drives BOTH the     //--
--//   bullet tracers AND silent aim Method 2.                    //--
--// ============================================================ //--

keepConn(Lighting.ChildAdded:Connect(function(child)
    if not child:IsA("BlurEffect") then return end

    if Client.bulletTracers and State.Running then
        task.defer(addTracerFromShot)
    end
    if Combat.silentAim and State.Running then
        task.defer(sendDirectInflict)
    end
end))

--// ========================================================= //--
--//   SILENT AIM - METHOD 3: in-flight remote arg rewrite       //--
--// ========================================================= //--

local function redirectArgs(remote, args)
    if not (Combat.silentAim and CurrentTarget and CurrentTarget.aimPoint) then return end

    if remote == InflictTargetRemote then
        if args[1] ~= "Gun" then return end
        local t = CurrentTarget
        local c = t.player and t.player.Character
        if not c then return end
        local hum = c:FindFirstChildOfClass("Humanoid")
        local hrp = c:FindFirstChild("HumanoidRootPart")
        local hd = c:FindFirstChild("Head")
        if hum and hrp and hd then
            args[4], args[5], args[6] = hum, hrp, hd
            Diag.redirectHits += 1
        end

    elseif remote == VisualizeBulletRemote then
        local dirs = args[6]
        local firePoint = args[7]
        if type(dirs) == "table" and typeof(firePoint) == "Instance" and firePoint:IsA("Attachment") then
            local origin = firePoint.WorldPosition
            if (CurrentTarget.aimPoint - origin).Magnitude > 0.1 then
                local newDir = (CurrentTarget.aimPoint - origin).Unit
                for i, v in ipairs(dirs) do
                    if typeof(v) == "Vector3" then
                        dirs[i] = newDir
                    end
                end
            end
        end
    end
end

do
    local oldFireServer, oldInvokeServer

    local function fireBody(self, ...)
        local args = {...}
        if State.Running and Combat.silentAim and CurrentTarget
            and self == VisualizeBulletRemote then
            pcall(redirectArgs, self, args)
            return oldFireServer(self, unpack(args))
        end
        return oldFireServer(self, ...)
    end

    local function invokeBody(self, ...)
        local args = {...}
        if State.Running and Combat.silentAim and CurrentTarget
            and self == InflictTargetRemote then
            pcall(redirectArgs, self, args)
            return oldInvokeServer(self, unpack(args))
        end
        return oldInvokeServer(self, ...)
    end

    local installedFire, installedInvoke = false, false

    if typeof(hookfunction) == "function" then
        installedFire = pcall(function()
            oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, fireBody)
        end)
        installedInvoke = pcall(function()
            oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, invokeBody)
        end)
    end

    if not (installedFire and installedInvoke) then
        pcall(function()
            if typeof(hookmetamethod) ~= "function" then error("no hookmetamethod") end
            local old
            old = hookmetamethod(game, "__namecall", function(self, ...)
                local args = {...}
                if State.Running and Combat.silentAim and CurrentTarget then
                    local method = getnamecallmethod()
                    if (self == InflictTargetRemote and method == "InvokeServer")
                        or (self == VisualizeBulletRemote and method == "FireServer") then
                        pcall(redirectArgs, self, args)
                        return old(self, unpack(args))
                    end
                end
                return old(self, ...)
            end)
            Diag.remoteHookMethod = "namecall(fallback)"
        end)
    else
        Diag.remoteHookMethod = "hookfunction"
    end
end

--// ---------- triggerbot ---------- //--

local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUserService = game:GetService("VirtualUser")

local tbHolding = false
local tbLastAcquireAt = 0
local TB_GRACE = 0.25

local function tbMouseDown()
    if tbHolding then return end
    tbHolding = true
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5, 0, true, game, 1)
    end)
    if not ok then
        pcall(function()
            VirtualUserService:CaptureController()
            VirtualUserService:Button1Down()
        end)
    end
end

local function tbMouseUp()
    if not tbHolding then return end
    tbHolding = false
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5, 0, false, game, 1)
    end)
    if not ok then
        pcall(function()
            VirtualUserService:CaptureController()
            VirtualUserService:Button1Up()
        end)
    end
end

local tbRayParams = RaycastParams.new()
tbRayParams.FilterType = Enum.RaycastFilterType.Exclude
tbRayParams.IgnoreWater = true

-- Mouse-position triggerbot check (silent aim OFF):
-- ray through the ACTUAL mouse position, fires at players under cursor
local function crosshairOnEnemy()
    local char = localPlayer.Character
    if not char then return false end
    if not char:FindFirstChildOfClass("Tool") then return false end

    local vm = Workspace:FindFirstChild("Camera")
    local filter = { char }
    if vm then filter[#filter + 1] = vm end
    tbRayParams.FilterDescendantsInstances = filter

    local mouse = UserInputService:GetMouseLocation()
    local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)

    local result = Workspace:Raycast(ray.Origin, ray.Direction * 5000, tbRayParams)
    if not result or not result.Instance then return false end

    local model = result.Instance:FindFirstAncestorOfClass("Model")
    while model and model ~= Workspace do
        local plr = Players:GetPlayerFromCharacter(model)
        if plr then
            if isFriendly(plr) then return false end
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local myRoot = char:FindFirstChild("HumanoidRootPart")
                local theirRoot = model:FindFirstChild("HumanoidRootPart")
                if myRoot and theirRoot then
                    return (theirRoot.Position - myRoot.Position).Magnitude <= Combat.tbMaxDist
                end
            end
            return false
        end
        model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") or nil
    end
    return false
end

-- FOV-lock triggerbot check (silent aim ON):
-- true when the current FOV-circle lock is alive and within max distance
local function targetValidForTriggerbot(myRoot)
    local t = CurrentTarget
    if not t or not t.root or not myRoot then return false end
    local hum = t.player and t.player.Character
        and t.player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return (t.root.Position - myRoot.Position).Magnitude <= Combat.tbMaxDist
end

--// ---------- combat render loop ---------- //--

local fovOutline = Drawing.new("Circle")
fovOutline.Filled = false; fovOutline.Color = Color3.fromRGB(0, 0, 0)
fovOutline.Visible = false; fovOutline.Transparency = 1
fovOutline.NumSides = 64; fovOutline.Thickness = 2

local fovCircle = Drawing.new("Circle")
fovCircle.Filled = false; fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Visible = false; fovCircle.Transparency = 1
fovCircle.NumSides = 64; fovCircle.Thickness = 1

local cTracerOutline = newLine(2, Color3.fromRGB(0, 0, 0))
local cTracerLine = newLine(1, Color3.fromRGB(255, 255, 255))

local cDebugText = Drawing.new("Text")
cDebugText.Visible = false; cDebugText.Size = 12; cDebugText.Outline = true
cDebugText.Font = 2; cDebugText.Color = ACCENT_DARK; cDebugText.Position = Vector2.new(12, 12)

local combatFrame = 0

RunService.RenderStepped:Connect(function(dt)
    if not State.Running then return end
    combatFrame += 1

    if combatFrame % 10 == 0 then
        pcall(refreshWeaponEdits)
    end

    local myRoot = localPlayer.Character
        and localPlayer.Character:FindFirstChild("HumanoidRootPart")

    -- target acquisition: fuels silent aim AND the target tracer.
    -- also required for the triggerbot's silent-aim FOV-lock path.
    if Combat.silentAim or Combat.tracer then
        local tPlr, tPart, tRoot = pickTarget()
        if tPlr then
            local ball = getBallistics()
            local camPos = Camera.CFrame.Position
            local aimPoint = computeAimPoint(camPos, tPart, tRoot)
            CurrentTarget = { player = tPlr, part = tPart, root = tRoot, aimPoint = aimPoint }
        else
            CurrentTarget = nil
        end
    else
        CurrentTarget = nil
    end

    -- FOV circle: independent toggle
    local mousePos = UserInputService:GetMouseLocation()
    fovCircle.Position = mousePos; fovOutline.Position = mousePos
    fovCircle.Radius = Combat.fovRadius; fovOutline.Radius = Combat.fovRadius
    fovCircle.Thickness = Combat.fovThickness; fovOutline.Thickness = Combat.fovThickness + 1
    fovCircle.Color = Combat.fovColor
    fovCircle.Visible = Combat.fovVisible; fovOutline.Visible = Combat.fovVisible

    -- target tracer: independent toggle
    cTracerLine.Color = Combat.fovColor
    if Combat.tracer and CurrentTarget then
        local sp = Camera:WorldToViewportPoint(CurrentTarget.part.Position)
        if sp.Z > 0 then
            local to = Vector2.new(sp.X, sp.Y)
            cTracerOutline.From = mousePos; cTracerOutline.To = to; cTracerOutline.Visible = true
            cTracerLine.From = mousePos; cTracerLine.To = to; cTracerLine.Visible = true
        else
            cTracerOutline.Visible = false; cTracerLine.Visible = false
        end
    else
        cTracerOutline.Visible = false; cTracerLine.Visible = false
    end

    -- debug HUD with diagnostics
    if Combat.debugHud then
        cDebugText.Text = "sim:" .. (Diag.simHookInstalled and "Y" or "N")
            .. " remote:" .. Diag.remoteHookMethod
            .. " shots:" .. Diag.remoteLookups
            .. " inflicts:" .. Diag.directInflicts
            .. " redirs:" .. Diag.redirectHits
            .. " lock:" .. (CurrentTarget and CurrentTarget.player.Name or "none")
            .. (Combat.fireRateEnabled and (" | rate:" .. Combat.fireRate) or "")
        cDebugText.Visible = true
    else
        cDebugText.Visible = false
    end

    -- triggerbot:
    --   silent aim ON  -> fire while a player is locked inside the FOV circle
    --   silent aim OFF -> fire when the player is under the MOUSE position
    if Combat.triggerbot and not freecamActive then
        local now = os.clock()

        local shouldFire
        if Combat.silentAim then
            shouldFire = targetValidForTriggerbot(myRoot)
        else
            shouldFire = crosshairOnEnemy()
        end
        if shouldFire then tbLastAcquireAt = now end

        local locked = shouldFire or (tbHolding and (now - tbLastAcquireAt) < TB_GRACE)

        if locked then
            tbMouseDown()
        else
            tbMouseUp()
        end
    else
        tbMouseUp()
    end
end)

local function combatShutdown()
    Combat.silentAim = false
    Combat.triggerbot = false
    Combat.noRecoil = false
    Combat.noSpread = false
    Combat.fireRateEnabled = false
    CurrentTarget = nil
    tbMouseUp()
    restoreAllWeapons()
    pcall(function() fovCircle:Remove() end)
    pcall(function() fovOutline:Remove() end)
    pcall(function() cTracerLine:Remove() end)
    pcall(function() cTracerOutline:Remove() end)
    pcall(function() cDebugText:Remove() end)
end

--// ========================================================= //--
--//                    CUSTOM CHARACTER                       //--
--// ========================================================= //--

local CharacterMods = {
    Enabled = false,
    material = "ForceField",
    color = Color3.fromRGB(0, 170, 255),
    transparency = 0.5,
    saved = {},
}

function CharacterMods:stylePart(part)
    if not part:IsA("BasePart") then return end
    if part:FindFirstAncestorOfClass("Tool") then return end

    if not self.saved[part] then
        self.saved[part] = { part.Color, part.Transparency, part.Material }
    end
    pcall(function()
        part.Color = self.color
        part.Transparency = self.transparency
        part.Material = Enum.Material[self.material]
    end)
end

function CharacterMods:apply()
    local char = localPlayer.Character
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        self:stylePart(d)
    end
end

function CharacterMods:revert()
    for part, orig in pairs(self.saved) do
        if part and part.Parent then
            pcall(function()
                part.Color = orig[1]
                part.Transparency = orig[2]
                part.Material = orig[3]
            end)
        end
    end
    for k in pairs(self.saved) do
        if k.Parent == nil then self.saved[k] = nil end
    end
end

function CharacterMods:setEnabled(enabled)
    self.Enabled = enabled
    if enabled then
        self:apply()
    else
        self:revert()
    end
end

keepConn(localPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if CharacterMods.Enabled and State.Running then
        CharacterMods:apply()
    end
end))

keepConn(localPlayer.CharacterAdded:Connect(function(char)
    char.DescendantAdded:Connect(function(d)
        if CharacterMods.Enabled and State.Running then
            task.defer(function()
                CharacterMods:stylePart(d)
            end)
        end
    end)
end))

do
    local char = localPlayer.Character
    if char then
        char.DescendantAdded:Connect(function(d)
            if CharacterMods.Enabled and State.Running then
                task.defer(function()
                    CharacterMods:stylePart(d)
                end)
            end
        end)
    end
end

local function clientShutdown()
    if freecamActive then
        freecamActive = false
        setFreecamBodyFrozen(false)
        for _, g in ipairs(hiddenGuis) do pcall(function() g.Enabled = true end) end
        hiddenGuis = {}
        HUD.Enabled = false
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        pcall(function() UserInputService.MouseIconEnabled = true end)
        pcall(function() Camera.CameraType = Enum.CameraType.Custom end)
    end
    pcall(function()
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Anchored = false end
    end)

    setZoomHolding(false)
    applyFullbright(false)
    applyForceDay(false)

    for i = #tracerEntries, 1, -1 do
        removeTracer(i)
    end

    espShutdown()
    combatShutdown()

    CharacterMods.Enabled = false
    CharacterMods:revert()

    for _, conn in ipairs(clientConnections) do
        if conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
    end

    pcall(function() HUD:Destroy() end)
end

--// ========================================================= //--
--//          CLIENT RENDER LOOP (zoom, freecam, tracers,      //--
--//          fullbright, force day)                           //--
--// ========================================================= //--

local clientFrame = 0

RunService.RenderStepped:Connect(function(dt)
    if not State.Running then return end
    clientFrame += 1

    if zoomHolding then
        pcall(function()
            if Camera.FieldOfView ~= Client.zoomFov then
                Camera.FieldOfView = Client.zoomFov
            end
        end)
    else
        pcall(function()
            local f = Camera.FieldOfView
            if f ~= Client.zoomFov then zoomSavedFov = f end
        end)
    end

    -- fullbright enforcement (re-applies every frame vs game lighting)
    if Client.fullbright then
        if Lighting.Brightness ~= 3 then Lighting.Brightness = 3 end
        if Lighting.FogEnd ~= 1e6 then Lighting.FogEnd = 1e6 end
        if Lighting.FogStart ~= 1e6 then Lighting.FogStart = 1e6 end
        if Lighting.GlobalShadows ~= false then Lighting.GlobalShadows = false end
        if Lighting.ExposureCompensation ~= 1.2 then Lighting.ExposureCompensation = 1.2 end
        if Lighting.Ambient ~= white3 then Lighting.Ambient = white3; Lighting.OutdoorAmbient = white3 end
        if Lighting.ColorShift_Top ~= white3 then Lighting.ColorShift_Top = white3; Lighting.ColorShift_Bottom = white3 end
        for _, fx in ipairs(lightingFx) do
            if fx:IsA("Atmosphere") then
                if fx.Density ~= 0 then fx.Density = 0 end
                if fx.Haze ~= 0 then fx.Haze = 0 end
            elseif fx:IsA("DepthOfFieldEffect") then
                if fx.Enabled then fx.Enabled = false end
            end
        end
    end

    -- force day enforcement
    if Client.forceDay then
        if Lighting.ClockTime ~= 14 then
            pcall(function() Lighting:SetMinutesAfterMidnight(14 * 60) end)
        end
    end

    if freecamActive then
        if Camera.CameraType ~= Enum.CameraType.Scriptable then
            Camera.CameraType = Enum.CameraType.Scriptable
        end
        if clientFrame % 30 == 0 then setFreecamBodyFrozen(true) end
        if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
        local delta = UserInputService:GetMouseDelta()
        if delta.Magnitude > 0 then
            local sens = 0.22 * math.pi / 180
            camYaw = camYaw - delta.X * sens
            camPitch = math.clamp(camPitch - delta.Y * sens, -1.55, 1.55)
        end
        local rot = CFrame.fromEulerAnglesYXZ(camPitch, camYaw, 0)
        local fwd, right = rot.LookVector, rot.RightVector
        local move = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += fwd end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= fwd end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then move += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move += Vector3.new(0, -1, 0) end
        if move.Magnitude > 0 then
            local slow = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            local speed = slow and Client.slowSpeed or Client.flySpeed
            camPos += move.Unit * speed * dt
            if not SlowLabel then SlowLabel = HUD:FindFirstChild("SlowLabel", true) end
            if SlowLabel then
                SlowLabel.Text = "[SHIFT] slow: " .. (slow and "ON" or "OFF")
                SlowLabel.TextColor3 = slow and ACCENT or Color3.fromRGB(200, 215, 235)
            end
        end
        if not PosLabel then PosLabel = HUD:FindFirstChild("PosLabel", true) end
        if PosLabel then
            PosLabel.Text = string.format("pos: %.0f, %.0f, %.0f", camPos.X, camPos.Y, camPos.Z)
        end
        Camera.CFrame = CFrame.new(camPos) * rot
    end

    pcall(updateTracers, os.clock())
end)

--// ========================================================= //--
--//              CONFIG SAVE SYSTEM                            //--
--// ========================================================= //--

local SAVES_FOLDER = "autofarm_saves"

local SERIALIZABLE_KEYS = {
    -- combat
    "silentAim", "wallCheck", "triggerbot", "noRecoil", "noSpread",
    "tbMaxDist", "targetPart", "fovVisible", "fovRadius", "fovThickness",
    "tracer", "fireRateEnabled", "fireRate", "debugHud",
    -- esp
    "enabled", "boxes", "names", "dist", "health", "held", "skel",
    "highlight", "viewcheck", "espThickness", "renderDist",
    "boxStyle", "textFont", "textSize",
    -- client
    "bulletTracers", "tracerTime", "tracerMax",
    "zoomFov", "flySpeed", "slowSpeed", "fullbright", "forceDay",
    -- character mods
    "transparency",
}

local COLOR_KEYS = {
    { tbl = Combat, key = "fovColor", name = "fovColor" },
    { tbl = Client, key = "tracerColor", name = "tracerColor" },
    { tbl = CharacterMods, key = "color", name = "charColor" },
    { tbl = ESP, key = "visCol", name = "visCol" },
    { tbl = ESP, key = "hidCol", name = "hidCol" },
    { tbl = ESP, key = "frndCol", name = "frndCol" },
}

local KEY_TABLES = { Combat, ESP, Client, CharacterMods, State }

local function stateTableFor(key)
    for _, tbl in ipairs(KEY_TABLES) do
        if tbl[key] ~= nil and type(tbl[key]) ~= "function" then
            return tbl
        end
    end
    return nil
end

--// ---------- widget registry (UI sync on config load) ---------- //--

local widgetRegistry = {}
local groupRegistry = {}

local function reg(key, widget)
    if widget then
        widgetRegistry[key] = widget
    end
end

local function regGroup(name, widget, applyFn)
    groupRegistry[name] = { widget = widget, apply = applyFn }
end

local function syncUIFromState()
    for key, w in pairs(widgetRegistry) do
        local tbl = stateTableFor(key)
        if tbl and tbl[key] ~= nil then
            pcall(function() w:SetValue(tbl[key]) end)
        end
    end
end

local function ensureSavesFolder()
    local ok = pcall(function()
        if isfolder and not isfolder(SAVES_FOLDER) then
            makefolder(SAVES_FOLDER)
        end
    end)
    return ok
end

local function getSavesList()
    local list = {}
    if not ensureSavesFolder() or typeof(listfiles) ~= "function" then return list end
    pcall(function()
        for _, f in ipairs(listfiles(SAVES_FOLDER)) do
            local name = f:match("([^%\\%/]+)%.json$")
            if name then list[#list + 1] = name end
        end
    end)
    table.sort(list)
    return list
end

local function savePath(name)
    return SAVES_FOLDER .. "/" .. name .. ".json"
end

local function serializeCurrentConfig()
    local data = {}
    for _, key in ipairs(SERIALIZABLE_KEYS) do
        local tbl = stateTableFor(key)
        if tbl then
            data[key] = tbl[key]
        end
    end
    local colors = {}
    for _, c in ipairs(COLOR_KEYS) do
        colors[c.name] = colorToTable(c.tbl[c.key])
    end
    data.colors = colors
    data.FarmSettings = State.FarmSettings
    data.Whitelist = Whitelist
    return HttpService:JSONEncode(data)
end

local function loadConfig(name)
    local ok, json = pcall(function()
        return readfile(savePath(name))
    end)
    if not ok or not json then
        notify("Config", "could not read '" .. tostring(name) .. "'")
        return false
    end
    local ok2, data = pcall(function()
        return HttpService:JSONDecode(json)
    end)
    if not ok2 or type(data) ~= "table" then
        notify("Config", "corrupt config '" .. tostring(name) .. "'")
        return false
    end

    for _, key in ipairs(SERIALIZABLE_KEYS) do
        if data[key] ~= nil then
            local tbl = stateTableFor(key)
            if tbl and type(data[key]) == type(tbl[key]) then
                tbl[key] = data[key]
            end
        end
    end
    if type(data.colors) == "table" then
        for _, c in ipairs(COLOR_KEYS) do
            local col = tableToColor(data.colors[c.name])
            if col then c.tbl[c.key] = col end
        end
    end
    if type(data.FarmSettings) == "table" then
        State.FarmSettings = {}
        for k, v in pairs(data.FarmSettings) do State.FarmSettings[k] = v == true end
    end
    if type(data.Whitelist) == "table" then
        Whitelist = {}
        for k, v in pairs(data.Whitelist) do Whitelist[k] = v == true end
    end

    -- live-apply side-effect toggles
    setNoPromptDelay(State.NoPromptDelay)
    setAntiAfk(State.AntiAfk)
    applyFullbright(Client.fullbright)
    applyForceDay(Client.forceDay)
    if CharacterMods.Enabled then CharacterMods:apply() end
    pcall(refreshWeaponEdits)

    -- UI SYNC: checkbox groups first (their callbacks write state),
    -- then individual widgets (toggles re-check, sliders move,
    -- dropdowns select, colors update)
    pcall(function()
        if groupRegistry.combatModules then
            pcall(groupRegistry.combatModules.apply, groupRegistry.combatModules.widget)
        end
        if groupRegistry.espModules then
            pcall(groupRegistry.espModules.apply, groupRegistry.espModules.widget)
        end
        if groupRegistry.farmMethods then
            pcall(groupRegistry.farmMethods.apply, groupRegistry.farmMethods.widget)
        end
    end)
    pcall(syncUIFromState)

    notify("Config", "loaded '" .. name .. "' (UI synced)")
    return true
end

local function saveConfig(name)
    if not name or name == "" then
        notify("Config", "invalid save name")
        return false
    end
    local ok = pcall(function()
        ensureSavesFolder()
        writefile(savePath(name), serializeCurrentConfig())
    end)
    if ok then notify("Config", "saved '" .. name .. "'") end
    return ok
end

local function deleteSave(name)
    local ok = pcall(function()
        if isfile(savePath(name)) then
            delfile(savePath(name))
        end
    end)
    if ok then notify("Config", "deleted '" .. name .. "'") end
    return ok
end

local function clearAllSaves()
    local ok = pcall(function()
        for _, name in ipairs(getSavesList()) do
            delfile(savePath(name))
        end
    end)
    if ok then notify("Config", "cleared all saves") end
    return ok
end

--// ---------- Task Definitions ---------- //--

local Tasks = {}

--// Task: Robbable Vans //--
table.insert(Tasks, {
    name = "Van Farm",

    getVanPrompt = function(van)
        local stealScript = van:FindFirstChild("Steal Script")
        if not stealScript then return nil end
        local scriptsPart = stealScript:FindFirstChild("Scripts")
        if not scriptsPart then return nil end
        return scriptsPart:FindFirstChild("ProximityPrompt")
    end,

    getTargets = function(self)
        local targets = {}
        for _, van in ipairs(workspace:GetChildren()) do
            if van.Name == "Robbable Van" and van:IsA("Model") then
                local prompt = self.getVanPrompt(van)
                if prompt and prompt.Enabled then
                    table.insert(targets, {
                        prompt = prompt,
                        position = van:GetPivot(),
                    })
                end
            end
        end
        return targets
    end,
})

--// Task: Bank Robbery //--
table.insert(Tasks, {
    name = "Bank Robbery",
    c4Prompt = nil,
    dufflebagValue = nil,
    numberValue = nil,
    lastValueSearch = 0,
    EXPLOSION_WAIT = 5.25,
    GRAB_TIMEOUT = 2,

    isReady = function(self)
        local doorPrompt = self:getDoorPrompt()
        if doorPrompt and doorPrompt.Enabled then
            return true
        end
        return self:findC4Tool() ~= nil or self:getBagCount() > 0
    end,

    findBagValues = function(self)
        local now = os.clock()
        if now - self.lastValueSearch < 1 then return end
        self.lastValueSearch = now

        local searchRoots = {
            localPlayer,
            localPlayer.Character,
            localPlayer:FindFirstChildOfClass("Backpack"),
            workspace:FindFirstChild("BankRobberyType"),
        }

        for _, root in ipairs(searchRoots) do
            if root then
                local bag = root:FindFirstChild("dufflebag", true)
                if bag and bag:IsA("BoolValue") then
                    local num = root:FindFirstChild("number", true)
                    if num and num:IsA("NumberValue") then
                        self.dufflebagValue = bag
                        self.numberValue = num
                        return
                    end
                end
            end
        end

        local bag = workspace:FindFirstChild("dufflebag", true)
        local num = workspace:FindFirstChild("number", true)
        if bag and bag:IsA("BoolValue") and num and num:IsA("NumberValue") then
            self.dufflebagValue = bag
            self.numberValue = num
        end
    end,

    getBagCount = function(self)
        local valid = self.numberValue and self.numberValue.Parent
            and self.dufflebagValue and self.dufflebagValue.Parent

        if not valid then
            self:findBagValues()
            valid = self.numberValue and self.numberValue.Parent
        end

        if valid then
            return math.clamp(self.numberValue.Value, 0, 5)
        end
        return 0
    end,

    findC4Prompt = function(self)
        for _, model in ipairs(workspace:GetChildren()) do
            if model.Name == "Model" and model:IsA("Model") then
                local c4 = model:FindFirstChild("C4")
                if c4 then
                    local mesh = c4:FindFirstChild("c41")
                    if mesh then
                        local attachment = mesh:FindFirstChild("Attachment")
                        if attachment then
                            local prompt = attachment:FindFirstChild("ProximityPrompt")
                            if prompt and prompt:IsA("ProximityPrompt") then
                                return prompt
                            end
                        end
                    end
                end
            end
        end
        return nil
    end,

    getDoorPrompt = function(self)
        local bank = workspace:FindFirstChild("BankRobberyType")
        if not bank then return nil end
        local xd = bank:FindFirstChild("xd")
        if not xd then return nil end
        local prompt = xd:FindFirstChild("ProximityPrompt")
        if prompt and prompt:IsA("ProximityPrompt") then
            return prompt
        end
        return nil
    end,

    getPickupPrompts = function(self)
        local prompts = {}
        local bank = workspace:FindFirstChild("BankRobberyType")
        if not bank then return prompts end
        local holder = bank:FindFirstChild("MoneyPromptHolder")
        if not holder then return prompts end

        for _, materialName in ipairs({ "Cash", "Gold" }) do
            local group = holder:FindFirstChild(materialName)
            if group then
                for _, model in ipairs(group:GetChildren()) do
                    local tier1 = model:FindFirstChild(materialName .. "1")
                    if tier1 then
                        local prompt = tier1:FindFirstChild(materialName)
                        if prompt and prompt:IsA("ProximityPrompt") then
                            table.insert(prompts, prompt)
                        end
                    end
                end
            end
        end
        return prompts
    end,

    getSellPrompt = function(self)
        local desk = workspace:FindFirstChild("Desk")
        if not desk then return nil end
        local sellPart = desk:FindFirstChild("sellpart")
        if not sellPart then return nil end
        local prompt = sellPart:FindFirstChild("ProximityPrompt")
        if prompt and prompt:IsA("ProximityPrompt") then
            return prompt
        end
        return nil
    end,

    plantC4 = function(self, doorPrompt, c4Tool)
        for _ = 1, 3 do
            if not State.Running then return false end

            equipTool(c4Tool)
            task.wait(0.2)

            teleportTo(getPromptPosition(doorPrompt))
            task.wait(0.15)
            firePrompt(doorPrompt)

            local deadline = os.clock() + 3
            repeat
                task.wait(0.1)
                if not doorPrompt.Parent then return true end
            until not doorPrompt.Enabled or os.clock() > deadline or not State.Running

            if not doorPrompt.Enabled then
                return true
            end

            task.wait(0.5)
            if not c4Tool.Parent then return false end
        end
        return false
    end,

    sellBag = function(self)
        local sellPrompt = self:getSellPrompt()
        if not sellPrompt then return end

        for _ = 1, 3 do
            if not State.Running then return end
            if self:getBagCount() == 0 then return end

            unequipTools()
            teleportTo(getPromptPosition(sellPrompt))
            task.wait(0.15)
            firePrompt(sellPrompt)

            local deadline = os.clock() + 3
            while os.clock() < deadline and State.Running do
                if self:getBagCount() == 0 then
                    return
                end
                task.wait(0.05)
            end
            task.wait(0.25)
        end
    end,

    findC4Tool = function(self)
        for _, container in ipairs({
            localPlayer:FindFirstChildOfClass("Backpack"),
            localPlayer.Character,
        }) do
            if container then
                for _, item in ipairs(container:GetChildren()) do
                    if item:IsA("Tool") and item.Name:lower():find("c4") then
                        return item
                    end
                end
            end
        end
        return nil
    end,

    waitForGrab = function(self, prompt, bagBefore)
        local deadline = os.clock() + self.GRAB_TIMEOUT
        while os.clock() < deadline and State.Running do
            if not prompt.Parent then return true end
            if not prompt.Enabled then return true end
            if self:getBagCount() > bagBefore then return true end
            task.wait(0.05)
        end
        return false
    end,

    run = function(self)
        if not State.Running then return false end

        self.lastValueSearch = 0
        self:findBagValues()

        local doorPrompt = self:getDoorPrompt()

        local c4Tool = self:findC4Tool()
        if not c4Tool then
            if not doorPrompt or not doorPrompt.Enabled then
                return false
            end

            if not self.c4Prompt or not self.c4Prompt.Parent then
                self.c4Prompt = self:findC4Prompt()
            end
            local c4Prompt = self.c4Prompt
            if not c4Prompt then
                return false
            end

            unequipTools()
            teleportTo(getPromptPosition(c4Prompt))
            task.wait(0.15)
            firePrompt(c4Prompt)

            local deadline = os.clock() + 5
            while os.clock() < deadline and State.Running do
                task.wait(0.1)
                c4Tool = self:findC4Tool()
                if c4Tool then break end
            end
            if not c4Tool then
                return false
            end
        end

        if not doorPrompt or not doorPrompt.Parent then
            doorPrompt = self:getDoorPrompt()
        end
        if not doorPrompt then
            return false
        end
        if not self:plantC4(doorPrompt, c4Tool) then
            return false
        end

        task.wait(self.EXPLOSION_WAIT)

        if not State.Running then return false end

        local grabbed = 0

        for _, prompt in ipairs(self:getPickupPrompts()) do
            if not State.Running then break end
            if not (prompt.Parent and prompt.Enabled) then continue end

            if self:getBagCount() >= 5 then
                self:sellBag()
                if not State.Running then break end
            end

            local bagBefore = self:getBagCount()

            local ok = false
            for _ = 1, 2 do
                if not State.Running then break end
                if not (prompt.Parent and prompt.Enabled) then
                    ok = true
                    break
                end

                unequipTools()
                teleportTo(getPromptPosition(prompt))
                task.wait(State.NoPromptDelay and 0 or 0.1)
                firePrompt(prompt)

                if self:waitForGrab(prompt, bagBefore) then
                    ok = true
                    break
                end
                task.wait(0.1)
            end

            if ok then
                grabbed += 1
            end
        end

        if self:getBagCount() > 0 then
            self:sellBag()
        end

        return true
    end,
})

--// ---------- Task Runner ---------- //--

local function isTaskEnabled(t)
    return State.FarmSettings[t.name] == true
end

local function startTask(t)
    task.spawn(function()
        while State.Running do
            if isTaskEnabled(t) then
                local ready = true
                if t.isReady then
                    local ok, r = pcall(t.isReady, t)
                    ready = ok and r
                end

                if ready and acquireLock(t.name) then
                    local ok, result
                    if t.run then
                        ok, result = pcall(t.run, t)
                        if not ok then
                            warn("[AutoFarm] task '" .. t.name .. "' errored: " .. tostring(result))
                        end
                    else
                        ok, result = pcall(t.getTargets, t)
                        if ok and result and #result > 0 then
                            for _, target in ipairs(result) do
                                if not State.Running then break end
                                if target.prompt.Enabled then
                                    teleportTo(target.position)
                                    task.wait(State.NoPromptDelay and 0 or 0.15)
                                    firePrompt(target.prompt)
                                end
                            end
                            releaseLock(t.name)
                            task.wait(0.05)
                            continue
                        end
                    end
                    releaseLock(t.name)
                end
                task.wait(0.25)
            else
                task.wait(0.25)
            end
        end
    end)
end

for _, t in ipairs(Tasks) do
    startTask(t)
end

--// ========================================================= //--
--//                          UI                                //--
--// ========================================================= //--

local window = Library.new("chicago_life")

local BOX_STYLES = { "Bounding Box", "Corner Brackets", "Angular" }
local ESP_FONTS = { "UI [0]", "System [1]", "Plex [2]", "Monospace [3]" }
local TARGET_PARTS = { "HumanoidRootPart", "Head", "Torso", "Find Closest Part" }

--// Tab 1: General & Stats //--
local generalTab = window:CreateTab("General & Stats")

do
    generalTab:AddLabel("WELCOME, " .. localPlayer.DisplayName:upper() .. " [" .. localPlayer.Name .. "]")
    generalTab:AddLabel("SYSTEM STATUS: ONLINE / SECURE")

    generalTab:AddLabel("# GAME INFO")

    local gameName = game.Name or "Unknown"
    pcall(function()
        gameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or gameName
    end)

    local upTimeLabel = generalTab:AddLabel("session uptime: 0s")
    generalTab:AddLabel("game: " .. gameName)
    generalTab:AddLabel("place id: " .. game.PlaceId)
    generalTab:AddLabel("job id: " .. game.JobId)
    generalTab:AddLabel("server time: " .. os.date("%H:%M:%S UTC", Workspace:GetServerTimeNow()))

    generalTab:AddLabel("# SESSION STATS")

    local statFramesLabel = generalTab:AddLabel("fps: --")
    local statPingLabel = generalTab:AddLabel("ping: -- ms")
    local statPlrLabel = generalTab:AddLabel("players: --/--")
    generalTab:AddLabel("max players: " .. Players.MaxPlayers)

    generalTab:AddLabel("# ACCOUNT INFO")

    generalTab:AddLabel("account age: " .. localPlayer.AccountAge .. " days")
    generalTab:AddLabel("user id: " .. localPlayer.UserId)

    generalTab:AddLabel("# HARDWARE")

    local statMemLabel = generalTab:AddLabel("memory: -- mb")

    task.spawn(function()
        while State.Running do
            task.wait(2)

            pcall(function()
                local uptimeSec = math.floor(os.clock() - scriptStartClock)
                local mins = math.floor(uptimeSec / 60)
                local secs = uptimeSec % 60
                if upTimeLabel then
                    upTimeLabel.Text = "session uptime: " .. mins .. "m " .. secs .. "s"
                end
            end)
            pcall(function()
                if statFramesLabel then statFramesLabel.Text = "fps: " .. math.floor(fpsSmooth + 0.5) end
            end)
            pcall(function()
                local ping = 0
                pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
                if statPingLabel then statPingLabel.Text = "ping: " .. math.floor(ping) .. " ms" end
            end)
            pcall(function()
                if statPlrLabel then
                    statPlrLabel.Text = "players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
                end
            end)
            pcall(function()
                if statMemLabel then
                    statMemLabel.Text = "memory: " .. math.floor(Stats:GetTotalMemoryUsageMb()) .. " mb"
                end
            end)
        end
    end)

    generalTab:AddLabel("# ACTIONS")

    generalTab:AddButton("Execute Diagnostic Scan", function()
        local ping = "n/a"
        pcall(function()
            ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) .. "ms"
        end)
        print("[chicagolife]: Diagnostic scan -> fps " .. math.floor(fpsSmooth)
            .. " | ping " .. ping
            .. " | players " .. #Players:GetPlayers()
            .. " | uptime " .. math.floor(os.clock() - scriptStartClock) .. "s")
    end)

    generalTab:AddButton("Rejoin Server", function()
        TeleportService:Teleport(game.PlaceId, localPlayer)
    end)
end

--// Tab 2: Combat Mods //--
local combatTab = window:CreateTab("Combat Mods")

combatTab:AddLabel("COMBAT MODULES")

regGroup("combatModules", combatTab:AddCheckboxGroup("Primary Combat Modules",
    { "Silent Aim", "Wallcheck", "Triggerbot" }, function(activeStates)
        Combat.silentAim = activeStates["Silent Aim"] == true
        Combat.wallCheck = activeStates["Wallcheck"] == true
        Combat.triggerbot = activeStates["Triggerbot"] == true
        if not Combat.triggerbot then tbMouseUp() end
    end), function(w)
        w:SetValue({
            ["Silent Aim"] = Combat.silentAim,
            ["Wallcheck"] = Combat.wallCheck,
            ["Triggerbot"] = Combat.triggerbot,
        })
    end)

reg("tbMaxDist", combatTab:AddSlider("Triggerbot Max Distance", 50, 2000, 1000, function(v)
    Combat.tbMaxDist = v
end))

reg("targetPart", combatTab:AddDropdown("Combat Target Part", TARGET_PARTS, "HumanoidRootPart", function(v)
    Combat.targetPart = v
end))

reg("debugHud", combatTab:AddToggle("Debug HUD", false, function(v)
    Combat.debugHud = v
end))

combatTab:AddLabel("FIELD OF VIEW")

reg("fovVisible", combatTab:AddToggle("FOV Circle", false, function(v)
    Combat.fovVisible = v
end))

reg("tracer", combatTab:AddToggle("Target Tracer", false, function(v)
    Combat.tracer = v
end))

reg("fovRadius", combatTab:AddSlider("FOV Circle Radius", 10, 500, 100, function(v)
    Combat.fovRadius = v
end))

reg("fovColor", combatTab:AddColorPicker("FOV Circle Color", Color3.fromRGB(255, 255, 255), function(c)
    Combat.fovColor = c
end))

reg("fovThickness", combatTab:AddSlider("FOV Circle Thickness", 1, 5, 1, function(v)
    Combat.fovThickness = v
end))

combatTab:AddLabel("WEAPON MODIFICATIONS")

reg("noRecoil", combatTab:AddToggle("No Recoil", false, function(v)
    Combat.noRecoil = v
    pcall(refreshWeaponEdits)
end))

reg("noSpread", combatTab:AddToggle("No Spread", false, function(v)
    Combat.noSpread = v
    pcall(refreshWeaponEdits)
end))

reg("fireRateEnabled", combatTab:AddToggle("Fire Rate Enabled", false, function(v)
    Combat.fireRateEnabled = v
    pcall(refreshWeaponEdits)
end))

-- DECIMAL-STEP SLIDER: explicit 0.005 step so the default 0.115
-- (Fully Draco's real fire rate) and fine adjustments are all
-- reachable. Auto-step would give 0.01 since the min 0.01 has a
-- decimal — 0.005 keeps it finer AND makes 0.115 exact.
reg("fireRate", combatTab:AddSlider("Weapon Fire Rate (seconds)", 0.01, 1, 0.115,
    function(v)
        Combat.fireRate = v
        if Combat.fireRateEnabled then
            pcall(refreshWeaponEdits)
        end
    end, 0.005))

--// Tab 3: Visuals & ESP //--
local visTab = window:CreateTab("Visuals & ESP")

visTab:AddLabel("ESP MODULES")

reg("enabled", visTab:AddToggle("ESP Enabled", false, function(v)
    ESP.enabled = v
end))

regGroup("espModules", visTab:AddCheckboxGroup("Primary ESP Modules",
    { "Boxes", "Names", "Distance", "Health Bar", "Skeleton", "Highlight", "Held Item", "Viewcheck" }, function(activeStates)
        ESP.boxes = activeStates["Boxes"] == true
        ESP.names = activeStates["Names"] == true
        ESP.dist = activeStates["Distance"] == true
        ESP.health = activeStates["Health Bar"] == true
        ESP.skel = activeStates["Skeleton"] == true
        ESP.highlight = activeStates["Highlight"] == true
        ESP.held = activeStates["Held Item"] == true
        ESP.viewcheck = activeStates["Viewcheck"] == true
    end), function(w)
        w:SetValue({
            ["Boxes"] = ESP.boxes,
            ["Names"] = ESP.names,
            ["Distance"] = ESP.dist,
            ["Health Bar"] = ESP.health,
            ["Skeleton"] = ESP.skel,
            ["Highlight"] = ESP.highlight,
            ["Held Item"] = ESP.held,
            ["Viewcheck"] = ESP.viewcheck,
        })
    end)

reg("espThickness", visTab:AddSlider("ESP Thickness", 1, 5, 1, function(v)
    ESP.espThickness = v
end))

reg("renderDist", visTab:AddSlider("ESP Render Distance", 0, 5000, 5000, function(v)
    ESP.renderDist = v
end))

reg("visCol", visTab:AddColorPicker("Visible Color", Color3.fromRGB(255, 255, 0), function(c)
    ESP.visCol = c
end))

reg("hidCol", visTab:AddColorPicker("Hidden Color", Color3.fromRGB(255, 255, 255), function(c)
    ESP.hidCol = c
end))

reg("frndCol", visTab:AddColorPicker("Friendly Color", Color3.fromRGB(0, 255, 0), function(c)
    ESP.frndCol = c
end))

reg("boxStyle", visTab:AddDropdown("ESP Boxes", BOX_STYLES, "Bounding Box", function(v)
    ESP.boxStyle = v
end))

reg("textFont", visTab:AddDropdown("ESP Text", ESP_FONTS, "Plex [2]", function(v)
    ESP.textFont = v
end))

reg("textSize", visTab:AddSlider("ESP Text Size", 9, 16, 11, function(v)
    ESP.textSize = v
end))

--// Tab 4: Game Specific (auto farm + vehicles) //--
local gameTab = window:CreateTab("Game Specific")

gameTab:AddLabel("AUTO FARM")

reg("NoPromptDelay", gameTab:AddToggle("No Prompt Delay", false, function(value)
    setNoPromptDelay(value)
end))

reg("AntiAfk", gameTab:AddToggle("Anti Idle / AFK", false, function(value)
    setAntiAfk(value)
end))

regGroup("farmMethods", gameTab:AddCheckboxGroup("Farm Methods", { "Van Farm", "Bank Robbery" }, function(selected)
    for name, on in pairs(selected) do
        State.FarmSettings[name] = on
    end
end), function(w)
    w:SetValue({
        ["Van Farm"] = State.FarmSettings["Van Farm"] == true,
        ["Bank Robbery"] = State.FarmSettings["Bank Robbery"] == true,
    })
end)

gameTab:AddLabel("CAR MODIFICATIONS")

gameTab:AddToggle("Car Mods Enabled", false, function(value)
    CarMods:setEnabled(value)
end)

local function carSlider(text, min, max, default, key)
    local slider = gameTab:AddSlider(text, min, max, default, function(value)
        CarMods.values[key] = value
        if CarMods.Enabled then
            CarMods:apply()
        end
    end)
    CarMods.sliderRefs[key] = slider
end

carSlider("Acceleration", 1, 1000, 35, "acceleration")
carSlider("Deceleration", 1, 1000, 35, "deceleration")
carSlider("Braking Strength", 1, 1000, 105, "braking")
carSlider("Hand Braking Strength", 1, 25000, 9000, "handBrakeTorque")
carSlider("Forward Max Speed", 1, 1000, 70, "forwardMaxSpeed")
carSlider("Reverse Max Speed", 1, 1000, 30, "reverseMaxSpeed")

gameTab:AddButton("Set to Default", function()
    CarMods:resetToDefaults()
end)

gameTab:AddLabel("SCOOTER MODIFICATIONS")

gameTab:AddToggle("Scooter Mods Enabled", false, function(value)
    ScooterMods:setEnabled(value)
end)

local function scooterSlider(text, min, max, default, key)
    local slider = gameTab:AddSlider(text, min, max, default, function(value)
        ScooterMods.values[key] = value
        if ScooterMods.Enabled then
            ScooterMods:apply()
        end
    end)
    ScooterMods.sliderRefs[key] = slider
end

scooterSlider("Forward Max Speed", 1, 1000, 35, "Forwards Speed")
scooterSlider("Reverse Max Speed", 1, 1000, 35, "Reverse Speed")

gameTab:AddButton("Set to Default", function()
    ScooterMods:resetToDefaults()
end)

--// Tab 5: Client Settings //--
local clientTab = window:CreateTab("Client Settings")

clientTab:AddLabel("ZOOM")

clientTab:AddKeybind("Zoom Key", Enum.KeyCode.Z, function(key)
    if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
        Client.zoomKey = key
    end
end)

reg("zoomFov", clientTab:AddSlider("Zoom FOV", 5, 30, 10, function(value)
    Client.zoomFov = value
    if zoomHolding then
        pcall(function() Camera.FieldOfView = value end)
    end
end))

clientTab:AddLabel("FREECAM")

clientTab:AddKeybind("Toggle Freecam", Enum.KeyCode.V, function()
    toggleFreecam()
end)

reg("flySpeed", clientTab:AddSlider("Fly Speed", 5, 120, 40, function(value)
    Client.flySpeed = value
end))

reg("slowSpeed", clientTab:AddSlider("Slow Speed", 1, 40, 8, function(value)
    Client.slowSpeed = value
end))

clientTab:AddLabel("BULLET TRACERS")

reg("bulletTracers", clientTab:AddToggle("Bullet Tracers", false, function(value)
    Client.bulletTracers = value
    if not value then
        for i = #tracerEntries, 1, -1 do
            removeTracer(i)
        end
    end
end))

reg("tracerColor", clientTab:AddColorPicker("Tracer Color", Color3.fromRGB(0, 170, 255), function(c)
    Client.tracerColor = c
end))

-- DECIMAL-STEP SLIDER: min 0.5 is a decimal so auto-mode already gives
-- 0.1 steps, and the label now shows e.g. "3.5" cleanly instead of
-- rounding to whole seconds.
reg("tracerTime", clientTab:AddSlider("Time On Screen", 0.5, 10, 3, function(value)
    Client.tracerTime = value
end))

reg("tracerMax", clientTab:AddSlider("Max Tracers", 1, 200, 50, function(value)
    Client.tracerMax = value
end))

clientTab:AddLabel("CUSTOM CHARACTER")

clientTab:AddToggle("Custom Character", false, function(value)
    CharacterMods:setEnabled(value)
end)

reg("charColor", clientTab:AddColorPicker("Character Color", Color3.fromRGB(0, 170, 255), function(c)
    CharacterMods.color = c
    if CharacterMods.Enabled then
        CharacterMods:apply()
    end
end))

clientTab:AddDropdown("Character Material",
    { "ForceField", "Neon", "Glass", "Metal", "DiamondPlate", "Plastic", "SmoothPlastic", "Ice", "Marble", "Granite" },
    "ForceField", function(v)
    CharacterMods.material = v
    if CharacterMods.Enabled then
        CharacterMods:apply()
    end
end)

reg("transparency", clientTab:AddSlider("Character Transparency", 0, 100, 50, function(value)
    CharacterMods.transparency = value / 100
    if CharacterMods.Enabled then
        CharacterMods:apply()
    end
end))

clientTab:AddLabel("LIGHTING FX")

reg("fullbright", clientTab:AddToggle("Fullbright", false, function(v)
    applyFullbright(v)
end))

reg("forceDay", clientTab:AddToggle("Force Day", false, function(v)
    applyForceDay(v)
end))

clientTab:AddLabel("MENU")

-- Toggle Menu keybind (default RightShift, like brisk):
-- opens/closes the main window with its open/close tween animation
clientTab:AddKeybind("Toggle Menu", Enum.KeyCode.RightShift, function()
    window:Toggle()
end)

--// Tab 6: System Settings //--
local settingsTab = window:CreateTab("System Settings")

settingsTab:AddLabel("CONFIG SAVES")

local selectedSave = nil
local pendingSaveName = ""

do
    local list = getSavesList()
    if #list > 0 then
        settingsTab:AddDropdown("Select Save", list, list[1], function(v)
            selectedSave = v
        end)
        selectedSave = list[1]
    else
        settingsTab:AddLabel("no saves on disk")
    end
end

settingsTab:AddButton("Refresh Save List", function()
    local list = getSavesList()
    notify("Config", "refreshed (" .. #list .. " saves) — rejoin or reload if dropdown is stale")
    if #list > 0 then
        selectedSave = list[1]
    else
        selectedSave = nil
    end
end)

settingsTab:AddButton("Load Selected Save", function()
    if selectedSave then
        loadConfig(selectedSave)
    else
        notify("Config", "no save selected")
    end
end)

settingsTab:AddTextBox("Load Save By Name", "exact save name...", function(text, enterPressed)
    if enterPressed and text ~= "" then
        if loadConfig(text) then
            selectedSave = text
        end
    end
end)

settingsTab:AddTextBox("New Save Name", "save name...", function(text, enterPressed)
    pendingSaveName = text or ""
    if enterPressed and pendingSaveName ~= "" then
        if saveConfig(pendingSaveName) then
            selectedSave = pendingSaveName
        end
    end
end)

settingsTab:AddButton("Create / Overwrite Save", function()
    if pendingSaveName ~= "" then
        if saveConfig(pendingSaveName) then
            selectedSave = pendingSaveName
        end
    else
        notify("Config", "enter a save name first")
    end
end)

settingsTab:AddButton("Delete Selected Save", function()
    if selectedSave then
        if deleteSave(selectedSave) then
            selectedSave = nil
        end
    else
        notify("Config", "no save selected")
    end
end)

settingsTab:AddButton("Clear All Saves", function()
    if clearAllSaves() then
        selectedSave = nil
    end
end)

settingsTab:AddLabel("WHITELIST")

settingsTab:AddTextBox("Add Player", "player name...", function(text, enterPressed)
    if enterPressed and text ~= "" then
        local found = false
        for _, p in ipairs(Players:GetPlayers()) do
            if string.lower(p.Name):sub(1, #text) == string.lower(text)
                or string.lower(p.DisplayName):sub(1, #text) == string.lower(text) then
                if Whitelist[p.Name] then
                    Whitelist[p.Name] = nil
                    notify("Whitelist", p.Name .. " removed")
                else
                    Whitelist[p.Name] = true
                    notify("Whitelist", p.Name .. " added")
                end
                found = true
            end
        end
        if not found then
            notify("Whitelist", "no matching player")
        end
    end
end)

settingsTab:AddButton("Clear Whitelist", function()
    Whitelist = {}
    notify("Whitelist", "Cleared")
end)

settingsTab:AddLabel("MISC")

settingsTab:AddKeybind("Panic Key", Enum.KeyCode.End, function()
    Combat.silentAim = false
    Combat.triggerbot = false
    ESP.enabled = false
    Client.bulletTracers = false
    tbMouseUp()
    applyFullbright(false)
    applyForceDay(false)
    setNoPromptDelay(false)
    notify("Panic", "features toggled off")
end)

settingsTab:AddButton("Rejoin Server", function()
    TeleportService:Teleport(game.PlaceId, localPlayer)
end)

settingsTab:AddButton("Purge & Unload UI Completely", function()
    State.Running = false
    setAntiAfk(false)
    setNoPromptDelay(false)
    CarMods:shutdown()
    ScooterMods:shutdown()
    clientShutdown()
    releaseLock(FarmLock.owner)
    task.delay(0.5, function()
        window:Destroy()
    end)
end)
