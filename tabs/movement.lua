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
    local cwalkConn
    local cwalkStrength = 50 -- 0-100 scale
    local cwalkSmartSprint = false

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
    -- CFrame walk (slide-style speed boost)
    ----------------------------------------------------------------
    local function strengthToSpeed(strength)
        local t = math.clamp(strength or 0, 0, 100) / 100
        return 10 + t * 80 -- 10..90 studs/s
    end

    local function isGrounded(hum)
        return hum and hum.FloorMaterial and hum.FloorMaterial ~= Enum.Material.Air
    end

    local function stopCFrameWalk()
        if cwalkConn then
            cwalkConn:Disconnect()
            cwalkConn = nil
        end
    end

    local function startCFrameWalk()
        local char, hum, root = getCharacter()
        if not (char and hum and root) then
            return
        end
        stopCFrameWalk()

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        cwalkConn = RunService.RenderStepped:Connect(function(dt)
            if not (hum and root and char and char.Parent) then
                return
            end
            if hum.Sit or not isGrounded(hum) then
                return
            end

            local moveDir = hum.MoveDirection
            if moveDir.Magnitude <= 0.01 then
                return
            end
            if cwalkSmartSprint and not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                return
            end

            moveDir = Vector3.new(moveDir.X, 0, moveDir.Z)
            if moveDir.Magnitude <= 0 then
                return
            end
            moveDir = moveDir.Unit

            local extraSpeed = strengthToSpeed(cwalkStrength)
            local step = moveDir * extraSpeed * dt

            rayParams.FilterDescendantsInstances = {char}
            local hit = Workspace:Raycast(root.Position, step + moveDir * 0.2, rayParams)
            if hit and hit.Instance and hit.Instance.CanCollide ~= false then
                return
            end

            root.CFrame = root.CFrame + step
        end)
    end

    local function setCFrameWalk(enabled)
        if enabled then
            startCFrameWalk()
        else
            stopCFrameWalk()
        end
    end

    ----------------------------------------------------------------
    -- Follow Player (MoveTo / simple fly assist)
    ----------------------------------------------------------------
    local followEnabled = false
    local followConn
    local followTargetName = nil
    local followNearest = false
    local followFlyEnabled = false
    local followOrbit = false
    local followBodyVelocity

    local function listPlayers()
        local result = { "None" }
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                table.insert(result, plr.Name)
            end
        end
        return result
    end

    local function nearestPlayer()
        local myChar = LocalPlayer and LocalPlayer.Character
        local myRoot = myChar and getCharacter()
        myRoot = select(3, getCharacter())
        if not myRoot then
            return nil
        end
        local best, bestDist = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local root = plr.Character and (plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character:FindFirstChild("Torso") or plr.Character:FindFirstChild("UpperTorso"))
                if root then
                    local d = (root.Position - myRoot.Position).Magnitude
                    if d < bestDist then
                        bestDist = d
                        best = plr
                    end
                end
            end
        end
        return best
    end

    local function resolveFollowTarget()
        if followNearest then
            return nearestPlayer()
        end
        if not followTargetName or followTargetName == "None" then
            return nil
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Name == followTargetName then
                return plr
            end
        end
        return nil
    end

    local function cleanupFollowFly()
        if followBodyVelocity then
            pcall(function()
                followBodyVelocity:Destroy()
            end)
            followBodyVelocity = nil
        end
    end

    local function stopFollow()
        followEnabled = false
        if followConn then
            followConn:Disconnect()
            followConn = nil
        end
        cleanupFollowFly()
    end

    local function startFollow()
        if followEnabled then
            return
        end
        followEnabled = true
        cleanupFollowFly()

        followConn = RunService.Heartbeat:Connect(function(dt)
            if not followEnabled then
                return
            end

            local targetPlr = resolveFollowTarget()
            local targetRoot = targetPlr and targetPlr.Character and (targetPlr.Character:FindFirstChild("HumanoidRootPart") or targetPlr.Character:FindFirstChild("Torso") or targetPlr.Character:FindFirstChild("UpperTorso"))
            local myChar, myHum, myRoot = getCharacter()
            if not (targetRoot and myHum and myRoot) then
                cleanupFollowFly()
                return
            end

            local delta = targetRoot.Position - myRoot.Position
            local dist = delta.Magnitude

            -- better grounded check via ray when humanoid floor fails
            local function grounded()
                if isGrounded(myHum) then
                    return true
                end
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = { myChar }
                local ray = Workspace:Raycast(myRoot.Position, Vector3.new(0, -5, 0), params)
                return ray ~= nil
            end

            local onGround = grounded()
            local shouldFly = followFlyEnabled and ((dist > 10) or (math.abs(delta.Y) > 6) or not onGround)

            if shouldFly then
                if not followBodyVelocity then
                    followBodyVelocity = Instance.new("BodyVelocity")
                    followBodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                    followBodyVelocity.Velocity = Vector3.zero
                    followBodyVelocity.Parent = myRoot
                end
                local dir = dist > 0.25 and delta.Unit or Vector3.zero
                local targetSpeed = math.clamp(dist * 6, 0, 80)
                followBodyVelocity.Velocity = dir * targetSpeed

                local horiz = Vector3.new(delta.X, 0, delta.Z)
                if horiz.Magnitude > 0.1 then
                    myRoot.CFrame = CFrame.new(myRoot.Position, myRoot.Position + horiz.Unit)
                end

                -- if the player is steering manually, don't force the follow; allow manual control until they stop
                if UserInputService:IsKeyDown(Enum.KeyCode.W)
                    or UserInputService:IsKeyDown(Enum.KeyCode.A)
                    or UserInputService:IsKeyDown(Enum.KeyCode.S)
                    or UserInputService:IsKeyDown(Enum.KeyCode.D) then
                    return
                end
            else
                cleanupFollowFly()
                myHum.PlatformStand = false
                myRoot.Velocity = Vector3.zero
                myRoot.RotVelocity = Vector3.zero
            end

            -- ground follow
            local desired = 8
            local slack = 3
            local horiz = Vector3.new(delta.X, 0, delta.Z)
            if followOrbit and horiz.Magnitude > 1 then
                local angle = tick() * 1.5
                local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.clamp(dist, 5, 10)
                myHum:MoveTo(targetRoot.Position + offset)
            elseif dist > desired + slack then
                if horiz.Magnitude > 0.1 and not (
                    UserInputService:IsKeyDown(Enum.KeyCode.W)
                    or UserInputService:IsKeyDown(Enum.KeyCode.A)
                    or UserInputService:IsKeyDown(Enum.KeyCode.S)
                    or UserInputService:IsKeyDown(Enum.KeyCode.D)
                ) then
                    myHum:MoveTo(targetRoot.Position)
                end
            elseif dist < desired - slack and horiz.Magnitude > 0.1 then
                if not (
                    UserInputService:IsKeyDown(Enum.KeyCode.W)
                    or UserInputService:IsKeyDown(Enum.KeyCode.A)
                    or UserInputService:IsKeyDown(Enum.KeyCode.S)
                    or UserInputService:IsKeyDown(Enum.KeyCode.D)
                ) then
                    myHum:MoveTo(myRoot.Position - horiz.Unit * 2)
                end
            else
                if not (
                    UserInputService:IsKeyDown(Enum.KeyCode.W)
                    or UserInputService:IsKeyDown(Enum.KeyCode.A)
                    or UserInputService:IsKeyDown(Enum.KeyCode.S)
                    or UserInputService:IsKeyDown(Enum.KeyCode.D)
                ) then
                    myHum:Move(Vector3.new(), true)
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- Freecam (lightweight)
    ----------------------------------------------------------------
    local freecam = {
        enabled = false,
        speed = 4,
        yaw = 0,
        pitch = 0,
        pos = nil,
        conn = nil,
        inputConn = nil,
        saved = nil,
        charSaved = nil,
    }

    local function freezeCharacter(enable)
        local char, hum, root = getCharacter()
        if not (char and hum and root) then
            return
        end
        if enable then
            freecam.charSaved = {
                anchored = root.Anchored,
                platform = hum.PlatformStand,
                autorotate = hum.AutoRotate,
                walk = hum.WalkSpeed,
                jump = hum.JumpPower,
                velocity = root.Velocity,
                rotVelocity = root.RotVelocity,
            }
            root.Anchored = true
            hum.PlatformStand = true
            hum.AutoRotate = false
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            root.Velocity = Vector3.zero
            root.RotVelocity = Vector3.zero
        else
            local saved = freecam.charSaved
            if saved then
                root.Anchored = saved.anchored
                hum.PlatformStand = saved.platform
                hum.AutoRotate = saved.autorotate
                hum.WalkSpeed = saved.walk
                hum.JumpPower = saved.jump
                root.Velocity = saved.velocity or Vector3.zero
                root.RotVelocity = saved.rotVelocity or Vector3.zero
            end
            freecam.charSaved = nil
        end
    end

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
        UserInputService.MouseIconEnabled = true
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        freezeCharacter(false)
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
        freezeCharacter(true)

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
                move = move.Unit * speed * 12 * dt
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

    local walkSection = Tab:AddSection({Name = "CFrame Walk"})
    walkSection:AddToggle({
        Name = "Enable CFrame Walk",
        Default = false,
        Save = true,
        Flag = "mv_cwalk",
        Callback = function(value)
            setCFrameWalk(value)
        end,
    })

    walkSection:AddToggle({
        Name = "Smart Sprint (Shift)",
        Default = false,
        Save = true,
        Flag = "mv_cwalk_sprint",
        Callback = function(value)
            cwalkSmartSprint = value
        end,
    })

    walkSection:AddSlider({
        Name = "Slide Strength",
        Min = 0,
        Max = 100,
        Increment = 1,
        Default = cwalkStrength,
        Save = true,
        Flag = "mv_cwalk_strength",
        Callback = function(value)
            cwalkStrength = value
        end,
    })

    local followSection = Tab:AddSection({Name = "Follow Player"})

    local followDropdown = followSection:AddDropdown({
        Name = "Target Player",
        Options = listPlayers(),
        Default = "None",
        Save = false,
        Flag = "mv_follow_target",
        Callback = function(selected)
            followTargetName = selected == "None" and nil or selected
        end,
    })

    followSection:AddToggle({
        Name = "Enable Follow",
        Default = false,
        Save = false,
        Flag = "mv_follow_enabled",
        Callback = function(value)
            if value then
                startFollow()
            else
                stopFollow()
            end
        end,
    })

    followSection:AddToggle({
        Name = "Follow Nearest",
        Default = false,
        Save = true,
        Flag = "mv_follow_nearest",
        Callback = function(value)
            followNearest = value
        end,
    })

    followSection:AddToggle({
        Name = "Orbit Target",
        Default = false,
        Save = true,
        Flag = "mv_follow_orbit",
        Callback = function(value)
            followOrbit = value
        end,
    })

    followSection:AddToggle({
        Name = "Fly Assist",
        Default = false,
        Save = true,
        Flag = "mv_follow_fly",
        Callback = function(value)
            followFlyEnabled = value
            if not value then
                cleanupFollowFly()
            end
        end,
    })

    Players.PlayerAdded:Connect(function()
        if followDropdown and followDropdown.Set then
            followDropdown:Set({
                Options = listPlayers(),
                CurrentValue = followTargetName or "None",
            })
        end
    end)

    Players.PlayerRemoving:Connect(function(plr)
        if followTargetName == plr.Name then
            followTargetName = nil
        end
        if followDropdown and followDropdown.Set then
            followDropdown:Set({
                Options = listPlayers(),
                CurrentValue = followTargetName or "None",
            })
        end
    end)

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
        Max = 30,
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
