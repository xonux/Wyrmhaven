-- Gems it costs to skip the rest of a timer (a construction, an upgrade's
-- works, an obstacle's clearing, an egg's hatching), by the time left: up to
-- 5 min 1, 15 min 2, 30 min 3, 45 min 4, 1 h 5; then one more per started
-- 20 min up to 3 h (11), per started 30 min up to 8 h (21), and per started
-- hour beyond. Shared so the option bars show exactly what the server charges.
local STEPS = { { 5, 1 }, { 15, 2 }, { 30, 3 }, { 45, 4 }, { 60, 5 } } -- { up to minutes, Gems }

return function(secondsLeft)
	local minutes = math.max(0, secondsLeft) / 60
	for _, step in ipairs(STEPS) do
		if minutes <= step[1] then
			return step[2]
		end
	end
	if minutes <= 180 then
		return 5 + math.ceil((minutes - 60) / 20)
	end
	if minutes <= 480 then
		return 11 + math.ceil((minutes - 180) / 30)
	end
	return 21 + math.ceil((minutes - 480) / 60)
end
