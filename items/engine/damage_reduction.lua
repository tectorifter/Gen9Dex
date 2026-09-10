-- Handles items that reduce damage or trigger on damage (Rocky Helmet, Focus Band, etc.)
-- Follows Showdown order: check for item-based reduction before passing to engine
local damage_reduction = {}

local REDUCTION_DATA = {
    -- item_id = { type = "flat/percent", value = X }
    ["ROCKY_HELMET"] = { type = "flat", value = 12 },
    ["FOCUS_BAND"] = { type = "chance_avoid", value = 0.10 },
}

function damage_reduction.apply(event, current_damage)
    local target = event.target
    local item = target.held_item

    if not item or not REDUCTION_DATA[item] then
        return current_damage
    end

    local data = REDUCTION_DATA[item]

    -- Handle chance-based avoidance (e.g., Focus Band)
    if data.type == "chance_avoid" then
        if math.random() < data.value then
            return 0
        end
    end

    -- Handle flat reduction
    if data.type == "flat" then
        current_damage = current_damage - data.value
    end

    -- Ensure damage doesn't drop below 0
    return math.max(0, current_damage)
end

return damage_reduction
