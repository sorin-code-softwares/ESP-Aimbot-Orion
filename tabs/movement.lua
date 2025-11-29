-- movement.lua
-- Movement utilities: noclip, cframe fly, freecam
return function(Tab, OrionLib, Window, ctx)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer

    local function getCharacter()
        local char = LocalPlayer and LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
        local head = char and char:FindFirstChild("Head")
        return char, hum, root, head
    end

    ----------------------------------------------------------------
    -- Noclip
    ----------------------------------------------------------------
    local noclipConn

    local function setCharacterCollision(state)
        local char = LocalPlayer and LocalPlayer.Character
        if not char then
            return
        end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide ~= (state == true) then
                part.CanCollide = state == true
            end
        end
    end

    local function toggleNoclip(enabled)
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end
        if enabled then
            noclipConn = RunService.Stepped:Connect(function()
                setCharacterCollision(false)
            end)
        else
            setCharacterCollision(true)
        end
    end

    ----------------------------------------------------------------
    -- CFrame fly
    ----------------------------------------------------------------
    local cflyConn
    local cflySpeed = 50

    local function stopCFrameFly()
        if cflyConn then
            cflyConn:Disconnect()
            cflyConn = nil
        end
        local _, hum, _, head = getCharacter()
        if hum then
            hum.PlatformStand = false
        end
        if head then
            head.Anchored = false
        end
    end

    local function startCFrameFly()
        local char, hum, _, head = getCharacter()
        if not (char and hum and head) then
            return
        end

        hum.PlatformStand = true
        head.Anchored = true

        if cflyConn then
            cflyConn:Disconnect()
        end

        cflyConn = RunService.Heartbeat:Connect(function(dt)
            local moveDir = hum.MoveDirection * (cflySpeed * dt)
            local headCF = head.CFrame
            local cameraCF = Workspace.CurrentCamera.CFrame

            -- Keep head aligned to camera orientation; move relative to camera facing
            local cameraOffset = headCF:ToObjectSpace(cameraCF).Position
            cameraCF = cameraCF * CFrame.new(-cameraOffset.X, -cameraOffset.Y, -cameraOffset.Z + 1)

            local camPos = cameraCF.Position
            local headPos = headCF.Position
            local objectSpaceVelocity = CFrame.new(camPos, Vector3.new(headPos.X, camPos.Y, headPos.Z)):VectorToObjectSpace(moveDir)
            head.CFrame = CFrame.new(headPos) * (cameraCF - camPos) * CFrame.new(objectSpaceVelocity)
        end)
    end

    local function setCFrameFly(enabled)
        if enabled then
            startCFrameFly()
        else
            stopCFrameFly()
        end
    end

    ----------------------------------------------------------------
    -- Freecam (lightweight)
    ----------------------------------------------------------------
    local freecam = {
        enabled = false,
        speed = 1,
        yaw = 0,
        pitch = 0,
        pos = nil,
        conn = nil,
        inputConn = nil,
        saved = nil,
    }

    local function saveCameraState()
        local cam = Workspace.CurrentCamera
        return {
            CameraType = cam.CameraType,
            CameraSubject = cam.CameraSubject,
            CFrame = cam.CFrame,
            FieldOfView = cam.FieldOfView,
            MouseIconEnabled = UserInputService.MouseIconEnabled,
            MouseBehavior = UserInputService.MouseBehavior,
        }
    end

    local function restoreCameraState(state)
        if not state then
            return
        end
        local cam = Workspace.CurrentCamera
        cam.CameraType = state.CameraType or Enum.CameraType.Custom
        cam.CameraSubject = state.CameraSubject
        cam.CFrame = state.CFrame or cam.CFrame
        cam.FieldOfView = state.FieldOfView or 70
        UserInputService.MouseIconEnabled = state.MouseIconEnabled ~= false
        UserInputService.MouseBehavior = state.MouseBehavior or Enum.MouseBehavior.Default
    end

    local function stopFreecam()
        if not freecam.enabled then
            return
        end
        freecam.enabled = false
        if freecam.conn then
            freecam.conn:Disconnect()
            freecam.conn = nil
        end
        if freecam.inputConn then
            freecam.inputConn:Disconnect()
            freecam.inputConn = nil
        end
        restoreCameraState(freecam.saved)
        freecam.saved = nil
    end

    local function startFreecam()
        if freecam.enabled then
            stopFreecam()
        end
        local cam = Workspace.CurrentCamera
        freecam.saved = saveCameraState()
        freecam.enabled = true
        freecam.pos = cam.CFrame.Position

        local look = cam.CFrame.LookVector
        freecam.yaw = math.atan2(-look.X, -look.Z)
        freecam.pitch = math.asin(look.Y)

        cam.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseIconEnabled = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

        freecam.inputConn = UserInputService.InputChanged:Connect(function(input, gpe)
            if gpe then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Delta
                freecam.yaw = freecam.yaw - delta.X * 0.0025
                freecam.pitch = math.clamp(freecam.pitch - delta.Y * 0.0025, -1.2, 1.2)
            end
        end)

        freecam.conn = RunService.RenderStepped:Connect(function(dt)
            local move = Vector3.new()
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + Vector3.new(0, 0, -1) end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move + Vector3.new(0, 0, 1) end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move + Vector3.new(-1, 0, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + Vector3.new(1, 0, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.E) then move = move + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.Q) then move = move + Vector3.new(0, -1, 0) end

            local speed = freecam.speed
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                speed = speed * 2
            end

            if move.Magnitude > 0 then
                move = move.Unit * speed * dt
            end

            local camCF = CFrame.new(freecam.pos) * CFrame.fromOrientation(freecam.pitch, freecam.yaw, 0)
            freecam.pos = (camCF * CFrame.new(move)).Position
            Workspace.CurrentCamera.CFrame = CFrame.new(freecam.pos) * CFrame.fromOrientation(freecam.pitch, freecam.yaw, 0)
        end)
    end

    local function setFreecam(enabled)
        if enabled then
            startFreecam()
        else
            stopFreecam()
        end
    end

    ----------------------------------------------------------------
    -- UI
    ----------------------------------------------------------------
    local moveSection = Tab:AddSection({Name = "Noclip"})
    moveSection:AddToggle({
        Name = "Noclip",
        Default = false,
        Save = true,
        Flag = "mv_noclip",
        Callback = function(value)
            toggleNoclip(value)
        end,
    })

    local flySection = Tab:AddSection({Name = "CFrame Fly"})
    flySection:AddToggle({
        Name = "Enable Fly",
        Default = false,
        Save = true,
        Flag = "mv_cfly",
        Callback = function(value)
            setCFrameFly(value)
        end,
    })

    flySection:AddSlider({
        Name = "Fly Speed",
        Min = 10,
        Max = 300,
        Increment = 5,
        Default = cflySpeed,
        Save = true,
        Flag = "mv_cfly_speed",
        Callback = function(value)
            cflySpeed = value
        end,
    })

    flySection:AddBind({
        Name = "Toggle Fly",
        Default = Enum.KeyCode.F,
        Save = true,
        Flag = "mv_cfly_bind",
        Callback = function()
            local enabled = not (cflyConn ~= nil)
            setCFrameFly(enabled)
            local flag = OrionLib.Flags["mv_cfly"]
            if flag and flag.Set then
                flag:Set(enabled)
            end
        end,
    })

    local freecamSection = Tab:AddSection({Name = "Freecam"})
    freecamSection:AddToggle({
        Name = "Enable Freecam",
        Default = false,
        Save = true,
        Flag = "mv_freecam",
        Callback = function(value)
            setFreecam(value)
        end,
    })

    freecamSection:AddSlider({
        Name = "Freecam Speed",
        Min = 0.5,
        Max = 10,
        Increment = 0.1,
        Default = freecam.speed,
        Save = true,
        Flag = "mv_freecam_speed",
        Callback = function(value)
            freecam.speed = value
        end,
    })

    freecamSection:AddBind({
        Name = "Toggle Freecam",
        Default = Enum.KeyCode.G,
        Save = true,
        Flag = "mv_freecam_bind",
        Callback = function()
            local enabled = not freecam.enabled
            setFreecam(enabled)
            local flag = OrionLib.Flags["mv_freecam"]
            if flag and flag.Set then
                flag:Set(enabled)
            end
        end,
    })

    -- Clean up on character death
    LocalPlayer.CharacterAdded:Connect(function()
        toggleNoclip(false)
        setCFrameFly(false)
        setFreecam(false)
    end)
end
