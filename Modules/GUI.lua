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

GUI.Dependencies = {}

function GUI.Bind(depends)
    GUI.Dependencies = depends
end

function Drag(frame)
    Hold = true
    dragStart = UIS:GetMouseLocation()
    startPos = frame.Position
    dragFrame = frame
end

function GUI.Init_GUI()
    
    local UI : ScreenGui = game:GetObjects(getcustomasset("Mysterious Importer X/UI.rbxm"))[1]
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

    UI.Main.Top.Import.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            print(UI.Main.CarID.Input.Text)
            GUI.Dependencies.Import.import_Init(game:GetObjects(getcustomasset("Mysterious Importer X/"..UI.Main.CarID.Input.Text..".rbxm"))[1])
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