local GUI = {}

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer =  Players.LocalPlayer


local dragStart
local startPos
local dragFrame
local Hold = false

GUI.Values = {
    CarID = "",
    RimID = "",

    File = "",

    FR_O = 0,
    FL_O = 0,
    RL_O = 0,
    RR_O = 0,
    MAIN_O = 0,

    FR_S = 0,
    FL_S = 0,
    RL_S = 0,
    RR_S = 0,
    MAIN_S = 0,

    A_Spoiler = false,
    Turbine = false,
}

GUI.App = {}

local function findViewport(UI)
    for _, item in ipairs(UI:GetDescendants()) do
        if item:IsA("ViewportFrame") then
            return item
        end
    end
    return nil
end

local function setupViewport(viewport)
    if not viewport then
        return nil
    end

    local camera = viewport:FindFirstChild("ViewportCamera")
    if not camera then
        camera = Instance.new("Camera")
        camera.Name = "ViewportCamera"
        camera.Parent = viewport
    end

    viewport.CurrentCamera = camera
    return camera
end

local function clearViewportContents(viewport)
    if not viewport then
        return
    end

    for _, child in ipairs(viewport:GetChildren()) do
        if not child:IsA("Camera") then
            child:Destroy()
        end
    end
end

local function updateViewportModel(viewport, model)
    if not viewport or not model then
        return
    end

    setupViewport(viewport)
    clearViewportContents(viewport)

    local clone = model:Clone()
    clone.Parent = viewport

    local success, center, size = pcall(function()
        return clone:GetBoundingBox()
    end)

    if success and center and size then
        local lookAt = center.Position
        local offset = Vector3.new(0, math.max(size.Y, 4) * 0.75 + 1.5, math.max(size.X, size.Y, size.Z) * 1.75)
        viewport.CurrentCamera.CFrame = CFrame.lookAt(lookAt + offset, lookAt)
        viewport.CurrentCamera.Focus = CFrame.new(lookAt)
    end
end

local function tryPreviewCarID(viewport, carId)
    if not viewport or carId == "" or not GUI.App.LoadVehicle then
        return
    end

    local model = GUI.App.LoadVehicle(carId)
    if model then
        updateViewportModel(viewport, model)
    end
end

function GUI.Bind(depends)
    GUI.App = depends
end

function Drag(frame)
    Hold = true
    dragStart = UIS:GetMouseLocation()
    startPos = frame.Position
    dragFrame = frame
end

function GUI.Init_GUI(UI : ScreenGui)
    UI.Parent = LocalPlayer.PlayerGui

    UI.Main.Top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Drag(UI.Main)
        end
    end)

    UI.Main.Top.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Hold = false
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if Hold and dragFrame and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = UIS:GetMouseLocation() - dragStart

            dragFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    local viewport = findViewport(UI)

    for i,v in ipairs(UI:GetDescendants()) do
        if v:IsA("TextBox") then
            v.FocusLost:Connect(function(enterPressed)
                if enterPressed then
                    GUI.Values[v.Parent.Name] = v.Text
                    if v.Name == "Input" and v.Parent.Name == "CarID" then
                        tryPreviewCarID(viewport, v.Text)
                    end
                end
            end)
        end
    end

    UI.Main.Top.Import.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            print(UI.Main.CarID.Input.Text)
            local model = GUI.App.LoadVehicle and GUI.App.LoadVehicle(UI.Main.CarID.Input.Text)
            GUI.App.Import.import_Init(model)
        end
    end)

    UI.Main.Exit.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            UI.Main.Visible = false
        end
    end)
    
    UI.Open.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            UI.Main.Visible = true
        end
    end)
    
    for i,v in ipairs(UI:GetDescendants()) do
        if v:IsA("TextButton") then
            if v:FindFirstChildOfClass("BoolValue") and v:FindFirstChild("Toggle") then
                v.MouseButton1Click:Connect(function()
                    GUI.Values[v.Name] = not GUI.Values[v.Name]
                    v.TextColor3 = GUI.Values[v.Name] and Color3.fromRGB(133, 255, 163) or Color3.fromRGB(255, 111, 111)
                end)
            end
        end
    end
end

return GUI
