local GridUtil = {}

function GridUtil.GetCellKey(gridX, gridY)
	return string.format("%d:%d", gridX, gridY)
end

function GridUtil.IsInsideBounds(gridX, gridY, width, height)
	return gridX >= 1 and gridX <= width and gridY >= 1 and gridY <= height
end

return GridUtil
