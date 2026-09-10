-- Showdown-based Berry consumption and effects
-- Berries are triggered by specific events (hit, status, etc.) and then consumed
local berry_effects = {}

-- Formula: Current HP / Max HP threshold or specific condition
-- Showdown handles berries as "triggers" that apply a modification then vanish
berry_effects.triggers = {
    HP_THRESHOLD = function(pokemon) 
        return pokemon.hp / pokemon.maxHp <= 0.25 
    end,
    STATUS_CONDITION = function(pokemon) 
        return pokemon.status ~= "NONE" 
    end,
}

berry_effects.apply = function(pokemon, berry_id)
    local berry = mod.content.items:get(berry_id)
    if not berry or not berry.effect then return end
    
    local effect = berry.effect
    if effect.type == "heal" then
        -- Showdown formula: specific amount or %
        local amount = effect.value or 20
        pokemon.hp = pokemon.hp + amount
        mod.log:info(pokemon.name .. " consumed " .. berry_id .. " and healed " .. amount)
    elseif effect.type == "stat_boost" then
        -- Trigger immediate stat change
        local stat = effect.stat
        local stages = effect.stages or 1
        -- Use engine's stat modification logic
        pokemon.stats[stat] = pokemon.stats[stat] + stages
    end
    
    -- Consume item
    pokemon.heldItem = mod.DELETE
    return true
end

return berry_effects
