extends "res://tests/test_base.gd"

## Validiert die echten Spieldaten – fängt kaputte Balance-Edits in CI ab.


func test_generators_load() -> void:
	var defs := ContentDB.generators()
	assert_true(defs.size() >= 1, "mindestens ein Generator definiert")
	for def in defs:
		assert_true(def.validate().is_empty(), "Generator '%s' ist gültig" % def.id)


func test_first_generator_is_immediately_available() -> void:
	var defs := ContentDB.generators()
	assert_true(defs.size() > 0)
	assert_eq(defs[0].unlock_at_lifetime, 0.0, "Der erste Generator darf nicht versteckt sein")


func test_progression_is_ascending() -> void:
	# Kosten und Freischaltschwellen müssen aufsteigen, sonst stimmt
	# die Progression nicht.
	var defs := ContentDB.generators()
	for i in range(1, defs.size()):
		assert_true(defs[i].base_cost > defs[i - 1].base_cost,
			"'%s' muss teurer sein als '%s'" % [defs[i].id, defs[i - 1].id])
		assert_true(defs[i].unlock_at_lifetime >= defs[i - 1].unlock_at_lifetime,
			"Freischaltreihenfolge von '%s'" % defs[i].id)


func test_lookup() -> void:
	var defs := ContentDB.generators()
	assert_eq(ContentDB.generator(defs[0].id).id, defs[0].id)
	assert_eq(ContentDB.generator("gibt_es_nicht"), null)


func test_dungeons_load() -> void:
	var defs := ContentDB.dungeons()
	assert_true(defs.size() >= 1, "mindestens ein Dungeon definiert")
	for def in defs:
		assert_true(def.validate().is_empty(), "Dungeon '%s' ist gültig" % def.id)
	assert_eq(defs[0].unlocked_by, "", "der erste Dungeon ist sofort verfügbar")
	assert_eq(ContentDB.dungeon("gibt_es_nicht"), null)


func test_perma_upgrades_load() -> void:
	var defs := ContentDB.perma_upgrades()
	assert_true(defs.size() >= 1, "mindestens ein Perma-Upgrade definiert")
	for def in defs:
		assert_true(def.validate().is_empty(), "Perma-Upgrade '%s' ist gültig" % def.id)
	assert_true(ContentDB.perma_upgrade(defs[0].id) != null)
	assert_eq(ContentDB.perma_upgrade("gibt_es_nicht"), null)


func test_saga_lines_load() -> void:
	assert_false(ContentDB.saga_line(0).is_empty(), "erste Nacherzählung hat einen Text")
	assert_false(ContentDB.saga_line(9999).is_empty(), "jenseits der Liste trägt die letzte Zeile")
	assert_eq(ContentDB.saga_line(9999), ContentDB.saga_line(99999), "Eskalation klemmt am Ende fest")


## Balance-Wächter: Diese Tests simulieren echte Runs mit den echten
## Daten. Wer data/dungeons.json oder die Heldenwerte kaputt-balanced,
## bricht hier die CI – nicht erst das Spielgefühl.


func _simulate(def: DungeonDef, hp_level: int, atk_level: int) -> bool:
	var state := GameState.new()
	state.hero_hp_level = hp_level
	state.hero_atk_level = atk_level
	var run := RunState.start(def, state.hero_stats())
	var guard := 100000
	while run.status == RunState.Status.ACTIVE and guard > 0:
		run.step()
		guard -= 1
	assert_true(guard > 0, "Run in '%s' terminiert" % def.id)
	return run.status == RunState.Status.VICTORY


func test_first_dungeon_is_beatable_untrained() -> void:
	var first := ContentDB.dungeons()[0]
	assert_true(_simulate(first, 0, 0),
		"'%s' muss mit Basiswerten schaffbar sein – sonst ist der Einstieg tot" % first.id)


func test_second_dungeon_needs_training_but_not_too_much() -> void:
	if ContentDB.dungeons().size() < 2:
		return
	var second := ContentDB.dungeons()[1]
	assert_false(_simulate(second, 0, 0),
		"'%s' darf ohne Training nicht fallen, sonst ist die Progression trivial" % second.id)
	var beatable_at := -1
	for level in range(5, 81, 5):
		if _simulate(second, level, level):
			beatable_at = level
			break
	assert_true(beatable_at > 0,
		"'%s' muss mit <= 80 Trainingsstufen schaffbar sein" % second.id)
