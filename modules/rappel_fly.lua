return function(ctx)
    local Runtime = ctx and ctx.Runtime or {}
    local cloneref = Runtime.cloneref or cloneref or function(obj)
        return obj
    end
    local clonefunction = Runtime.clonefunction or clonefunction or function(fn)
        return fn
    end
    local newcclosure = Runtime.newcclosure or newcclosure or function(fn)
        return fn
    end
    local hookfunction = Runtime.hookfunction or hookfunction or function(f)
        return f
    end
    local getrawmetatable = Runtime.getrawmetatable or getrawmetatable
    local setreadonly = Runtime.setreadonly or setreadonly
    local InstanceNew = Runtime.InstanceNew or Instance.new

    local rawset = clonefunction(rawset)
    local rawget = clonefunction(rawget)
    local pcall = clonefunction(pcall)
    local setmetatable = clonefunction(setmetatable)

    local Services = ctx and ctx.Services or {}
    local ReplicatedStorage = Services.ReplicatedStorage or cloneref(game:GetService("ReplicatedStorage"))
    local RunService = Services.RunService or cloneref(game:GetService("RunService"))
    local UserInputService = Services.UserInputService or cloneref(game:GetService("UserInputService"))
    local Players = Services.Players or cloneref(game:GetService("Players"))
    local Workspace = Services.Workspace or cloneref(game:GetService("Workspace"))

    local GrappleModule = require(ReplicatedStorage.Modules.Items.Item.Utility.GrapplingHook)

    local config = {
        speed = 9,
        pull_speed = 0.5,
        fly_key = Enum.KeyCode.G
    }

    local M = {
        enabled = false,
        speed = config.speed,
        pullSpeed = config.pull_speed,
        _initialized = false
    }

    local flying = false
    local flyConnection = nil
    local grappleSelfRef = nil
    local grappleOwnerRef = nil
    local oldWalkSpeed = nil
    local oldJumpPower = nil
    local realSelfStates = nil
    local realOwnerStates = nil
    local trackedHumanoid = nil
    local dummyEvent = InstanceNew("BindableEvent")
    local inputConnection = nil
    local localViewmodelAddedConnection = nil
    local localViewmodelConnections = {}

    local function getCamera()
        return Workspace.CurrentCamera
    end

    local function getWasdDirection()
        local camera = getCamera()
        if not camera then
            return Vector3.new()
        end

        local direction = Vector3.new()
        local cameraFrame = camera.CFrame

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direction = direction + cameraFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direction = direction - cameraFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direction = direction - cameraFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direction = direction + cameraFrame.RightVector
        end

        if direction.Magnitude > 0 then
            direction = direction.Unit
        end

        return direction
    end

    local function makeStateProxy(real, setIntercept)
        return setmetatable({}, {
            __index = newcclosure(function(_, method)
                if method == "set" then
                    return newcclosure(function(_, value)
                        return setIntercept(real, value)
                    end)
                end
                return real[method]
            end),
            __newindex = newcclosure(function(_, key, value)
                real[key] = value
            end),
            __metatable = "locked"
        })
    end

    local statesProxyMt = {
        __index = newcclosure(function(t, key)
            local real = rawget(t, "__real_states")[key]
            if not real then
                return nil
            end

            if key == "rappeling" then
                return makeStateProxy(real, function(state, value)
                    if flying and value == false then
                        return
                    end
                    return state:set(value)
                end)
            end

            return real
        end),
        __newindex = newcclosure(function(t, key, value)
            rawget(t, "__real_states")[key] = value
        end),
        __metatable = "locked"
    }

    local ownerStatesProxyMt = {
        __index = newcclosure(function(t, key)
            local real = rawget(t, "__real_states")[key]
            if not real then
                return nil
            end

            if key == "climbing" then
                return makeStateProxy(real, function(state, value)
                    if flying and value == 0 then
                        return
                    end
                    return state:set(value)
                end)
            end

            if key == "vault" then
                return makeStateProxy(real, function(state, value)
                    if flying and value > 0 then
                        return
                    end
                    return state:set(value)
                end)
            end

            return real
        end),
        __newindex = newcclosure(function(t, key, value)
            rawget(t, "__real_states")[key] = value
        end),
        __metatable = "locked"
    }

    local function stopFlying()
        if not flying then
            return
        end
        flying = false

        if flyConnection then
            flyConnection:Disconnect()
            flyConnection = nil
        end

        local selfRef = grappleSelfRef
        local ownerRef = grappleOwnerRef

        if selfRef then
            pcall(function()
                if realSelfStates then
                    selfRef.states = realSelfStates
                    realSelfStates = nil
                end
            end)

            pcall(function()
                if selfRef.move_position then
                    selfRef.move_position.MaxVelocity = math.huge
                    selfRef.move_position.Responsiveness = 0
                end
            end)

            pcall(function()
                if selfRef.states then
                    selfRef.states.rappeling:set(false)
                    selfRef.states.hook:set(CFrame.new())
                end
            end)
        end

        if ownerRef then
            pcall(function()
                if realOwnerStates then
                    ownerRef.states = realOwnerStates
                    realOwnerStates = nil
                end
            end)

            pcall(function()
                local humanoid = ownerRef.instance and ownerRef.instance:FindFirstChildOfClass("Humanoid")
                local root = ownerRef.instance and ownerRef.instance:FindFirstChild("HumanoidRootPart")
                if humanoid and root and root.Parent then
                    humanoid.WalkSpeed = oldWalkSpeed or 16
                    humanoid.JumpPower = oldJumpPower or 50
                end
            end)
        end

        trackedHumanoid = nil
        oldWalkSpeed = nil
        oldJumpPower = nil

    end

    local function startFlying()
        if not M.enabled or not grappleSelfRef or not grappleOwnerRef then
            return
        end

        local selfRef = grappleSelfRef
        local ownerRef = grappleOwnerRef
        if not selfRef or not ownerRef or not ownerRef.instance then
            return
        end

        flying = true

        pcall(function()
            realSelfStates = selfRef.states
            selfRef.states = setmetatable({__real_states = realSelfStates}, statesProxyMt)
        end)

        pcall(function()
            realOwnerStates = ownerRef.states
            ownerRef.states = setmetatable({__real_states = realOwnerStates}, ownerStatesProxyMt)
        end)

        pcall(function()
            local humanoid = ownerRef.instance:FindFirstChildOfClass("Humanoid")
            if humanoid then
                trackedHumanoid = humanoid
                oldWalkSpeed = humanoid.WalkSpeed
                oldJumpPower = humanoid.JumpPower
                humanoid.WalkSpeed = 0
                humanoid.JumpPower = 0
            end
        end)

        pcall(function()
            if selfRef.move_position then
                selfRef.move_position.MaxVelocity = config.pull_speed
                selfRef.move_position.Responsiveness = 10
            end
        end)

        local root = ownerRef.instance:FindFirstChild("HumanoidRootPart")
        local camera = getCamera()
        local currentTarget = root and root.Position or (camera and camera.CFrame.Position) or Vector3.new()

        pcall(function()
            local stayCf = CFrame.new(currentTarget)
            selfRef:start_rappel_mode(ownerRef, stayCf, stayCf)
        end)

        flyConnection = RunService.Heartbeat:Connect(newcclosure(function(dt)
            if not flying or not M.enabled then
                stopFlying()
                return
            end

            local direction = getWasdDirection()
            if direction.Magnitude > 0 then
                local currentRoot = ownerRef.instance and ownerRef.instance:FindFirstChild("HumanoidRootPart")
                if currentRoot then
                    currentTarget = currentTarget + direction * config.speed * dt
                end
            end

            pcall(function()
                if selfRef.move_position then
                    selfRef.move_position.Position = currentTarget
                    selfRef.move_position.MaxVelocity = config.pull_speed
                end
            end)
        end))

    end

    local function connectLocalViewmodel(viewmodel, viewmodelsFolder)
        if localViewmodelConnections[viewmodel] then
            return
        end

        localViewmodelConnections[viewmodel] = viewmodel.AncestryChanged:Connect(newcclosure(function(_, parent)
            if flying and parent ~= viewmodelsFolder then
                stopFlying()
            end

            if not parent and localViewmodelConnections[viewmodel] then
                localViewmodelConnections[viewmodel]:Disconnect()
                localViewmodelConnections[viewmodel] = nil
            end
        end))
    end

    local function installHooks()
        local oldGetPropertyChangedSignal
        oldGetPropertyChangedSignal = hookfunction(game.GetPropertyChangedSignal, newcclosure(function(self, property)
            if flying and self == trackedHumanoid then
                if property == "WalkSpeed" or property == "JumpPower" then
                    return dummyEvent.Event
                end
            end
            return oldGetPropertyChangedSignal(self, property)
        end))

        if getrawmetatable and setreadonly then
            local mt = getrawmetatable(game)
            if mt and mt.__index then
                local oldIndex = mt.__index
                setreadonly(mt, false)
                mt.__index = newcclosure(function(self, key)
                    if flying and self == trackedHumanoid then
                        if key == "WalkSpeed" then
                            return oldWalkSpeed or 16
                        end
                        if key == "JumpPower" then
                            return oldJumpPower or 50
                        end
                    end
                    return oldIndex(self, key)
                end)
                setreadonly(mt, true)
            end
        end

        local oldHookInputs = clonefunction(GrappleModule.hook_inputs)
        rawset(GrappleModule, "hook_inputs", newcclosure(function(self, ...)
            grappleSelfRef = self
            grappleOwnerRef = self.owner
            return oldHookInputs(self, ...)
        end))

        local oldCanRappel = clonefunction(GrappleModule.can_rappel)
        rawset(GrappleModule, "can_rappel", newcclosure(function(self, owner)
            if not flying then
                return oldCanRappel(self, owner)
            end

            local camera = getCamera()
            if not camera then
                return oldCanRappel(self, owner)
            end

            local target = camera.CFrame.Position + camera.CFrame.LookVector * 100
            return CFrame.new(target), CFrame.new(target + Vector3.new(0, 2, 0))
        end))

        local oldStartRappel = clonefunction(GrappleModule.start_rappel_mode)
        rawset(GrappleModule, "start_rappel_mode", newcclosure(function(self, owner, ...)
            return oldStartRappel(self, owner, ...)
        end))
    end

    function M:Init()
        if self._initialized then
            return
        end

        installHooks()

        local viewmodelsFolder = Workspace:WaitForChild("Viewmodels")
        local existing = viewmodelsFolder:FindFirstChild("LocalViewmodel")
        if existing then
            connectLocalViewmodel(existing, viewmodelsFolder)
        end

        localViewmodelAddedConnection = viewmodelsFolder.ChildAdded:Connect(newcclosure(function(child)
            if child.Name == "LocalViewmodel" then
                connectLocalViewmodel(child, viewmodelsFolder)
            end
        end))

        inputConnection = UserInputService.InputBegan:Connect(newcclosure(function(input, processed)
            if processed or input.KeyCode ~= config.fly_key or not M.enabled then
                return
            end

            if flying then
                stopFlying()
                return
            end

            if grappleSelfRef and grappleOwnerRef then
                startFlying()
            else
            end
        end))

        self._initialized = true
    end

    function M:SetEnabled(value)
        self.enabled = value and true or false
        if not self.enabled then
            stopFlying()
        end
    end

    function M:SetSpeed(value)
        config.speed = value
        self.speed = value
    end

    function M:SetPullSpeed(value)
        config.pull_speed = value
        self.pullSpeed = value

        if flying and grappleSelfRef and grappleSelfRef.move_position then
            pcall(function()
                grappleSelfRef.move_position.MaxVelocity = value
            end)
        end
    end

    return M
end
