local Import = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer =  Players.LocalPlayer

local GetLocalVehiclePacket = require(ReplicatedStorage.Vehicle.VehicleUtils).GetLocalVehiclePacket


function WeldAllToPrimary(Model: Model)
    local PrimaryPart = Model.PrimaryPart
    if not PrimaryPart then
        warn("No PrimaryPart set!")
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
    for i, meshPart : Part in ipairs(RealModel:GetChildren()) do
        if meshPart:IsA("MeshPart") then
            meshPart.Transparency = 1
        end
        if meshPart.Name == "Windows" then
            meshPart.Size = Vector3.one * 0.001
        end
    end
end

function SetupLocalModel(LocalModel, RealModel)
    for i, meshPart : Part in ipairs(LocalModel:GetChildren()) do
        if meshPart.Name == "Wheels" then meshPart:Destroy() continue end
        meshPart.CanCollide = false
        meshPart.Massless = true
        meshPart.CanTouch = false
    end

    LocalModel:PivotTo(CFrame.new())
    
    local Engine = Instance.new("Part")
    Engine.CFrame = CFrame.new()
    Engine.Parent = LocalModel

    LocalModel.PrimaryPart = Engine
    LocalModel.Name = "LocalCustomModel"
    LocalModel.Parent = RealModel.Parent
end

function SetModelToEngine(LocalModel, RealModel)
    local LocalEngine = LocalModel.PrimaryPart
    local RealEngine = RealModel.Parent:FindFirstChild("Engine")
    print(RealEngine)
    local MainWeld = Instance.new("Weld")
    MainWeld.Parent = LocalEngine
    MainWeld.Part0 = LocalEngine
    MainWeld.Part1 = RealEngine
end

function Import.import_Init(CustomModel)
    local RealModel : Model = GetLocalVehiclePacket().Model.Model
    if not CustomModel or not RealModel then return end
    CleanRealModel(RealModel)
    SetupLocalModel(CustomModel, RealModel)
    WeldAllToPrimary(CustomModel)
    SetModelToEngine(CustomModel, RealModel)
    
end

return Import