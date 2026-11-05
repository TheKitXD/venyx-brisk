-- ═══════ venyx (new UI) ═══════
local Library = loadstring(game:HttpGet("https://pastebin.com/raw/7UKF8MKf"))()
local Window = Library.new("brisk_survival")

-- ─── Services ───────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer      = Players.LocalPlayer
local Lighting         = game:GetService("Lighting")
local Workspace        = game:GetService("Workspace")
local Stats            = game:GetService("Stats")

local V2         = Vector2.new
local V3         = Vector3.new
local fromRGB    = Color3.fromRGB
local floor      = math.floor
local clamp      = math.clamp
local round      = math.round
local tfind      = table.find
local ZERO2      = V2(0,0)

local black = fromRGB(0,0,0)
local white = fromRGB(255,255,255)
local green = fromRGB(0,255,0)
local yellow = fromRGB(255,255,0)

-- ═══ CONFIG CONSTANT ═══
local MELEE_RANGE = 50   -- melee aura hardset range

-- ─── CONNECTION REGISTRY (for full unload) ────────────────
local scriptConnections = {}
local function keepConn(conn)
    if conn then
        scriptConnections[#scriptConnections + 1] = conn
    end
    return conn
end

-- ─── Color helpers (for config serialization of Color3s) ────────────────
local function colorToTable(c)
    return { r = floor(c.R * 255 + 0.5), g = floor(c.G * 255 + 0.5), b = floor(c.B * 255 + 0.5) }
end
local function tableToColor(t)
    if type(t) ~= "table" then return nil end
    local r = tonumber(t.r); local g = tonumber(t.g); local b = tonumber(t.b)
    if r == nil or g == nil or b == nil then return nil end
    return fromRGB(clamp(r,0,255), clamp(g,0,255), clamp(b,0,255))
end

-- ─── Lighting originals ──────────────────────────────────────────────────
local origBrightness = Lighting.Brightness
local origAmbient    = Lighting.Ambient
local origOutdoor    = Lighting.OutdoorAmbient
local origClockTime  = Lighting.ClockTime
local origFogEnd     = Lighting.FogEnd
local origFogStart   = Lighting.FogStart
local origShadows    = Lighting.GlobalShadows
local origExposure   = Lighting.ExposureCompensation
local origCSTop      = Lighting.ColorShift_Top
local origCSBottom   = Lighting.ColorShift_Bottom
local lightingFx     = {}
for _, fx in ipairs(Lighting:GetChildren()) do
    lightingFx[#lightingFx + 1] = fx
end

-- ─── State ────────────────────────────────────────────────────────────────
local st = {
    -- combat
    aimbot = false, aimSmooth = 0,
    silentAim = false, wallCheck = false, triggerbot = false,
    tbMaxDist = 1000,
    meleeAura = false,
    tracer = false, debugHud = false, targetPart = "HumanoidRootPart",
    aimKey = Enum.KeyCode.E,
    -- fov
    fovVisible = false, fovRadius = 100, fovThickness = 1, fovColor = white,
    -- esp
    espEnabled = false, boxes = false, names = false, dist = false,
    health = false, held = false, skel = false,
    highlight = false, viewcheck = true,
    espThickness = 1, renderDist = 5000,
    boxStyle = "Bounding Box", textFont = "Plex [2]", textSize = 11,
    visCol = yellow, hidCol = white, frndCol = green,
    -- freecam
    flySpeed = 40, slowSpeed = 8,
    -- zoom
    zoomFov = 10, zoomKey = Enum.KeyCode.Z,
    -- world fx
    fullbright = false, forceDay = false,
    -- viewmodel
    vmEnabled = false, vmMaterial = "ForceField",
    vmColor = fromRGB(0,170,255), vmTransparency = 0.5,
    -- bullet tracers
    bulletTracers = false, tracerColor = yellow,
    tracerTime = 3, tracerMax = 50,
}

local noRecoil, noSpread = false, false

local function notify(title, text)
    print("[venyx] " .. tostring(title) .. ": " .. tostring(text))
end

-- ─── Whitelist ───────────────────────────────────────────────────────────
local Whitelist = {}
keepConn(Players.PlayerRemoving:Connect(function(p)
    if Whitelist[p.Name] then Whitelist[p.Name] = nil end
end))

-- ─── Camera ──────────────────────────────────────────────────────────────
local Camera = Workspace.CurrentCamera
keepConn(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local newCam = Workspace.CurrentCamera
    if newCam and newCam ~= Camera then
        Camera = newCam
    end
end))
local OKGui = (gethui and gethui()) or game:GetService("CoreGui")

-- ─── ESP font resolution ─────────────────────────────────────────────────
local FONT_INDICES = { ["UI [0]"] = 0, ["System [1]"] = 1, ["Plex [2]"] = 2, ["Monospace [3]"] = 3 }
local function espFontIndex()
    return FONT_INDICES[st.textFont] or 2
end

-- ─── Drawing helpers ──────────────────────────────────────────────────
local function newQuad(t,c)
    local q=Drawing.new("Quad"); q.Visible=false
    q.PointA,q.PointB,q.PointC,q.PointD=ZERO2,ZERO2,ZERO2,ZERO2
    q.Color=c; q.Filled=false; q.Thickness=t; q.Transparency=1; return q
end
local function newLine(t,c)
    local l=Drawing.new("Line"); l.Visible=false; l.From,l.To=ZERO2,ZERO2
    l.Color=c; l.Thickness=t; l.Transparency=1; return l
end
local function newText(s,c)
    local t=Drawing.new("Text"); t.Visible=false; t.Center=true; t.Outline=true
    t.Font=2; t.Color=c; t.Size=s; return t
end

-- ─── ESP box help ────────────────────────────────────────────────────
local function hideESPBoxSegs(d)
    if d.segs then for i=1,8 do d.segs[i].Visible=false end end
end

-- ─── ESP box style rendering ───────────────────────────────────────────
local function drawESPBox(d, minX, minY, maxX, maxY, col, thick)
    if st.boxStyle == "Bounding Box" then
        d.box.PointA=V2(maxX,minY); d.box.PointB=V2(minX,minY)
        d.box.PointC=V2(minX,maxY); d.box.PointD=V2(maxX,maxY)
        d.box.Color=col; d.box.Thickness=thick; d.box.Visible=true
        d.blackbox.PointA=V2(maxX,minY); d.blackbox.PointB=V2(minX,minY)
        d.blackbox.PointC=V2(minX,maxY); d.blackbox.PointD=V2(maxX,maxY)
        d.blackbox.Thickness=thick+1; d.blackbox.Visible=true
        hideESPBoxSegs(d)
    else
        d.box.Visible=false; d.blackbox.Visible=false
        local w = maxX - minX
        local h = maxY - minY
        local L = math.min(w, h) * 0.25

        if st.boxStyle == "Corner Brackets" then
            d.segs[1].From=V2(minX,minY);       d.segs[1].To=V2(minX+L,minY)
            d.segs[2].From=V2(minX,minY);       d.segs[2].To=V2(minX,minY+L)
            d.segs[3].From=V2(maxX,minY);       d.segs[3].To=V2(maxX-L,minY)
            d.segs[4].From=V2(maxX,minY);       d.segs[4].To=V2(maxX,minY+L)
            d.segs[5].From=V2(minX,maxY);       d.segs[5].To=V2(minX+L,maxY)
            d.segs[6].From=V2(minX,maxY);       d.segs[6].To=V2(minX,maxY-L)
            d.segs[7].From=V2(maxX,maxY);       d.segs[7].To=V2(maxX-L,maxY)
            d.segs[8].From=V2(maxX,maxY);       d.segs[8].To=V2(maxX,maxY-L)
        else
            local C = math.min(w, h) * 0.18
            d.segs[1].From=V2(minX,minY);       d.segs[1].To=V2(minX+L,minY)
            d.segs[2].From=V2(minX,minY);       d.segs[2].To=V2(minX+C,minY+C)
            d.segs[3].From=V2(maxX,minY);       d.segs[3].To=V2(maxX-L,minY)
            d.segs[4].From=V2(maxX,minY);       d.segs[4].To=V2(maxX-C,minY+C)
            d.segs[5].From=V2(minX,maxY);       d.segs[5].To=V2(minX+L,maxY)
            d.segs[6].From=V2(minX,maxY);       d.segs[6].To=V2(minX+C,maxY-C)
            d.segs[7].From=V2(maxX,maxY);       d.segs[7].To=V2(maxX-L,maxY)
            d.segs[8].From=V2(maxX,maxY);       d.segs[8].To=V2(maxX-C,maxY-C)
        end

        for i=1,8 do
            local seg = d.segs[i]
            seg.Color=col; seg.Thickness=thick
            seg.Visible=true
        end
    end
end

-- ─── Health bar color cache ─────────────────────────────────────────────
local hpColors = {}
for i = 0, 100 do
    local pct = i / 100
    hpColors[i] = fromRGB(floor(255*(1-pct)), floor(255*pct), 0)
end
local function hpColor(pct)
    return hpColors[clamp(floor(pct*100+0.5), 0, 100)]
end

-- ─── Entry factory ────────────────────────────────────────────────────
local BONE_KEYS = {
    "Head_Torso","Torso_LTorso",
    "Shoulder_R","Shoulder_L",
    "Torso_RUA","RUA_RLA",
    "Torso_LUA","LUA_LLA",
    "Hip_R","Hip_L",
    "LTorso_RUL","RUL_RLL",
    "LTorso_LUL","LUL_LLL",
}

-- PERF: bones are now created LAZILY (only when skeleton ESP is actually
-- enabled for that player) instead of 28 drawing objects per player up-front.
local function makeEntry()
    local e = {
        hiddenFlag = true,   -- starts hidden so hideEntry is free until drawn
        blackbox = newQuad(2, black),
        box      = newQuad(1, white),
        name     = newText(11, white),
        dist     = newText(11, white),
        item     = newText(11, fromRGB(255,210,90)),
        hpbg     = newLine(4, black),
        hpfill   = newLine(2, green),
        segs = {
            newLine(2, black), newLine(1, white),
            newLine(2, black), newLine(1, white),
            newLine(2, black), newLine(1, white),
            newLine(2, black), newLine(1, white),
        },
        highlightRef = nil,
        bones = nil,
    }
    return e
end

local function hideBones(bones)
    for _,bl in pairs(bones) do bl.o.Visible=false; bl.l.Visible=false end
end

local function destroyEntry(e)
    pcall(function() e.blackbox:Remove() end); pcall(function() e.box:Remove() end)
    pcall(function() e.name:Remove() end);     pcall(function() e.dist:Remove() end)
    pcall(function() e.item:Remove() end)
    pcall(function() e.hpbg:Remove() end);     pcall(function() e.hpfill:Remove() end)
    for _, seg in ipairs(e.segs) do
        pcall(function() seg:Remove() end)
    end
    if e.highlightRef then pcall(function() e.highlightRef:Destroy() end) end
    if e.bones then for _,bl in pairs(e.bones) do
        pcall(function() bl.o:Remove() end); pcall(function() bl.l:Remove() end)
    end end
end

-- PERF FIX: dirty flag — hidden entries cost ZERO drawing calls on repeat.
-- Was re-writing Visible=false to ~30 drawing objects per player/object
-- per frame (100k+ native calls/sec in big servers).
local function hideEntry(e)
    if e.hiddenFlag then return end
    e.hiddenFlag = true
    e.blackbox.Visible=false; e.box.Visible=false
    e.name.Visible=false;     e.dist.Visible=false
    e.item.Visible=false
    e.hpbg.Visible=false;     e.hpfill.Visible=false
    hideESPBoxSegs(e)
    if e.highlightRef then pcall(function() e.highlightRef:Destroy() end); e.highlightRef = nil end
    if e.bones then hideBones(e.bones) end
end

-- ─── Skeleton ────────────────────────────────────────────────────────
local _bones, _thick, _col, _cam = nil, 1, white, Camera

local function drawBone(key, fp, tp)
    local bl = _bones[key]; if not bl then return end
    local va = _cam:WorldToViewportPoint(fp)
    local vb = _cam:WorldToViewportPoint(tp)
    if va.Z<=0 or vb.Z<=0 then bl.o.Visible=false; bl.l.Visible=false; return end
    local f,t2 = V2(va.X,va.Y), V2(vb.X,vb.Y)
    bl.o.From=f; bl.o.To=t2; bl.o.Thickness=_thick+1; bl.o.Color=black; bl.o.Visible=true
    bl.l.From=f; bl.l.To=t2; bl.l.Thickness=_thick;   bl.l.Color=_col;  bl.l.Visible=true
end

local function getPos(obj, name)
    local p = obj:FindFirstChild(name); return p and p.Position or nil
end

local function drawSkeletonR6(char, head)
    local torso = char:FindFirstChild("Torso"); if not torso then return end
    local cf = torso.CFrame
    local top  = (cf * CFrame.new(0, 1, 0)).Position
    local bot  = (cf * CFrame.new(0,-1, 0)).Position
    local rSh  = (cf * CFrame.new( 1.5, 1, 0)).Position
    local lSh  = (cf * CFrame.new(-1.5, 1, 0)).Position
    local rHip = (cf * CFrame.new( 0.5,-1, 0)).Position
    local lHip = (cf * CFrame.new(-0.5,-1, 0)).Position

    drawBone("Head_Torso", head and head.Position or top, top)
    drawBone("Torso_LTorso", top, bot)

    local function drawLimb(jointKey, limbKey, joint, partName)
        local part = char:FindFirstChild(partName)
        if not part then
            for _, k in ipairs({jointKey, limbKey}) do
                local bl = _bones[k]; if bl then bl.o.Visible=false; bl.l.Visible=false end
            end
            return
        end
        drawBone(jointKey, joint, part.Position)
        drawBone(limbKey, part.Position, part.Position + part.CFrame.UpVector * -(part.Size.Y/2))
    end

    drawLimb("Shoulder_R","Torso_RUA", rSh, "Right Arm")
    drawLimb("Shoulder_L","Torso_LUA", lSh, "Left Arm")
    drawLimb("Hip_R","LTorso_RUL", rHip, "Right Leg")
    drawLimb("Hip_L","LTorso_LUL", lHip, "Left Leg")

    for _, k in ipairs({"RUA_RLA","LUA_LLA","RUL_RLL","LUL_LLL"}) do
        local bl = _bones[k]; if bl then bl.o.Visible=false; bl.l.Visible=false end
    end
end

local function drawSkeletonR15(obj, head)
    local ut=getPos(obj,"UpperTorso"); local lt=getPos(obj,"LowerTorso")
    local rua=getPos(obj,"RightUpperArm"); local rla=getPos(obj,"RightLowerArm"); local rha=getPos(obj,"RightHand")
    local lua=getPos(obj,"LeftUpperArm");  local lla=getPos(obj,"LeftLowerArm");  local lha=getPos(obj,"LeftHand")
    local rul=getPos(obj,"RightUpperLeg"); local rll=getPos(obj,"RightLowerLeg"); local rf=getPos(obj,"RightFoot")
    local lul=getPos(obj,"LeftUpperLeg");  local lll=getPos(obj,"LeftLowerLeg");  local lf=getPos(obj,"LeftFoot")
    local hp = head and head.Position
    if hp  and ut  then drawBone("Head_Torso",  hp,ut)  end
    if ut  and lt  then drawBone("Torso_LTorso",ut,lt)  end
    if ut  and rua then drawBone("Shoulder_R",  ut,rua) end
    if ut  and lua then drawBone("Shoulder_L",  ut,lua) end
    if rua and rla then drawBone("Torso_RUA",   rua,rla) end
    if rla and rha then drawBone("RUA_RLA",     rla,rha) end
    if lua and lla then drawBone("Torso_LUA",   lua,lla) end
    if lla and lha then drawBone("LUA_LLA",     lla,lha) end
    if lt  and rul then drawBone("Hip_R",        lt,rul) end
    if lt  and lul then drawBone("Hip_L",        lt,lul) end
    if rul and rll then drawBone("LTorso_RUL",  rul,rll) end
    if rll and rf  then drawBone("RUL_RLL",     rll,rf)  end
    if lul and lll then drawBone("LTorso_LUL",  lul,lll) end
    if lll and lf  then drawBone("LUL_LLL",     lll,lf)  end
end

-- ─── Projection helper ─────────────────────────────────────────────
-- PERF FIX: pcall stripped — WorldToViewportPoint does not throw; it
-- returns on=false for behind-camera points, which we already handle.
-- (was 8 pcalls per tracked object per frame)
local function projectBox(center, halfExtents)
    local minV = math.huge
    local minV2y = math.huge
    local maxV = -math.huge
    local maxV2y = -math.huge
    for sx=-1,1,2 do for sy=-1,1,2 do for sz=-1,1,2 do
        local p3 = center + V3(halfExtents.X*sx, halfExtents.Y*sy, halfExtents.Z*sz)
        local pos, on = Camera:WorldToViewportPoint(p3)
        if not on then return nil end
        if pos.X < minV then minV = pos.X end
        if pos.Y < minV2y then minV2y = pos.Y end
        if pos.X > maxV then maxV = pos.X end
        if pos.Y > maxV2y then maxV2y = pos.Y end
    end end end
    return Vector2.new(minV, minV2y), Vector2.new(maxV, maxV2y)
end

-- ─── Visibility check ──────────────────────────────────────────────
local visParams = RaycastParams.new()
visParams.FilterType=Enum.RaycastFilterType.Exclude; visParams.IgnoreWater=true
local filterTable = { nil, Camera }

local function isVisibleChar(char, lc, lh)
    local th = char:FindFirstChild("Head")
    if not th then return false end
    filterTable[1] = lc
    visParams.FilterDescendantsInstances = filterTable
    local hit = Workspace:Raycast(lh.Position, th.Position - lh.Position, visParams)
    return not hit or hit.Instance:IsDescendantOf(char)
end

keepConn(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    filterTable[2] = Workspace.CurrentCamera
    _cam = Workspace.CurrentCamera
end))

