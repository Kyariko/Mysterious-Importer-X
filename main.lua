local base = "https://raw.githubusercontent.com/Kyariko/Mysterious-Importer-X/dev/Modules/"
local baseVehicles = "https://raw.githubusercontent.com/Kyariko/Mysterious-Importer-X/dev/Vehicles/"

local cache = {}

local localFolder = "MIX_CACHE"

if not isfolder(localFolder) then
    makefolder(localFolder)
end

local function ensureCacheFolder(subfolder)
    if not subfolder or subfolder == "" then
        return localFolder
    end

    local folder = localFolder .. "/" .. subfolder
    if not isfolder(folder) then
        makefolder(folder)
    end
    return folder
end

local function loadRBXM(name, rootUrl, cacheSubfolder)
    local url = (rootUrl or base) .. name .. ".rbxm"
    local cacheDir = ensureCacheFolder(cacheSubfolder)
    local path = cacheDir .. "/" .. name .. ".rbxm"

    if not isfile(path) then
        local ok, data = pcall(function()
            return game:HttpGet(url)
        end)

        if not ok then
            warn("Download failed:", name, url)
            return nil
        end

        writefile(path, data)
    end

    task.wait()

    local ok, result = pcall(function()
        return game:GetObjects(getcustomasset(path))[1]
    end)

    if not ok then
        warn("RBXM load failed:", name, result)
        return nil
    end

    return result
end

local function loadVehicle(name)
    return loadRBXM(name, baseVehicles, "Vehicles")
end

local function loadModule(name)
    if cache[name] then
        return cache[name]
    end

    local success, code = pcall(function()
        return game:HttpGet(base .. name .. ".lua")
    end)

    if not success then
        warn("Failed to fetch module:", name)
        return nil
    end

    local fn, err = loadstring(code)
    if not fn then
        error("Compile error in " .. name .. ": " .. err)
    end

    local module = fn()
    cache[name] = module

    return module
end

local GUI = loadModule("GUI")
local Import = loadModule("Import")
local Custom = loadModule("Customization")

local App = {
    Import = Import,
    Customization = Custom,
    LoadVehicle = loadVehicle
}

GUI.Bind(App)
GUI.Init_GUI(loadRBXM("UI"))