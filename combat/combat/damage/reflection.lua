-- Implements Showdown-based damage reflection logic
-- Rule: Calculate true damage via Showdown formulas, pass results to engine
return {
  calculate = function(event)
    if not event then return { reflected = false } end
    local attacker = event.attacker
    local defender = event.defender
    local damage = event.damage or 0
    local move = event.move

    -- Check for Ability-based reflection (e.g., Rough Skin, Rocky Helmet)
    -- These usually happen as a secondary hit after the primary damage
    local reflection_damage = 0
    local reflection_source = nil

    -- 1. Ability/Item Reflection (Passive)
    -- Logic: If defender has a reflection ability/item, calculate a % of damage dealt back
    -- In Showdown, Rough Skin is 1/8 of damage dealt
    if defender and defender.ability == "ROUGH_SKIN" then
      reflection_damage = math.floor(damage / 8)
      reflection_source = "ABILITY_ROUGH_SKIN"
    end

    -- 2. Move-based Reflection (Active)
    -- Logic: Counter (Physical) and Mirror Coat (Special)
    -- These typically reflect 100% of damage back if the condition is met
    if move and move.id == "COUNTER" and event.category == "PHYSICAL" then
      reflection_damage = damage
      reflection_source = "MOVE_COUNTER"
    elseif move and move.id == "MIRROR_COAT" and event.category == "SPECIAL" then
      reflection_damage = damage
      reflection_source = "MOVE_MIRROR_COAT"
    end

    if reflection_damage > 0 then
      -- We return a structure that the damage_pipeline can use to trigger
      -- a second damage event in the correct order.
      return {
        reflected = true,
        damage = reflection_damage,
        source = reflection_source,
        target = attacker,
      }
    end

    return { reflected = false }
  end,
}