-- ─── World categories ─────────────────────────────────────────────
local WorldCategories = {
    Drones         = { names = {"SentinelTroop","LowTierSentinelTroop"}, flag="sel_drones", color=fromRGB(255,70,70),   label="Drone" },
    Iron           = { kw = {"IronOre"},    flag="sel_iron",   color=fromRGB(200,200,200), label="Iron Ore" },
    Sulfur         = { kw = {"NitrateOre"}, flag="sel_sulfur", color=fromRGB(235,220,60),  label="Sulfur Ore" },
    Stone          = { kw = {"Stone"},      flag="sel_stone",  color=fromRGB(140,140,140), label="Stone" },
    Trees          = { kw = {"Cactus","Pine","Tree"}, flag="sel_trees", color=fromRGB(60,200,90), label="Tree" },
    BrownCrates    = { kw = {"ClosedBox"},  flag="sel_brown",  color=fromRGB(180,120,60), label="Crate" },
    MilitaryCrates = { kw = {"GreenBox"},   flag="sel_mil",    color=fromRGB(80,160,70),  label="Military Crate" },
    EliteCrates    = { kw = {"EliteBox"},   flag="sel_elite",  color=fromRGB(170,90,255), label="Elite Crate" },
}
local WorldSel = {}
local PlayersSel = false

local function worldAnySelected()
    for _, info in pairs(WorldCategories) do
        if WorldSel[info.flag] then return true end
    end
    return false
end

local Tracked = {}
local PlayerDrawings = {}

local function classify(inst)
    local name = inst.Name
    for cat, info in pairs(WorldCategories) do
        if info.names and tfind(info.names, name) then return cat end
        if info.kw then
            for _,k in ipairs(info.kw) do
                if name:find(k) then return cat end
            end
        end
    end
end

local function trackInstance(inst, cat)
    if Tracked[inst] or not inst:IsDescendantOf(Workspace) then return end
    if inst:IsDescendantOf(Camera) then return end
    local anchor = inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")) or inst
    if not anchor then return end
    Tracked[inst] = { draw=makeEntry(), cat=cat, anchor=anchor, isModel=inst:IsA("Model") }
end

local function untrack(inst)
    local t = Tracked[inst]
    if t then
        destroyEntry(t.draw)
        Tracked[inst] = nil
    end
end

-- ─── Player ESP registry ───────────────────────────────────────
local function buildPlayerDraw(player)
    if PlayerDrawings[player] then return end
    local e = makeEntry()
    e.visFrame = 0
    e.isVisible = false
    PlayerDrawings[player] = e
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
for _,p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then buildPlayerDraw(p) end end

-- ─── BALLISTICS ──────────────────────────────────────────────
local cachedToolRef = nil
local cachedEnv     = nil
local cachedBallistics = nil
local BallDebug = "no tool"

local function findClientGunScript(tool)
    if not tool then return nil end
    local child = tool:FindFirstChild("ClientGun")
    if child and child:IsA("LocalScript") then return child end
    return tool:FindFirstChildWhichIsA("LocalScript", true)
end

local function getBallistics()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then
        cachedToolRef, cachedEnv, cachedBallistics = nil, nil, nil
        BallDebug = "no tool"
        return nil
    end
    if tool == cachedToolRef then return cachedBallistics end
    cachedToolRef = tool
    cachedEnv, cachedBallistics = nil, nil

    if typeof(getsenv) == "function" then
        local ok, result = pcall(function()
            local gunScript = findClientGunScript(tool)
            if not gunScript then error("no ClientGun script") end
            return getsenv(gunScript)
        end)
        if ok and type(result) == "table" then
            cachedEnv = result
            local s = result.u3 or result.settings or result.Settings
            if type(s) == "table" then
                cachedBallistics = s
                if typeof(s.BulletSpeed) == "number" then
                    BallDebug = "LIVE spd:" .. floor(s.BulletSpeed) .. (s.BulletDrop==true and " drop" or " flat")
                else
                    BallDebug = "LIVE hitscan"
                end
                return cachedBallistics
            end
        end
    end

    local tier = tonumber(tool:GetAttribute("WeaponTier")) or 1
    local mod = tool:FindFirstChild("Settings" .. clamp(floor(tier),1,3))
        or tool:FindFirstChild("Settings1")
        or tool:FindFirstChild("Settings")
    if mod and mod:IsA("ModuleScript") then
        local ok, s = pcall(require, mod)
        if ok and type(s) == "table" then
            cachedBallistics = s
            if typeof(s.BulletSpeed) == "number" then
                BallDebug = "spd:" .. floor(s.BulletSpeed) .. (s.BulletDrop==true and " drop" or " flat")
            else
                BallDebug = "hitscan"
            end
        else
            BallDebug = "require failed"
        end
    else
        BallDebug = "no settings"
    end
    return cachedBallistics
end

-- ─── EDIT-SETTINGS ENGINE (idempotent — no value churn) ─────────────
local RECOIL_KEYS = {
    { "RecoilYawMult", 0 }, { "RecoilPitchMult", 0 },
    { "RecoilAutoReturn", false }, { "RecoilCameraAutoReturn", false },
    { "ADSRecoilMult", 0 },
    { "HipSpreadIncreasePerShot", 0 }, { "ADSSpreadIncreasePerShot", 0 },
    { "SpreadIncreasePerShot", 0 },
}
local SPREAD_KEYS = {
    { "HipSpreadDegrees", 0 }, { "ADSSpreadDegrees", 0 },
    { "SpreadMaxDegrees", 0 }, { "SpreadIncreasePerShot", 0 },
    { "HipSpreadIncreasePerShot", 0 }, { "ADSSpreadIncreasePerShot", 0 },
}

local settingsBackup = {}
local settingsToolRefForEdits = nil

local function backupSetting(modTable, key)
    local t = settingsBackup[modTable]
    if t == nil then
        t = {}
        settingsBackup[modTable] = t
    end
    if t[key] == nil then
        t[key] = modTable[key]
    end
    return t[key]
end

local function applySettingsEdits(tool, keys, on)
    if not tool then return end
    for i = 1, 3 do
        local mod = tool:FindFirstChild("Settings"..i)
        if mod and mod:IsA("ModuleScript") then
            local ok, s = pcall(require, mod)
            if ok and type(s) == "table" then
                for _, entry in ipairs(keys) do
                    local key, val = entry[1], entry[2]
                    if s[key] ~= nil then
                        local orig = backupSetting(s, key)
                        local newVal = on and val or orig
                        if s[key] ~= newVal then
                            s[key] = newVal
                        end
                    end
                end
            end
        end
    end
    local mod = tool:FindFirstChild("Settings")
    if mod and mod:IsA("ModuleScript") then
        local ok, s = pcall(require, mod)
        if ok and type(s) == "table" then
            for _, entry in ipairs(keys) do
                local key, val = entry[1], entry[2]
                if s[key] ~= nil then
                    local orig = backupSetting(s, key)
                    local newVal = on and val or orig
                    if s[key] ~= newVal then
                        s[key] = newVal
                    end
                end
            end
        end
    end
end

local function refreshSettingsEdits()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool ~= settingsToolRefForEdits then
        if settingsToolRefForEdits then
            applySettingsEdits(settingsToolRefForEdits, RECOIL_KEYS, false)
            applySettingsEdits(settingsToolRefForEdits, SPREAD_KEYS, false)
        end
        settingsToolRefForEdits = tool
    end
    if tool then
        if noRecoil then
            applySettingsEdits(tool, RECOIL_KEYS, true)
        else
            applySettingsEdits(tool, RECOIL_KEYS, false)
        end
        if noSpread then
            applySettingsEdits(tool, SPREAD_KEYS, true)
        else
            applySettingsEdits(tool, SPREAD_KEYS, false)
        end
    end
end

local function restoreAllSettings()
    if settingsToolRefForEdits then
        applySettingsEdits(settingsToolRefForEdits, RECOIL_KEYS, false)
        applySettingsEdits(settingsToolRefForEdits, SPREAD_KEYS, false)
        settingsToolRefForEdits = nil
    end
end

