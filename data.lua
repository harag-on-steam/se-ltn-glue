data:extend {
	-- We don't own the elevator entity (SE does), so we need a separate entity to connect surfaces in LTN.
	-- Otherwise the connection won't disappear if this mod is removed from a game.
	{
		type = "simple-entity-with-owner",
		name = "se-ltn-elevator-connector",
		selectable_in_game = false,
		hidden = true,
		flags = {
			"not-blueprintable",
			"not-deconstructable",
			"not-in-kill-statistics",
			"not-on-map",
			"not-repairable",
			"not-rotatable",
		},
	},
}
