return {
    -- onSwitchIn is called when a pokemon enters the field
    -- It checks if the pokemon has an ability that triggers a stat change
    onSwitchIn = function(event)
        local pokemon = event.pokemon
        local ability_id = pokemon.ability
        
        local stat_data = require("abilities/data/stat_change_switchin")
        if not stat_data[ability_id] then return end

        -- Retrieve the effect definition from the species data (national_dex)
        local species_data = mod.content.pokemon:get(pokemon.species)
        local effect = species_data.abilityBehaviorOf[ability_id]

        if effect and effect.kind == "stat_change" then
            -- effect.changes = { {stat = "attack", stages = 2}, ... }
            for _, change in ipairs(effect.changes) do
                local stat = change.stat
                local stages = change.stages
                
                -- Apply the change to the pokemon's current battle stats
                -- Using the engine's stat modification method to ensure consistency
                pokemon.stats:modifyStage(stat, stages)
                
                mod.log:info(string.format("Ability %s triggered: %s changed by %d stages", 
                    ability_id, stat, stages))
            end
        end
    end
}
