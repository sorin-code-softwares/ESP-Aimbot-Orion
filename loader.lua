-- loader.lua
-- Orion loader for SorinHub (ESP, visuals, hub settings)

local GUI_NAME = "SorinHub"
getgenv()._SorinWinCfg = getgenv()._SorinWinCfg or { GuiName = GUI_NAME }

local ORION_URL = "https://raw.githubusercontent.com/sorinservice/script-libary/main/OrionLibary.lua"
local TABS_BASE = "https://raw.githubusercontent.com/sorin-code-softwares/ESP-Aimbot-Orion/main/tabs/"

local function loadLocalChunk(path)
    if typeof(readfile) ~= "function" then
        return nil, "readfile is not available in this environment"
    end

    local okRead, contents = pcall(readfile, path)
    if not okRead then
        return nil, ("Failed to read %s: %s"):format(path, tostring(contents))
    end

    contents = contents
        :gsub("^\239\187\191", "")        -- strip UTF-8 BOM
        :gsub("\226\128\139", "")         -- strip ZERO WIDTH NO-BREAK SPACE

    local chunk, compileErr = loadstring(contents, "=" .. path)
    if not chunk then
        return nil, ("loadstring failed for %s: %s"):format(path, tostring(compileErr))
    end

    local okRun, result = pcall(chunk)
    if not okRun then
        return nil, ("Error while executing %s: %s"):format(path, tostring(result))
    end

    return result, nil
end

local function loadRemoteChunk(url)
    local okFetch, body = pcall(function()
        return game:HttpGet(url)
    end)
    if not okFetch then
        return nil, ("HTTP error on %s: %s"):format(url, tostring(body))
    end

    body = body
        :gsub("^\239\187\191", "")
        :gsub("\226\128\139", "")

    local chunk, compileErr = loadstring(body, "=" .. url)
    if not chunk then
        return nil, ("loadstring failed for %s: %s"):format(url, tostring(compileErr))
    end

    local okRun, result = pcall(chunk)
    if not okRun then
        return nil, ("Error while executing %s: %s"):format(url, tostring(result))
    end

    return result, nil
end

local OrionLib, libErr = loadLocalChunk("OrionLib.lua")
if not OrionLib then
    OrionLib, libErr = loadRemoteChunk(ORION_URL)
    if not OrionLib then
        error(libErr)
    end
end

local Window = OrionLib:MakeWindow({
    Name = "SorinHub | ESP & Aimbot",
    IntroText = "by SorinSoftware Services",
    SaveConfig = true,
    ConfigFolder = "SorinHub",
    ShowIcon = true,
    ShowLogo = false,
    Icon = "rbxassetid://84637769762084",
})

local MODULES = {
    {
        name = "Hub Settings",
        url = TABS_BASE .. "HubSettings.lua",
        file = "HubSettings.lua",
        icon = "info",
    },
    {
        name = "Visuals & Graphics",
        url = TABS_BASE .. "visuals_graphics.lua",
        file = "visuals_and_graphics.lua",
        icon = "graphics",
    },
    {
        name = "Aimbot",
        url = TABS_BASE .. "aimbot.lua",
        file = "aimbot.lua",
        icon = "aimbot",
    },
    {
        name = "Movement",
        url = TABS_BASE .. "movement.lua",
        file = "movement.lua",
        icon = "vehicle",
    },
}

local function attachTab(entry)
    local Tab = Window:MakeTab({Name = entry.name, Icon = entry.icon})

    local mod, err
    if entry.url then
        mod, err = loadRemoteChunk(entry.url)
    end
    if not mod and entry.file then
        mod, err = loadLocalChunk(entry.file)
    end
    if not mod then
        Tab:AddParagraph("Loader Error", tostring(err))
        return
    end
    if type(mod) ~= "function" then
        Tab:AddParagraph("Loader Error", (entry.url or entry.file or "module") .. " must return a function.")
        return
    end

    local ok, initErr = pcall(mod, Tab, OrionLib, Window, {guiName = GUI_NAME})
    if not ok then
        Tab:AddParagraph("Tab Init Failed", tostring(initErr))
    end
end

for _, entry in ipairs(MODULES) do
    attachTab(entry)
end

OrionLib:Init()