-- ─── PREDICTIVE AIM ──────────────────────────────────────────
local function computeAimPoint(origin, targetPart, targetRoot, ball)
    local point = targetPart.Position
    if not ball then return point end

    local speed = typeof(ball.BulletSpeed) == "number" and ball.BulletSpeed or nil
    if not speed or speed <= 0 then return point end

    local g = 0
    local dropThresholdDist = math.huge
    if ball.BulletDrop == true then
        local gm = typeof(ball.BulletGravityMult) == "number" and ball.BulletGravityMult or 1
        g = Workspace.Gravity * gm
        if typeof(ball.BulletDropStartDistance) == "number" then
            dropThresholdDist = ball.BulletDropStartDistance
        elseif typeof(ball.BulletDropStartFraction) == "number" then
            local fr = ball.BulletDropStartFraction
            if fr > 1 then fr = fr / 100 end
            dropThresholdDist = (point - origin).Magnitude * clamp(fr, 0, 1)
        else
            dropThresholdDist = 0
        end
    end

    local vel = Vector3.zero
    if targetRoot then
        vel = targetRoot.AssemblyLinearVelocity
    end

    local aim = point
    for _ = 1, 5 do
        local flightDist = (aim - origin).Magnitude
        local t = flightDist / speed
        local p = point + vel * t
        if g > 0 then
            local flatTime = math.min(t, dropThresholdDist / speed)
            local dropTime  = math.max(0, t - flatTime)
            p = p + V3(0, 0.5 * g * dropTime * dropTime, 0)
        end
        aim = p
    end
    return aim
end

-- ─── Targeting ───────────────────────────────────────────────
local CurrentTarget = nil
local GunFireSeen = 0
local ShotsRedirected = 0
local HookMethod = "none"
local hookActive = false
local Holding = false

local function isFriendly(plr)
    if plr == LocalPlayer then return true end
    if Whitelist[plr.Name] then return true end
    if LocalPlayer.Team ~= nil and plr.Team ~= nil and plr.Team == LocalPlayer.Team then
        return true
    end
    return false
end

keepConn(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 and st.aimbot then
        Holding = true
    end
    if input.UserInputType == Enum.UserInputType.Keyboard
    and input.KeyCode == st.aimKey and st.aimbot then
        Holding = true
    end
end))
keepConn(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        Holding = false
    end
    if input.UserInputType == Enum.UserInputType.Keyboard
    and input.KeyCode == st.aimKey then
        Holding = false
    end
end))

-- ═══ TRIGGERBOT ═════════════════════════════════════════════
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUserService = game:GetService("VirtualUser")

local tbHolding = false
local tbLastAcquireAt = 0
local tbLastClickAt = 0
local TB_GRACE = 0.25

local function tbMouseDown()
    if tbHolding then return end
    tbHolding = true
    local cam = Camera
    local cx = cam.ViewportSize.X * 0.5
    local cy = cam.ViewportSize.Y * 0.5
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
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
    local cam = Camera
    local cx = cam.ViewportSize.X * 0.5
    local cy = cam.ViewportSize.Y * 0.5
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
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

local function crosshairOnEnemy()
    local char = LocalPlayer.Character
    if not char then return false end

    if not char:FindFirstChildOfClass("Tool") then return false end

    local viewmodelFolder = Workspace:FindFirstChild("Camera")
    if viewmodelFolder then
        tbRayParams.FilterDescendantsInstances = { char, viewmodelFolder }
    else
        tbRayParams.FilterDescendantsInstances = { char }
    end

    local ball = getBallistics()
    local maxDist = (ball and typeof(ball.MaxDistance) == "number" and ball.MaxDistance > 0) and ball.MaxDistance or 1000

    local camCF = Camera.CFrame
    local result = Workspace:Raycast(camCF.Position, camCF.LookVector * maxDist, tbRayParams)
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
                    return (theirRoot.Position - myRoot.Position).Magnitude <= st.tbMaxDist
                end
                return false
            end
            return false
        end
        model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") or nil
    end
    return false
end

local function targetValidForTriggerbot(lRoot)
    local t = CurrentTarget
    if not t or not t.part or not t.part.Parent or not t.root or not lRoot then
        return false
    end
    local hum = t.player and t.player.Character
        and t.player.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end
    return (t.root.Position - lRoot.Position).Magnitude <= st.tbMaxDist
end

-- ═══ MELEE AURA (hammers) — hardset range ═══════════════
local HammerMeleeRemote = ReplicatedStorage:FindFirstChild("HammerMeleeRemote")
    or ReplicatedStorage:WaitForChild("HammerMeleeRemote", 5)

local MA_lastSwingAt = 0
local MA_fires = 0
local MA_lastTargetName = "-"
local MA_status = "off"

local meleeToolNames = {}
do
    for _, c in ipairs(Workspace:GetChildren()) do
        if c.Name:sub(1, 12) == "ServerProtoco" then
            for _, tmpl in ipairs(c:GetChildren()) do
                if tmpl:FindFirstChild("HammerClient", true) then
                    meleeToolNames[tmpl.Name] = true
                end
            end
        end
    end
end

local function isMeleeTool(tool)
    if meleeToolNames[tool.Name] then return true end
    return tool.Name:find("Hammer") ~= nil
end

local function getMeleeSettings(tool)
    local s = getBallistics()
    if s then return s end
    for i = 1, 3 do
        local mod = tool:FindFirstChild("Settings"..i)
        if mod and mod:IsA("ModuleScript") then
            local ok, t = pcall(require, mod)
            if ok and type(t) == "table" then return t end
        end
    end
    local mod = tool:FindFirstChild("Settings")
    if mod and mod:IsA("ModuleScript") then
        local ok, t = pcall(require, mod)
        if ok and type(t) == "table" then return t end
    end
    return nil
end

local function meleeAuraStep(now)
    if not st.meleeAura then
        MA_status = "off"
        return
    end

    local char = LocalPlayer.Character
    if not char then MA_status = "no char" return end

    local myHum = char:FindFirstChildOfClass("Humanoid")
    if not myHum or myHum.Health <= 0 then MA_status = "dead" return end

    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then MA_status = "no root" return end

    local nearest, nearestRoot, nearestDist = nil, nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isFriendly(plr) then
            local pchar = plr.Character
            local phum  = pchar and pchar:FindFirstChildOfClass("Humanoid")
            local proot = pchar and pchar:FindFirstChild("HumanoidRootPart")
            if pchar and phum and proot and phum.Health > 0 then
                local d = (proot.Position - myRoot.Position).Magnitude
                if d <= MELEE_RANGE and d < nearestDist then
                    nearest, nearestRoot, nearestDist = plr, proot, d
                end
            end
        end
    end

    local tool = char:FindFirstChildOfClass("Tool")

    if not (tool and isMeleeTool(tool)) then
        if not nearestRoot then MA_status = "no target" return end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, t in ipairs(backpack:GetChildren()) do
                if t:IsA("Tool") and isMeleeTool(t) then
                    pcall(function()
                        myHum:EquipTool(t)
                    end)
                    MA_status = "equipping"
                    return
                end
            end
        end
        MA_status = "no melee tool"
        return
    end
    if tool.Parent ~= char then MA_status = "not held" return end

    if not nearestRoot then
        MA_status = "no target"
        MA_lastTargetName = "-"
        return
    end

    local settings = getMeleeSettings(tool)
    local rpm = 50
    if settings then
        rpm = tonumber(settings.MeleeRPM) or tonumber(settings.FireRateRPM) or 50
    end
    local cooldown = 60 / math.max(rpm, 1)

    if (now - MA_lastSwingAt) < cooldown then
        MA_status = "cooling"
        return
    end

    local origin = Camera.CFrame.Position
    local aimAt = nearestRoot.Position + V3(0, 0.5, 0)
    local direction = (aimAt - origin)
    if direction.Magnitude < 0.05 then return end
    direction = direction.Unit

    local verifyParams = RaycastParams.new()
    verifyParams.FilterType = Enum.RaycastFilterType.Exclude
    verifyParams.IgnoreWater = true
    verifyParams.FilterDescendantsInstances = { char, nearest.Character }
    local hit = Workspace:Raycast(origin, direction * (nearestDist + 20), verifyParams)
    if hit and (hit.Position - origin).Magnitude < (nearestDist - 2) then
        MA_status = "wall"
        return
    end

    if not HammerMeleeRemote then MA_status = "no remote" return end

    MA_lastSwingAt = now
    MA_fires += 1
    MA_lastTargetName = nearest.Name
    MA_status = "SWING"

    local okFire = pcall(function()
        HammerMeleeRemote:FireServer(tool.Name, origin, direction, Workspace:GetServerTimeNow())
    end)
    if not okFire then MA_status = "fire err" end
end

local function pickTarget()
    local fovR = st.fovRadius
    local targetPartName = st.targetPart
    local wallCheck = st.wallCheck
    local mouse = UserInputService:GetMouseLocation()
    local ok, targetPlayer, targetPart, targetRoot = pcall(function()
        local best, bestPart, bestRoot, bestDist = nil, nil, nil, fovR
        local rayParams = RaycastParams.new()
        rayParams.FilterType=Enum.RaycastFilterType.Exclude; rayParams.IgnoreWater=true
        local myChar = LocalPlayer.Character
        local camCF = Camera.CFrame

        if targetPartName == "Find Closest Part" then
            for _,plr in ipairs(Players:GetPlayers()) do
                if not isFriendly(plr) then
                    local char = plr.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if char and hum and hum.Health > 0 and root then
                        for _, desc in ipairs(char:GetDescendants()) do
                            if desc:IsA("BasePart") and desc.Parent then
                                local sp, on = Camera:WorldToViewportPoint(desc.Position)
                                if on then
                                    local dist = (V2(mouse.X,mouse.Y) - V2(sp.X,sp.Y)).Magnitude
                                    if dist <= fovR and dist < bestDist then
                                        if wallCheck then
                                            rayParams.FilterDescendantsInstances = {myChar, char}
                                            local dir = desc.Position - camCF.Position
                                            local hit = Workspace:Raycast(camCF.Position, dir, rayParams)
                                            if not hit or hit.Instance:IsDescendantOf(char) then
                                                best, bestPart, bestRoot, bestDist = plr, desc, root, dist
                                            end
                                        else
                                            best, bestPart, bestRoot, bestDist = plr, desc, root, dist
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        else
            for _,plr in ipairs(Players:GetPlayers()) do
                if not isFriendly(plr) then
                    local char = plr.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local part = char and (char:FindFirstChild(targetPartName)
                        or char:FindFirstChild("Head")
                        or char:FindFirstChild("HumanoidRootPart"))
                    if char and hum and hum.Health>0 and part and part.Parent then
                        local sp, on = Camera:WorldToViewportPoint(part.Position)
                        if on then
                            local dist = (V2(mouse.X,mouse.Y) - V2(sp.X,sp.Y)).Magnitude
                            if dist <= fovR and dist < bestDist then
                                if wallCheck then
                                    rayParams.FilterDescendantsInstances = {myChar, char}
                                    local dir = part.Position - camCF.Position
                                    local hit = Workspace:Raycast(camCF.Position, dir, rayParams)
                                    if not hit or hit.Instance:IsDescendantOf(char) then
                                        best, bestPart, bestRoot, bestDist = plr, part, root, dist
                                    end
                                else
                                    best, bestPart, bestRoot, bestDist = plr, part, root, dist
                                end
                            end
                        end
                    end
                end
            end
        end
        return best, bestPart, bestRoot
    end)
    if ok then return targetPlayer, targetPart, targetRoot end
    return nil, nil, nil
end

-- ═══ GUNFIRE HOOK (silent aim redirection) ═══
local GunFireRemote = ReplicatedStorage:WaitForChild("GunFire", 10)

local function redirectShot(args)
    if typeof(args[2]) ~= "Vector3" or typeof(args[3]) ~= "Vector3" then return end
    if CurrentTarget and CurrentTarget.aimPoint then
        args[3] = (CurrentTarget.aimPoint - args[2]).Unit
        ShotsRedirected += 1
    end
end

local function makeHookBody(oldFn)
    return function(self, ...)
        if hookActive and self == GunFireRemote then
            GunFireSeen += 1
            local args = {...}
            pcall(redirectShot, args)
            return oldFn(self, unpack(args))
        end
        return oldFn(self, ...)
    end
end

local hookInstalled = false

if GunFireRemote then
    pcall(function()
        if typeof(hookmetamethod) ~= "function" then error("no hookmetamethod") end
        local oldNamecall
        local fn = makeHookBody(function(...) return oldNamecall(...) end)
        oldNamecall = hookmetamethod(game, "__namecall", fn)
        HookMethod = "hookmetamethod"
        hookInstalled = true
    end)

    if not hookInstalled then
        pcall(function()
            if typeof(getrawmetatable) ~= "function" then error("no getrawmetatable") end
            local mt = getrawmetatable(game)
            local oldNamecall = mt.__namecall
            mt.__namecall = makeHookBody(oldNamecall)
            HookMethod = "metatable"
            hookInstalled = true
        end)
    end

    if not hookInstalled then
        pcall(function()
            if typeof(hookfunction) ~= "function" then error("no hookfunction") end
            local oldFire
            oldFire = hookfunction(GunFireRemote.FireServer, makeHookBody(function(...) return oldFire(...) end))
            HookMethod = "hookfunction"
            hookInstalled = true
        end)
    end

    if hookInstalled then hookActive = true end
