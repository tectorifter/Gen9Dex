local registry = require("items/data/combat_items_registry")

local CombatItemsHandler = {}

-- Calculates final damage after applying all held item modifiers
-- Following Showdown order of operations: Base -> Ability -> Item -> Final
function CombatItemsHandler.apply_damage_modifiers(event, current_damage)
    local damage = current_damage
    local attacker_item = event.attacker.held_item
    local defender_item = event.defender.held_item

    -- 1. Attacker Item Boosts (e.g., Life Orb)
    if attacker_item and registry.stat_modifiers[attacker_item] then
        local mod = registry.stat_modifiers[attacker_item]
        if mod.damage_mult then
            damage = damage * mod.damage_mult
        end
    end

    -- 2. Defender Item Reductions (e.g., Assault Vest - simplified as a flat red if applicable)
    if defender_item and registry.damage_reduction[defender_item] then
        local red = registry.damage_reduction[defender_item]
        if type(red) == "number" then
            damage = damage * red
        elseif red.damage_mult then
            damage = damage * red.damage_mult
        end
    end

    return damage
end

-- Checks if a berry should trigger based on current HP percentage
function CombatItemsHandler.check_berry_trigger(pokemon)
    local item = pokemon.held_item
    if not item then return nil end
    
    local berry = registry.berry_triggers[item]
    if berry then
        local hp_perc = pokemon.hp / pokemon.max_hp
        if hp_perc <= berry.threshold then
            return berry
        end
    end
    return nil
end

return CombatItemsHandler
