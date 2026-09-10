return {
    -- Bridges national_dex item properties to engine effects
    -- Focuses on triggers: onSwitchIn, onDamage, onTurnEnd
    processItemTrigger = function(event)
        local item = event.pokemon.heldItem
        if not item then return end

        local item_data = mod.content.items:get(item.id)
        if not item_data then return end

        -- Map national_dex item properties to Showdown-style triggers
        if event.type == "onDamage" and item_data.onDamageEffect then
            return item_data.onDamageEffect(event)
        end

        if event.type == "onTurnEnd" and item_data.onTurnEndEffect then
            -- e.g. Leftovers recovery
            return item_data.onTurnEndEffect(event)
        end

        if event.type == "onSwitchIn" and item_data.onSwitchInEffect then
            -- e.g. Focus Band, Eviolite (though Eviolite is a stat mod)
            return item_data.onSwitchInEffect(event)
        end
    end
}
