extends "res://tests/test_base.gd"


func _first_def() -> GeneratorDef:
	return ContentDB.generators()[0]


func test_add_and_spend() -> void:
	var state := GameState.new()
	state.add_resource("gold", BigNum.from_float(100.0))
	assert_big_eq(state.get_resource("gold"), BigNum.from_float(100.0))
	assert_big_eq(state.get_lifetime("gold"), BigNum.from_float(100.0))

	assert_true(state.spend_resource("gold", BigNum.from_float(40.0)))
	assert_big_eq(state.get_resource("gold"), BigNum.from_float(60.0))
	assert_big_eq(state.get_lifetime("gold"), BigNum.from_float(100.0), "Lifetime sinkt durch Ausgeben nicht")

	assert_false(state.spend_resource("gold", BigNum.from_float(1000.0)), "zu teuer")
	assert_big_eq(state.get_resource("gold"), BigNum.from_float(60.0), "Fehlkauf ändert nichts")


func test_buy_generator() -> void:
	var state := GameState.new()
	var def := _first_def()
	assert_false(state.buy_generator(def.id), "pleite = kein Kauf")
	assert_eq(state.owned(def.id), 0)

	state.add_resource(def.resource_id, BigNum.from_float(def.base_cost))
	assert_true(state.buy_generator(def.id))
	assert_eq(state.owned(def.id), 1)
	assert_false(state.buy_generator("gibt_es_nicht"), "unbekannte ID")


func test_production_and_advance() -> void:
	var state := GameState.new()
	var def := _first_def()
	assert_true(state.production_per_second(def.resource_id).is_zero(), "ohne Generatoren keine Produktion")

	state.generators[def.id] = 10
	var expected_rate := def.base_rate * 10.0
	assert_almost(state.production_per_second(def.resource_id).to_float(), expected_rate, 1e-9)

	var gains := state.advance(60.0)
	assert_almost(state.get_resource(def.resource_id).to_float(), expected_rate * 60.0, 1e-6)
	assert_almost(gains[def.resource_id].to_float(), expected_rate * 60.0, 1e-6)

	# Ein großer Schritt muss exakt dasselbe ergeben wie viele kleine.
	var step_state := GameState.new()
	step_state.generators[def.id] = 10
	for i in 600:
		step_state.advance(0.1)
	assert_almost(step_state.get_resource(def.resource_id).to_float(),
		state.get_resource(def.resource_id).to_float(), 1e-3,
		"geschlossene Form == iteriert")

	assert_true(GameState.new().advance(-5.0).is_empty(), "negative Zeit wird ignoriert")


func test_visibility() -> void:
	var state := GameState.new()
	var defs := ContentDB.generators()
	assert_true(state.is_generator_visible(defs[0]), "erster Generator sofort sichtbar")
	if defs.size() > 1:
		var second := defs[1]
		assert_false(state.is_generator_visible(second), "zweiter Generator anfangs versteckt")
		state.add_resource(second.resource_id, BigNum.from_float(second.unlock_at_lifetime))
		assert_true(state.is_generator_visible(second), "Lifetime schaltet frei")
		state.spend_resource(second.resource_id, state.get_resource(second.resource_id))
		assert_true(state.is_generator_visible(second), "Ausgeben versteckt nicht wieder")


func test_offline_progress() -> void:
	var def := _first_def()
	var state := GameState.new()
	state.generators[def.id] = 5
	var report := GameState.apply_offline(state, 3600.0)
	assert_almost(float(report["seconds"]), 3600.0, 1e-9)
	assert_false(bool(report["capped"]))
	assert_almost(state.get_resource(def.resource_id).to_float(),
		def.base_rate * 5.0 * 3600.0 * Balance.OFFLINE_EFFICIENCY, 1e-3)

	# Über dem Limit wird gedeckelt.
	var capped_state := GameState.new()
	capped_state.generators[def.id] = 5
	var capped_report := GameState.apply_offline(capped_state, float(Balance.OFFLINE_CAP_SECONDS) * 10.0)
	assert_true(bool(capped_report["capped"]))
	assert_almost(float(capped_report["seconds"]), float(Balance.OFFLINE_CAP_SECONDS), 1e-9)

	# Zurückgestellte Systemuhr: keine Gutschrift, kein Schaden.
	var negative_report := GameState.apply_offline(GameState.new(), -999.0)
	assert_almost(float(negative_report["seconds"]), 0.0, 1e-9)


