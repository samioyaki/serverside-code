local HttpService = game:GetService("HttpService")

local IdUtil = {}

function IdUtil.GenerateGuid()
	return HttpService:GenerateGUID(false)
end

return IdUtil
