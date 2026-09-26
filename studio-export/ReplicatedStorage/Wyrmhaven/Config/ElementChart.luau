-- Which element beats which, in one loop (the user's own order):
--   Fire > Nature > Metal > Light > Dark > Earth > Electric > Water > Fire
--
-- Two rules, and only two:
--   * a skill hitting the element it beats does Advantage damage;
--   * a skill hitting its OWN element does SameElement damage - fire hardly
--     burns a fire dragon.
-- Everything else is normal damage. In particular the other way round is NOT
-- a penalty: Water hits Fire hard, and Fire hitting Water back is simply
-- normal. That was the user's call, and it keeps a bad matchup from being
-- punished twice over.
--
-- A hybrid is judged on both of its elements, one after the other. Since an
-- element beats exactly one other and equals exactly one, a single skill can
-- never be strong against both halves: the whole thing stays between
-- SameElement and Advantage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(script.Parent.GameConstants)

local ElementChart = {}

-- The loop, in order.
ElementChart.Order = { "Fire", "Nature", "Metal", "Light", "Dark", "Earth", "Electric", "Water" }

ElementChart.Beats = {}
ElementChart.BeatenBy = {}
for index, element in ipairs(ElementChart.Order) do
	local prey = ElementChart.Order[index % #ElementChart.Order + 1]
	ElementChart.Beats[element] = prey
	ElementChart.BeatenBy[prey] = element
end

-- How much damage a skill of `attackElement` does to a dragon of `element`.
function ElementChart.Against(attackElement, element)
	if not attackElement or not element then
		return 1
	end
	if attackElement == element then
		return GameConstants.ElementSameMultiplier
	end
	if ElementChart.Beats[attackElement] == element then
		return GameConstants.ElementAdvantageMultiplier
	end
	return 1
end

-- The multiplier against a whole dragon (one element, or a hybrid's two).
function ElementChart.Factor(attackElement, elements)
	if not attackElement or not elements then
		return 1
	end
	local factor = 1
	for _, element in ipairs(elements) do
		factor *= ElementChart.Against(attackElement, element)
	end
	return factor
end

-- What the battle screen says about a factor: "Strong", "Resisted" or nil
-- when nothing special happened.
function ElementChart.Label(factor)
	if factor > 1.001 then
		return "Strong"
	elseif factor < 0.999 then
		return "Resisted"
	end
	return nil
end

return ElementChart
