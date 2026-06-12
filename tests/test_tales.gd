extends "res://tests/test_base.gd"

## Tatentracking: Taten im Run werden zu Tavernenerzählungen –
## qualitative Meilensteine, die später Klassen freischalten.


func _victory_result(overrides := {}) -> Dictionary:
	var result := {
		"dungeon_id": "ratten_keller",
		"status": RunState.Status.VICTORY,
		"victory": true,
		"gold": BigNum.from_float(100.0),
		"items": {},
		"rooms_cleared": 5,
		"ticks": 30,
		"took_damage": true,
		"damage_taken": BigNum.from_float(20.0),
		"doors_seen": 4,
		"elite_chosen": 0,
		"rest_chosen": 0,
		"strikes_used": 2,
		"breathers_used": 1,
	}
	for key: String in overrides:
		result[key] = overrides[key]
	return result


func test_def_validate() -> void:
	var valid := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F", "type": "victory",
	})
	assert_true(valid.validate().is_empty())
	var storyless := TaleDef.from_dict({"id": "t", "display_name": "T", "type": "victory"})
	assert_false(storyless.validate().is_empty(), "ohne Geschichte keine Erzählung")
	var weird := TaleDef.from_dict({"id": "t", "display_name": "T", "flavor": "F", "type": "tanzen"})
	assert_false(weird.validate().is_empty(), "unbekannter Typ wird abgelehnt")
	var slow := TaleDef.from_dict({"id": "t", "display_name": "T", "flavor": "F", "type": "speed"})
	assert_false(slow.validate().is_empty(), "speed braucht max_ticks")


func test_conditions_match() -> void:
	var clear_keller := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F",
		"type": "victory", "dungeon_id": "ratten_keller",
	})
	assert_true(clear_keller.matches(_victory_result()))
	assert_false(clear_keller.matches(_victory_result({"dungeon_id": "finsterwald"})), "falscher Dungeon")
	assert_false(clear_keller.matches(_victory_result({
		"victory": false, "status": RunState.Status.DEFEAT,
	})), "Niederlage zählt nicht als Sieg")

	var no_damage := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F", "type": "no_damage",
	})
	assert_false(no_damage.matches(_victory_result()))
	assert_true(no_damage.matches(_victory_result({"took_damage": false})))

	var all_elite := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F", "type": "all_elite",
	})
	assert_false(all_elite.matches(_victory_result()))
	assert_true(all_elite.matches(_victory_result({"doors_seen": 4, "elite_chosen": 4})))
	assert_false(all_elite.matches(_victory_result({"doors_seen": 0, "elite_chosen": 0})),
		"ohne Gabelungen keine Schatzjäger-Geschichte")

	var speed := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F", "type": "speed", "max_ticks": 25,
	})
	assert_false(speed.matches(_victory_result()), "30 Ticks sind zu langsam")
	assert_true(speed.matches(_victory_result({"ticks": 25})))

	var lazy := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F", "type": "no_abilities",
	})
	assert_false(lazy.matches(_victory_result()))
	assert_true(lazy.matches(_victory_result({"strikes_used": 0, "breathers_used": 0})))

	var fled := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F", "type": "fled",
	})
	assert_true(fled.matches(_victory_result({
		"victory": false, "status": RunState.Status.FLED,
	})))
	assert_false(fled.matches(_victory_result()), "Sieg ist kein Rückzug")

	var defeat := TaleDef.from_dict({
		"id": "t", "display_name": "T", "flavor": "F", "type": "defeat",
	})
	assert_true(defeat.matches(_victory_result({
		"victory": false, "status": RunState.Status.DEFEAT,
	})))


func test_tales_load_and_cover_every_dungeon() -> void:
	var defs := ContentDB.tales()
	assert_true(defs.size() >= 1, "mindestens eine Erzählung definiert")
	for def in defs:
		assert_true(def.validate().is_empty(), "Erzählung '%s' ist gültig" % def.id)
	assert_eq(ContentDB.tale("gibt_es_nicht"), null)
	# Jeder Dungeon braucht seine Sieges-Geschichte.
	for dungeon_def in ContentDB.dungeons():
		var found := false
		for def in defs:
			if def.type == "victory" and def.dungeon_id == dungeon_def.id:
				found = true
		assert_true(found, "'%s' braucht eine Sieg-Erzählung" % dungeon_def.id)


