return function(mod)
  return {
    -- Handles items that trigger status conditions
    -- Called during switch-in or specific move triggers
    handle_switch_in = function(pokemon)
      if not pokemon then return end
      local item = pokemon.item
      if not item then return end

      if item == "FLAMEORB" then
        pokemon.status = "BRN"
        mod.content.items:patch("FLAMEORB", { consumed = true }) -- Item is consumed
      elseif item == "TOXICORB" then
        pokemon.status = "PSN"
        mod.content.items:patch("TOXICORB", { consumed = true })
      end
    end,

    -- Handles items that trigger status on hit/move
    handle_move_usage = function(pokemon)
      -- Logic for items like Flame Orb that might trigger on specific conditions
    end,
  }
end
