-- visuals_and_graphics.lua
-- Unified "Visuals & Graphics" tab for Orion interface
-- Includes ESP overlays plus Fullbright, X-Ray and camera helpers.
return function(Tab, OrionLib, Window, ctx)
    ------------------------------------------------------------
    -- Core services
    ------------------------------------------------------------
    local Players = game:GetService("Players")
    local Teams = game:GetService("Teams")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local Workspace = game:GetService("Workspace")

    local LocalPlayer = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    ------------------------------------------------------------
    -- Self-ESP policy
    ------------------------------------------------------------
    local SHOW_SELF_POLICY = "toggle" -- off | on | toggle

    ------------------------------------------------------------
    -- ESP runtime state
    ------------------------------------------------------------
    local STATE = {
        enabled = false,

        showFriendESP = true,
        showEnemyESP = true,
        showNeutralESP = true,
        showSelf = false,

        showDisplayName = true,
        showUsername = true,
        showEquipped = true,
        showDistance = true,
        showBones = false,

        maxDistance = 750,

        textSizeMain = 14,
        textSizeSub = 13,
        lineGap = 2,
        outlineText = true,

        bonesThickness = 2,
    }

    if SHOW_SELF_POLICY == "on" then
        STATE.showSelf = true
    elseif SHOW_SELF_POLICY == "off" then
        STATE.showSelf = false
    end

    ------------------------------------------------------------
    -- ESP categorisation helpers
    ------------------------------------------------------------
    local ESP_TYPE = {
        SELF = "Self",
        FRIEND = "Friend",
        ENEMY = "Enemy",
        NEUTRAL = "Neutral",
    }

    local friendCache = {}

    local function isFriendTarget(plr)
        local cached = friendCache[plr]
        if cached ~= nil then
            return cached
        end

        local ok, isFriend = pcall(function()
            return LocalPlayer:IsFriendsWith(plr.UserId)
        end)

        cached = (ok and isFriend) or false
        friendCache[plr] = cached
        return cached
    end

    Players.PlayerRemoving:Connect(function(plr)
        friendCache[plr] = nil
    end)

    local function teamIsEnemy(a, b)
        if not a.Team or not b.Team then
            return false
        end
        return a.Team ~= b.Team
    end

    local function categorize(plr)
        if plr == LocalPlayer then
            return ESP_TYPE.SELF
        elseif isFriendTarget(plr) then
            return ESP_TYPE.FRIEND
        elseif teamIsEnemy(LocalPlayer, plr) then
            return ESP_TYPE.ENEMY
        end
        return ESP_TYPE.NEUTRAL
    end

    ------------------------------------------------------------
    -- ESP theme
    ------------------------------------------------------------
    local THEME = {
        TextFriend = Color3.fromRGB(0, 255, 150),
        TextEnemy = Color3.fromRGB(255, 80, 80),
        TextNeutral = Color3.fromRGB(220, 220, 220),
        TextSelf = Color3.fromRGB(100, 180, 255),

        TextUsername = Color3.fromRGB(180, 180, 180),
        TextEquip = Color3.fromRGB(170, 170, 170),
        TextDist = Color3.fromRGB(200, 200, 200),

        BonesFriend = Color3.fromRGB(0, 200, 120),
        BonesEnemy = Color3.fromRGB(255, 100, 100),
        BonesNeutral = Color3.fromRGB(0, 200, 255),
        BonesSelf = Color3.fromRGB(100, 180, 255),
    }

    local function getCategoryColors(category)
        if category == ESP_TYPE.FRIEND then
            return THEME.TextFriend, THEME.BonesFriend
        elseif category == ESP_TYPE.ENEMY then
            return THEME.TextEnemy, THEME.BonesEnemy
        elseif category == ESP_TYPE.SELF then
            return THEME.TextSelf, THEME.BonesSelf
        end
        return THEME.TextNeutral, THEME.BonesNeutral
    end

    ------------------------------------------------------------
    -- Drawing helpers (gracefully degrade if Drawing API is missing)
    ------------------------------------------------------------
    if not Drawing then
        Tab:AddSection({Name = "Visuals & Graphics"})
        Tab:AddParagraph("Drawing API", "Drawing API missing: ESP name tags disabled, 3D highlights still work.")
    end

    local FONT_OPTIONS = {
        ["Gotham Bold"] = 2,
        ["System"] = 1,
        ["Monospace"] = 3,
        ["UI"] = 0,
    }
    local FONT_LIST = { "Gotham Bold", "System", "Monospace", "UI" }

    local CATEGORY_BADGES = {
        [ESP_TYPE.FRIEND] = "FR",
        [ESP_TYPE.ENEMY] = "EN",
        [ESP_TYPE.NEUTRAL] = "NE",
        [ESP_TYPE.SELF] = "ME",
    }

    -- fixed font style (no user selection)
    STATE.fontStyle = STATE.fontStyle or "Monospace"
    STATE.showCategoryBadge = STATE.showCategoryBadge ~= false

    local function currentFontId()
        return FONT_OPTIONS[STATE.fontStyle] or FONT_OPTIONS["Monospace"]
    end

    local function NewText(size)
        local text = Drawing and Drawing.new("Text") or {}
        if Drawing then
            text.Visible = false
            text.Size = size
            text.Center = true
            text.Outline = STATE.outlineText
            text.Transparency = 1
            text.Font = currentFontId()
        end
        return text
    end

    local function NewLine()
        local line = Drawing and Drawing.new("Line") or {}
        if Drawing then
            line.Visible = false
            line.Thickness = STATE.bonesThickness
            line.Transparency = 1
        end
        return line
    end

    ------------------------------------------------------------
    -- ESP pool
    ------------------------------------------------------------
    local pool = {}

    local function applyFontToObj(obj)
        if not (Drawing and obj) then
            return
        end
        local fontId = currentFontId()
        obj.textMain.Font = fontId
        obj.textUser.Font = fontId
        obj.textEquip.Font = fontId
        obj.textDist.Font = fontId
    end

    local function refreshFontPool()
        if not Drawing then
            return
        end
        for _, obj in pairs(pool) do
            applyFontToObj(obj)
        end
    end

    local function alloc(plr)
        if pool[plr] then
            return pool[plr]
        end

        local obj = {
            textMain = NewText(STATE.textSizeMain),
            textUser = NewText(STATE.textSizeSub),
            textEquip = NewText(STATE.textSizeSub),
            textDist = NewText(STATE.textSizeSub),
            bones = {},
            highlight = nil,
        }

        for i = 1, 16 do
            obj.bones[i] = NewLine()
        end

        -- Surrounding highlight based on character / team
        local highlight = Instance.new("Highlight")
        highlight.Name = "SorinESP_Highlight"
        highlight.FillTransparency = 0.75
        highlight.OutlineTransparency = 0.15
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Enabled = false
        highlight.Parent = Workspace
        obj.highlight = highlight

        applyFontToObj(obj)
        pool[plr] = obj
        return obj
    end

    local function hideObj(obj)
        if not obj then
            return
        end

        if Drawing then
            if obj.textMain then obj.textMain.Visible = false end
            if obj.textUser then obj.textUser.Visible = false end
            if obj.textEquip then obj.textEquip.Visible = false end
            if obj.textDist then obj.textDist.Visible = false end
            if obj.bones then
                for _, line in ipairs(obj.bones) do
                    if line then
                        line.Visible = false
                    end
                end
            end
        end

        if obj.highlight then
            obj.highlight.Enabled = false
        end
    end

    local function free(plr)
        local obj = pool[plr]
        if not obj then
            return
        end

        if Drawing then
            pcall(function() if obj.textMain then obj.textMain:Remove() end end)
            pcall(function() if obj.textUser then obj.textUser:Remove() end end)
            pcall(function() if obj.textEquip then obj.textEquip:Remove() end end)
            pcall(function() if obj.textDist then obj.textDist:Remove() end end)
            if obj.bones then
                for _, line in ipairs(obj.bones) do
                    pcall(function() if line then line:Remove() end end)
                end
            end
        end

        if obj.highlight then
            pcall(function() obj.highlight:Destroy() end)
        end

        pool[plr] = nil
    end

    Players.PlayerRemoving:Connect(function(plr)
        free(plr)
        friendCache[plr] = nil
    end)

    ------------------------------------------------------------
    -- ESP helpers
    ------------------------------------------------------------
    local function findEquippedToolName(char)
        if not char then
            return nil
        end

        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            return tool.Name
        end

        for _, desc in ipairs(char:GetDescendants()) do
            if desc:IsA("Tool") then
                return desc.Name
            end
        end

        return nil
    end

    local BONES_R15 = {
        {"UpperTorso", "Head"},
        {"LowerTorso", "UpperTorso"},

        {"UpperTorso", "LeftUpperArm"},
        {"LeftUpperArm", "LeftLowerArm"},
        {"LeftLowerArm", "LeftHand"},

        {"UpperTorso", "RightUpperArm"},
        {"RightUpperArm", "RightLowerArm"},
        {"RightLowerArm", "RightHand"},

        {"LowerTorso", "LeftUpperLeg"},
        {"LeftUpperLeg", "LeftLowerLeg"},
        {"LeftLowerLeg", "LeftFoot"},

        {"LowerTorso", "RightUpperLeg"},
        {"RightUpperLeg", "RightLowerLeg"},
        {"RightLowerLeg", "RightFoot"},
    }

    local BONES_R6 = {
        {"Torso", "Head"},
        {"Torso", "Left Arm"},
        {"Torso", "Right Arm"},
        {"Torso", "Left Leg"},
        {"Torso", "Right Leg"},
    }

    local function partPos(char, name)
        local part = char and char:FindFirstChild(name)
        return part and part.Position
    end

    local function setLine(line, a, b, color, thickness)
        if not (line and a and b and Drawing) then
            if line then
                line.Visible = false
            end
            return
        end

        local A, aVisible = Camera:WorldToViewportPoint(a)
        local B, bVisible = Camera:WorldToViewportPoint(b)
        if not (aVisible or bVisible) then
            line.Visible = false
            return
        end

        line.From = Vector2.new(A.X, A.Y)
        line.To = Vector2.new(B.X, B.Y)
        line.Visible = true
        line.Thickness = thickness
        line.Color = color
    end

    local function drawSkeletonLines(obj, char, color, thickness)
        if not Drawing then
            return
        end

        local isR6 = char and char:FindFirstChild("Torso") ~= nil
        local layout = isR6 and BONES_R6 or BONES_R15

        for index, link in ipairs(layout) do
            setLine(
                obj.bones[index],
                partPos(char, link[1]),
                partPos(char, link[2]),
                color,
                thickness
            )
        end

        for index = #layout + 1, #obj.bones do
            obj.bones[index].Visible = false
        end
    end

    local function placeText(tObj, text, x, y, color, outline)
        if not (Drawing and tObj) then
            return
        end
        if not text or text == "" then
            tObj.Visible = false
            return
        end

        tObj.Text = text
        tObj.Position = Vector2.new(x, y)
        tObj.Color = color
        tObj.Outline = outline
        tObj.Visible = true
    end

    local function formatMainDisplay(plr, category)
        local base = plr.DisplayName or plr.Name
        if not STATE.showCategoryBadge then
            return base
        end
        local badge = CATEGORY_BADGES[category] or "--"
        return string.format("[%s] %s", badge, base)
    end

    ------------------------------------------------------------
    -- ESP render loop (Highlight + text tag)
    ------------------------------------------------------------
    RunService.RenderStepped:Connect(function()
        if SHOW_SELF_POLICY == "off" then
            STATE.showSelf = false
        elseif SHOW_SELF_POLICY == "on" then
            STATE.showSelf = true
        end

        if not STATE.enabled then
            for _, obj in pairs(pool) do
                hideObj(obj)
            end
            return
        end

        local myChar = LocalPlayer and LocalPlayer.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP then
            for _, obj in pairs(pool) do
                hideObj(obj)
            end
            return
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            local shouldRender = true

            if plr == LocalPlayer and not STATE.showSelf then
                shouldRender = false
            end

            local char, hum, hrp, head
            if shouldRender then
                char = plr.Character
                hum = char and char:FindFirstChildOfClass("Humanoid")
                hrp = char and char:FindFirstChild("HumanoidRootPart")
                head = char and char:FindFirstChild("Head")
                if not (hum and hum.Health > 0 and hrp and head) then
                    shouldRender = false
                end
            end

            local dist
            if shouldRender then
                dist = (myHRP.Position - hrp.Position).Magnitude
                if dist > STATE.maxDistance then
                    shouldRender = false
                end
            end

            local pos, onScreen
            if shouldRender then
                pos, onScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 2.5, 0))
                if not onScreen then
                    shouldRender = false
                end
            end

            local category
            if shouldRender then
                category = categorize(plr)
                if (category == ESP_TYPE.FRIEND and not STATE.showFriendESP)
                    or (category == ESP_TYPE.ENEMY and not STATE.showEnemyESP)
                    or (category == ESP_TYPE.NEUTRAL and not STATE.showNeutralESP)
                then
                    shouldRender = false
                end
            end

            if not shouldRender then
                hideObj(pool[plr])
            else
                local obj = alloc(plr)
                if obj then
                    local textColor = getCategoryColors(category)

                    -- Surrounding highlight (team color if available, otherwise category color)
                    if obj.highlight then
                        obj.highlight.Adornee = char
                        obj.highlight.Parent = char
                        local fillColor = (plr.Team and plr.Team.TeamColor and plr.Team.TeamColor.Color) or textColor
                        obj.highlight.FillColor = fillColor
                        obj.highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                        obj.highlight.Enabled = true
                    end

                    if Drawing then
                        local screenX, screenY = pos.X, pos.Y
                        local yCursor = screenY

                        if STATE.showDisplayName then
                            placeText(
                                obj.textMain,
                                formatMainDisplay(plr, category),
                                screenX,
                                yCursor,
                                textColor,
                                STATE.outlineText
                            )
                            yCursor = yCursor + obj.textMain.Size + STATE.lineGap
                        else
                            obj.textMain.Visible = false
                        end

                        if STATE.showUsername then
                            placeText(
                                obj.textUser,
                                "@" .. plr.Name,
                                screenX,
                                yCursor,
                                THEME.TextUsername,
                                STATE.outlineText
                            )
                            yCursor = yCursor + obj.textUser.Size + STATE.lineGap
                        else
                            obj.textUser.Visible = false
                        end

                        if STATE.showEquipped then
                            local toolName = findEquippedToolName(char)
                            local equippedText = toolName and ("[" .. toolName .. "]") or "[Nothing equipped]"
                            placeText(
                                obj.textEquip,
                                equippedText,
                                screenX,
                                yCursor,
                                THEME.TextEquip,
                                STATE.outlineText
                            )
                            yCursor = yCursor + obj.textEquip.Size + STATE.lineGap
                        else
                            obj.textEquip.Visible = false
                        end

                        if STATE.showDistance then
                            placeText(
                                obj.textDist,
                                string.format("%.0fm", dist),
                                screenX,
                                yCursor,
                                THEME.TextDist,
                                STATE.outlineText
                            )
                            yCursor = yCursor + obj.textDist.Size + STATE.lineGap
                        else
                            obj.textDist.Visible = false
                        end
                    end
                end
            end
        end
    end)

    ------------------------------------------------------------
    -- Graphics helpers (Fullbright, X-Ray, Zoom)
    ------------------------------------------------------------
    local BOOT = { ready = false }

    local function approach(current, target, alpha)
        alpha = math.clamp(alpha or 0.15, 0, 1)
        return current + (target - current) * alpha
    end

    local function lerpColor(a, b, t)
        return Color3.new(
            approach(a.R, b.R, t),
            approach(a.G, b.G, t),
            approach(a.B, b.B, t)
        )
    end

    --------------------------------------------------------
    -- Fullbright
    --------------------------------------------------------
    local FB = {
        enabled = false,
        loop = nil,
        cc = nil,
        saved = nil,
        targets = {
            targetAmbient = Color3.fromRGB(180, 180, 180),
        },
    }

    local function estimateSceneBrightness()
        local b = Lighting.Brightness or 0
        local amb = Lighting.Ambient or Color3.new(0, 0, 0)
        local oamb = Lighting.OutdoorAmbient or Color3.new(0, 0, 0)
        local ambAvg = (amb.R + amb.G + amb.B) / 3
        local oambAvg = (oamb.R + oamb.G + oamb.B) / 3
        -- Weighted sum (rough approximation of perceived brightness)
        return b * 0.35 + ambAvg * 0.4 + oambAvg * 0.25
    end

    local function computeFullbrightTargets()
        local scene = estimateSceneBrightness()
        -- Very dark scenes: strong boost
        if scene < 0.35 then
            return {
                minBrightness = 2.4,
                minExposure = 1.0,
                ccBrightness = 0.12,
                ccContrast = 0.08,
                ambientLerp = 0.14,
            }
        -- Medium scenes: moderate boost
        elseif scene < 0.9 then
            return {
                minBrightness = 2.0,
                minExposure = 0.8,
                ccBrightness = 0.07,
                ccContrast = 0.05,
                ambientLerp = 0.10,
            }
        end
        -- Already bright: keep the effect subtle to avoid overexposure
        return {
            minBrightness = 1.0,
            minExposure = 0.0,
            ccBrightness = 0.0,
            ccContrast = 0.0,
            ambientLerp = 0.04,
        }
    end

    local function fb_enable()
        if FB.enabled then
            return
        end
        FB.enabled = true

        FB.saved = {
            Brightness = Lighting.Brightness,
            Exposure = Lighting.ExposureCompensation,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        }

        FB.cc = Instance.new("ColorCorrectionEffect")
        FB.cc.Name = "Fullbright_Sorin"
        FB.cc.Brightness = 0
        FB.cc.Contrast = 0
        FB.cc.Saturation = 0
        FB.cc.Parent = Lighting

        FB.loop = RunService.RenderStepped:Connect(function()
            if not FB.enabled then
                return
            end

            local t = computeFullbrightTargets()

            if Lighting.Brightness < t.minBrightness then
                Lighting.Brightness = approach(Lighting.Brightness, t.minBrightness, 0.18)
            end
            if t.minExposure > 0 and Lighting.ExposureCompensation < t.minExposure then
                Lighting.ExposureCompensation = approach(Lighting.ExposureCompensation, t.minExposure, 0.18)
            end

            local amb = Lighting.Ambient
            if (amb.R + amb.G + amb.B) / 3 < 0.55 or t.ambientLerp > 0.1 then
                Lighting.Ambient = lerpColor(amb, FB.targets.targetAmbient, t.ambientLerp)
            end
            local oamb = Lighting.OutdoorAmbient
            if (oamb.R + oamb.G + oamb.B) / 3 < 0.55 or t.ambientLerp > 0.1 then
                Lighting.OutdoorAmbient = lerpColor(oamb, FB.targets.targetAmbient, t.ambientLerp)
            end

            if Lighting.EnvironmentDiffuseScale and Lighting.EnvironmentDiffuseScale < 1 then
                Lighting.EnvironmentDiffuseScale = approach(Lighting.EnvironmentDiffuseScale, 1, 0.25)
            end
            if Lighting.EnvironmentSpecularScale and Lighting.EnvironmentSpecularScale < 1 then
                Lighting.EnvironmentSpecularScale = approach(Lighting.EnvironmentSpecularScale, 1, 0.25)
            end

            FB.cc.Brightness = approach(FB.cc.Brightness, t.ccBrightness, 0.1)
            FB.cc.Contrast = approach(FB.cc.Contrast, t.ccContrast, 0.1)
        end)
    end

    local function fb_disable()
        if not FB.enabled then
            return
        end
        FB.enabled = false

        if FB.loop then
            FB.loop:Disconnect()
            FB.loop = nil
        end
        if FB.cc then
            FB.cc:Destroy()
            FB.cc = nil
        end

        if FB.saved then
            Lighting.Brightness = FB.saved.Brightness
            Lighting.ExposureCompensation = FB.saved.Exposure
            Lighting.Ambient = FB.saved.Ambient
            Lighting.OutdoorAmbient = FB.saved.OutdoorAmbient
            if FB.saved.EnvironmentDiffuseScale then
                Lighting.EnvironmentDiffuseScale = FB.saved.EnvironmentDiffuseScale
            end
            if FB.saved.EnvironmentSpecularScale then
                Lighting.EnvironmentSpecularScale = FB.saved.EnvironmentSpecularScale
            end
            FB.saved = nil
        end
    end

    local function fb_set(value)
        if not BOOT.ready then
            return
        end
        if value then
            fb_enable()
        else
            fb_disable()
        end
    end

    --------------------------------------------------------
    -- X-Ray
    --------------------------------------------------------
    local XR = {
        enabled = false,
        tracked = {},
        conns = {},
    }

    local function clearTable(t)
        if table.clear then
            table.clear(t)
            return
        end
        for key in pairs(t) do
            t[key] = nil
        end
    end

    local function isCharacterPart(inst)
        local current = inst
        while current do
            if current:FindFirstChildOfClass("Humanoid") then
                return true
            end
            current = current.Parent
        end
        return false
    end

    local function tryXray(obj)
        if not (obj and obj:IsA("BasePart")) then
            return
        end
        if isCharacterPart(obj) then
            return
        end
        XR.tracked[obj] = true
        pcall(function()
            obj.LocalTransparencyModifier = 0.5
        end)
    end

    local function clearXray()
        for part in pairs(XR.tracked) do
            if part and part.Parent then
                pcall(function()
                    part.LocalTransparencyModifier = 0
                end)
            end
        end
        clearTable(XR.tracked)
    end

    local function xr_enable()
        if XR.enabled then
            return
        end
        XR.enabled = true

        for _, descendant in ipairs(Workspace:GetDescendants()) do
            tryXray(descendant)
        end

        XR.conns[#XR.conns + 1] = Workspace.DescendantAdded:Connect(tryXray)
    end

    local function xr_disable()
        if not XR.enabled then
            return
        end
        XR.enabled = false

        for _, conn in ipairs(XR.conns) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        clearTable(XR.conns)

        clearXray()
    end

    local function xr_set(value)
        if not BOOT.ready then
            return
        end
        if value then
            xr_enable()
        else
            xr_disable()
        end
    end

    --------------------------------------------------------
    -- Camera zoom lock
    --------------------------------------------------------
    local ZOOM = {
        target = (LocalPlayer and LocalPlayer.CameraMaxZoomDistance) or 128,
        guardConn = nil,
    }

    local function applyZoom(value, force)
        local newTarget = math.clamp(value or ZOOM.target, 6, 2000)
        ZOOM.target = newTarget

        if not (force or BOOT.ready) then
            return
        end

        if not LocalPlayer then
            return
        end

        if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
        end
        LocalPlayer.CameraMaxZoomDistance = ZOOM.target
    end

    if not ZOOM.guardConn then
        ZOOM.guardConn = RunService.Stepped:Connect(function()
            if not LocalPlayer then
                return
            end
            if LocalPlayer.CameraMaxZoomDistance ~= ZOOM.target then
                LocalPlayer.CameraMaxZoomDistance = ZOOM.target
            end
        end)
    end

    LocalPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            applyZoom(ZOOM.target, true)
        end)
    end)

    ------------------------------------------------------------
    -- UI: ESP section
    ------------------------------------------------------------
    local espSection = Tab:AddSection({Name = "Visuals & Graphics - ESP Overlay"})

    espSection:AddToggle({
        Name = "ESP",
        Default = STATE.enabled,
        Save = true,
        Flag = "esp_enabled",
        Callback = function(value)
            STATE.enabled = value
        end,
    })

    if SHOW_SELF_POLICY == "toggle" then
        espSection:AddToggle({
            Name = "Self ESP",
            Default = STATE.showSelf,
            Save = true,
            Flag = "esp_self",
            Callback = function(value)
                STATE.showSelf = value
            end,
        })
    end

    espSection:AddSlider({
        Name = "Render Range (studs)",
        Min = 50,
        Max = 2500,
        Increment = 10,
        Default = STATE.maxDistance,
        Save = true,
        Flag = "esp_range",
        Callback = function(value)
            STATE.maxDistance = value
        end,
    })

    espSection:AddToggle({
        Name = "Show Equipped Tool",
        Default = STATE.showEquipped,
        Save = true,
        Flag = "esp_equipped",
        Callback = function(value)
            STATE.showEquipped = value
        end,
    })

    espSection:AddParagraph("Info", "ESP shows DisplayName, @username, distance and optional equipped tool.")

    ------------------------------------------------------------
    -- UI: Graphics section
    ------------------------------------------------------------
    local worldSection = Tab:AddSection({Name = "Visuals & Graphics - World"})

    worldSection:AddToggle({
        Name = "Fullbright",
        Default = false,
        Save = true,
        Flag = "gfx_fullbright",
        Callback = function(value)
            fb_set(value)
        end,
    })

    worldSection:AddToggle({
        Name = "X-Ray (world transparency)",
        Default = false,
        Save = true,
        Flag = "gfx_xray",
        Callback = function(value)
            xr_set(value)
        end,
    })

    local cameraSection = Tab:AddSection({Name = "Camera"})

    cameraSection:AddSlider({
        Name = "Max Zoom Distance",
        Min = 6,
        Max = 2000,
        Increment = 10,
        Default = ZOOM.target,
        Save = true,
        Flag = "gfx_zoom_max",
        Callback = function(value)
            applyZoom(value)
        end,
    })

    ------------------------------------------------------------
    -- Bootstrap saved flags
    ------------------------------------------------------------
    task.defer(function()
        local function getFlag(flagName, defaultValue)
            local flag = OrionLib and OrionLib.Flags and OrionLib.Flags[flagName]
            if type(flag) == "table" and flag.Value ~= nil then
                return flag.Value
            end
            return defaultValue
        end

        BOOT.ready = true

        STATE.enabled = getFlag("esp_enabled", STATE.enabled)
        if SHOW_SELF_POLICY == "toggle" then
            STATE.showSelf = getFlag("esp_self", STATE.showSelf)
        end
        STATE.maxDistance = getFlag("esp_range", STATE.maxDistance)
        STATE.showEquipped = getFlag("esp_equipped", STATE.showEquipped)

        applyZoom(getFlag("gfx_zoom_max", ZOOM.target), true)
        fb_set(getFlag("gfx_fullbright", false))
        xr_set(getFlag("gfx_xray", false))
    end)
end
