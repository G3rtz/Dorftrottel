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


const GUARD_SEEDS: Array[int] = [11, 22, 33]


## Simuliert einen Run mit einem Bot, der minimale Spielintelligenz
## modelliert: angekündigte schwere Schläge werden geblockt, wenn die
## LP unter der Hälfte liegen – sonst stur angreifen. "Schaffbar"
## heißt im manuellen Kampf: schaffbar für jemanden, der hinschaut.
func _simulate(def: DungeonDef, hp_level: int, atk_level: int, rng_seed: int) -> bool:
	var state := GameState.new()
	state.hero_hp_level = hp_level
	state.hero_atk_level = atk_level
	var run := RunState.start(def, state.hero_stats(), rng_seed)
	var half_hp := run.hero_max_hp.mul(BigNum.from_float(0.5))
	var guard := 100000
	while run.status == RunState.Status.ACTIVE and guard > 0:
		guard -= 1
		if run.phase == RunState.Phase.CHOOSING:
			run.choose(RunState.RoomType.NORMAL)
			continue
		if run.enemy_intent == RunState.Intent.HEAVY and run.hero_hp.lt(half_hp):
			run.take_action(RunState.Action.BLOCK)
		else:
			run.take_action(RunState.Action.ATTACK)
	assert_true(guard > 0, "Run in '%s' terminiert" % def.id)
	return run.status == RunState.Status.VICTORY


## Schaffbar = der Bot gewinnt auf ALLEN Prüf-Seeds – robust gegen
## Absichts-Glück und -Pech.
func _beatable(def: DungeonDef, level: int) -> bool:
	for rng_seed in GUARD_SEEDS:
		if not _simulate(def, level, level, rng_seed):
			return false
	return true


func test_first_dungeon_is_beatable_untrained() -> void:
	var first := ContentDB.dungeons()[0]
	assert_true(_beatable(first, 0),
		"'%s' muss mit Basiswerten schaffbar sein – sonst ist der Einstieg tot" % first.id)


## Sucht die kleinste Trainingsstufe (HP=ATK), mit der der Dungeon
## fällt; -1 wenn er bis zum Limit nicht fällt.
func _minimum_training_level(def: DungeonDef, limit: int) -> int:
	for level in range(5, limit + 1, 5):
		if _beatable(def, level):
			return level
	return -1


func test_dungeon_chain_difficulty_is_staged() -> void:
	# Jeder spätere Dungeon braucht Progression (kein Trivial-Durchmarsch),
	# bleibt aber mit vertretbarem Training erreichbar. Die Schwellen
	# pro Kettenglied sind die Balance-Leitplanken.
	var dungeons := ContentDB.dungeons()
	var training_limits := {"finsterwald": 35, "vergessene_aecker": 60, "eis_hoehle": 100}
	var minima := {}
	for i in range(1, dungeons.size()):
		var def := dungeons[i]
		for rng_seed in GUARD_SEEDS:
			assert_false(_simulate(def, 0, 0, rng_seed),
				"'%s' darf ohne Training nicht fallen, sonst ist die Progression trivial" % def.id)
		assert_true(training_limits.has(def.id),
			"'%s' braucht eine Balance-Leitplanke in diesem Test" % def.id)
		var limit := int(training_limits.get(def.id, 100))
		var needed := _minimum_training_level(def, limit)
		print("Balance: '%s' fällt ab Trainingsstufe %d (Limit %d)" % [def.id, needed, limit])
		assert_true(needed > 0,
			"'%s' muss mit <= %d Trainingsstufen schaffbar sein" % [def.id, limit])
		minima[def.id] = needed
	# Die Kette muss monoton steiler werden.
	if minima.has("finsterwald") and minima.has("vergessene_aecker") and minima.has("eis_hoehle"):
		assert_true(int(minima["finsterwald"]) < int(minima["vergessene_aecker"]),
			"Wald (%s) muss vor den Äckern (%s) fallen" % [minima["finsterwald"], minima["vergessene_aecker"]])
		assert_true(int(minima["vergessene_aecker"]) < int(minima["eis_hoehle"]),
			"Äcker (%s) müssen vor dem Eis (%s) fallen" % [minima["vergessene_aecker"], minima["eis_hoehle"]])