func test_training() -> void:
	var state := GameState.new()
	var base_stats := state.hero_stats()
	assert_almost(base_stats["hp"].to_float(), Balance.HERO_BASE_HP)
	assert_almost(base_stats["atk"].to_float(), Balance.HERO_BASE_ATK)

	assert_false(state.train("hp"), "pleite = kein Training")
	assert_false(state.train("quatsch"), "unbekannte Art")

	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(1000000.0))
	var first_cost := state.training_cost("hp")
	assert_almost(first_cost.to_float(), Balance.TRAINING_BASE_COST)
	assert_true(state.train("hp"))
	assert_eq(state.hero_hp_level, 1)
	assert_almost(state.hero_stats()["hp"].to_float(), Balance.HERO_BASE_HP + Balance.HERO_HP_PER_TRAINING)
	assert_almost(state.training_cost("hp").to_float(),
		Balance.TRAINING_BASE_COST * Balance.TRAINING_COST_GROWTH, 1e-6, "Kosten wachsen geometrisch")
	assert_almost(state.training_cost("atk").to_float(),
		Balance.TRAINING_BASE_COST, 1e-6, "Stränge haben getrennte Stufen")

	assert_true(state.train("atk"))
	assert_almost(state.hero_stats()["atk"].to_float(), Balance.HERO_BASE_ATK + Balance.HERO_ATK_PER_TRAINING)


func test_dungeon_unlock_chain() -> void:
	var state := GameState.new()
	var dungeons := ContentDB.dungeons()
	assert_true(state.is_dungeon_unlocked(dungeons[0]), "erster Dungeon sofort frei")
	if dungeons.size() < 2:
		return
	var second := dungeons[1]
	assert_false(state.is_dungeon_unlocked(second), "zweiter Dungeon anfangs gesperrt")
	state.bank_run_result({
		"dungeon_id": second.unlocked_by,
		"victory": true,
		"gold": BigNum.from_float(60.0),
	})
	assert_true(state.is_dungeon_unlocked(second), "Sieg schaltet die Kette frei")
	assert_almost(state.get_resource(Balance.PRIMARY_RESOURCE).to_float(), 60.0, 1e-6, "Beute verbucht")
	assert_eq(state.runs_completed, 1)


func test_bank_run_result_on_defeat() -> void:
	var state := GameState.new()
	state.bank_run_result({
		"dungeon_id": "ratten_keller",
		"victory": false,
		"gold": BigNum.from_float(12.0),
	})
	assert_almost(state.get_resource(Balance.PRIMARY_RESOURCE).to_float(), 12.0, 1e-6, "Beute bleibt bei Tod")
	assert_false(state.dungeons_cleared.has("ratten_keller"), "kein Sieg, keine Freischaltung")
	assert_eq(state.runs_completed, 0)


func test_serialization_roundtrip() -> void:
	var state := GameState.new()
	var def := _first_def()
	state.add_resource("gold", BigNum.from_parts(1.5, 42))
	state.spend_resource("gold", BigNum.from_parts(1.0, 41))
	state.generators[def.id] = 17
	state.total_playtime = 123.5
	state.prestige_count = 3
	state.hero_hp_level = 4
	state.hero_atk_level = 9
	state.dungeons_cleared["ratten_keller"] = true
	state.runs_completed = 6

	var restored := GameState.from_dict(state.to_dict())
	assert_big_eq(restored.get_resource("gold"), state.get_resource("gold"))
	assert_big_eq(restored.get_lifetime("gold"), state.get_lifetime("gold"))
	assert_eq(restored.owned(def.id), 17)
	assert_almost(restored.total_playtime, 123.5)
	assert_eq(restored.prestige_count, 3)
	assert_eq(restored.hero_hp_level, 4)
	assert_eq(restored.hero_atk_level, 9)
	assert_true(restored.dungeons_cleared.has("ratten_keller"))
	assert_eq(restored.runs_completed, 6)

	# Durch JSON hindurch (Ints werden Floats) muss es ebenfalls überleben.
	var json_text := JSON.stringify(state.to_dict())
	var from_json := GameState.from_dict(JSON.parse_string(json_text))
	assert_eq(from_json.owned(def.id), 17)
	assert_big_eq(from_json.get_resource("gold"), state.get_resource("gold"))

	assert_eq(GameState.from_dict({}).owned(def.id), 0, "leeres Dict ergibt frischen State")
