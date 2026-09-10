return {
    -- Eviolite: Boosts defense/special if pokemon is not fully evolved
    apply_eviolite = function(pokemon, stats)
        if not pokemon or not stats then return stats end
        if pokemon.item == "EVIOLITE" and not pokemon.is_fully_evolved then
            stats.defense = stats.defense * 1.5
            stats.special = stats.special * 1.5
        end
        return stats
    end,

    -- Shell Bell: Heals user based on damage dealt
    handle_shell_bell = function(attacker, damage)
        if attacker and attacker.item == "SHELLBELL" then
            local heal_amount = math.floor(damage * 0.1 / 8) * 8 -- Simplified Gen1-style rounding
            attacker.hp = attacker.hp + heal_amount
        end
    end,

    -- Air Balloon: Negates ground moves
    is_immune = function(target, move_type)
        if target and target.item == "AIRBALLOON" and move_type == "GROUND" then
            return true
        end
        return false
    end,
}
