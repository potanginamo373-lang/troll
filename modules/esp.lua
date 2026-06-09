return function(ctx)
    local Runtime = ctx and ctx.Runtime or {}
    local cloneref = Runtime.cloneref or cloneref or function(v)
        return v
    end
    local clonefunction = Runtime.clonefunction or clonefunction or function(v)
        return v
    end
    local Services = ctx and ctx.Services or {}

    local Workspace = Services.Workspace or cloneref(game:GetService("Workspace"))
    local RunService = Services.RunService or cloneref(game:GetService("RunService"))
    local UserInputService = Services.UserInputService or cloneref(game:GetService("UserInputService"))

    local tickFn = tick
    local acos = math.acos
    local min = math.min
    local max = math.max
    local rad = math.rad
    local huge = math.huge
    local Vector2new = Vector2.new
    local Vector3new = Vector3.new

    local ESP_ENABLED = false
    local TEAM_CHECK = true

    local PLAYER_BOX_ENABLED = true
    local PLAYER_BOX_COLOR = Color3.fromRGB(210, 50, 80)
    local PLAYER_BOX_THICK = 2
    local PLAYER_BOX_TRANSP = 1

    local OBJECT_BOX_ENABLED = true
    local OBJECT_NAME_ENABLED = true
    local OBJECT_NAME_SIZE = 14
    local DRONE_BOX_COLOR = Color3.fromRGB(0, 255, 255)
    local CLAYMORE_BOX_COLOR = Color3.fromRGB(255, 0, 0)
    local PROXIMITY_ALARM_BOX_COLOR = Color3.fromRGB(255, 165, 0)
    local STICKY_CAMERA_BOX_COLOR = Color3.fromRGB(255, 192, 203)
    local REMOTE_C4_BOX_COLOR       = Color3.fromRGB(255, 50, 50)
    local THERMITE_BOX_COLOR        = Color3.fromRGB(255, 140, 0)
    local TOXIC_BOX_COLOR           = Color3.fromRGB(80, 255, 80)
    local HARD_BREACH_CHARGE_COLOR  = Color3.fromRGB(255, 220, 120)
    local SHOCK_BATTERY_BOX_COLOR   = Color3.fromRGB(120, 180, 255)
    local DEPLOYABLE_SHIELD_BOX_COLOR = Color3.fromRGB(220, 220, 220)
    local BARBED_WIRE_BOX_COLOR     = Color3.fromRGB(255, 80, 80)
    local SIGNAL_DISRUPTOR_BOX_COLOR = Color3.fromRGB(180, 120, 255)
    local BULLETPROOF_CAMERA_COLOR  = Color3.fromRGB(80, 220, 220)
    local BREACH_CHARGE_COLOR       = Color3.fromRGB(255, 200, 90)
    local OBJECT_BOX_THICK = 1.5
    local OBJECT_BOX_TRANSP = 0.9

    local TEAM_CACHE = {}
    local LAST_TEAM_CACHE = 0
    local TEAM_CACHE_INTERVAL = 0.7

    local playerBoxes = {}
    local objectBoxes = {}
    local connections = {}
    local mainRenderConn = nil

    local OBJECT_WHITELIST = {
        Drone = true,
        Claymore = true,
        ProximityAlarm = true,
        StickyCamera = true,
        RemoteC4 = true,
        ThermiteCharge = true,
        ToxicCharge = true,
        BreachCharge = true,
        HardBreachCharge = true,
        ShockBattery = true,
        DeployableShield = true,
        BarbedWire = true,
        SignalDisruptor = true,
        BulletproofCamera = true
    }

    local corners = {}
    local points = {}
    for i = 1, 8 do
        corners[i] = Vector3new(0, 0, 0)
    end
    for i = 1, 4 do
        points[i] = Vector3new(0, 0, 0)
    end

    local currentCamera = Workspace.CurrentCamera
    local worldToViewportPoint = currentCamera and clonefunction(currentCamera.WorldToViewportPoint) or nil
    local createObjectBox
    local cleanupObjectBox

    local function getObjectDisplayName(name)
        if name == "ProximityAlarm" then
            return "Proximity Alarm"
        elseif name == "StickyCamera" then
            return "Sticky Camera"
        elseif name == "RemoteC4" then
            return "Remote C4"
        elseif name == "ThermiteCharge" then
            return "Thermite"
        elseif name == "ToxicCharge" then
            return "Toxic"
        elseif name == "HardBreachCharge" then
            return "HardBreachCharge"
        elseif name == "ShockBattery" then
            return "Shock Battery"
        elseif name == "DeployableShield" then
            return "Deployable Shield"
        elseif name == "BarbedWire" then
            return "Barbed Wire"
        elseif name == "SignalDisruptor" then
            return "SignalDisruptor"
        elseif name == "BulletproofCamera" then
            return "BulletproofCamera"
        elseif name == "BreachCharge" then
            return "BreachCharge"
        end
        return name
    end

    local function refreshObjectsByName(name)
        local children = Workspace:GetChildren()
        for i = 1, #children do
            local child = children[i]
            if child:IsA("Model") and child.Name == name then
                createObjectBox(child)
            end
        end
    end

    local function setObjectEnabled(name, value)
        local enabled = value == true
        OBJECT_WHITELIST[name] = enabled

        if enabled then
            refreshObjectsByName(name)
            return
        end

        local toRemove = {}
        for obj in pairs(objectBoxes) do
            if obj.Name == name then
                toRemove[#toRemove + 1] = obj
            end
        end

        for i = 1, #toRemove do
            cleanupObjectBox(toRemove[i])
        end
    end

    local M = {
        initialized = false,
        enabled = ESP_ENABLED,
        teamCheck = TEAM_CHECK,
        playerBoxEnabled = PLAYER_BOX_ENABLED,
        objectBoxEnabled = OBJECT_BOX_ENABLED,
        objectNameEnabled = OBJECT_NAME_ENABLED,
        objectNameSize = OBJECT_NAME_SIZE,
        playerColor = PLAYER_BOX_COLOR,
        droneEnabled = OBJECT_WHITELIST.Drone,
        claymoreEnabled = OBJECT_WHITELIST.Claymore,
        proximityEnabled = OBJECT_WHITELIST.ProximityAlarm,
        stickyEnabled = OBJECT_WHITELIST.StickyCamera,
        remoteC4Enabled = OBJECT_WHITELIST.RemoteC4,
        thermiteEnabled = OBJECT_WHITELIST.ThermiteCharge,
        toxicEnabled = OBJECT_WHITELIST.ToxicCharge,
        hardBreachChargeEnabled = OBJECT_WHITELIST.HardBreachCharge,
        shockBatteryEnabled = OBJECT_WHITELIST.ShockBattery,
        deployableShieldEnabled = OBJECT_WHITELIST.DeployableShield,
        barbedWireEnabled = OBJECT_WHITELIST.BarbedWire,
        signalDisruptorEnabled = OBJECT_WHITELIST.SignalDisruptor,
        bulletproofCameraEnabled = OBJECT_WHITELIST.BulletproofCamera,
        breachChargeEnabled = OBJECT_WHITELIST.BreachCharge,
        droneColor = DRONE_BOX_COLOR,
        claymoreColor = CLAYMORE_BOX_COLOR,
        proximityColor = PROXIMITY_ALARM_BOX_COLOR,
        stickyColor = STICKY_CAMERA_BOX_COLOR,
        remoteC4Color = REMOTE_C4_BOX_COLOR,
        thermiteColor = THERMITE_BOX_COLOR,
        toxicColor = TOXIC_BOX_COLOR,
        hardBreachChargeColor = HARD_BREACH_CHARGE_COLOR,
        shockBatteryColor = SHOCK_BATTERY_BOX_COLOR,
        deployableShieldColor = DEPLOYABLE_SHIELD_BOX_COLOR,
        barbedWireColor = BARBED_WIRE_BOX_COLOR,
        signalDisruptorColor = SIGNAL_DISRUPTOR_BOX_COLOR,
        bulletproofCameraColor = BULLETPROOF_CAMERA_COLOR,
        breachChargeColor = BREACH_CHARGE_COLOR,
        playerThickness = PLAYER_BOX_THICK,
        objectThickness = OBJECT_BOX_THICK
    }

    local function clearMap(map)
        for k in next, map do
            map[k] = nil
        end
    end

    local function updateCamera()
        currentCamera = Workspace.CurrentCamera
        worldToViewportPoint = currentCamera and clonefunction(currentCamera.WorldToViewportPoint) or nil
    end

    local function worldToScreen(worldPos)
        if not currentCamera or not worldToViewportPoint then
            return nil, false
        end
        return worldToViewportPoint(currentCamera, worldPos)
    end

    local function updateTeamCache()
        clearMap(TEAM_CACHE)
        local children = Workspace:GetChildren()
        for i = 1, #children do
            local obj = children[i]
            if obj:IsA("Highlight") and obj.Adornee then
                TEAM_CACHE[obj.Adornee] = true
            end
        end
        LAST_TEAM_CACHE = tickFn()
    end

    local function isTeammate(model)
        if not TEAM_CHECK then
            return false
        end
        if tickFn() - LAST_TEAM_CACHE > TEAM_CACHE_INTERVAL then
            updateTeamCache()
        end
        return TEAM_CACHE[model] == true
    end

    local function isInFrustum(worldPos)
        if not currentCamera then
            return false
        end

        local relativePos = worldPos - currentCamera.CFrame.Position
        local lookDir = currentCamera.CFrame.LookVector
        if relativePos:Dot(lookDir) <= 0 then
            return false
        end

        local mag = relativePos.Magnitude
        if mag <= 0 then
            return true
        end

        local angle = acos(min(1, relativePos.Unit:Dot(lookDir)))
        return angle < rad(60)
    end

    local function isOnScreen(worldPos)
        local _, onScreen = worldToScreen(worldPos)
        return onScreen
    end

    local function createBox(color, thickness, transparency, zIndex)
        local lines = {}
        local state = {
            Position = Vector2new(0, 0),
            Size = Vector2new(0, 0),
            Visible = false,
            Color = color,
            Thickness = thickness,
            Transparency = transparency,
            ZIndex = zIndex
        }

        local function setLineProp(line, prop, value)
            if line then
                pcall(function()
                    line[prop] = value
                end)
            end
        end

        for i = 1, 4 do
            local okLine, line = pcall(function()
                return Drawing.new("Line")
            end)
            if not okLine then
                line = nil
            end
            setLineProp(line, "Visible", false)
            setLineProp(line, "Thickness", thickness)
            setLineProp(line, "Transparency", transparency)
            setLineProp(line, "Color", color)
            setLineProp(line, "ZIndex", zIndex)
            lines[i] = line
        end

        local function updateLines()
            local pos = state.Position or Vector2new(0, 0)
            local size = state.Size or Vector2new(0, 0)
            local x, y = pos.X, pos.Y
            local w, h = size.X, size.Y
            local visible = state.Visible == true and w > 0 and h > 0
            local tl = Vector2new(x, y)
            local tr = Vector2new(x + w, y)
            local br = Vector2new(x + w, y + h)
            local bl = Vector2new(x, y + h)
            local pts = {{tl, tr}, {tr, br}, {br, bl}, {bl, tl}}

            for i = 1, 4 do
                local line = lines[i]
                if line then
                    setLineProp(line, "From", pts[i][1])
                    setLineProp(line, "To", pts[i][2])
                    setLineProp(line, "Visible", visible)
                end
            end
        end

        local box = {}
        return setmetatable(box, {
            __index = function(_, key)
                if key == "Remove" then
                    return function()
                        for i = 1, 4 do
                            local line = lines[i]
                            if line then
                                pcall(line.Remove, line)
                                lines[i] = nil
                            end
                        end
                    end
                end
                return state[key]
            end,
            __newindex = function(_, key, value)
                state[key] = value
                if key == "Position" or key == "Size" or key == "Visible" then
                    updateLines()
                elseif key == "Color" or key == "Thickness" or key == "Transparency" or key == "ZIndex" then
                    for i = 1, 4 do
                        setLineProp(lines[i], key, value)
                    end
                end
            end
        })
    end

    local function createText(color, size, transparency, zIndex)
        local text = Drawing.new("Text")
        text.Visible = false
        text.Center = true
        text.Outline = true
        text.Font = 2
        text.Size = size
        text.Transparency = transparency
        text.Color = color
        text.Text = ""
        text.Position = Vector2new(0, 0)
        text.ZIndex = zIndex
        return text
    end

        local function getObjectColor(name)
        if name == "Drone"           then return DRONE_BOX_COLOR
        elseif name == "Claymore"    then return CLAYMORE_BOX_COLOR
        elseif name == "ProximityAlarm" then return PROXIMITY_ALARM_BOX_COLOR
        elseif name == "StickyCamera"   then return STICKY_CAMERA_BOX_COLOR
        elseif name == "RemoteC4"       then return REMOTE_C4_BOX_COLOR
        elseif name == "ThermiteCharge" then return THERMITE_BOX_COLOR
        elseif name == "ToxicCharge"    then return TOXIC_BOX_COLOR
        elseif name == "HardBreachCharge" then return HARD_BREACH_CHARGE_COLOR
        elseif name == "ShockBattery"   then return SHOCK_BATTERY_BOX_COLOR
        elseif name == "DeployableShield" then return DEPLOYABLE_SHIELD_BOX_COLOR
        elseif name == "BarbedWire"     then return BARBED_WIRE_BOX_COLOR
        elseif name == "SignalDisruptor" then return SIGNAL_DISRUPTOR_BOX_COLOR
        elseif name == "BulletproofCamera" then return BULLETPROOF_CAMERA_COLOR
        elseif name == "BreachCharge"   then return BREACH_CHARGE_COLOR
        end
        return nil
    end

    local function resolvePlayerParts(char)
        local head = char:FindFirstChild("head") or char:FindFirstChild("Head")
        local torso = char:FindFirstChild("torso") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso") or
            char:FindFirstChild("HumanoidRootPart")

        if not head or not torso then
            return nil, nil
        end
        if not head:IsA("BasePart") or not torso:IsA("BasePart") then
            return nil, nil
        end

        return head, torso
    end

    local function getObjectBox2D(model)
        local cf, size = model:GetBoundingBox()

        if not isInFrustum(cf.Position) or not isOnScreen(cf.Position) then
            return false
        end

        local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
        corners[1] = cf * Vector3new(-hx, -hy, -hz)
        corners[2] = cf * Vector3new(-hx, -hy, hz)
        corners[3] = cf * Vector3new(-hx, hy, -hz)
        corners[4] = cf * Vector3new(-hx, hy, hz)
        corners[5] = cf * Vector3new(hx, -hy, -hz)
        corners[6] = cf * Vector3new(hx, -hy, hz)
        corners[7] = cf * Vector3new(hx, hy, -hz)
        corners[8] = cf * Vector3new(hx, hy, hz)

        local minX, minY = huge, huge
        local maxX, maxY = -huge, -huge
        local anyVisible = false

        for i = 1, 8 do
            local screenPos, visible = worldToScreen(corners[i])
            if visible then
                anyVisible = true
                local x, y = screenPos.X, screenPos.Y
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            end
        end

        if not anyVisible then
            return false
        end

        return true, minX, minY, maxX - minX, maxY - minY
    end

    local function getPlayerBox2D(head, torso)
        if not head or not torso then
            return false
        end

        local torsoPos = torso.Position
        if not isInFrustum(torsoPos) or not isOnScreen(torsoPos) then
            return false
        end

        local hsx, hsy = head.Size.X * 0.5, head.Size.Y * 0.5
        local tsx, tsy = torso.Size.X * 0.5, torso.Size.Y * 0.5

        points[1] = head.Position + Vector3new(-hsx, hsy, 0)
        points[2] = head.Position + Vector3new(hsx, hsy, 0)
        points[3] = torso.Position + Vector3new(-tsx, -tsy, 0)
        points[4] = torso.Position + Vector3new(tsx, -tsy, 0)

        local minX, minY = huge, huge
        local maxX, maxY = -huge, -huge
        local anyVisible = false

        for i = 1, 4 do
            local screenPos, visible = worldToScreen(points[i])
            if visible then
                anyVisible = true
                local x, y = screenPos.X, screenPos.Y
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            end
        end

        if not anyVisible then
            return false
        end

        local padding = 3
        return true, minX - padding, minY - padding, (maxX - minX) + padding * 2, (maxY - minY) + padding * 2
    end

    local function cleanupPlayerBox(char)
        local data = playerBoxes[char]
        if not data then
            return
        end

        if data.headConn then data.headConn:Disconnect() end
        if data.torsoConn then data.torsoConn:Disconnect() end
        if data.ancestryConn then data.ancestryConn:Disconnect() end
        if data.box then data.box:Remove() end

        playerBoxes[char] = nil
    end

    cleanupObjectBox = function(obj)
        local data = objectBoxes[obj]
        if not data then
            return
        end

        if data.ancestryConn then data.ancestryConn:Disconnect() end
        if data.box then data.box:Remove() end
        if data.nameText then data.nameText:Remove() end

        objectBoxes[obj] = nil
    end

    local function createPlayerBox(char)
        if playerBoxes[char] or char.Name == "LocalViewmodel" then
            return
        end

        local head, torso = resolvePlayerParts(char)
        if not head or not torso then
            return
        end

        local data = {
            box = createBox(PLAYER_BOX_COLOR, PLAYER_BOX_THICK, PLAYER_BOX_TRANSP, 2),
            head = head,
            torso = torso,
            isVisible = torso.Transparency <= 0.95,
            headConn = nil,
            torsoConn = nil,
            ancestryConn = nil
        }

        data.headConn = head:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = playerBoxes[char]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        data.torsoConn = torso:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = playerBoxes[char]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        data.ancestryConn = char.AncestryChanged:Connect(function(_, parent)
            if not parent then
                cleanupPlayerBox(char)
            end
        end)

        playerBoxes[char] = data
    end

    createObjectBox = function(obj)
        if objectBoxes[obj] or not OBJECT_WHITELIST[obj.Name] then
            return
        end

        local color = getObjectColor(obj.Name)
        if not color then
            return
        end

        objectBoxes[obj] = {
            box = createBox(color, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP, 3),
            nameText = createText(color, OBJECT_NAME_SIZE, 1, 4),
            ancestryConn = obj.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    cleanupObjectBox(obj)
                end
            end)
        }
    end

    local function applyStyles()
        for _, data in pairs(playerBoxes) do
            local box = data.box
            box.Thickness = PLAYER_BOX_THICK
            box.Transparency = PLAYER_BOX_TRANSP
            box.Color = PLAYER_BOX_COLOR
        end

        for obj, data in pairs(objectBoxes) do
            local box = data.box
            box.Thickness = OBJECT_BOX_THICK
            box.Transparency = OBJECT_BOX_TRANSP
            box.Color = getObjectColor(obj.Name)

            local nameText = data.nameText
            if nameText then
                nameText.Size = OBJECT_NAME_SIZE
                nameText.Color = getObjectColor(obj.Name)
            end
        end
    end

    local function hideAll()
        for _, data in pairs(playerBoxes) do
            data.box.Visible = false
        end
        for _, data in pairs(objectBoxes) do
            data.box.Visible = false
            if data.nameText then
                data.nameText.Visible = false
            end
        end
    end

    local function scanInitial()
        local vmFolder = Workspace:FindFirstChild("Viewmodels")
        if vmFolder then
            local vmChildren = vmFolder:GetChildren()
            for i = 1, #vmChildren do
                local model = vmChildren[i]
                if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                    createPlayerBox(model)
                end
            end
        end

        local children = Workspace:GetChildren()
        for i = 1, #children do
            local child = children[i]
            if child:IsA("Model") then
                createObjectBox(child)
            end
        end
    end

    local function bindWorkspace()
        local vmFolder = Workspace:FindFirstChild("Viewmodels")
        if vmFolder then
            table.insert(connections, vmFolder.ChildAdded:Connect(function(model)
                if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                    task.delay(0.2, function()
                        createPlayerBox(model)
                    end)
                end
            end))
        end

        table.insert(connections, Workspace.ChildAdded:Connect(function(child)
            if child:IsA("Folder") and child.Name == "Viewmodels" then
                table.insert(connections, child.ChildAdded:Connect(function(model)
                    if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                        task.delay(0.2, function()
                            createPlayerBox(model)
                        end)
                    end
                end))
                return
            end

            if child:IsA("Model") then
                createObjectBox(child)
            end
        end))

        table.insert(connections, UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then
                return
            end
            if input.KeyCode == Enum.KeyCode.Insert then
                ESP_ENABLED = not ESP_ENABLED
                M.enabled = ESP_ENABLED
            end
        end))
    end

    local function renderStep()
        if not currentCamera or not worldToViewportPoint then
            updateCamera()
            if not currentCamera or not worldToViewportPoint then
                hideAll()
                return
            end
        end

        if not ESP_ENABLED then
            hideAll()
            return
        end

        if tickFn() - LAST_TEAM_CACHE > TEAM_CACHE_INTERVAL then
            updateTeamCache()
        end

        if PLAYER_BOX_ENABLED then
            for char, data in pairs(playerBoxes) do
                if not char:IsDescendantOf(Workspace) then
                    cleanupPlayerBox(char)
                else
                    local canRender = true
                    if not data.head or not data.head.Parent or not data.torso or not data.torso.Parent then
                        local newHead, newTorso = resolvePlayerParts(char)
                        if newHead and newTorso then
                            data.head = newHead
                            data.torso = newTorso
                            data.isVisible = newTorso.Transparency <= 0.95
                        else
                            canRender = false
                        end
                    end

                    if not canRender or isTeammate(char) or not data.isVisible then
                        data.box.Visible = false
                    else
                        local ok, x, y, w, h = getPlayerBox2D(data.head, data.torso)
                        if ok then
                            data.box.Position = Vector2new(x, y)
                            data.box.Size = Vector2new(w, h)
                            data.box.Visible = true
                        else
                            data.box.Visible = false
                        end
                    end
                end
            end
        else
            for _, data in pairs(playerBoxes) do
                data.box.Visible = false
            end
        end

        if OBJECT_BOX_ENABLED then
            for obj, data in pairs(objectBoxes) do
                if not obj:IsDescendantOf(Workspace) then
                    cleanupObjectBox(obj)
                else
                    local ok, x, y, w, h = getObjectBox2D(obj)
                    if ok then
                        data.box.Position = Vector2new(x, y)
                        data.box.Size = Vector2new(w, h)
                        data.box.Visible = true
                        if data.nameText then
                            if OBJECT_NAME_ENABLED then
                                data.nameText.Text = getObjectDisplayName(obj.Name)
                                data.nameText.Size = OBJECT_NAME_SIZE
                                data.nameText.Color = getObjectColor(obj.Name)
                                data.nameText.Position = Vector2new(x + (w * 0.5), y - data.nameText.Size - 2)
                                data.nameText.Visible = true
                            else
                                data.nameText.Visible = false
                            end
                        end
                    else
                        data.box.Visible = false
                        if data.nameText then
                            data.nameText.Visible = false
                        end
                    end
                end
            end
        else
            for _, data in pairs(objectBoxes) do
                data.box.Visible = false
                if data.nameText then
                    data.nameText.Visible = false
                end
            end
        end
    end

    function M:Init()
        if self.initialized then
            return
        end

        updateCamera()
        updateTeamCache()
        scanInitial()
        bindWorkspace()

        mainRenderConn = RunService.RenderStepped:Connect(renderStep)
        self.initialized = true
    end

    function M:SetEnabled(value)
        ESP_ENABLED = value == true
        self.enabled = ESP_ENABLED
    end

    function M:SetTeamCheck(value)
        TEAM_CHECK = value == true
        self.teamCheck = TEAM_CHECK
    end

    function M:SetPlayerBoxEnabled(value)
        PLAYER_BOX_ENABLED = value == true
        self.playerBoxEnabled = PLAYER_BOX_ENABLED
        if not PLAYER_BOX_ENABLED then
            for _, data in pairs(playerBoxes) do
                data.box.Visible = false
            end
        end
    end

    function M:SetObjectBoxEnabled(value)
        OBJECT_BOX_ENABLED = value == true
        self.objectBoxEnabled = OBJECT_BOX_ENABLED
        if not OBJECT_BOX_ENABLED then
            for _, data in pairs(objectBoxes) do
                data.box.Visible = false
                if data.nameText then
                    data.nameText.Visible = false
                end
            end
        end
    end

    function M:SetObjectNameEnabled(value)
        OBJECT_NAME_ENABLED = value == true
        self.objectNameEnabled = OBJECT_NAME_ENABLED
        if not OBJECT_NAME_ENABLED then
            for _, data in pairs(objectBoxes) do
                if data.nameText then
                    data.nameText.Visible = false
                end
            end
        end
    end

    function M:SetObjectNameSize(value)
        OBJECT_NAME_SIZE = value
        self.objectNameSize = OBJECT_NAME_SIZE
        applyStyles()
    end

    function M:SetPlayerThickness(value)
        PLAYER_BOX_THICK = value
        self.playerThickness = value
        applyStyles()
    end

    function M:SetObjectThickness(value)
        OBJECT_BOX_THICK = value
        self.objectThickness = value
        applyStyles()
    end

    function M:SetPlayerColor(value)
        PLAYER_BOX_COLOR = value
        self.playerColor = value
        applyStyles()
    end

    function M:SetDroneColor(value)
        DRONE_BOX_COLOR = value
        self.droneColor = value
        applyStyles()
    end

    function M:SetDroneEnabled(value)
        setObjectEnabled("Drone", value)
        self.droneEnabled = OBJECT_WHITELIST.Drone
    end

    function M:SetClaymoreColor(value)
        CLAYMORE_BOX_COLOR = value
        self.claymoreColor = value
        applyStyles()
    end

    function M:SetClaymoreEnabled(value)
        setObjectEnabled("Claymore", value)
        self.claymoreEnabled = OBJECT_WHITELIST.Claymore
    end

    function M:SetProximityColor(value)
        PROXIMITY_ALARM_BOX_COLOR = value
        self.proximityColor = value
        applyStyles()
    end

    function M:SetProximityEnabled(value)
        setObjectEnabled("ProximityAlarm", value)
        self.proximityEnabled = OBJECT_WHITELIST.ProximityAlarm
    end

    function M:SetStickyColor(value)
        STICKY_CAMERA_BOX_COLOR = value
        self.stickyColor = value
        applyStyles()
    end

    function M:SetStickyEnabled(value)
        setObjectEnabled("StickyCamera", value)
        self.stickyEnabled = OBJECT_WHITELIST.StickyCamera
    end

    function M:SetRemoteC4Color(value)
        REMOTE_C4_BOX_COLOR = value
        self.remoteC4Color = value
        applyStyles()
    end

    function M:SetRemoteC4Enabled(value)
        setObjectEnabled("RemoteC4", value)
        self.remoteC4Enabled = OBJECT_WHITELIST.RemoteC4
    end

    function M:SetThermiteColor(value)
        THERMITE_BOX_COLOR = value
        self.thermiteColor = value
        applyStyles()
    end

    function M:SetThermiteEnabled(value)
        setObjectEnabled("ThermiteCharge", value)
        self.thermiteEnabled = OBJECT_WHITELIST.ThermiteCharge
    end

    function M:SetToxicColor(value)
        TOXIC_BOX_COLOR = value
        self.toxicColor = value
        applyStyles()
    end

    function M:SetToxicEnabled(value)
        setObjectEnabled("ToxicCharge", value)
        self.toxicEnabled = OBJECT_WHITELIST.ToxicCharge
    end

    function M:SetHardBreachChargeColor(value)
        HARD_BREACH_CHARGE_COLOR = value
        self.hardBreachChargeColor = value
        applyStyles()
    end

    function M:SetHardBreachChargeEnabled(value)
        setObjectEnabled("HardBreachCharge", value)
        self.hardBreachChargeEnabled = OBJECT_WHITELIST.HardBreachCharge
    end

    function M:SetShockBatteryColor(value)
        SHOCK_BATTERY_BOX_COLOR = value
        self.shockBatteryColor = value
        applyStyles()
    end

    function M:SetShockBatteryEnabled(value)
        setObjectEnabled("ShockBattery", value)
        self.shockBatteryEnabled = OBJECT_WHITELIST.ShockBattery
    end

    function M:SetDeployableShieldColor(value)
        DEPLOYABLE_SHIELD_BOX_COLOR = value
        self.deployableShieldColor = value
        applyStyles()
    end

    function M:SetDeployableShieldEnabled(value)
        setObjectEnabled("DeployableShield", value)
        self.deployableShieldEnabled = OBJECT_WHITELIST.DeployableShield
    end

    function M:SetBarbedWireColor(value)
        BARBED_WIRE_BOX_COLOR = value
        self.barbedWireColor = value
        applyStyles()
    end

    function M:SetBarbedWireEnabled(value)
        setObjectEnabled("BarbedWire", value)
        self.barbedWireEnabled = OBJECT_WHITELIST.BarbedWire
    end

    function M:SetSignalDisruptorColor(value)
        SIGNAL_DISRUPTOR_BOX_COLOR = value
        self.signalDisruptorColor = value
        applyStyles()
    end

    function M:SetSignalDisruptorEnabled(value)
        setObjectEnabled("SignalDisruptor", value)
        self.signalDisruptorEnabled = OBJECT_WHITELIST.SignalDisruptor
    end

    function M:SetBulletproofCameraColor(value)
        BULLETPROOF_CAMERA_COLOR = value
        self.bulletproofCameraColor = value
        applyStyles()
    end

    function M:SetBulletproofCameraEnabled(value)
        setObjectEnabled("BulletproofCamera", value)
        self.bulletproofCameraEnabled = OBJECT_WHITELIST.BulletproofCamera
    end

    function M:SetBreachChargeColor(value)
        BREACH_CHARGE_COLOR = value
        self.breachChargeColor = value
        applyStyles()
    end

    function M:SetBreachChargeEnabled(value)
        setObjectEnabled("BreachCharge", value)
        self.breachChargeEnabled = OBJECT_WHITELIST.BreachCharge
    end

    function M:RefreshStyles()
        applyStyles()
    end

    function M:Unload()
        ESP_ENABLED = false

        if mainRenderConn then
            mainRenderConn:Disconnect()
            mainRenderConn = nil
        end

        for i = 1, #connections do
            pcall(function()
                connections[i]:Disconnect()
            end)
        end
        clearMap(connections)

        for char in pairs(playerBoxes) do
            cleanupPlayerBox(char)
        end
        for obj in pairs(objectBoxes) do
            cleanupObjectBox(obj)
        end

        self.initialized = false
    end

    return M
end


