local Client = script.Parent:WaitForChild("Client")

local NetworkClient = require(Client:WaitForChild("NetworkClient"))
local ReplicaClient = require(Client:WaitForChild("ReplicaClient"))
local ShopScreen = require(Client:WaitForChild("UI"):WaitForChild("ShopScreen"))
local PlotScreen = require(Client:WaitForChild("UI"):WaitForChild("PlotScreen"))

NetworkClient:Init()
ReplicaClient:Init()
ShopScreen:Init(NetworkClient, ReplicaClient)
PlotScreen:Init(NetworkClient, ReplicaClient, ShopScreen)
