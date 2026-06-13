extends "res://tests/test_base.gd"

## Klassen = Versionen der Sage. Freischaltung aus Tavernenerzählungen
## abgeleitet, Wirkung über hero_stats() und Start-Segen.


func test_def_validate() -> void:
	var ok := ClassDef.from_dict({
		"id": "k", "display_name": "K", "flavor": "f", "hp_mult": 1.0, "atk_mult": 1.0,
	})
	assert_true(ok.validate().is_empty())
	var no_flavor := ClassDef.from_dict({"id": "k", "display_name": "K", "hp_mult": 1.0, "atk_mult": 1.0})
	assert_false(no_flavor.validate().is_empty(), "ohne Sage keine Klasse")
	var bad := ClassDef.from_dict({"id": "k", "display_name": "K", "flavor": "f", "hp_mult": 0.0})
	assert_false(bad.validate().is_empty(), "hp_mult muss > 0")


func test_starter_and_unlock_logic() -> void:
	var starter := ClassDef.from_dict({"id": "k", "display_name": "K", "flavor": "f"})
	assert_true(starter.is_starter())
	assert_true(starter.is_unlocked_by({}), "Starter immer offen")

	var gated := ClassDef.from_dict({
		"id": "m", "display_name": "M", "flavor": "f", "unlock_tales": ["kein_kratzer"],
	})
	assert_false(gated.is_starter())
	assert_false(gated.is_unlocked_by({}))
	assert_true(gated.is_unlocked_by({"kein_kratzer": true}))

	var counted := ClassDef.from_dict({
		"id": "c", "display_name": "C", "flavor": "f", "unlock_tale_count": 2,
	})
	assert_false(counted.is_unlocked_by({"a": true}))
	assert_true(counted.is_unlocked_by({"a": true, "b": true}))


func test_classes_load_and_are_wired() -> void:
	var defs := ContentDB.classes()
	assert_true(defs.size() >= 2, "Krieger + mindestens eine Freischaltung")
	var has_starter := false
	for def in defs:
		assert_true(def.validate().is_empty(), "Klasse '%s' ist gültig" % def.id)
		if def.is_starter():
			has_starter = true
		for tale_id: String in def.unlock_tales:
			assert_true(ContentDB.tale(tale_id) != null,
				"Klasse '%s' verweist auf existierende Erzählung '%s'" % [def.id, tale_id])
		for boon_id: String in def.start_boons:
			assert_true(ContentDB.boon(boon_id) != null,
				"Klasse '%s' Start-Segen '%s' existiert" % [def.id, boon_id])
	assert_true(has_starter, "es braucht eine Starter-Klasse")
	assert_eq(ContentDB.class_def("gibt_es_nicht"), null)


func test_default_class_is_baseline() -> void:
	# Frischer Zustand: aktive Klasse fällt auf den Starter zurück und
	# verändert die Basiswerte nicht (sonst bräche die ganze Balance).
	var state := GameState.new()
	assert_true(state.active_class_def() != null)
	assert_true(state.active_class_def().is_starter())
	assert_almost(state.hero_stats()["hp"].to_float(), Balance.HERO_BASE_HP, 1e-6)
	assert_almost(state.hero_stats()["atk"].to_float(), Balance.HERO_BASE_ATK, 1e-6)


func test_class_multipliers_apply() -> void:
	var state := GameState.new()
	var base_hp: float = state.hero_stats()["hp"].to_float()
	var base_atk: float = state.hero_stats()["atk"].to_float()
	# Magier direkt setzen (Freischaltung umgehen wir hier bewusst).
	state.active_class = "magier"
	var mag := ContentDB.class_def("magier")
	assert_almost(state.hero_stats()["hp"].to_float(), base_hp * mag.hp_mult, 1e-6)
	assert_almost(state.hero_stats()["atk"].to_float(), base_atk * mag.atk_mult, 1e-6)


func test_unlock_derived_from_tales() -> void:
	var state := GameState.new()
	var mag := ContentDB.class_def("magier")
	assert_false(state.is_class_unlocked(mag), "anfangs gesperrt")
	assert_false(state.set_active_class("magier"), "gesperrt = nicht wählbar")

	state.tales_earned["kein_kratzer"] = true
	assert_true(state.is_class_unlocked(mag), "die richtige Erzählung schaltet frei")
	assert_true(state.unlocked_class_ids().has("magier"))
	assert_true(state.set_active_class("magier"))
	assert_eq(state.active_class, "magier")


func test_unlock_survives_prestige() -> void:
	# Erzählungen (und damit Klassen) sind perma.
	var state := GameState.new()
	state.tales_earned["kein_kratzer"] = true
	state.set_active_class("magier")
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.FRAGMENT_BASE_GOLD))
	state.prestige()
	assert_true(state.is_class_unlocked(ContentDB.class_def("magier")), "Klasse bleibt im Hirn")
	assert_eq(state.active_class, "magier", "die gewählte Sage bleibt gewählt")


func test_start_boons_applied_at_run_start() -> void:
	# Ein Run mit den Start-Segen des Magiers bringt diese sofort mit.
	var def := ContentDB.dungeon("ratten_keller")
	var stats := {"hp": BigNum.from_float(100.0), "atk": BigNum.from_float(10.0)}
	var run := RunState.start(def, stats, 0, ContentDB.boons(), ["schwungvoll"])
	assert_eq(run.boon_stacks("schwungvoll"), 1, "Start-Segen ist von Beginn an aktiv")


func test_serialization_roundtrip() -> void:
	var state := GameState.new()
	state.tales_earned["kein_kratzer"] = true
	state.set_active_class("magier")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(restored.active_class, "magier")
	assert_true(restored.is_class_unlocked(ContentDB.class_def("magier")))
