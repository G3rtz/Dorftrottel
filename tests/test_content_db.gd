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


func test_items_load() -> void:
	var defs := ContentDB.items()
	assert_true(defs.size() >= 1, "mindestens ein Item definiert")
	for def in defs:
		assert_true(def.validate().is_empty(), "Item '%s' ist gültig" % def.id)
	assert_true(ContentDB.item(defs[0].id) != null)
	assert_eq(ContentDB.item("gibt_es_nicht"), null)


func test_dungeon_drop_tables_are_wired() -> void:
	# Jeder Dungeon braucht Drops, jeder Drop ein existierendes Item,
	# und jeder Boss soll auch ein Liedfragment in der Tabelle haben –
	# der GDD-Grund, Dungeons wieder zu betreten.
	for dungeon_def in ContentDB.dungeons():
		assert_false(dungeon_def.drops.is_empty(), "'%s' braucht eine Drop-Tabelle" % dungeon_def.id)
		assert_false(dungeon_def.boss_drops.is_empty(), "'%s' braucht Boss-Drops" % dungeon_def.id)
		var has_fragment := false
		for table: Array in [dungeon_def.drops, dungeon_def.boss_drops]:
			for entry: Dictionary in table:
				var item_def := ContentDB.item(str(entry.get("item_id", "")))
				assert_true(item_def != null,
					"'%s' droppt unbekanntes Item '%s'" % [dungeon_def.id, entry.get("item_id")])
				if item_def != null and item_def.is_song_fragment():
					has_fragment = true
		assert_true(has_fragment, "'%s' sollte irgendwo ein Liedfragment droppen" % dungeon_def.id)


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
		guard -= 1
		if run.phase == RunState.Phase.CHOOSING:
			run.choose(RunState.RoomType.NORMAL)
			continue
		run.step()
	assert_true(guard > 0, "Run in '%s' terminiert" % def.id)
	return run.status == RunState.Status.VICTORY


func test_first_dungeon_is_beatable_untrained() -> void:
	var first := ContentDB.dungeons()[0]
	assert_true(_simulate(first, 0, 0),
		"'%s' muss mit Basiswerten schaffbar sein – sonst ist der Einstieg tot" % first.id)


## Sucht die kleinste Trainingsstufe (HP=ATK), mit der der Dungeon
## fällt; -1 wenn er bis zum Limit nicht fällt.
func _minimum_training_level(def: DungeonDef, limit: int) -> int:
	for level in range(5, limit + 1, 5):
		if _simulate(def, level, level):
			return level
	return -1


func test_dungeon_chain_difficulty_is_staged() -> void:
	# Jeder spätere Dungeon braucht Progression (kein Trivial-Durchmarsch),
	# bleibt aber mit vertretbarem Training erreichbar. Die Schwellen
	# pro Kettenglied sind die Balance-Leitplanken.
	var dungeons := ContentDB.dungeons()
	var training_limits := {"finsterwald": 30, "eis_hoehle": 80}
	for i in range(1, dungeons.size()):
		var def := dungeons[i]
		assert_false(_simulate(def, 0, 0),
			"'%s' darf ohne Training nicht fallen, sonst ist die Progression trivial" % def.id)
		assert_true(training_limits.has(def.id),
			"'%s' braucht eine Balance-Leitplanke in diesem Test" % def.id)
		var limit := int(training_limits.get(def.id, 80))
		var needed := _minimum_training_level(def, limit)
		assert_true(needed > 0,
			"'%s' muss mit <= %d Trainingsstufen schaffbar sein" % [def.id, limit])
	# Die Kette muss steiler werden: Wald vor Eis.
	if dungeons.size() >= 3:
		var wald_needed := _minimum_training_level(ContentDB.dungeon("finsterwald"), 80)
		var eis_needed := _minimum_training_level(ContentDB.dungeon("eis_hoehle"), 80)
		assert_true(wald_needed < eis_needed,
			"Finsterwald (%d) muss vor der Eishöhle (%d) fallen" % [wald_needed, eis_needed])
