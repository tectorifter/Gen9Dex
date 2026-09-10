return function(mod)
  local item_effects_combat = {}

  -- Berry consumption logic (Showdown accurate)
  -- Returns true if the item was consumed
  function item_effects_combat.handle_berry_trigger(pokemon, trigger_type, effect_data)
    if not pokemon then return false end
    local item = pokemon.held_item
    if not item or not item.is_berry then return false end

    local berry_data = mod.content.items:get(item)
    if not berry_data then return false end
    local trigger = berry_data.trigger -- e.g., "on_hit", "on_status"

    if trigger == trigger_type then
      -- Execute the berry effect (defined in national_dex/item_effects)
      local effect = berry_data.effect
      if effect then
        mod.log:info(string.format("Berry %s triggered by %s", item, trigger_type))
        -- The actual effect application is handled by the engine's effect dispatcher
        -- but we signal the consumption here.
      end

      -- Consume the item
      pokemon.held_item = nil
      return true
    end
    return false
  end

  -- Leftovers logic: Heals 1/16 of max HP at the end of the turn
  -- or reduces damage in specific custom pipeline contexts.
  function item_effects_combat.apply_leftovers(pokemon, current_hp, max_hp)
    local heal_amount = math.floor(max_hp / 16)
    return math.min(current_hp + heal_amount, max_hp)
  end

  -- Focus Band logic: 10% chance to survive hit with 1 HP
  function item_effects_combat.handle_focus_band(pokemon, damage, current_hp)
    if damage >= current_hp then
      if math.random(1, 100) <= 10 then
        mod.log:info("Focus Band triggered! Pokémon survived with 1 HP.")
        return 1 -- New HP
      end
    end
    return nil -- No trigger
  end

  return item_effects_combat
end
