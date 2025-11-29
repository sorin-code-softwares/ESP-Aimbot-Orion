-- aimbot.lua
-- Orion tab for aimlock / silent aim with FOV circle
return function(Tab, OrionLib, Window, ctx)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Camera = workspace.CurrentCamera

    local LocalPlayer = Players.LocalPlayer

    local state = {
        aimlock = false,
        aimbot = false,
        smooth = false,
        smoothness = 0.4,
        aimPart = "Head",
        wallCheck = true,
        fovEnabled = false,
        fovSize = 100,
        fovColor = Color3.fromRGB(255, 255, 255),
        target = nil,
    }

    local fovCircle

    local function ensureFovCircle()
        if fovCircle or not Drawing then
            return
        end
        fovCircle = Drawing.new("Circle")
        fovCircle.Thickness = 2
        fovCircle.NumSides = 50
        fovCircle.Radius = state.fovSize
        fovCircle.Filled = false
        fovCircle.Transparency = 1
        fovCircle.Color = state.fovColor
        fovCircle.Visible = false
        fovCircle.ZIndex = 2
    end

    local function updateFovCircle()
        if not fovCircle then
            return
        end
        local center = Camera.ViewportSize * 0.5
        fovCircle.Position = Vector2.new(center.X, center.Y)
        fovCircle.Radius = state.fovSize
        fovCircle.Color = state.fovColor
        fovCircle.Visible = state.fovEnabled and (state.aimlock or state.aimbot)
    end

    local function getClosestPlayerToCursor()
        local closestPlayer
        local shortestDistance = state.fovEnabled and state.fovSize or math.huge
        local mousePos = UserInputService:GetMouseLocation()

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local character = player.Character
                local root = character:FindFirstChild("HumanoidRootPart")
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if root and humanoid and humanoid.Health > 0 then
                    local targetPart = character:FindFirstChild(state.aimPart)
                    if targetPart then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                        if onScreen then
                            local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude

                            local canSee = true
                            if state.wallCheck then
                                local ray = Ray.new(Camera.CFrame.Position, (targetPart.Position - Camera.CFrame.Position).Unit * 1000)
                                local hit = workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character})
                                canSee = hit and hit:IsDescendantOf(character)
                            end

                            if canSee and distance < shortestDistance then
                                closestPlayer = player
                                shortestDistance = distance
                            end
                        end
                    end
                end
            end
        end

        return closestPlayer
    end

    local function aimlock()
        if not state.aimlock then
            return
        end

        local target = getClosestPlayerToCursor()
        state.target = target

        if target and target.Character then
            local targetPart = target.Character:FindFirstChild(state.aimPart)
            if targetPart then
                local aimPosition = targetPart.Position
                local cameraPosition = Camera.CFrame.Position
                local direction = (aimPosition - cameraPosition).Unit
                local targetCFrame = CFrame.new(cameraPosition, cameraPosition + direction)

                if state.smooth then
                    Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, state.smoothness)
                else
                    Camera.CFrame = targetCFrame
                end
            end
        end
    end

    local function aimbot()
        if not state.aimbot then
            return
        end
        state.target = getClosestPlayerToCursor()
    end

    -- UI
    if not Drawing then
        Tab:AddParagraph("Hinweis", "Drawing API fehlt: FOV-Kreis wird nicht angezeigt, Aimlock funktioniert dennoch.")
    end

    local aimlockSection = Tab:AddSection({Name = "Aimlock"})

    aimlockSection:AddToggle({
        Name = "Aimlock aktiv",
        Default = false,
        Save = true,
        Flag = "aimlock_enabled",
        Callback = function(value)
            state.aimlock = value
            ensureFovCircle()
            updateFovCircle()
        end,
    })

    aimlockSection:AddToggle({
        Name = "Smooth Aim",
        Default = state.smooth,
        Save = true,
        Flag = "aimlock_smooth",
        Callback = function(value)
            state.smooth = value
        end,
    })

    aimlockSection:AddSlider({
        Name = "Smoothness",
        Min = 0.05,
        Max = 1,
        Increment = 0.05,
        Default = state.smoothness,
        Save = true,
        Flag = "aimlock_smoothness",
        Callback = function(value)
            state.smoothness = value
        end,
    })

    aimlockSection:AddToggle({
        Name = "Wall Check",
        Default = state.wallCheck,
        Save = true,
        Flag = "aimlock_wallcheck",
        Callback = function(value)
            state.wallCheck = value
        end,
    })

    aimlockSection:AddDropdown({
        Name = "Zielknochen",
        Options = {"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart"},
        Default = state.aimPart,
        Save = true,
        Flag = "aimlock_part",
        Callback = function(value)
            state.aimPart = value
        end,
    })

    local fovSection = Tab:AddSection({Name = "FOV Kreis"})

    fovSection:AddToggle({
        Name = "FOV anzeigen",
        Default = state.fovEnabled,
        Save = true,
        Flag = "aim_fov_enabled",
        Callback = function(value)
            state.fovEnabled = value
            ensureFovCircle()
            updateFovCircle()
        end,
    })

    fovSection:AddSlider({
        Name = "FOV Radius",
        Min = 50,
        Max = 500,
        Increment = 5,
        Default = state.fovSize,
        Save = true,
        Flag = "aim_fov_size",
        Callback = function(value)
            state.fovSize = value
            updateFovCircle()
        end,
    })

    fovSection:AddColorpicker({
        Name = "FOV Farbe",
        Default = state.fovColor,
        Save = true,
        Flag = "aim_fov_color",
        Callback = function(value)
            state.fovColor = value
            updateFovCircle()
        end,
    })

    local aimbotSection = Tab:AddSection({Name = "Aimbot (Silent)"})

    aimbotSection:AddToggle({
        Name = "Silent Aim",
        Default = state.aimbot,
        Save = true,
        Flag = "aimbot_enabled",
        Callback = function(value)
            state.aimbot = value
        end,
    })

    RunService.RenderStepped:Connect(function()
        updateFovCircle()
        aimlock()
        aimbot()
    end)
end