func test_banking_awards_once() -> void:
	var state := GameState.new()
	var first := state.bank_run_result(_victory_result())
	assert_true(first.has("koenig_der_ratten"), "Keller-Sieg gibt die Kronen-Geschichte")
	assert_true(state.has_tale("koenig_der_ratten"))

	var second := state.bank_run_result(_victory_result())
	assert_false(second.has("koenig_der_ratten"), "Geschichten gibt es nur einmal")
	assert_eq(state.tale_count(), first.size(), "Zähler bleibt stabil")


func test_tales_survive_prestige_and_save() -> void:
	var state := GameState.new()
	state.bank_run_result(_victory_result())
	assert_true(state.tale_count() > 0)
	var count_before := state.tale_count()

	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.FRAGMENT_BASE_GOLD))
	state.prestige()
	assert_eq(state.tale_count(), count_before, "die Taverne vergisst nichts")

	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_true(restored.has_tale("koenig_der_ratten"))
	assert_eq(restored.tale_count(), count_before)


func test_run_counters_are_tracked() -> void:
	# Derselbe deterministische Run wie in test_exact_combat_math:
	# 8 Ticks, 5 Gegentreffer à 3, eine Gabelung, keine Fähigkeiten.
	var def := DungeonDef.from_dict({
		"id": "tiny", "display_name": "Tiny", "rooms": 2,
		"enemy_names": ["Gegner"], "boss_name": "Boss",
		"enemy_hp": 10.0, "enemy_atk": 3.0, "hp_growth": 1.0, "atk_growth": 1.0,
		"boss_hp_mult": 2.0, "boss_atk_mult": 1.0, "heal_per_room": 4.0,
		"gold_per_enemy": 5.0, "gold_growth": 1.0, "boss_gold": 20.0, "completion_bonus": 30.0,
	})
	var run := RunState.start(def, {"hp": BigNum.from_float(30.0), "atk": BigNum.from_float(5.0)})
	var guard := 0
	while run.status == RunState.Status.ACTIVE and guard < 1000:
		guard += 1
		if run.phase == RunState.Phase.CHOOSING:
			run.choose(RunState.RoomType.NORMAL)
			continue
		run.step()
	var result := run.result()
	assert_eq(int(result["ticks"]), 8)
	assert_almost(result["damage_taken"].to_float(), 15.0, 1e-6)
	assert_true(bool(result["took_damage"]))
	assert_eq(int(result["doors_seen"]), 1)
	assert_eq(int(result["elite_chosen"]), 0)
	assert_eq(int(result["strikes_used"]), 0)


func test_integration_one_shot_hero_earns_tales() -> void:
	# Ein One-Shot-Held räumt den Keller ohne Schaden und ohne
	# Fähigkeiten ab – das gibt gleich mehrere Geschichten.
	var keller := ContentDB.dungeon("ratten_keller")
	var run := RunState.start(keller, {
		"hp": BigNum.from_float(10000.0), "atk": BigNum.from_float(100000.0),
	})
	var guard := 0
	while run.status == RunState.Status.ACTIVE and guard < 1000:
		guard += 1
		if run.phase == RunState.Phase.CHOOSING:
			run.choose(RunState.RoomType.ELITE)
			continue
		run.step()
	var state := GameState.new()
	var new_tales := state.bank_run_result(run.result())
	assert_true(new_tales.has("koenig_der_ratten"), "Sieg im Keller")
	assert_true(new_tales.has("kein_kratzer"), "kein Schaden genommen")
	assert_true(new_tales.has("jede_tuer_die_goldene"), "nur Schatzkammern gewählt")
	assert_true(new_tales.has("schneller_als_das_geruecht"), "One-Shots sind schnell")
	assert_true(new_tales.has("haende_in_den_taschen"), "keine Fähigkeiten benutzt")


func test_integration_flee_and_defeat_tales() -> void:
	var keller := ContentDB.dungeon("ratten_keller")
	var fleeing := RunState.start(keller, GameState.new().hero_stats())
	fleeing.flee()
	var state := GameState.new()
	assert_true(state.bank_run_result(fleeing.result()).has("der_taktische_rueckzug"))

	var doomed := RunState.start(keller, {
		"hp": BigNum.from_float(1.0), "atk": BigNum.from_float(1.0),
	})
	var guard := 0
	while doomed.status == RunState.Status.ACTIVE and guard < 1000:
		guard += 1
		if doomed.phase == RunState.Phase.CHOOSING:
			doomed.choose(RunState.RoomType.NORMAL)
			continue
		doomed.step()
	assert_eq(doomed.status, RunState.Status.DEFEAT)
	assert_true(state.bank_run_result(doomed.result()).has("der_tag_an_dem_er_fast_starb"))
