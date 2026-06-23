local Import = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer =  Players.LocalPlayer

local GetLocalVehiclePacket = require(ReplicatedStorage.Vehicle.VehicleUtils).GetLocalVehiclePacket

local wheelOffsetCache = setmetatable({}, {__mode = "k"})

local function findFirstBasePart(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant
        end
    end
    return nil
end

local function ensureLocalEngine(LocalModel)
    if not LocalModel then
        return nil
    end

    local engine = LocalModel:FindFirstChild("LocalCustomEngine")
    if engine and engine:IsA("BasePart") then
        LocalModel.PrimaryPart = engine
        return engine
    end

    local success, center, size = pcall(function()
        return LocalModel:GetBoundingBox()
    end)

    if not success or not center or not size then
        local fallbackPart = findFirstBasePart(LocalModel)
        if fallbackPart then
            center = fallbackPart.CFrame
            size = Vector3.new(1, 1, 1)
        else
            center = CFrame.new()
            size = Vector3.new(1, 1, 1)
        end
    end

    local paddedSize = Vector3.new(
        math.max(0.1, size.X),
        math.max(0.1, size.Y),
        math.max(0.1, size.Z)
    )

    engine = Instance.new("Part")
    engine.Name = "LocalCustomEngine"
    engine.Size = paddedSize
    engine.Transparency = 1
    engine.CanCollide = false
    engine.Massless = false
    engine.Anchored = false
    engine.CFrame = center
    engine.Parent = LocalModel

    LocalModel.PrimaryPart = engine
    return engine
end

function WeldAllToPrimary(Model: Model)
    local PrimaryPart = Model.PrimaryPart or findFirstBasePart(Model)
    if not PrimaryPart then
        warn("No PrimaryPart set or found for model")
        return
    end

    for _, part in ipairs(Model:GetDescendants()) do
        if part:IsA("BasePart") and part ~= PrimaryPart then
            part.Anchored = false

            local weld = Instance.new("Weld")
            weld.Name = part.Name .. "_Weld"
            weld.Part0 = PrimaryPart
            weld.Part1 = part

            weld.C0 = PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
            weld.C1 = CFrame.new()

            weld.Parent = PrimaryPart
        end
    end
end

function CleanRealModel(RealModel)
    for _, part in ipairs(RealModel:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Transparency = 1
            if part.Name == "Windows" then
                part.Size = Vector3.one * 0.001
            end
        end
    end
end

function SetupLocalModel(LocalModel, RealModel)
    local wheelsFolder = LocalModel:FindFirstChild("Wheels")
    for _, obj in ipairs(LocalModel:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.CanCollide = false
            obj.Massless = false
            obj.CanTouch = false
        end
    end

    local Engine = ensureLocalEngine(LocalModel)
    if not Engine then
        warn("SetupLocalModel: failed to create local engine")
        return
    end

    LocalModel.Name = "LocalCustomModel"

    if wheelsFolder then
        local wheelOffsets = {}
        for _, localWheel in ipairs(wheelsFolder:GetChildren()) do
            if localWheel:IsA("Model") then
                local success, pivot = pcall(function()
                    return localWheel:GetPivot()
                end)
                if success and pivot then
                    wheelOffsets[localWheel.Name] = Engine.CFrame:ToObjectSpace(pivot)
                end
            end
        end
        wheelOffsetCache[LocalModel] = wheelOffsets
        wheelsFolder:Destroy()
    end

    LocalModel.Parent = RealModel.Parent
end

local function findDescendantByName(root, name)
    if not root or type(name) ~= "string" then
        return nil
    end

    if root.Name == name then
        return root
    end

    for _, child in ipairs(root:GetDescendants()) do
        if child.Name == name then
            return child
        end
    end

    return nil
end

local function scaleCFrame(cframe, scale)
    if typeof(cframe) ~= "CFrame" or type(scale) ~= "number" then
        return cframe
    end

    local right = cframe.RightVector * scale
    local up = cframe.UpVector * scale
    local look = cframe.LookVector * scale
    local pos = cframe.Position * scale

    return CFrame.fromMatrix(pos, right, up, look)
end

local function hideLocalModel(Model)
    if not Model then
        return
    end

    for _, part in ipairs(Model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Transparency = 1
            part.CanCollide = false
            part.CanTouch = false
        end
    end
end

function SetModelToEngine(LocalModel, RealModel)
    local LocalEngine = LocalModel.PrimaryPart
    if not LocalEngine then
        warn("Local custom model has no PrimaryPart")
        return
    end

    local RealEngine = findDescendantByName(RealModel, "Engine")
    if not RealEngine or not RealEngine:IsA("BasePart") then
        warn("Real vehicle engine part not found")
        return
    end
    -- copy physical properties from the real engine to preserve mass/density
    pcall(function()
        if LocalEngine and LocalEngine:IsA("BasePart") then
            local phys = RealEngine.CustomPhysicalProperties
            if phys then
                LocalEngine.CustomPhysicalProperties = phys
            end
            LocalEngine.Massless = false
            LocalEngine.Transparency = 1
            LocalEngine.CanCollide = false
            LocalEngine.CanTouch = false
        end
    end)

    local MainWeld = Instance.new("Weld")
    MainWeld.Name = "CustomModelEngineWeld"
    MainWeld.Parent = LocalEngine
    MainWeld.Part0 = LocalEngine
    MainWeld.Part1 = RealEngine
    MainWeld.C0 = CFrame.new()
    MainWeld.C1 = CFrame.new()
end

function Import.applyOffsets(LocalModel, c0, c1)
    if not LocalModel then
        warn("Import.applyOffsets: LocalModel is nil")
        return
    end

    local primary = LocalModel.PrimaryPart
    if not primary then
        warn("Import.applyOffsets: LocalModel has no PrimaryPart")
        return
    end

    -- find the engine weld on the primary part
    local weld = primary:FindFirstChild("CustomModelEngineWeld")
    if not weld then
        -- try searching descendants
        for _, v in ipairs(primary:GetDescendants()) do
            if v:IsA("Weld") and v.Name == "CustomModelEngineWeld" then
                weld = v
                break
            end
        end
    end

    if not weld then
        local RealModel = GetLocalVehiclePacket().Model
        if RealModel then
            SetModelToEngine(LocalModel, RealModel)
            weld = primary:FindFirstChild("CustomModelEngineWeld")
            if not weld then
                for _, v in ipairs(primary:GetDescendants()) do
                    if v:IsA("Weld") and v.Name == "CustomModelEngineWeld" then
                        weld = v
                        break
                    end
                end
            end
        end
    end

    if not weld then
        warn("Import.applyOffsets: engine weld not found on local model")
        return
    end

    if c0 and typeof(c0) == "CFrame" then
        weld.C0 = c0
    end

    if c1 and typeof(c1) == "CFrame" then
        weld.C1 = c1
    end
end

function Import.applyScale(LocalModel, scale)
    if not LocalModel then return end
    scale = tonumber(scale) or 1
    if scale == 1 then return end

    -- Use the engine-provided scaling method only
    pcall(function()
        LocalModel:ScaleTo(scale)
    end)
end

function Import.syncWheelOffsets(LocalModel, values)
    if not LocalModel then
        warn("Import.syncWheelOffsets: LocalModel is nil")
        return
    end

    local offsets = wheelOffsetCache[LocalModel]
    if not offsets then
        warn("Import.syncWheelOffsets: no cached wheel offsets for local model")
        return
    end

    local RealModel = GetLocalVehiclePacket().Model
    if not RealModel then
        warn("Import.syncWheelOffsets: unable to get packet model")
        return
    end

    local preset = findDescendantByName(RealModel, "Preset")
    if not preset then
        warn("Import.syncWheelOffsets: real preset not found")
        return
    end

    local mapping = {
        FL = "WheelFrontLeft",
        FR = "WheelFrontRight",
        RL = "WheelBackLeft",
        RR = "WheelBackRight",
    }

    for localName, localOffset in pairs(offsets) do
        local realName = mapping[localName] or localName
        local realWheel = findDescendantByName(preset, realName)
        if not realWheel then
            warn("Import.syncWheelOffsets: real wheel model not found for", realName)
            continue
        end

        local thrust = realWheel:FindFirstChild("Thrust", true)
        if not thrust or not thrust:IsA("BasePart") then
            warn("Import.syncWheelOffsets: Thrust part missing for", realName)
            continue
        end

        local weld = thrust:FindFirstChild("Weld", true)
        if not weld or not weld:IsA("Weld") then
            warn("Import.syncWheelOffsets: Weld missing in Thrust for", realName)
            continue
        end

        local uiOffset = Vector3.new()
        if values then
            local delta = tonumber(values[localName .. "_O"]) or 0
            uiOffset = Vector3.new(0, delta, 0)
        end

        local enginePart = findDescendantByName(RealModel, "Engine")
        if not enginePart or not enginePart:IsA("BasePart") then
            warn("Import.syncWheelOffsets: real engine part missing")
            continue
        end

        local desired = enginePart.CFrame * (localOffset * CFrame.new(uiOffset))

        if weld.Part0 == thrust and weld.Part1 == enginePart then
            weld.C0 = thrust.CFrame:ToObjectSpace(desired)
            weld.C1 = CFrame.new()
        elseif weld.Part1 == thrust and weld.Part0 == enginePart then
            weld.C1 = thrust.CFrame:ToObjectSpace(desired)
            weld.C0 = CFrame.new()
        else
            warn("Import.syncWheelOffsets: unexpected weld orientation for", realName)
            if weld.Part0 == thrust then
                weld.C0 = thrust.CFrame:ToObjectSpace(desired)
            elseif weld.Part1 == thrust then
                weld.C1 = thrust.CFrame:ToObjectSpace(desired)
            end
        end
    end
end

function Import.import_Init(CustomModel)
    local RealModel : Model = GetLocalVehiclePacket().Model
    if not CustomModel or not RealModel then return end
    CleanRealModel(RealModel)
    SetupLocalModel(CustomModel, RealModel)
    WeldAllToPrimary(CustomModel)
    SetModelToEngine(CustomModel, RealModel)
end

return Import