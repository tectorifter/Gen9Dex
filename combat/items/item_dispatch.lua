return function(mod)
    local items_battle = require("items/data/items_battle")

    local function dispatch(event)
        -- Process items for both attacker and defender if applicable
        local targets = {
            { role = "attacker", mon = event.attacker },
            { role = "defender", mon = event.defender }
        }

        for _, target in ipairs(targets) do
            local mon = target.mon
            if not mon or not mon.heldItem then
                -- Lua 5.1/LuaJIT does not have 'goto' for loop skipping in this context
                -- and 'continue' is not a keyword. We use a simple if-check.
            else
                local item_id = mon.heldItem
                local effect = items_battle[item_id]

                if effect then
                    if event.type == "onDamageCalculate" then
                        -- Check if the item modifies damage for the role (e.g., Leftovers for defender)
                        if effect.onDamageCalculate then
                            local res = effect.onDamageCalculate(event, target.role)
                            if res == "INTERRUPT" then return "INTERRUPT" end
                        end
                    end
                    
                    if event.type == "onSwitchIn" and effect.onSwitchIn then
                        effect.onSwitchIn(event)
                    end
                end
            end
        end

        return nil
    end

    return {
        dispatch = dispatch
    }
end
