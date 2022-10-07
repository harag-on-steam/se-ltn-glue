data:extend {
	-- We don't own the elevator entity (SE does), so we need a separate entity to connect surfaces in LTN.
	-- Otherwise the connection won't disappear if this mod is removed from a game.
	{
		type = "simple-entity-with-force",
		name = "se-ltn-elevator-connector",
		selectable_in_game = false,
		picture = {
			-- we depend on SE so we can re-use this
			filename = "__space-exploration-graphics__/graphics/blank.png",
			priority = "high",
			frame_count = 1,
			height = 1,
			width = 1,
			direction_count = 1,
			variation_count = 1,
		},
		flags = {
			"hidden",
			"not-blueprintable",
			"not-deconstructable",
			"not-repairable",
			"not-in-kill-statistics",
			"not-on-map",
			"not-rotatable",
		},
	},
}
