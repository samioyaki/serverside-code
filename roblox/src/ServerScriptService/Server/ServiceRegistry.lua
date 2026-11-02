local ServiceRegistry = {}
ServiceRegistry.__index = ServiceRegistry

function ServiceRegistry.new()
	local self = setmetatable({
		Order = {
			"WorldService",
			"MonetizationService",
			"PlayerDataService",
			"ReplicaService",
			"LeaderstatsService",
			"LeaderboardService",
			"PlotService",
			"CollectionService",
			"EconomyService",
			"InventoryService",
			"RollService",
			"TraitService",
			"DatingService",
			"RodComponentService",
			"FishingService",
			"RodToolService",
			"PlacementService",
			"IncomeService",
			"ClaimService",
			"UpgradeService",
			"ShopService",
			"FusionService",
			"CrateService",
			"RebirthService",
			"RemoteRouterService",
		},
		Services = {},
	}, ServiceRegistry)

	self:_ConstructServices()

	return self
end

function ServiceRegistry:_ConstructServices()
	local servicesFolder = script.Parent.Services

	for _, serviceName in ipairs(self.Order) do
		local module = require(servicesFolder:WaitForChild(serviceName))
		self.Services[serviceName] = module.new(self)
	end
end

function ServiceRegistry:Get(serviceName)
	local service = self.Services[serviceName]
	assert(service, string.format("Unknown service %s", serviceName))

	return service
end

function ServiceRegistry:Start()
	for _, serviceName in ipairs(self.Order) do
		local service = self.Services[serviceName]
		if service.Init then
			service:Init()
		end
	end

	for _, serviceName in ipairs(self.Order) do
		local service = self.Services[serviceName]
		if service.Start then
			service:Start()
		end
	end
end

return ServiceRegistry
