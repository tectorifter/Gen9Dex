return {
    -- Routes move effects from national_dex (Showdown-based) to the combat engine
    -- This bridge ensures we don't use vanilla Gen 2 logic for Gen 9 effects
    dispatch = function(event)
        local move = event.move
        local user = event.user
        local target = event.target
        local effect_id = move.effectId -- Exported from national_dex

        if not effect_id then return nil end

        -- Route to the specific logic handler
        local handler = mod.content.move_effects:get(effect_id)
        if handler and handler.onExecute then
            local result = handler.onExecute(event)
            return result
        end

        -- Fallback for moves with generic Showdown logic (e.g. "secondary" effects)
        if move.secondaryEffect then
            return mod.combat.showdown_logic:processSecondary(move.secondaryEffect, event)
        end

        return nil
    end,

    -- Special handling for Tera-related move modifications
    applyTeraModifier = function(damage, move, user, target)
        if user.teraType and move.type ~= user.teraType then
            -- Showdown: Tera-type moves get a specific modifier or the type change affects effectiveness
            -- The actual damage calc in national_dex handles the multiplier; we just ensure the bridge respects it
            return damage
        end
        return damage
    end
}