end

-- ─── Combat drawings ────────────────────────────────────────
local fovOutline = Drawing.new("Circle")
fovOutline.Filled=false; fovOutline.Color=black; fovOutline.Visible=false
fovOutline.Transparency=1; fovOutline.NumSides=64; fovOutline.Thickness=2

local fovCircle = Drawing.new("Circle")
fovCircle.Filled=false; fovCircle.Color=white; fovCircle.Visible=false
fovCircle.Transparency=1; fovCircle.NumSides=64; fovCircle.Thickness=1

local tracerOutline = newLine(2, black)
local tracerLine    = newLine(1, white)

local ACCENT      = fromRGB(0,195,255)
local ACCENT_DARK = fromRGB(0,95,160)

local DebugText = Drawing.new("Text")
DebugText.Visible=false; DebugText.Size=12; DebugText.Outline=true
DebugText.Font=2; DebugText.Color=ACCENT_DARK; DebugText.Position=Vector2.new(12,12)

local DebugText2 = Drawing.new("Text")
DebugText2.Visible=false; DebugText2.Size=12; DebugText2.Outline=true
DebugText2.Font=2; DebugText2.Color=fromRGB(120,140,165); DebugText2.Position=Vector2.new(12,28)
DebugText2.Text = "lock: -"

local DebugText3 = Drawing.new("Text")
DebugText3.Visible=false; DebugText3.Size=12; DebugText3.Outline=true
DebugText3.Font=2; DebugText3.Color=ACCENT_DARK; DebugText3.Position=Vector2.new(12,44)
DebugText3.Text = "tracked: 0"

local DebugText4 = Drawing.new("Text")
DebugText4.Visible=false; DebugText4.Size=12; DebugText4.Outline=true
DebugText4.Font=2; DebugText4.Color=ACCENT_DARK; DebugText4.Position=Vector2.new(12,60)
DebugText4.Text = "aura: off"

-- ═══ BULLET TRACERS ═════════════════════════════════════════
local BT_MAX_HIST = 240
local BT_PREDICT_STEPS = 16

local BT_templates = {}
do
    local pt = ReplicatedStorage:FindFirstChild("ProjectileTemplates")
    if pt then
        for _, c in ipairs(pt:GetChildren()) do
            BT_templates[c.Name] = true
        end
    end
end

local function btIsTemplate(name)
    local base = name:match("^(.*)_Local$") or name
    return BT_templates[base] == true
end

local function btIsOwnBullet(name)
    return name:match("_Local$") ~= nil and btIsTemplate(name)
end

local function btFindContainer(inst)
    local node = inst
    while node and node ~= Workspace do
        if btIsTemplate(node.Name) then return node end
        node = node.Parent
    end
    return nil
end

local function btGetPos(root)
    if root:IsA("Model") then
        local ok, p = pcall(root.GetPivot, root)
        if ok and p then return p.Position end
        return nil
    end
    return root.Position
end

local btActive = {}
local btByContainer = {}

local function btRemoveEntry(entry)
    if entry.removed then return end
    entry.removed = true
    btByContainer[entry.root] = nil
    for _, r in ipairs(entry.saved) do
        if r[1] and r[1].Parent then
            if r[2] == "t" then
                pcall(function() r[1].Transparency = r[3] end)
            elseif r[2] == "l" then
                pcall(function() r[1].Enabled = r[3] end)
            end
        end
    end
    for _, seg in ipairs(entry.lines) do
        seg.o.Visible = false; seg.l.Visible = false
        pcall(function() seg.o:Remove() end)
        pcall(function() seg.l:Remove() end)
    end
    for i, e in ipairs(btActive) do
        if e == entry then table.remove(btActive, i) break end
    end
end

local function btTryPrediction(entry)
    if not st.silentAim then return false end
    local t = CurrentTarget
    if not t or not t.aimPoint then return false end
    local origin = btGetPos(entry.root)
    if not origin then return false end

    local ball = getBallistics()
    local aim = t.aimPoint
    local hist = {}

    local speed = ball and typeof(ball.BulletSpeed) == "number" and ball.BulletSpeed or nil
    if not speed or speed <= 0 then
        hist[1] = origin
        hist[2] = aim
    else
        local dist = (aim - origin).Magnitude
        local tTotal = dist / speed

        local g = 0
        local dropStartDist = math.huge
        if ball.BulletDrop == true then
            local gm = typeof(ball.BulletGravityMult) == "number" and ball.BulletGravityMult or 1
            g = Workspace.Gravity * gm
            if typeof(ball.BulletDropStartDistance) == "number" then
                dropStartDist = ball.BulletDropStartDistance
            elseif typeof(ball.BulletDropStartFraction) == "number" then
                local fr = ball.BulletDropStartFraction
                if fr > 1 then fr = fr / 100 end
                dropStartDist = dist * clamp(fr, 0, 1)
            else
                dropStartDist = 0
            end
        end

        local dir = (aim - origin).Unit
        local tFlat = math.min(tTotal, dropStartDist / speed)
        for i = 0, BT_PREDICT_STEPS do
            local tt = tTotal * i / BT_PREDICT_STEPS
            local dT = math.max(0, tt - tFlat)
            hist[i + 1] = origin + dir * speed * tt - V3(0, 0.5 * g * dT * dT, 0)
        end
    end

    table.clear(entry.hist)
    for i, p in ipairs(hist) do entry.hist[i] = p end
    entry.predict = true
    return true
end

local function btRegister(container)
    local existing = btByContainer[container]
    if existing then
        if container.Parent == Workspace then
            existing.bornAt = os.clock()
            table.clear(existing.hist)
            existing.predict = false
            pcall(btTryPrediction, existing)
        end
        return
    end
    if #btActive >= st.tracerMax and btActive[1] then
        btRemoveEntry(btActive[1])
    end

    local entry = {
        root = container,
        hist = {},
        lines = {},
        saved = {},
        bornAt = os.clock(),
        removed = false,
        predict = false,
    }

    if container:IsA("BasePart") then
        entry.saved[#entry.saved+1] = {container, "t", container.Transparency}
        pcall(function() container.Transparency = 1 end)
    end
    for _, d in ipairs(container:GetDescendants()) do
        if d:IsA("BasePart") then
            entry.saved[#entry.saved+1] = {d, "t", d.Transparency}
            pcall(function() d.Transparency = 1 end)
        elseif d:IsA("PointLight") then
            entry.saved[#entry.saved+1] = {d, "l", d.Enabled}
            pcall(function() d.Enabled = false end)
        end
    end

    pcall(btTryPrediction, entry)

    btByContainer[container] = entry
    btActive[#btActive+1] = entry
end

local btVMFolder = Workspace:FindFirstChild("Camera")
keepConn(Workspace.DescendantAdded:Connect(function(desc)
    if not st.bulletTracers then return end
    if not (desc:IsA("BasePart") or desc:IsA("Model")) then return end
    if btVMFolder and desc:IsDescendantOf(btVMFolder) then
        btVMFolder = Workspace:FindFirstChild("Camera") or btVMFolder
        if btVMFolder and desc:IsDescendantOf(btVMFolder) then return end
    end
    local container = btFindContainer(desc)
    if container and btIsOwnBullet(container.Name) then
        pcall(btRegister, container)
    end
end))

local function btUpdate(now)
    if not st.bulletTracers then
        if #btActive > 0 then
            local copy = table.clone(btActive)
            for _, e in ipairs(copy) do pcall(btRemoveEntry, e) end
        end
        return
    end
    for i = #btActive, 1, -1 do
        local e = btActive[i]
        local age = now - e.bornAt
        if age >= st.tracerTime then
            btRemoveEntry(e)
        else
            if not e.predict then
                local root = e.root
                if root.Parent == Workspace then
                    local pos = btGetPos(root)
                    if pos then
                        e.hist[#e.hist + 1] = pos
                        if #e.hist > BT_MAX_HIST then
                            table.remove(e.hist, 1)
                        end
                    end
                end
            end

            while #e.lines < #e.hist - 1 do
                e.lines[#e.lines + 1] = {
                    o = newLine(2, black),
                    l = newLine(1, st.tracerColor),
                }
            end

            local fade = 1 - (age / st.tracerTime)
            local visibleSegs = #e.hist - 1
            for s = 1, #e.lines do
                local seg = e.lines[s]
                if s <= visibleSegs then
                    local a, b = e.hist[s], e.hist[s + 1]
                    local va = Camera:WorldToViewportPoint(a)
                    local vb = Camera:WorldToViewportPoint(b)
                    if va.Z > 0 and vb.Z > 0 then
                        seg.o.From = V2(va.X, va.Y); seg.o.To = V2(vb.X, vb.Y)
                        seg.l.From = V2(va.X, va.Y); seg.l.To = V2(vb.X, vb.Y)
                        seg.o.Thickness = 2; seg.l.Thickness = 1
                        seg.o.Color = black
                        seg.l.Color = st.tracerColor
                        seg.o.Transparency = fade
                        seg.l.Transparency = fade
                        seg.o.Visible = true; seg.l.Visible = true
                    else
                        seg.o.Visible = false; seg.l.Visible = false
                    end
                else
                    seg.o.Visible = false; seg.l.Visible = false
                end
            end
        end
    end
end

-- ─── Viewmodel ────────────────────────────────────────────
local function applyViewmodel()
    if not st.vmEnabled then return end
    local folder = Workspace:FindFirstChild("Camera")
    if not folder then return end
    pcall(function()
        local mat = Enum.Material[st.vmMaterial]
        local col = st.vmColor
        local tr  = st.vmTransparency
        for _,part in ipairs(folder:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Material=mat; part.Color=col; part.Transparency=tr
            end
        end
    end)
end

do
    local function stylePartInstant(part)
        if not st.vmEnabled then return end
        task.defer(function()
            if part.Parent and part:IsA("BasePart") then
                pcall(function()
                    part.Material = Enum.Material[st.vmMaterial]
                    part.Color = st.vmColor
                    part.Transparency = st.vmTransparency
                end)
            end
        end)
    end
    local currentFolder = Workspace:FindFirstChild("Camera")
    local currentConn = currentFolder and keepConn(currentFolder.DescendantAdded:Connect(stylePartInstant))
    keepConn(Workspace.ChildAdded:Connect(function(child)
        if child.Name=="Camera" and child~=currentFolder then
            if currentConn then currentConn:Disconnect() end
            currentFolder = child
            btVMFolder = child
            currentConn = keepConn(child.DescendantAdded:Connect(stylePartInstant))
            applyViewmodel()
        end
    end))
end

-- ─── Zoom ────────────────────────────────────────────────
local zoomHolding = false
local zoomSavedFov = Camera.FieldOfView

local function setZoomHolding(held)
    if zoomHolding == held then return end
    zoomHolding = held
    pcall(function()
        if held then
            zoomSavedFov = Camera.FieldOfView
            Camera.FieldOfView = st.zoomFov
        else
            Camera.FieldOfView = zoomSavedFov
        end
    end)
end

keepConn(UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == st.zoomKey then
        setZoomHolding(true)
    end
end))
keepConn(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == st.zoomKey then
        setZoomHolding(false)
    end
end))
keepConn(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    zoomHolding = false
end))

-- ─── Freecam ─────────────────────────────────────────────
local freecamActive = false
local camYaw, camPitch = 0, 0
local camPos = V3(0,0,0)
local hiddenGuis = {}

local HUD = Instance.new("ScreenGui")
HUD.Name="venyx_FreecamHUD"; HUD.ResetOnSpawn=false; HUD.IgnoreGuiInset=true
HUD.Enabled=false; HUD.DisplayOrder=2000; HUD.Parent=OKGui

do
    local function HN(class, props, parent)
        local inst = Instance.new(class)
        for k,v in pairs(props) do inst[k]=v end
        inst.Parent=parent
        return inst
    end
    HN("Frame", {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(22,1), BackgroundColor3=ACCENT, BackgroundTransparency=0.25, BorderSizePixel=0}, HUD)
    HN("Frame", {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(1,22), BackgroundColor3=ACCENT, BackgroundTransparency=0.25, BorderSizePixel=0}, HUD)
    local function tickMark(x,y,w,h)
        HN("Frame", {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,x,0.5,y),
            Size=UDim2.fromOffset(w,h), BackgroundColor3=ACCENT_DARK, BorderSizePixel=0, BackgroundTransparency=0.4}, HUD)
    end
    tickMark(-24,-24,10,1) tickMark(-24,-24,1,10) tickMark(-24,-24,10,1) tickMark(-24,-24,1,10)
    tickMark(-24, 24,10,1) tickMark(-24, 24,1,10) tickMark(24, 24,10,1) tickMark(24, 24,1,10)
    local Banner = HN("Frame", {AnchorPoint=Vector2.new(0.5,0), Position=UDim2.new(0.5,0,0,14),
        Size=UDim2.fromOffset(210,22), BackgroundColor3=fromRGB(13,16,28), BackgroundTransparency=0.15, BorderSizePixel=0}, HUD)
    HN("UICorner", {CornerRadius=UDim.new(0,4)}, Banner)
    HN("TextLabel", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Font=Enum.Font.Code,
        TextSize=13, TextColor3=ACCENT, Text="venyx // FREECAM"}, Banner)
    local Panel = HN("Frame", {AnchorPoint=Vector2.new(0.5,1), Position=UDim2.new(0.5,0,1,-14),
        Size=UDim2.fromOffset(268,76), BackgroundColor3=fromRGB(8,10,18), BackgroundTransparency=0.15, BorderSizePixel=0}, HUD)
    HN("UICorner", {CornerRadius=UDim.new(0,5)}, Panel)
    HN("Frame", {Position=UDim2.new(0,5,0,0), Size=UDim2.new(1,-10,0,1), BackgroundColor3=ACCENT, BorderSizePixel=0}, Panel)
    HN("TextLabel", {Position=UDim2.fromOffset(8,8), Size=UDim2.new(1,-16,0,14), BackgroundTransparency=1,
        Font=Enum.Font.Code, TextSize=12, TextColor3=fromRGB(200,215,235),
        TextXAlignment=Enum.TextXAlignment.Left, Text="[WASD] fly   [Q] down   [E] up"}, Panel)
    HN("TextLabel", {Position=UDim2.fromOffset(8,23), Size=UDim2.new(1,-16,0,14), BackgroundTransparency=1,
        Font=Enum.Font.Code, TextSize=12, TextColor3=fromRGB(200,215,235),
        TextXAlignment=Enum.TextXAlignment.Left, Text="[SHIFT] slow: OFF", Name="SlowLabel"}, Panel)
    HN("TextLabel", {Position=UDim2.fromOffset(8,38), Size=UDim2.new(1,-16,0,14), BackgroundTransparency=1,
        Font=Enum.Font.Code, TextSize=12, TextColor3=fromRGB(200,215,235),
        TextXAlignment=Enum.TextXAlignment.Left, Text="[F] exit"}, Panel)
    HN("TextLabel", {Position=UDim2.fromOffset(8,53), Size=UDim2.new(1,-16,0,14), BackgroundTransparency=1,
        Font=Enum.Font.Code, TextSize=10, TextColor3=ACCENT_DARK,
        TextXAlignment=Enum.TextXAlignment.Left, Text="pos: 0,0,0", Name="PosLabel"}, Panel)
end

local function setFreecamBodyFrozen(frozen)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function() hrp.Anchored = frozen end)
end

