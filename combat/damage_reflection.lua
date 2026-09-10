local function calc_damage(attacker, defender, move, base_damage)
    local reflected = 0
    local absorbed = 0

    if move.id == "COUNTER" then
        -- Counter: Returns 100% of the physical damage taken
        reflected = base_damage
    elseif move.id == "MIRROR_COAT" then
        -- Mirror Coat: Returns 100% of the special damage taken
        reflected = base_damage
    elseif move.id == "METAL_BURST" then
        -- Metal Burst: Returns 100% of damage taken (Physical or Special)
        reflected = base_damage
    elseif move.id == "BIDE" then
        -- Bide: Absorbs damage, returns 100% of it on the next turn
        -- For the turn it's used, the user takes 0 damage
        absorbed = base_damage
        reflected = 0
    elseif move.id == "COMEUPPANCE" then
        -- Comeuppance: Returns 100% of damage taken this turn
        reflected = base_damage
    end

    return reflected, absorbed
end

return function(mod)
    return {
        calculate = function(attacker, defender, move, base_damage)
            return calc_damage(attacker, defender, move, base_damage)
        end
    }
end
