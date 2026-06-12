extends "res://tests/test_base.gd"


func test_def_validate() -> void:
	var valid := GeneratorUpgradeDef.from_dict({
		"id": "u", "generator_id": "oma", "display_name": "U",
		"cost": 100.0, "mult": 2.0, "unlock_at_owned": 5,
	})
	assert_true(valid.validate().is_empty())
	var useless := GeneratorUpgradeDef.from_dict({
		"id": "u", "generator_id": "oma", "display_name": "U",
		"cost": 100.0, "mult": 1.0,
	})
	assert_false(useless.validate().is_empty(), "mult 1.0 ist sinnlos")
	var free := GeneratorUpgradeDef.from_dict({
		"id": "u", "generator_id": "oma", "display_name": "U", "mult": 2.0,
	})
	assert_false(free.validate().is_empty(), "Ausbau muss etwas kosten")


func test_upgrades_load_and_reference_generators() -> void:
	var defs := ContentDB.generator_upgrades()
	assert_true(defs.size() >= 1, "mindestens ein Ausbau definiert")
	for def in defs:
		assert_true(def.validate().is_empty(), "Ausbau '%s' ist gültig" % def.id)
		assert_true(ContentDB.generator(def.generator_id) != null,
			"Ausbau '%s' gehört zu existierendem Generator" % def.id)
	assert_eq(ContentDB.generator_upgrade("gibt_es_nicht"), null)


func test_village_has_ten_generators() -> void:
	# GDD-Checkliste: "Erste 10 Dorf-Generatoren mit Bewohner-Flavor".
	var defs := ContentDB.generators()
	assert_true(defs.size() >= 10, "das Dorf braucht 10 Bewohner-Generatoren (sind: %d)" % defs.size())
	for def in defs:
		assert_false(def.flavor.is_empty(), "'%s' braucht Bewohner-Flavor" % def.id)


func test_availability_gating() -> void:
	var state := GameState.new()
	var def := ContentDB.generator_upgrade("oma_brille")
	assert_false(state.is_generator_upgrade_available(def), "ohne Omas kein Brillen-Ausbau")
	state.generators["oma"] = def.unlock_at_owned - 1
	assert_false(state.is_generator_upgrade_available(def))
	state.generators["oma"] = def.unlock_at_owned
	assert_true(state.is_generator_upgrade_available(def))

	assert_false(state.buy_generator_upgrade("oma_brille"), "pleite = kein Kauf")
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(def.cost))
	assert_true(state.buy_generator_upgrade("oma_brille"))
	assert_true(state.get_resource(Balance.PRIMARY_RESOURCE).is_zero(), "Gold bezahlt")
	assert_false(state.is_generator_upgrade_available(def), "gekauft = weg aus dem Angebot")
	assert_false(state.buy_generator_upgrade("oma_brille"), "kein Doppelkauf")
	assert_false(state.buy_generator_upgrade("gibt_es_nicht"))


func test_multiplier_applies_and_stacks() -> void:
	var state := GameState.new()
	state.generators["oma"] = 25
	var base_rate := state.production_per_second(Balance.PRIMARY_RESOURCE).to_float()

	state.generator_upgrades["oma_brille"] = true
	var once := state.production_per_second(Balance.PRIMARY_RESOURCE).to_float()
	assert_almost(once / base_rate, 2.0, 1e-9, "ein Ausbau verdoppelt")

	state.generator_upgrades["oma_stricktreff"] = true
	var twice := state.production_per_second(Balance.PRIMARY_RESOURCE).to_float()
	assert_almost(twice / base_rate, 4.0, 1e-9, "Ausbauten stapeln multiplikativ")

	# Ausbauten anderer Generatoren mischen sich nicht ein.
	assert_almost(state.generator_multiplier("schmied"), 1.0, 1e-9)


func test_prestige_resets_upgrades() -> void:
	var state := GameState.new()
	state.generator_upgrades["oma_brille"] = true
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.FRAGMENT_BASE_GOLD))
	state.prestige()
	assert_true(state.generator_upgrades.is_empty(), "Ausbauten sind Dorf-Vertrauen – weg beim Prestige")


func test_generated_tiers_exist_for_every_generator() -> void:
	# Hohe Staffeln (50/100/.../1000) werden generiert, nicht gepflegt.
	for generator_def in ContentDB.generators():
		for threshold in ContentDB.UPGRADE_TIER_THRESHOLDS:
			var tier_id := "%s_tier_%d" % [generator_def.id, threshold]
			var def := ContentDB.generator_upgrade(tier_id)
			assert_true(def != null, "Staffel '%s' fehlt" % tier_id)
			if def == null:
				continue
			assert_true(def.validate().is_empty())
			assert_eq(def.unlock_at_owned, threshold)
			assert_almost(def.mult, 2.0, 1e-9)


func test_generated_tier_costs_escalate() -> void:
	var previous := 0.0
	for threshold in ContentDB.UPGRADE_TIER_THRESHOLDS:
		var def := ContentDB.generator_upgrade("oma_tier_%d" % threshold)
		assert_true(def.cost > previous, "Staffelkosten steigen monoton (ab %d)" % threshold)
		previous = def.cost
	# Kosten ankern am Generatorpreis an der Schwelle: wer dort ankommt,
	# kann sich den Ausbau auch bald leisten.
	var oma := ContentDB.generator("oma")
	var tier_50 := ContentDB.generator_upgrade("oma_tier_50")
	assert_almost(tier_50.cost, oma.base_cost * pow(oma.cost_growth, 50.0) * 10.0, 1e-3)


func test_generated_tier_gating_works() -> void:
	var state := GameState.new()
	var def := ContentDB.generator_upgrade("oma_tier_50")
	state.generators["oma"] = 49
	assert_false(state.is_generator_upgrade_available(def))
	state.generators["oma"] = 50
	assert_true(state.is_generator_upgrade_available(def))
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(def.cost))
	assert_true(state.buy_generator_upgrade(def.id))
	assert_almost(state.generator_multiplier("oma"), 2.0, 1e-9)


func test_serialization_roundtrip() -> void:
	var state := GameState.new()
	state.generator_upgrades["oma_brille"] = true
	state.generator_upgrades["schmied_amboss"] = true
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_true(restored.generator_upgrades.has("oma_brille"))
	assert_almost(restored.generator_multiplier("oma"), 2.0, 1e-9)
	assert_almost(restored.generator_multiplier("schmied"), 2.0, 1e-9)
