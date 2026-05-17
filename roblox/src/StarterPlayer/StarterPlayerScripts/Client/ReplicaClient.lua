local NetworkClient = require(script.Parent.NetworkClient)

local ReplicaClient = {
	Replica = nil,
	Listeners = {},
	NotificationListeners = {},
}

local function shallowCopyTable(values)
	local copy = {}
	for key, value in pairs(values) do
		copy[key] = value
	end
	return copy
end

function ReplicaClient:Init()
	self.Replica = NetworkClient:Bootstrap()

	NetworkClient:BindStateDelta(function(payload)
		self:ApplyDelta(payload)
	end)

	NetworkClient:BindNotification(function(payload)
		for _, listener in ipairs(self.NotificationListeners) do
			listener(payload)
		end
	end)
end

function ReplicaClient:Get()
	return self.Replica
end

function ReplicaClient:Subscribe(listener)
	table.insert(self.Listeners, listener)

	return function()
		for index, currentListener in ipairs(self.Listeners) do
			if currentListener == listener then
				table.remove(self.Listeners, index)
				return
			end
		end
	end
end

function ReplicaClient:SubscribeNotifications(listener)
	table.insert(self.NotificationListeners, listener)

	return function()
		for index, currentListener in ipairs(self.NotificationListeners) do
			if currentListener == listener then
				table.remove(self.NotificationListeners, index)
				return
			end
		end
	end
end

function ReplicaClient:ApplyDelta(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.Full then
		self.Replica = payload.State
	else
		local currentRevision = self.Replica and self.Replica.Revision or 0
		if payload.Revision and payload.Revision < currentRevision then
			return
		end

		self.Replica = self.Replica or {}
		self.Replica.Revision = payload.Revision or currentRevision

		for _, operation in ipairs(payload.Ops or {}) do
			if operation.Op == "Replace" and type(operation.Path) == "string" then
				self.Replica[operation.Path] = operation.Value
			end
		end
	end

	local snapshot = self.Replica and shallowCopyTable(self.Replica) or nil
	for _, listener in ipairs(self.Listeners) do
		listener(snapshot)
	end
end

return ReplicaClient
