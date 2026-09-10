-- Handles damage reduction logic based on Showdown formulas
-- Items like Eviolite, Assault Vest, etc.
local damage_reduction = {}

local reduction_items = {
    EVIOLITE = function(pokemon, damage, move)
        -- Showdown: If pokemon has an evolution, reduce damage by 1/2 (roughly)
        -- In gen1recomp we check the species evolution chain
        if pokemon.species.hasEvolution then
            return damage * 0.5
        end
        return damage
    end,
    ASSAULTVEST = function(pokemon, damage, move)
        -- Showdown: SpDef * 1.5 when calculating damage taken
        -- Since we return final damage, we simulate the 1.5x SpDef boost
        if move.category == "SPECIAL" then
            return damage * (1 / 1.5)
        end
        return damage
    end,
}

damage_reduction.calculate = function(pokemon, damage, move)
    local item = pokemon.heldItem
    if item and reduction_items[item] then
        return reduction_items[item](pokemon, damage, move)
    end
    return damage
end

return damage_reduction
