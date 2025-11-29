-- HubSettings.lua
-- SorinHub: Loader behaviour & safety settings (auto-execute, toggle key, anti-fling)
return function(Tab, OrionLib, Window, ctx)
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")

    local LocalPlayer = Players.LocalPlayer
    local UI_NAME = (getgenv and getgenv()._SorinWinCfg and getgenv()._SorinWinCfg.GuiName) or "SorinHub"

    local function guiRoot()
        local getter = gethui
        if typeof(getter) == "function" then
            local ok, gui = pcall(getter)
            if ok and gui then
                return gui
            end
        end
        return game:GetService("CoreGui")
    end

    local function findMainWindow()
        local root = guiRoot()
        local gui = root and root:FindFirstChild(UI_NAME)
        if not gui then
            return nil
        end
        for _, child in ipairs(gui:GetChildren()) do
            if child:IsA("Frame") and child:FindFirstChild("TopBar") then
                return child
            end
        end
        return nil
    end

    local function notify(title, content)
        if OrionLib and typeof(OrionLib.MakeNotification) == "function" then
            pcall(function()
                OrionLib:MakeNotification({
                    Name = title or "Hub Settings",
                    Content = content or "",
                    Time = 5,
                })
            end)
        end
    end

    ----------------------------------------------------------------
    -- Auto-execute SorinHub (optional, user-controlled)
    ----------------------------------------------------------------
    local AutoExecStore = {
        folder = "SorinHubConfig",
        file = "auto-execute.txt",
        envKey = "__SorinHubAutoExecute",
        cached = nil,
    }

    local function getAutoExecEnv()
        local ok, env = pcall(function()
            return getgenv and getgenv()
        end)
        if ok and typeof(env) == "table" then
            return env
        end
        return nil
    end

    local function ensureAutoExecFolder()
        if typeof(isfolder) ~= "function" or typeof(makefolder) ~= "function" then
            return false
        end
        local okExists, exists = pcall(isfolder, AutoExecStore.folder)
        if okExists and exists then
            return true
        end
        local okCreate = pcall(makefolder, AutoExecStore.folder)
        return okCreate == true
    end

    local function loadAutoExecFlag()
        if AutoExecStore.cached ~= nil then
            return AutoExecStore.cached
        end

        local env = getAutoExecEnv()
        if env and env[AutoExecStore.envKey] ~= nil then
            AutoExecStore.cached = env[AutoExecStore.envKey] == true
            return AutoExecStore.cached
        end

        if typeof(isfile) == "function" and typeof(readfile) == "function" then
            if ensureAutoExecFolder() then
                local path = AutoExecStore.folder .. "/" .. AutoExecStore.file
                local okExists, exists = pcall(isfile, path)
                if okExists and exists then
                    local okRead, contents = pcall(readfile, path)
                    if okRead and type(contents) == "string" then
                        local lower = string.lower(contents)
                        local value = lower:find("true", 1, true)
                            or lower:find("1", 1, true)
                            or lower:find("yes", 1, true)
                            or lower:find("on", 1, true)
                        AutoExecStore.cached = value and true or false
                        if env then
                            env[AutoExecStore.envKey] = AutoExecStore.cached
                        end
                        return AutoExecStore.cached
                    end
                end
            end
        end

        AutoExecStore.cached = false
        if env then
            env[AutoExecStore.envKey] = false
        end
        return false
    end

    local function saveAutoExecFlag(value)
        local enabled = value == true
        AutoExecStore.cached = enabled

        local env = getAutoExecEnv()
        if env then
            env[AutoExecStore.envKey] = enabled
        end

        if typeof(writefile) == "function" then
            if ensureAutoExecFolder() then
                local path = AutoExecStore.folder .. "/" .. AutoExecStore.file
                pcall(writefile, path, enabled and "true" or "false")
            end
        end
    end

    local function queueHubAutoExecute()
        local env = getAutoExecEnv()
        if env and env.__SorinHubAutoExecQueued then
            return true
        end

        local q =
            (syn and syn.queue_on_teleport)
            or queue_on_teleport
            or (fluxus and fluxus.queue_on_teleport)

        if typeof(q) ~= "function" then
            return false, "queue_on_teleport is not available in this executor"
        end

        local scriptSource = "loadstring(game:HttpGet('https://raw.githubusercontent.com/sorin-code-softwares/285e0deb-ec6e-4a23-9c0b-e33eb2301255/main/gameshub-loader.lua'))()"
        local ok, err = pcall(q, scriptSource)
        if not ok then
            return false, tostring(err)
        end
        if env then
            env.__SorinHubAutoExecQueued = true
        end
        return true
    end

    local function applyAutoExecSetting(value, source)
        local enabled = value == true
        saveAutoExecFlag(enabled)

        if not enabled then
            if source == "ui" then
                notify("Auto execute", "Disabled for future teleports. Rejoin to fully clear queued scripts.")
            end
            return
        end

        local ok, err = queueHubAutoExecute()
        if not ok then
            notify("Auto execute", "Your executor does not support queue_on_teleport: " .. tostring(err))
            return
        end

        if source == "ui" then
            notify("Auto execute", "Sorin Script Hub will auto-load after your next teleport.")
        end
    end

    local initialAutoExec = loadAutoExecFlag()
    if initialAutoExec then
        applyAutoExecSetting(true, "init")
    end

    ----------------------------------------------------------------
    -- Toggle key store (shared between sessions)
    ----------------------------------------------------------------
    local function tryGetStore(container)
        if typeof(container) == "table" and typeof(container.SorinHubToggleKeyStore) == "table" then
            return container.SorinHubToggleKeyStore
        end
        return nil
    end

    local ToggleKeyApi do
        local okShared, sharedTable = pcall(function()
            return shared
        end)
        if okShared then
            ToggleKeyApi = tryGetStore(sharedTable)
        end

        if not ToggleKeyApi then
            local okEnv, env = pcall(function()
                return getgenv and getgenv()
            end)
            if okEnv then
                ToggleKeyApi = tryGetStore(env)
            end
        end
    end

    if not ToggleKeyApi then
        local keycodeLookup = {}
        for _, code in ipairs(Enum.KeyCode:GetEnumItems()) do
            keycodeLookup[string.lower(code.Name)] = code
        end

        local fallbackStore = {
            folder = "SorinHubConfig",
            file = "interface-toggle.txt",
            envKey = "__SorinHubToggleKey",
            cached = nil,
        }

        local function sanitizeKeyName(key)
            if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
                return key.Name
            end
            if type(key) == "string" then
                local trimmed = key:gsub("^%s+", ""):gsub("%s+$", "")
                trimmed = trimmed:gsub("Enum.KeyCode%.", "")
                trimmed = trimmed:gsub("%s+", "")
                if trimmed ~= "" then
                    return trimmed
                end
            end
            return nil
        end

        local function resolveKeyCode(key)
            if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
                return key
            end
            local cleaned = sanitizeKeyName(key)
            if not cleaned then
                return nil
            end
            return keycodeLookup[string.lower(cleaned)]
        end

        local function getEnvTable()
            local ok, env = pcall(function()
                return getgenv and getgenv()
            end)
            if ok and typeof(env) == "table" then
                return env
            end
            return nil
        end

        local function setEnvPreference(key)
            local env = getEnvTable()
            if env then
                env[fallbackStore.envKey] = key
            end
        end

        local function getEnvPreference()
            local env = getEnvTable()
            if env then
                return sanitizeKeyName(env[fallbackStore.envKey])
            end
            return nil
        end

        local function ensureFolder()
            if typeof(isfolder) ~= "function" or typeof(makefolder) ~= "function" then
                return false
            end
            local ok, exists = pcall(isfolder, fallbackStore.folder)
            if ok and exists then
                return true
            end
            local created = pcall(makefolder, fallbackStore.folder)
            return created == true
        end

        local function readFile()
            if typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then
                return nil
            end
            if not ensureFolder() then
                return nil
            end
            local path = fallbackStore.folder .. "/" .. fallbackStore.file
            local okExists, exists = pcall(isfile, path)
            if not okExists or not exists then
                return nil
            end
            local ok, contents = pcall(readfile, path)
            if not ok or type(contents) ~= "string" then
                return nil
            end
            return sanitizeKeyName(contents)
        end

        local function writeFile(key)
            if typeof(writefile) ~= "function" then
                return false
            end
            if not ensureFolder() then
                return false
            end
            local path = fallbackStore.folder .. "/" .. fallbackStore.file
            local ok = pcall(writefile, path, key)
            return ok == true
        end

        local function loadKey()
            if fallbackStore.cached then
                return fallbackStore.cached
            end
            local fromFile = readFile()
            if fromFile then
                fallbackStore.cached = fromFile
                setEnvPreference(fromFile)
                return fromFile
            end
            local fromEnv = getEnvPreference()
            if fromEnv then
                fallbackStore.cached = fromEnv
                return fromEnv
            end
            return nil
        end

        local function saveKey(key)
            local cleaned = sanitizeKeyName(key)
            if not cleaned then
                return false
            end
            fallbackStore.cached = cleaned
            setEnvPreference(cleaned)
            writeFile(cleaned)
            return true
        end

        ToggleKeyApi = {
            sanitize = sanitizeKeyName,
            resolve = resolveKeyCode,
            load = loadKey,
            save = saveKey,
        }
    end

    local function callToggleStore(method, ...)
        if not ToggleKeyApi then
            return nil
        end
        local fn = ToggleKeyApi[method]
        if typeof(fn) ~= "function" then
            return nil
        end
        local ok, result = pcall(fn, ...)
        if not ok then
            warn("[HubSettings] Toggle key store error (" .. tostring(method) .. "):", result)
            return nil
        end
        return result
    end

    local function sanitizeToggleKey(value)
        return callToggleStore("sanitize", value)
    end

    local function resolveToggleKey(value)
        return callToggleStore("resolve", value)
    end

    local function loadStoredToggleKey()
        return callToggleStore("load")
    end

    local function saveStoredToggleKey(value)
        return callToggleStore("save", value)
    end

    local function currentWindowHotkey()
        local stored = loadStoredToggleKey and loadStoredToggleKey()
        if type(stored) == "string" and stored ~= "" then
            return stored
        end
        return "RightShift"
    end

    local function hotkeyDescription(keyName)
        local readable = sanitizeToggleKey and sanitizeToggleKey(keyName) or keyName or "RightShift"
        if not readable or readable == "" then
            readable = "RightShift"
        end
        return string.format("Press %s to reopen the hub after hiding it.", readable)
    end

    ----------------------------------------------------------------
    -- Interface blur helper
    ----------------------------------------------------------------
    local BLUR_NAME = "SorinHub_Blur"

    local function findBlur()
        local blur = Lighting:FindFirstChild(BLUR_NAME)
        if blur and blur:IsA("BlurEffect") then
            return blur
        end
        return nil
    end

    local function setBlur(state)
        if state then
            local blur = findBlur()
            if not blur then
                blur = Instance.new("BlurEffect")
                blur.Name = BLUR_NAME
                blur.Size = 18
                blur.Parent = Lighting
            end
            blur.Enabled = true
        else
            local blur = findBlur()
            if blur then
                blur:Destroy()
            end
        end
    end

    local function currentBlurState()
        local blur = findBlur()
        return blur ~= nil and blur.Enabled ~= false
    end

    ----------------------------------------------------------------
    -- Anti-fling
    ----------------------------------------------------------------
    local antiFlingEnabled = false
    local antiFlingConn
    local antiFlingOriginalCollision = {}

    local function applyNoCollideToCharacter(char)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if antiFlingOriginalCollision[part] == nil then
                    antiFlingOriginalCollision[part] = part.CanCollide
                end
                part.CanCollide = false
            end
        end
    end

    local function restoreAntiFlingCollision()
        for part, canCollide in pairs(antiFlingOriginalCollision) do
            if typeof(part) == "Instance" and part:IsA("BasePart") then
                part.CanCollide = canCollide
            end
        end
        table.clear(antiFlingOriginalCollision)
    end

    local function setAntiFling(state)
        antiFlingEnabled = state == true

        if antiFlingConn then
            antiFlingConn:Disconnect()
            antiFlingConn = nil
        end

        if not antiFlingEnabled then
            restoreAntiFlingCollision()
            return
        end

        antiFlingConn = RunService.Stepped:Connect(function()
            local myChar = LocalPlayer and LocalPlayer.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            if not (myChar and myRoot) then
                return
            end

            for _, other in ipairs(Players:GetPlayers()) do
                if other ~= LocalPlayer then
                    local char = other.Character
                    if char then
                        applyNoCollideToCharacter(char)
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    -- Walk fling (experimental)
    ----------------------------------------------------------------
    local walkFlingActive = false
    local walkFlingLoopRunning = false
    local walkFlingHumanoidConn
    local walkFlingOriginalCollision = {}

    local function getRootPart(character)
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Torso")
            or character:FindFirstChild("UpperTorso")
    end

    local function applyWalkFlingNoclip(char)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if walkFlingOriginalCollision[part] == nil then
                    walkFlingOriginalCollision[part] = part.CanCollide
                end
                part.CanCollide = false
            end
        end
    end

    local function restoreWalkFlingCollision()
        for part, canCollide in pairs(walkFlingOriginalCollision) do
            if typeof(part) == "Instance" and part:IsA("BasePart") then
                part.CanCollide = canCollide
            end
        end
        table.clear(walkFlingOriginalCollision)
    end

    local function stopWalkFling()
        walkFlingActive = false

        if walkFlingHumanoidConn then
            walkFlingHumanoidConn:Disconnect()
            walkFlingHumanoidConn = nil
        end

        local player = LocalPlayer
        local character = player and player.Character
        local root = character and getRootPart(character)
        if root then
            root.Velocity = Vector3.new(0, 0, 0)
            root.RotVelocity = Vector3.new(0, 0, 0)
        end
    end

    local function startWalkFling()
        local player = LocalPlayer
        if not player then
            notify("Walk Fling", "LocalPlayer is not available.")
            return
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
        local root = getRootPart(character)
        if not (character and humanoid and root) then
            notify("Walk Fling", "Character, Humanoid or RootPart not found.")
            return
        end

        walkFlingActive = true

        if walkFlingHumanoidConn then
            walkFlingHumanoidConn:Disconnect()
        end
        walkFlingHumanoidConn = humanoid.Died:Connect(function()
            stopWalkFling()
        end)

        if walkFlingLoopRunning then
            return
        end
        walkFlingLoopRunning = true

        task.spawn(function()
            local movel = 0.1
            local playerRef = player

            while walkFlingActive do
                RunService.Heartbeat:Wait()
                if not walkFlingActive then
                    break
                end

                local character = playerRef.Character
                local rootPart = getRootPart(character)

                while walkFlingActive and not (character and character.Parent and rootPart and rootPart.Parent) do
                    RunService.Heartbeat:Wait()
                    character = playerRef.Character
                    rootPart = getRootPart(character)
                end

                if not walkFlingActive then
                    break
                end

                applyWalkFlingNoclip(character)

                local vel = rootPart.Velocity
                rootPart.Velocity = vel * 10000 + Vector3.new(0, 10000, 0)

                RunService.RenderStepped:Wait()
                if not walkFlingActive then
                    break
                end

                character = playerRef.Character
                rootPart = getRootPart(character)
                if character and character.Parent and rootPart and rootPart.Parent then
                    rootPart.Velocity = vel
                end

                RunService.Stepped:Wait()
                if not walkFlingActive then
                    break
                end

                character = playerRef.Character
                rootPart = getRootPart(character)
                if character and character.Parent and rootPart and rootPart.Parent then
                    rootPart.Velocity = vel + Vector3.new(0, movel, 0)
                    movel = -movel
                end
            end

            restoreWalkFlingCollision()
            walkFlingLoopRunning = false
        end)
    end

    local function setWalkFling(state)
        if state then
            if walkFlingActive then
                return
            end
            startWalkFling()
        else
            if not walkFlingActive then
                return
            end
            stopWalkFling()
        end
    end

    ----------------------------------------------------------------
    -- UI: Loader behaviour
    ----------------------------------------------------------------
    local loaderSection = Tab:AddSection({Name = "Loader Behaviour"})

    loaderSection:AddToggle({
        Name = "Auto execute",
        Default = initialAutoExec,
        Save = true,
        Flag = "hub_auto_execute",
        Callback = function(value)
            applyAutoExecSetting(value, "ui")
        end,
    })

    ----------------------------------------------------------------
    -- UI: Interface controls (toggle key, blur)
    ----------------------------------------------------------------
    local interfaceSection = Tab:AddSection({Name = "Interface Controls"})

    interfaceSection:AddToggle({
        Name = "Background Blur",
        Default = currentBlurState(),
        Save = true,
        Flag = "hub_background_blur",
        Callback = function(value)
            setBlur(value)
        end,
    })

    local initialHotkey = currentWindowHotkey()
    local hotkeyParagraph = interfaceSection:AddParagraph("Visibility Hotkey", hotkeyDescription(initialHotkey))
    local toggleBindControl

    local function applyHotkeyLabel(value)
        if saveStoredToggleKey and value then
            saveStoredToggleKey(value)
        end
        if hotkeyParagraph and value then
            hotkeyParagraph:Set(hotkeyDescription(value))
        end
    end

    local function toggleUiVisibility()
        local main = findMainWindow()
        if not main then
            notify("Toggle key", "Interface is not available right now.")
            return
        end
        main.Visible = not main.Visible
    end

    toggleBindControl = interfaceSection:AddBind({
        Name = "Interface Toggle Key",
        Default = resolveToggleKey(initialHotkey) or Enum.KeyCode.RightShift,
        Save = true,
        Flag = "hub_toggle_key",
        Callback = function()
            toggleUiVisibility()
            if toggleBindControl and toggleBindControl.Value then
                applyHotkeyLabel(toggleBindControl.Value)
            end
        end,
    })

    if toggleBindControl then
        local originalSet = toggleBindControl.Set
        function toggleBindControl:Set(key)
            originalSet(self, key)
            if self.Value then
                applyHotkeyLabel(self.Value)
            end
        end
        applyHotkeyLabel(toggleBindControl.Value or initialHotkey)
    end

    ----------------------------------------------------------------
    -- UI: Player safety & fling features
    ----------------------------------------------------------------
    local safetySection = Tab:AddSection({Name = "Player Safety & Fling (Experimental)"})
    safetySection:AddParagraph("Note", "Use these at your own risk, especially on games with strong anti-cheat.")

    safetySection:AddToggle({
        Name = "Anti-Fling",
        Default = false,
        Save = true,
        Flag = "sorin_antifling",
        Callback = function(value)
            setAntiFling(value)
        end,
    })

    safetySection:AddToggle({
        Name = "Walk Fling (experimental)",
        Default = false,
        Save = false,
        Flag = "sorin_walkfling",
        Callback = function(value)
            setWalkFling(value)
        end,
    })
end