function toggleFreecam()
    if not freecamActive then
        local look = Camera.CFrame.LookVector
        camPitch = math.asin(clamp(look.Y,-1,1))
        camYaw = math.atan2(-look.X, -look.Z)
        local char = LocalPlayer.Character
        local head = char and char:FindFirstChild("Head")
        camPos = (head and head.Parent and head.Position) or Camera.CFrame.Position
        freecamActive = true
        setFreecamBodyFrozen(true)
        hiddenGuis = {}
        local containers = { OKGui, LocalPlayer:FindFirstChildOfClass("PlayerGui") }
        for _,container in ipairs(containers) do
            if container then
                for _,g in ipairs(container:GetChildren()) do
                    if g:IsA("ScreenGui") and g.Enabled and g ~= HUD then
                        hiddenGuis[#hiddenGuis+1] = g
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
        for _,g in ipairs(hiddenGuis) do pcall(function() g.Enabled = true end) end
        hiddenGuis = {}
        HUD.Enabled = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
        Camera.CameraType = Enum.CameraType.Custom
    end
end

-- ─── Cleanup ──────────────────────────────────────────────
local syncMainWindow -- (assigned in UI section)

function venyx_Cleanup()
    -- ═══ 1. kill every runtime flag so the render loop goes fully idle ═══
    hookActive = false
    CurrentTarget = nil
    Holding = false
    st.aimbot, st.silentAim, st.fovVisible, st.espEnabled = false, false, false, false
    st.boxes, st.names, st.dist, st.health, st.held, st.skel = false, false, false, false, false, false
    st.highlight, st.viewcheck = false, true
    st.tracer, st.debugHud, st.triggerbot = false, false, false
    st.meleeAura = false
    st.fullbright, st.forceDay, st.vmEnabled = false, false, false
    st.bulletTracers = false
    noRecoil, noSpread = false, false
    PlayersSel = false
    table.clear(WorldSel)

    -- ═══ 2. live stops: trigger mouse, zoom, weapon settings ═══
    tbMouseUp()
    setZoomHolding(false)
    restoreAllSettings()

    if freecamActive then
        freecamActive = false
        setFreecamBodyFrozen(false)
        for _,g in ipairs(hiddenGuis) do pcall(function() g.Enabled = true end) end
        hiddenGuis = {}
        HUD.Enabled = false
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        pcall(function() UserInputService.MouseIconEnabled = true end)
        pcall(function() Camera.CameraType = Enum.CameraType.Custom end)
    end

    -- ═══ 3. destroy screen GUI + all Drawing objects ═══
    pcall(function() HUD:Destroy() end)
    pcall(function() fovCircle:Remove() end)
    pcall(function() fovOutline:Remove() end)
    pcall(function() tracerLine:Remove() end)
    pcall(function() tracerOutline:Remove() end)
    pcall(function() DebugText:Remove() end)
    pcall(function() DebugText2:Remove() end)
    pcall(function() DebugText3:Remove() end)
    pcall(function() DebugText4:Remove() end)

    -- ═══ 4. bullet tracer entries (restores bullet visibility too) ═══
    do
        local copy = table.clone(btActive)
        for _, e in ipairs(copy) do pcall(btRemoveEntry, e) end
    end

    -- ═══ 5. ESP drawings: every tracked player/world object ═══
    for inst in pairs(Tracked) do untrack(inst) end
    for player in pairs(PlayerDrawings) do clearPlayer(player) end

    -- ═══ 6. lighting fully restored ═══
    pcall(function()
        Lighting.Brightness=origBrightness; Lighting.Ambient=origAmbient
        Lighting.OutdoorAmbient=origOutdoor; Lighting.FogEnd=origFogEnd
        Lighting.FogStart=origFogStart; Lighting.GlobalShadows=origShadows
        Lighting.ClockTime=origClockTime
    end)
    pcall(function()
        Lighting.ExposureCompensation = origExposure
        Lighting.ColorShift_Top = origCSTop
        Lighting.ColorShift_Bottom = origCSBottom
    end)

    -- ═══ 7. body un-anchored (freecam freeze safety) ═══
    pcall(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Anchored = false end
    end)

    -- ═══ 8. default input behaviors ═══
    pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
    pcall(function() UserInputService.MouseIconEnabled = true end)

    -- ═══ 9. disconnect EVERY connection this script made ═══
    for i = #scriptConnections, 1, -1 do
        local conn = scriptConnections[i]
        if conn and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(scriptConnections)

    -- ═══ 10. if called from Panic (window stays open), visually clear UI ═══
    if syncMainWindow then
        pcall(function() syncMainWindow() end)
    end

    notify("venyx", "cleanup complete — features off, connections cut")
end

local SlowLabel, PosLabel

-- ─── CHUNKED world scanner ─────────────────────────────────
local SCAN_BUDGET       = 300
local CLEANUP_BUDGET    = 40
local PASS_COOLDOWN     = 240

local scanList          = nil
local scanIdx           = 1
local cooldownRemaining = 0

-- ─── Stats tracking ────────────────────────────────────────
local VIS_INTERVAL = 6
local frame = 0
local cameraFollowOffset = V3(0,2,10)
local scriptStartClock = os.clock()
local fpsSmooth = 60

keepConn(RunService.RenderStepped:Connect(function(dt)
    frame += 1
    if dt > 0 then fpsSmooth = fpsSmooth * 0.95 + (1 / dt) * 0.05 end

    if not Camera.Parent then Camera = Workspace.CurrentCamera or Camera end

    if frame % 10 == 0 then
        pcall(refreshSettingsEdits)
    end

    if zoomHolding then
        pcall(function()
            if Camera.FieldOfView ~= st.zoomFov then
                Camera.FieldOfView = st.zoomFov
            end
        end)
    else
        pcall(function()
            local f = Camera.FieldOfView
            if f ~= st.zoomFov then zoomSavedFov = f end
        end)
    end

    if st.espEnabled and worldAnySelected() then
        if scanList then
            local budgetLeft = SCAN_BUDGET
            while budgetLeft > 0 and scanIdx <= #scanList do
                local inst = scanList[scanIdx]
                scanIdx += 1
                budgetLeft -= 1
                if not Tracked[inst] and (inst:IsA("Model") or inst:IsA("BasePart")) then
                    local cat = classify(inst)
                    if cat then trackInstance(inst, cat) end
                end
            end
            if scanIdx > #scanList then
                scanList = nil
                cooldownRemaining = PASS_COOLDOWN
            end
        else
            if cooldownRemaining > 0 then
                cooldownRemaining -= 1
            elseif frame % 5 == 0 then
                scanList = Workspace:GetDescendants()
                scanIdx = 1
            end
        end
    end

    do
        local checked = 0
        for inst, t in pairs(Tracked) do
            if checked >= CLEANUP_BUDGET then break end
            checked += 1
            if not inst.Parent then
                untrack(inst)
            elseif t.anchor and not t.anchor.Parent then
                local newAnchor = t.isModel and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")) or inst
                if newAnchor then t.anchor = newAnchor else untrack(inst) end
            end
        end
    end

    if st.forceDay then
        if Lighting.ClockTime ~= 14 then
            pcall(function() Lighting:SetMinutesAfterMidnight(14*60) end)
        end
    end

    if st.fullbright then
        if Lighting.Brightness ~= 3 then Lighting.Brightness = 3 end
        if Lighting.FogEnd ~= 1e6 then Lighting.FogEnd = 1e6 end
        if Lighting.FogStart ~= 1e6 then Lighting.FogStart = 1e6 end
        if Lighting.GlobalShadows ~= false then Lighting.GlobalShadows = false end
        if Lighting.ExposureCompensation ~= 1.2 then Lighting.ExposureCompensation = 1.2 end
        if Lighting.Ambient ~= white then Lighting.Ambient = white; Lighting.OutdoorAmbient = white end
        if Lighting.ColorShift_Top ~= white then Lighting.ColorShift_Top = white; Lighting.ColorShift_Bottom = white end
        for _,fx in ipairs(lightingFx) do
            if fx:IsA("Atmosphere") then
                if fx.Density ~= 0 then fx.Density = 0 end
                if fx.Haze ~= 0 then fx.Haze = 0 end
            elseif fx:IsA("DepthOfFieldEffect") then
                if fx.Enabled then fx.Enabled = false end
            end
        end
    end

    if st.vmEnabled and frame % 15 == 0 then applyViewmodel() end

    -- cached frame values
    local lc       = LocalPlayer.Character
    local lRoot    = lc and lc:FindFirstChild("HumanoidRootPart")
    local lHead    = lc and lc:FindFirstChild("Head")
    local mousePos = UserInputService:GetMouseLocation()

    local espOn    = st.espEnabled
    local boxesOn  = st.boxes
    local namesOn  = st.names
    local distOn   = st.dist
    local healthOn = st.health
    local skelOn   = st.skel
    local hlOn     = st.highlight
    local viewcheckOn = st.viewcheck
    local thick    = st.espThickness
    local maxDist   = st.renderDist
    local maxDistSq = maxDist * maxDist
    local fontIdx  = espFontIndex()
    local txtSz    = st.textSize

    -- ── Aiming ──────────────────────────────────────────────
    local aimActive     = st.silentAim or st.aimbot
    local needTarget    = aimActive or st.tracer
    if needTarget then
        local tPlr, tPart, tRoot = pickTarget()
        if tPlr then
            local ball = getBallistics()
            local camPos3 = Camera.CFrame.Position
            local aimPoint = computeAimPoint(camPos3, tPart, tRoot, ball)
            CurrentTarget = { player=tPlr, part=tPart, root=tRoot, aimPoint=aimPoint }
        else
            CurrentTarget = nil
        end

        if not (st.aimbot and Holding) and lHead then
            local off = Camera.CFrame.Position - lHead.Position
            local m = off.Magnitude
            if m > 0.5 and m < 30 then
                cameraFollowOffset = off
            end
        end

        if st.aimbot and Holding and CurrentTarget and lHead then
            local camPosA = lHead.Position + cameraFollowOffset
            local delta = CurrentTarget.aimPoint - camPosA
            if delta.Magnitude > 0.01 then
                local targetCF = CFrame.new(camPosA, CurrentTarget.aimPoint)
                if st.aimSmooth <= 0 then
                    Camera.CFrame = targetCF
                else
                    local alpha = clamp(dt / math.max(st.aimSmooth, 0.016), 0, 1)
                    Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
                end
            end
        end

        if st.debugHud then
            DebugText.Text = "hook[" .. HookMethod .. "] seen: " .. GunFireSeen .. " redir: " .. ShotsRedirected
            DebugText.Visible = true
            DebugText2.Text = BallDebug .. " | lock: " .. (CurrentTarget and CurrentTarget.player.Name or "none")
            DebugText2.Visible = true
            local n = 0
            for _ in pairs(Tracked) do n += 1 end
            DebugText3.Text = "tracked: " .. n
            DebugText3.Visible = true
            DebugText4.Text = "aura: " .. MA_fires .. " @ " .. MA_lastTargetName .. " [" .. MA_status .. "]"
            DebugText4.Visible = true
        else
            DebugText.Visible = false; DebugText2.Visible = false
            DebugText3.Visible = false; DebugText4.Visible = false
        end
    else
        CurrentTarget = nil
        if st.debugHud then
            DebugText.Text = "aura: " .. MA_fires .. " @ " .. MA_lastTargetName .. " [" .. MA_status .. "]"
            DebugText.Visible = true
            DebugText2.Visible = false
            DebugText3.Visible = false
            DebugText4.Visible = false
        else
            DebugText.Visible=false; DebugText2.Visible=false; DebugText3.Visible=false; DebugText4.Visible=false
        end
    end

    -- ── FOV circle + tracer ────────────────────────────────
    fovCircle.Position = mousePos; fovOutline.Position = mousePos
    fovCircle.Radius = st.fovRadius;        fovOutline.Radius = st.fovRadius
    fovCircle.Thickness = st.fovThickness;  fovOutline.Thickness = st.fovThickness+1
    fovCircle.Color = st.fovColor
    fovCircle.Visible = st.fovVisible; fovOutline.Visible = st.fovVisible

    tracerLine.Color = st.fovColor
    if st.tracer and CurrentTarget then
        local sv = Camera:WorldToViewportPoint(CurrentTarget.part.Position)
        if sv.Z > 0 then
            local to = V2(sv.X, sv.Y)
            tracerOutline.From=mousePos; tracerOutline.To=to; tracerOutline.Visible=true
            tracerLine.From   =mousePos; tracerLine.To=to;    tracerLine.Visible=true
        else tracerOutline.Visible=false; tracerLine.Visible=false end
    else tracerOutline.Visible=false; tracerLine.Visible=false end

    pcall(btUpdate, os.clock())

    -- ── Triggerbot ──────────────────────────────────────────
    do
        if st.triggerbot and not freecamActive then
            local now = os.clock()

            local shouldFire
            if st.silentAim then
                shouldFire = targetValidForTriggerbot(lRoot)
            else
                shouldFire = crosshairOnEnemy()
            end
            if shouldFire then tbLastAcquireAt = now end

            local locked = shouldFire or (tbHolding and (now - tbLastAcquireAt) < TB_GRACE)

            if locked then
                local ball = getBallistics()
                local fireMode = (ball and type(ball.FireMode) == "string") and ball.FireMode or "Auto"
                if fireMode == "Semi" then
                    local cooldown = 60 / math.max((ball and typeof(ball.FireRateRPM) == "number") and ball.FireRateRPM or 600, 1)
                    if (now - tbLastClickAt) >= cooldown then
                        if tbHolding then tbMouseUp() end
                        tbMouseDown()
                        tbLastClickAt = now
                    end
                else
                    tbMouseDown()
                end
            else
                tbMouseUp()
            end
        else
            tbMouseUp()
        end
    end

    -- ── Melee aura (hardset 50 range) ───────────────────────
    if not freecamActive then
        pcall(meleeAuraStep, os.clock())
    end

    -- freecam
    if freecamActive then
        if Camera.CameraType ~= Enum.CameraType.Scriptable then
            Camera.CameraType = Enum.CameraType.Scriptable
        end
        if frame % 30 == 0 then setFreecamBodyFrozen(true) end
        if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
        local delta = UserInputService:GetMouseDelta()
        if delta.Magnitude > 0 then
            local sens = 0.22 * math.pi / 180
            camYaw = camYaw - delta.X * sens
            camPitch = clamp(camPitch - delta.Y * sens, -1.55, 1.55)
        end
        local rot = CFrame.fromEulerAnglesYXZ(camPitch, camYaw, 0)
        local fwd, right = rot.LookVector, rot.RightVector
        local move = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += fwd end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= fwd end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then move += V3(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move += V3(0,-1,0) end
        if move.Magnitude > 0 then
            local slow = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            local speed = slow and st.slowSpeed or st.flySpeed
            camPos += move.Unit * speed * dt
            if not SlowLabel then SlowLabel = HUD:FindFirstChild("SlowLabel", true) end
            if SlowLabel then
                SlowLabel.Text = "[SHIFT] slow: " .. (slow and "ON" or "OFF")
                SlowLabel.TextColor3 = slow and ACCENT or fromRGB(200,215,235)
            end
        end
        if not PosLabel then PosLabel = HUD:FindFirstChild("PosLabel", true) end
        if PosLabel then
            PosLabel.Text = string.format("pos: %.0f, %.0f, %.0f", camPos.X, camPos.Y, camPos.Z)
        end
        Camera.CFrame = CFrame.new(camPos) * rot
    end

    -- ── Player ESP ──────────────────────────────────────────
    -- PERF FIX: no per-player pcall wrapper (was a closure + pcall per
    -- player per frame); skeleton draws are individually wrapped instead.
    if espOn and PlayersSel then
        for player, e in pairs(PlayerDrawings) do
            local char = player.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
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
                        -- entry will be drawn this frame — clear hidden flag
                        e.hiddenFlag = false

                        local cx, cy = rv.X, rv.Y
                        local hv = Camera:WorldToViewportPoint(head.Position)
                        local dy = clamp((V2(hv.X,hv.Y) - V2(cx,cy)).Magnitude, 2, 1e9)
                        local hw, hh = dy*0.9, dy*1.9
                        local bL, bR = cx-hw, cx+hw
                        local bT, bB = cy-hh, cy+hh

                        if frame - e.visFrame >= VIS_INTERVAL then
                            e.visFrame = frame
                            if lHead and viewcheckOn then
                                e.isVisible = isVisibleChar(char, lc, lHead)
                            else
                                e.isVisible = true
                            end
                        end

                        local col = (Whitelist[player.Name] and st.frndCol) or (e.isVisible and st.visCol or st.hidCol)

                        if hlOn then
                            if not e.highlightRef or e.highlightRef.Parent ~= char then
                                if e.highlightRef then e.highlightRef:Destroy() end
                                local h = Instance.new("Highlight")
                                h.Name = "venyx_Highlight"
                                h.FillTransparency = 0.5
                                h.OutlineTransparency = 0
                                h.Parent = char
                                e.highlightRef = h
                            end
                            e.highlightRef.FillColor = col
                            e.highlightRef.OutlineColor = st.visCol
                        else
                            if e.highlightRef then e.highlightRef:Destroy(); e.highlightRef = nil end
                        end

                        if boxesOn then
                            drawESPBox(e, bL, bT, bR, bB, col, thick)
                        else
                            e.box.Visible=false; e.blackbox.Visible=false
                            hideESPBoxSegs(e)
                        end

                        if namesOn then
                            e.name.Position=V2(cx,bT-14); e.name.Text=char.Name
                            e.name.Color=col; e.name.Font=fontIdx; e.name.Size=txtSz; e.name.Visible=true
                        else e.name.Visible=false end

                        if distOn then
                            local d=round((lRoot.Position-root.Position).Magnitude)
                            e.dist.Position=V2(cx,bB+4); e.dist.Text=d.."m"
                            e.dist.Color=col; e.dist.Font=fontIdx; e.dist.Size=txtSz; e.dist.Visible=true
                        else e.dist.Visible=false end

                        if healthOn then
                            local maxHP=hum.MaxHealth>0 and hum.MaxHealth or 100
                            local pct=clamp(hum.Health/maxHP,0,1)
                            local barX=bL-5
                            e.hpbg.From=V2(barX,bT); e.hpbg.To=V2(barX,bB); e.hpbg.Visible=true
                            e.hpfill.From=V2(barX,bB-(hh*2*pct)); e.hpfill.To=V2(barX,bB)
                            e.hpfill.Color=hpColor(pct); e.hpfill.Visible=true
                        else e.hpbg.Visible=false; e.hpfill.Visible=false end

                        if st.held then
                            local tool = char:FindFirstChildOfClass("Tool")
                            if tool then
                                local iy = distOn and (bB+18) or (bB+4)
                                e.item.Position=V2(cx,iy); e.item.Text=tool.Name
                                e.item.Color=col; e.item.Font=fontIdx; e.item.Size=txtSz; e.item.Visible=true
                            else e.item.Visible=false end
                        else e.item.Visible=false end

                        if skelOn then
                            -- PERF: bones created lazily on first skeleton draw
                            if not e.bones then
                                e.bones = {}
                                for _,k in ipairs(BONE_KEYS) do
                                    e.bones[k] = { o=newLine(3,black), l=newLine(1,white) }
                                end
                            end
                            _bones=e.bones; _thick=thick; _col=col; _cam=Camera
                            if char:FindFirstChild("Torso") then
                                pcall(drawSkeletonR6, char, head)
                            elseif char:FindFirstChild("UpperTorso") then
                                pcall(drawSkeletonR15, char, head)
                            else
                                hideBones(e.bones)
                            end
                        elseif e.bones then
                            hideBones(e.bones)
                        end
                    end
                end
            else
                -- no local root (dead/loading) — keep 'if shown' logic simple
                local rv = Camera:WorldToViewportPoint(root.Position)
                if rv.Z <= 0 then
                    hideEntry(e)
                else
                    e.hiddenFlag = false
                    local cx, cy = rv.X, rv.Y
                    local hv = Camera:WorldToViewportPoint(head.Position)
                    local dy = clamp((V2(hv.X,hv.Y) - V2(cx,cy)).Magnitude, 2, 1e9)
                    local hw, hh = dy*0.9, dy*1.9
                    local bL, bR = cx-hw, cx+hw
                    local bT, bB = cy-hh, cy+hh

                    if frame - e.visFrame >= VIS_INTERVAL then
                        e.visFrame = frame
                        e.isVisible = true
                    end

                    local col = (Whitelist[player.Name] and st.frndCol) or (e.isVisible and st.visCol or st.hidCol)

                    if hlOn then
                        if not e.highlightRef or e.highlightRef.Parent ~= char then
                            if e.highlightRef then e.highlightRef:Destroy() end
                            local h = Instance.new("Highlight")
                            h.Name = "venyx_Highlight"
                            h.FillTransparency = 0.5
                            h.OutlineTransparency = 0
                            h.Parent = char
                            e.highlightRef = h
                        end
                        e.highlightRef.FillColor = col
                        e.highlightRef.OutlineColor = st.visCol
                    else
                        if e.highlightRef then e.highlightRef:Destroy(); e.highlightRef = nil end
                    end

                    if boxesOn then
                        drawESPBox(e, bL, bT, bR, bB, col, thick)
                    else
                        e.box.Visible=false; e.blackbox.Visible=false
                        hideESPBoxSegs(e)
                    end

                    if namesOn then
                        e.name.Position=V2(cx,bT-14); e.name.Text=char.Name
                        e.name.Color=col; e.name.Font=fontIdx; e.name.Size=txtSz; e.name.Visible=true
                    else e.name.Visible=false end

                    if healthOn then
                        local maxHP=hum.MaxHealth>0 and hum.MaxHealth or 100
                        local pct=clamp(hum.Health/maxHP,0,1)
                        local barX=bL-5
                        e.hpbg.From=V2(barX,bT); e.hpbg.To=V2(barX,bB); e.hpbg.Visible=true
                        e.hpfill.From=V2(barX,bB-(hh*2*pct)); e.hpfill.To=V2(barX,bB)
                        e.hpfill.Color=hpColor(pct); e.hpfill.Visible=true
                    else e.hpbg.Visible=false; e.hpfill.Visible=false end

                    if st.held then
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool then
                            local iy = (bB+4)
                            e.item.Position=V2(cx,iy); e.item.Text=tool.Name
                            e.item.Color=col; e.item.Font=fontIdx; e.item.Size=txtSz; e.item.Visible=true
                        else e.item.Visible=false end
                    else e.item.Visible=false end

                    if skelOn then
                        if not e.bones then
                            e.bones = {}
                            for _,k in ipairs(BONE_KEYS) do
                                e.bones[k] = { o=newLine(3,black), l=newLine(1,white) }
                            end
                        end
                        _bones=e.bones; _thick=thick; _col=col; _cam=Camera
                        if char:FindFirstChild("Torso") then
                            pcall(drawSkeletonR6, char, head)
                        elseif char:FindFirstChild("UpperTorso") then
                            pcall(drawSkeletonR15, char, head)
                        else
                            hideBones(e.bones)
                        end
                    elseif e.bones then
                        hideBones(e.bones)
                    end
                end
            end
        end
    else
        for _,e in pairs(PlayerDrawings) do hideEntry(e) end
    end

    -- ── World object ESP ────────────────────────────────────
    -- PERF FIX: no per-object pcall wrapper; hiddenFlag makes
    -- deselected/hidden objects cost ~nothing per frame.
    for inst, t in pairs(Tracked) do
        local catInfo = WorldCategories[t.cat]
        if espOn and catInfo and WorldSel[catInfo.flag] and t.anchor and t.anchor.Parent then
            local inRange = true
            if lRoot then
                local ap = t.anchor.Position
                local dx = ap.X - lRoot.Position.X
                local dy2 = ap.Y - lRoot.Position.Y
                local dz = ap.Z - lRoot.Position.Z
                inRange = (dx*dx + dy2*dy2 + dz*dz) <= maxDistSq
            end

            if inRange then
                local min, max
                if t.isModel then
                    local ok, cf, size = pcall(inst.GetBoundingBox, inst)
                    if ok and cf then min, max = projectBox(cf.Position, size/2) end
                else
                    min, max = projectBox(inst.Position, inst.Size/2)
                end

                if not min then
                    hideEntry(t.draw)
                else
                    t.draw.hiddenFlag = false
                    local col = catInfo.color
                    local cx2 = (min.X+max.X)/2

                    if boxesOn then
                        drawESPBox(t.draw, min.X, min.Y, max.X, max.Y, col, thick)
                    else
                        t.draw.box.Visible=false; t.draw.blackbox.Visible=false
                        hideESPBoxSegs(t.draw)
                    end

                    if namesOn then
                        t.draw.name.Position=V2(cx2,min.Y-14); t.draw.name.Text=catInfo.label
                        t.draw.name.Color=col; t.draw.name.Font=fontIdx; t.draw.name.Size=txtSz; t.draw.name.Visible=true
                    else t.draw.name.Visible=false end

                    if distOn and lRoot then
                        local d=round((lRoot.Position-t.anchor.Position).Magnitude)
                        t.draw.dist.Position=V2(cx2,max.Y+4); t.draw.dist.Text=d.."m"
                        t.draw.dist.Color=col; t.draw.dist.Font=fontIdx; t.draw.dist.Size=txtSz; t.draw.dist.Visible=true
                    else t.draw.dist.Visible=false end

                    t.draw.hpbg.Visible=false; t.draw.hpfill.Visible=false
                end
            else
                hideEntry(t.draw)
            end
        else
            hideEntry(t.draw)
        end
    end
end))

keepConn(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    cachedToolRef, cachedEnv, cachedBallistics = nil, nil, nil
    settingsToolRefForEdits = nil
    tbHolding = false
    MA_lastSwingAt = 0
    if freecamActive then setFreecamBodyFrozen(true) end
    if st.vmEnabled then applyViewmodel() end
end))

-- ═════════════════════════════════════════════
--  UI
-- ═══════════════════════════════════════════

local GeneralTab   = Window:CreateTab("General & Stats")
local CombatTab    = Window:CreateTab("Combat Mods")
local VisualsTab   = Window:CreateTab("Visuals & ESP")
local ClientTab    = Window:CreateTab("Client Settings")
local SettingsTab  = Window:CreateTab("System Settings")

local BOX_STYLES = {"Bounding Box","Corner Brackets","Angular"}
local ESP_FONTS  = {"UI [0]","System [1]","Plex [2]","Monospace [3]"}

-- ─── SAFE LABEL HELPER ─────────────────────────────────────
local function safeLabel(tab, text)
    if not tab or type(tab.AddLabel) ~= "function" then
        warn("[UI Error]: Invalid tab provided to safeLabel!")
        return nil
    end

    return tab:AddLabel(tostring(text or ""))
end

-- text divider between sections
local function addDivider(tab, title)
    safeLabel(tab, "")
    safeLabel(tab, "# "..title)
end

-- ═══ CONFIG SYSTEM v3 (Color3 serialization) ═════════════════════
local SAVES_FOLDER = "venyx_saves"

local SERIALIZABLE_STATE_KEYS = {
    "aimbot","aimSmooth","silentAim","wallCheck","triggerbot","tbMaxDist","meleeAura",
    "tracer","debugHud","targetPart",
    "fovVisible","fovRadius","fovThickness",
    "espEnabled","boxes","names","dist","health","held","skel","highlight","viewcheck",
    "espThickness","renderDist","boxStyle","textFont","textSize",
    "flySpeed","slowSpeed","zoomFov",
    "fullbright","forceDay",
    "vmEnabled","vmMaterial","vmTransparency",
    "bulletTracers","tracerTime","tracerMax",
}

local COLOR_STATE_KEYS = {
    "fovColor","visCol","hidCol","frndCol","vmColor","tracerColor",
}

-- widget registry — plain widgets stored directly under their key;
-- checkbox groups stored under __keys and synced separately
local widgetRegistry = {}
local function registerWidget(key, widget)
    if not widget then return end
    widgetRegistry[key] = widget
end

-- (assigned to the forward-declared local so venyx_Cleanup can call it)
function syncMainWindow()
    for key, w in pairs(widgetRegistry) do
        if key:sub(1,2) ~= "__" then
            local value = st[key]
            if value ~= nil then
                pcall(function() w:SetValue(value) end)
                pcall(function() w:Set(value) end)
            end
        end
    end

    if widgetRegistry.__combatModules then
        pcall(function()
            widgetRegistry.__combatModules:SetValue({
                ["Aimbot"]     = st.aimbot,
                ["Silent Aim"] = st.silentAim,
                ["Wallcheck"]  = st.wallCheck,
                ["Triggerbot"] = st.triggerbot,
                ["Melee Aura"] = st.meleeAura,
            })
        end)
    end

    if widgetRegistry.__weaponModules then
        pcall(function()
            widgetRegistry.__weaponModules:SetValue({
                ["No Recoil"] = noRecoil,
                ["No Spread"] = noSpread,
            })
        end)
    end

    if widgetRegistry.__espModules then
        pcall(function()
            widgetRegistry.__espModules:SetValue({
                ["Boxes"]      = st.boxes,
                ["Names"]      = st.names,
                ["Distance"]   = st.dist,
                ["Health Bar"] = st.health,
                ["Skeleton"]   = st.skel,
                ["Highlight"]  = st.highlight,
                ["Held Item"]  = st.held,
                ["Viewcheck"]  = st.viewcheck,
            })
        end)
    end

    if widgetRegistry.__targetObjects then
        pcall(function()
            widgetRegistry.__targetObjects:SetValue({
                ["Players"]          = PlayersSel,
                ["Drones"]          = WorldSel["sel_drones"] == true,
                ["Iron Ore"]        = WorldSel["sel_iron"]   == true,
                ["Sulfur Ore"]      = WorldSel["sel_sulfur"] == true,
                ["Stone"]           = WorldSel["sel_stone"]  == true,
                ["Trees"]           = WorldSel["sel_trees"]  == true,
                ["Brown Crates"]    = WorldSel["sel_brown"]  == true,
                ["Military Crates"] = WorldSel["sel_mil"]   == true,
                ["Elite Crates"]    = WorldSel["sel_elite"]  == true,
            })
        end)
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
            if name then list[#list+1] = name end
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
    for _, key in ipairs(SERIALIZABLE_STATE_KEYS) do
        data[key] = st[key]
    end
    local colors = {}
    for _, key in ipairs(COLOR_STATE_KEYS) do
        colors[key] = colorToTable(st[key])
    end
    data.colors = colors
    data.noRecoil  = noRecoil
    data.noSpread  = noSpread
    data.PlayersSel = PlayersSel
    data.WorldSel   = WorldSel
    data.Whitelist  = Whitelist
    return game:GetService("HttpService"):JSONEncode(data)
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

local function loadConfig(name)
    local ok, json = pcall(function()
        return readfile(savePath(name))
    end)
    if not ok or not json then
        notify("Config", "could not read '" .. tostring(name) .. "'")
        return false
    end
    local ok2, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(json)
    end)
    if not ok2 or type(data) ~= "table" then
        notify("Config", "corrupt config '" .. tostring(name) .. "'")
        return false
    end
    for _, key in ipairs(SERIALIZABLE_STATE_KEYS) do
        if data[key] ~= nil and type(data[key]) == type(st[key]) then
            st[key] = data[key]
        end
    end
    if type(data.colors) == "table" then
        for _, key in ipairs(COLOR_STATE_KEYS) do
            local c = tableToColor(data.colors[key])
            if c then st[key] = c end
        end
    end
    if data.noRecoil  ~= nil then noRecoil  = data.noRecoil  == true end
    if data.noSpread  ~= nil then noSpread  = data.noSpread  == true end
    if data.PlayersSel ~= nil then PlayersSel = data.PlayersSel == true end
    if type(data.WorldSel) == "table" then
        table.clear(WorldSel)
        for k, v in pairs(data.WorldSel) do WorldSel[k] = v == true end
    end
    if type(data.Whitelist) == "table" then
        table.clear(Whitelist)
        for k, v in pairs(data.Whitelist) do Whitelist[k] = v == true end
    end
    Holding = false
    tbMouseUp()
    pcall(refreshSettingsEdits)
    if st.vmEnabled then applyViewmodel() end
    pcall(syncMainWindow)
    notify("Config", "loaded '" .. name .. "' (UI synced)")
    return true
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

-- ── TAB 1: GENERAL & STATS ──
;(function()
    safeLabel(GeneralTab, "WELCOME, " .. LocalPlayer.DisplayName:upper() .. " [" .. LocalPlayer.Name .. "]")
    safeLabel(GeneralTab, "SYSTEM STATUS: ONLINE / SECURE")

    addDivider(GeneralTab, "GAME INFO")

    local gameName = game.Name or "Unknown"
    pcall(function()
        gameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or gameName
    end)

    local upTimeLabel  = safeLabel(GeneralTab, "session uptime: 0s")
    safeLabel(GeneralTab, "game: " .. gameName)
    safeLabel(GeneralTab, "place id: " .. game.PlaceId)
    safeLabel(GeneralTab, "job id: " .. game.JobId)
    safeLabel(GeneralTab, "server time: " .. os.date("%H:%M:%S UTC", Workspace:GetServerTimeNow()))

    addDivider(GeneralTab, "SESSION STATS")

    local statFramesLabel = safeLabel(GeneralTab, "fps: --")
    local statPingLabel   = safeLabel(GeneralTab, "ping: -- ms")
    local statPlrLabel   = safeLabel(GeneralTab, "players: --/--")
    safeLabel(GeneralTab, "max players: " .. Players.MaxPlayers)

    addDivider(GeneralTab, "ACCOUNT INFO")

    safeLabel(GeneralTab, "account age: " .. LocalPlayer.AccountAge .. " days")
    safeLabel(GeneralTab, "user id: " .. LocalPlayer.UserId)

    addDivider(GeneralTab, "HARDWARE")

    local statMemLabel = safeLabel(GeneralTab, "memory: -- mb")

    task.spawn(function()
        while true do
            task.wait(2)
            pcall(function()
                local uptimeSec = floor(os.clock() - scriptStartClock)
                local mins = floor(uptimeSec / 60)
                local secs = uptimeSec % 60
                if upTimeLabel then
                    upTimeLabel.Text = "session uptime: " .. mins .. "m " .. secs .. "s"
                end
            end)
            pcall(function()
                if statFramesLabel then statFramesLabel.Text = "fps: " .. floor(fpsSmooth + 0.5) end
            end)
            pcall(function()
                local ping = 0
                pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
                if statPingLabel then statPingLabel.Text = "ping: " .. floor(ping) .. " ms" end
            end)
            pcall(function()
                if statPlrLabel then statPlrLabel.Text = "players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers end
            end)
            pcall(function()
                if statMemLabel then statMemLabel.Text = "memory: " .. floor(Stats:GetTotalMemoryUsageMb()) .. " mb" end
            end)
        end
    end)

    addDivider(GeneralTab, "ACTIONS")

    GeneralTab:AddButton("Execute Diagnostic Scan", function()
        local ping = "n/a"
        pcall(function() ping = floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) .. "ms" end)
        print("[venyx]: Diagnostic scan -> fps " .. floor(fpsSmooth) .. " | ping " .. ping ..
            " | players " .. #Players:GetPlayers() .. " | uptime " .. floor(os.clock() - scriptStartClock) .. "s")
    end)
    GeneralTab:AddButton("Rejoin Server", function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    end)
end)()

-- ── TAB 2: COMBAT MODS ──
;(function()
    safeLabel(CombatTab, "COMBAT MODULES")

    registerWidget("__combatModules", CombatTab:AddCheckboxGroup("Primary Combat Modules",
        {"Aimbot", "Silent Aim", "Wallcheck", "Triggerbot", "Melee Aura"}, function(activeStates)
            st.aimbot     = activeStates["Aimbot"]     == true
            st.silentAim  = activeStates["Silent Aim"] == true
            st.wallCheck  = activeStates["Wallcheck"]  == true
            st.triggerbot = activeStates["Triggerbot"] == true
            st.meleeAura  = activeStates["Melee Aura"] == true
            if not st.aimbot then Holding = false end
            if not st.triggerbot then tbMouseUp() end
        end))

    CombatTab:AddKeybind("Aimbot Keybind", Enum.KeyCode.E, function(key)
        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            st.aimKey = key
        end
        if st.aimbot then Holding = true end
    end)

    CombatTab:AddSlider("Aimbot Smoothness", 0, 1, 0, function(v)
        st.aimSmooth = v
    end)

    CombatTab:AddSlider("Triggerbot Max Distance", 50, 2000, 1000, function(v)
        st.tbMaxDist = v
    end)

    -- Melee Aura range is HARDSET (MELEE_RANGE = 50)

    CombatTab:AddDropdown("Combat Target Part", {"HumanoidRootPart", "Head", "Torso", "Find Closest Part"}, "HumanoidRootPart", function(v)
        st.targetPart = v
    end)

    CombatTab:AddToggle("Debug HUD", false, function(v)
        st.debugHud = v
    end)

    addDivider(CombatTab, "FIELD OF VIEW")

    registerWidget("fovVisible", CombatTab:AddToggle("FOV Circle", false, function(v)
        st.fovVisible = v
    end))

    registerWidget("tracer", CombatTab:AddToggle("Target Tracer", false, function(v)
        st.tracer = v
    end))

    registerWidget("fovRadius", CombatTab:AddSlider("FOV Circle Radius", 10, 500, 100, function(v)
        st.fovRadius = v
    end))

    registerWidget("fovColor", CombatTab:AddColorPicker("FOV Circle Color", white, function(c)
        st.fovColor = c
    end))

    registerWidget("fovThickness", CombatTab:AddSlider("FOV Circle Thickness", 1, 5, 1, function(v)
        st.fovThickness = v
    end))

    addDivider(CombatTab, "WEAPON MODULES")

    registerWidget("__weaponModules", CombatTab:AddCheckboxGroup("Primary Weapon Modules",
        {"No Recoil", "No Spread"}, function(activeStates)
            noRecoil = activeStates["No Recoil"] == true
            noSpread = activeStates["No Spread"] == true
            pcall(refreshSettingsEdits)
        end))
end)()

-- ── TAB 3: VISUALS & ESP ──
;(function()
    safeLabel(VisualsTab, "ESP MODULES")

    registerWidget("espEnabled", VisualsTab:AddToggle("ESP Enabled", false, function(v)
        st.espEnabled = v
    end))

    registerWidget("__espModules", VisualsTab:AddCheckboxGroup("Primary ESP Modules",
        {"Boxes", "Names", "Distance", "Health Bar", "Skeleton", "Highlight", "Held Item", "Viewcheck"}, function(activeStates)
            st.boxes     = activeStates["Boxes"]      == true
            st.names     = activeStates["Names"]      == true
            st.dist      = activeStates["Distance"]    == true
            st.health    = activeStates["Health Bar"] == true
            st.skel      = activeStates["Skeleton"]   == true
            st.highlight = activeStates["Highlight"]  == true
            st.held      = activeStates["Held Item"]  == true
            st.viewcheck = activeStates["Viewcheck"]  == true
        end))

    registerWidget("espThickness", VisualsTab:AddSlider("ESP Thickness", 1, 5, 1, function(v)
        st.espThickness = v
    end))

    registerWidget("renderDist", VisualsTab:AddSlider("ESP Render Distance", 0, 5000, 5000, function(v)
        st.renderDist = v
    end))

    addDivider(VisualsTab, "ESP CUSTOMIZATION")

    registerWidget("visCol", VisualsTab:AddColorPicker("Visible Color", yellow, function(c)
        st.visCol = c
    end))

    registerWidget("hidCol", VisualsTab:AddColorPicker("Hidden Color", white, function(c)
        st.hidCol = c
    end))

    registerWidget("frndCol", VisualsTab:AddColorPicker("Friendly Color", green, function(c)
        st.frndCol = c
    end))

    registerWidget("boxStyle", VisualsTab:AddDropdown("ESP Boxes", BOX_STYLES, "Bounding Box", function(v)
        st.boxStyle = v
    end))

    registerWidget("textFont", VisualsTab:AddDropdown("ESP Text", ESP_FONTS, "Plex [2]", function(v)
        st.textFont = v
    end))

    registerWidget("textSize", VisualsTab:AddSlider("ESP Text Size", 9, 16, 11, function(v)
        st.textSize = v
    end))

    addDivider(VisualsTab, "TARGETED OBJECTS")

    registerWidget("__targetObjects", VisualsTab:AddCheckboxGroup("Targeted Objects",
        {"Players", "Drones", "Iron Ore", "Sulfur Ore", "Stone", "Trees", "Brown Crates", "Military Crates", "Elite Crates"}, function(activeStates)
            PlayersSel             = activeStates["Players"]          == true
            WorldSel["sel_drones"] = activeStates["Drones"]          == true
            WorldSel["sel_iron"]   = activeStates["Iron Ore"]        == true
            WorldSel["sel_sulfur"] = activeStates["Sulfur Ore"]      == true
            WorldSel["sel_stone"]  = activeStates["Stone"]           == true
            WorldSel["sel_trees"]  = activeStates["Trees"]            == true
            WorldSel["sel_brown"]  = activeStates["Brown Crates"]    == true
            WorldSel["sel_mil"]    = activeStates["Military Crates"]  == true
            WorldSel["sel_elite"]  = activeStates["Elite Crates"]    == true
        end))
end)()

-- ── TAB 4: CLIENT SETTINGS ──
;(function()
    safeLabel(ClientTab, "ZOOM")

    ClientTab:AddKeybind("Zoom Key", Enum.KeyCode.Z, function(key)
        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            st.zoomKey = key
            setZoomHolding(true)
        end
    end)
    registerWidget("zoomFov", ClientTab:AddSlider("Zoom FOV", 5, 30, 10, function(v)
        st.zoomFov = v
        if zoomHolding then
            pcall(function() Camera.FieldOfView = v end)
        end
    end))

    addDivider(ClientTab, "FREECAM")

    ClientTab:AddKeybind("Toggle Freecam", Enum.KeyCode.F, function()
        toggleFreecam()
    end)
    registerWidget("flySpeed", ClientTab:AddSlider("Fly Speed", 5, 120, 40, function(v) st.flySpeed = v end))
    registerWidget("slowSpeed", ClientTab:AddSlider("Slow Speed", 1, 40, 8, function(v) st.slowSpeed = v end))

    addDivider(ClientTab, "VIEWMODEL")

    registerWidget("vmEnabled", ClientTab:AddToggle("Viewmodel Enabled", false, function(v)
        st.vmEnabled = v
        if v then applyViewmodel() end
    end))

    registerWidget("vmMaterial", ClientTab:AddDropdown("Viewmodel Material", {"ForceField","Neon","Glass","Metal","DiamondPlate","Plastic","SmoothPlastic","Ice","Marble","Granite","Grass","Sand"}, "ForceField", function(v)
        st.vmMaterial = v
        if st.vmEnabled then applyViewmodel() end
    end))

    registerWidget("vmColor", ClientTab:AddColorPicker("Viewmodel Color", fromRGB(0,170,255), function(c)
        st.vmColor = c
        if st.vmEnabled then applyViewmodel() end
    end))

    registerWidget("vmTransparency", ClientTab:AddSlider("Viewmodel Transparency", 0, 100, 50, function(v)
        st.vmTransparency = v / 100
        if st.vmEnabled then applyViewmodel() end
    end))

    addDivider(ClientTab, "BULLET TRACERS")

    registerWidget("bulletTracers", ClientTab:AddToggle("Bullet Tracers", false, function(v)
        st.bulletTracers = v
    end))

    registerWidget("tracerColor", ClientTab:AddColorPicker("Tracer Color", yellow, function(c)
        st.tracerColor = c
    end))

    registerWidget("tracerTime", ClientTab:AddSlider("Time On Screen", 0.5, 10, 3, function(v)
        st.tracerTime = v
    end))

    registerWidget("tracerMax", ClientTab:AddSlider("Max On Screen", 1, 200, 50, function(v)
        st.tracerMax = v
    end))

    addDivider(ClientTab, "LIGHTING FX")

    registerWidget("fullbright", ClientTab:AddToggle("Fullbright", false, function(v)
        st.fullbright = v
        if not v then
            Lighting.Brightness=origBrightness; Lighting.Ambient=origAmbient
            Lighting.OutdoorAmbient=origOutdoor; Lighting.FogEnd=origFogEnd
            Lighting.FogStart=origFogStart; Lighting.GlobalShadows=origShadows
            Lighting.ExposureCompensation=origExposure
            Lighting.ColorShift_Top=origCSTop; Lighting.ColorShift_Bottom=origCSBottom
        end
    end))

    registerWidget("forceDay", ClientTab:AddToggle("Force Day", false, function(v)
        st.forceDay = v
        if not v then Lighting.ClockTime = origClockTime end
    end))

    addDivider(ClientTab, "MENU")

    ClientTab:AddKeybind("Toggle Menu Animation", Enum.KeyCode.RightShift, function(key)
        Window:Toggle()
    end)
end)()

-- ── TAB 5: SYSTEM SETTINGS ──
;(function()
    safeLabel(SettingsTab, "CONFIG SAVES")

    local selectedSave = nil
    local savesDropdownWidget = nil

    local function refreshSaveList()
        local list = getSavesList()
        local ok = false
        if savesDropdownWidget then
            ok = pcall(function()
                if typeof(savesDropdownWidget.SetOptions) == "function" then
                    savesDropdownWidget:SetOptions(list)
                elseif type(savesDropdownWidget.options) == "table" then
                    savesDropdownWidget.options = list
                elseif savesDropdownWidget.object and type(savesDropdownWidget.object) == "table" then
                    if typeof(savesDropdownWidget.object.SetOptions) == "function" then
                        savesDropdownWidget.object:SetOptions(list)
                    elseif type(savesDropdownWidget.object.Options) == "table" then
                        savesDropdownWidget.object.Options = list
                    else
                        error("no options setter")
                    end
                else
                    error("no refresh API")
                end
            end)
        end
        if not ok then
            notify("Config", "dropdown refresh unsupported — use Load Save By Name")
        end
        if #list > 0 then
            if not selectedSave or not tfind(list, selectedSave) then
                selectedSave = list[1]
            end
        else
            selectedSave = nil
            notify("Config", "no saves on disk")
        end
    end

    do
        local list = getSavesList()
        if #list > 0 then
            savesDropdownWidget = SettingsTab:AddDropdown("Select Save", list, list[1], function(v)
                selectedSave = v
            end)
            selectedSave = list[1]
        else
            safeLabel(SettingsTab, "no saves on disk")
        end
    end

    SettingsTab:AddButton("Refresh Save List", function()
        refreshSaveList()
        notify("Config", "list refreshed (" .. #getSavesList() .. " saves)")
    end)

    SettingsTab:AddButton("Load Selected Save", function()
        if selectedSave then
            loadConfig(selectedSave)
        else
            notify("Config", "no save selected")
        end
    end)

    SettingsTab:AddTextBox("Load Save By Name", "exact save name...", function(text, enterPressed)
        if enterPressed and text ~= "" then
            if loadConfig(text) then
                selectedSave = text
            end
        end
    end)

    safeLabel(SettingsTab, "")

    local pendingSaveName = ""
    SettingsTab:AddTextBox("New Save Name", "save name...", function(text, enterPressed)
        pendingSaveName = text or ""
        if enterPressed and pendingSaveName ~= "" then
            if saveConfig(pendingSaveName) then
                refreshSaveList()
            end
        end
    end)

    SettingsTab:AddButton("Create / Overwrite Save", function()
        if pendingSaveName ~= "" then
            if saveConfig(pendingSaveName) then
                selectedSave = pendingSaveName
                refreshSaveList()
            end
        else
            notify("Config", "enter a save name first")
        end
    end)

    SettingsTab:AddButton("Delete Selected Save", function()
        if selectedSave then
            if deleteSave(selectedSave) then
                selectedSave = nil
                refreshSaveList()
            end
        else
            notify("Config", "no save selected")
        end
    end)

    SettingsTab:AddButton("Clear All Saves", function()
        if clearAllSaves() then
            selectedSave = nil
            refreshSaveList()
        end
    end)

    addDivider(SettingsTab, "WHITELIST")

    SettingsTab:AddTextBox("Add Player", "player name...", function(text, enterPressed)
        if enterPressed and text ~= "" then
            for _, p in ipairs(Players:GetPlayers()) do
                if string.lower(p.Name):sub(1,#text) == string.lower(text)
                or string.lower(p.DisplayName):sub(1,#text) == string.lower(text) then
                    if Whitelist[p.Name] then
                        Whitelist[p.Name] = nil
                        notify("Whitelist", p.Name .. " removed")
                    else
                        Whitelist[p.Name] = true
                        notify("Whitelist", p.Name .. " added")
                    end
                end
            end
        end
    end)
    SettingsTab:AddButton("Clear Whitelist", function()
        table.clear(Whitelist)
        notify("Whitelist", "Cleared")
    end)

    addDivider(SettingsTab, "MISC")

    SettingsTab:AddKeybind("Panic Key", Enum.KeyCode.End, function()
        venyx_Cleanup()
        Window:Toggle()
    end)

    SettingsTab:AddButton("Rejoin Server", function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    end)

    SettingsTab:AddButton("Purge & Unload UI Completely", function()
        venyx_Cleanup()
        pcall(function() Window:Destroy() end)
    end)

    addDivider(SettingsTab, "STATUS")

    safeLabel(SettingsTab, " - Config system: runtime refresh + UI sync + color saves ENABLED")
    safeLabel(SettingsTab, " - Cleanup: full unload — connections + drawings + lighting on purge")
    safeLabel(SettingsTab, " - ColorPickers: RGB live")
end)()

notify("venyx", "welcome, have fun")
