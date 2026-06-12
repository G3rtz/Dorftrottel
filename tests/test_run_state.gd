extends "res://tests/test_base.gd"

## Kampf ist deterministisch – diese Tests rechnen Tick für Tick nach.


func _tiny_dungeon() -> DungeonDef:
	# 2 Räume + Boss, ohne Wachstum: leicht im Kopf nachrechenbar.
	return DungeonDef.from_dict({
		"id": "tiny",
		"display_name": "Tiny",
		"rooms": 2,
		"enemy_names": ["Gegner"],
		"boss_name": "Boss",
		"enemy_hp": 10.0,
		"enemy_atk": 3.0,
		"hp_growth": 1.0,
		"atk_growth": 1.0,
		"boss_hp_mult": 2.0,
		"boss_atk_mult": 1.0,
		"heal_per_room": 4.0,
		"gold_per_enemy": 5.0,
		"gold_growth": 1.0,
		"boss_gold": 20.0,
		"completion_bonus": 30.0,
	})


func _stats(hp: float, atk: float) -> Dictionary:
	return {"hp": BigNum.from_float(hp), "atk": BigNum.from_float(atk)}


## Spielt den Run zu Ende; an Gabelungen wird immer "Weitergehen"
## gewählt. Zählt nur echte Kampf-Ticks.
func _run_to_end(run: RunState) -> int:
	var ticks := 0
	var guard := 0
	while run.status == RunState.Status.ACTIVE and guard < 100000:
		guard += 1
		if run.phase == RunState.Phase.CHOOSING:
			run.choose(RunState.RoomType.NORMAL)
			continue
		run.step()
		ticks += 1
	assert_true(guard < 100000, "Kampf terminiert")
	return ticks


func test_one_shot_clear_takes_no_damage() -> void:
	# ATK >= Gegner-HP (auch Boss: 10 * 2 = 20): jeder Gegner stirbt am
	# ersten Schlag und schlägt nie zurück.
	var run := RunState.start(_tiny_dungeon(), _stats(50.0, 20.0))
	_run_to_end(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	assert_almost(run.hero_hp.to_float(), 50.0, 1e-6, "kein Schaden genommen")
	# Beute: 2 Räume à 5 + Boss 20 + Bonus 30 = 60.
	assert_almost(run.gold_earned.to_float(), 60.0, 1e-6)
	assert_eq(run.rooms_cleared, 2)


func test_exact_combat_math() -> void:
	# ATK 5 gegen HP 10: 2 Ticks pro Gegner, je 1 Gegentreffer à 3.
	# Raum 1: -3, dann +4 Heilung (Cap 30). Raum 2: -3, +4.
	# Boss (HP 20): 4 Ticks, 3 Gegentreffer à 3 = -9.
	var run := RunState.start(_tiny_dungeon(), _stats(30.0, 5.0))
	var ticks := _run_to_end(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	assert_eq(ticks, 2 + 2 + 4)
	assert_almost(run.hero_hp.to_float(), 30.0 - 3.0 + 3.0 - 3.0 + 3.0 - 9.0, 1e-6)


func test_heal_caps_at_max_hp() -> void:
	var def := _tiny_dungeon()
	def.heal_per_room = 9999.0
	var run := RunState.start(def, _stats(30.0, 5.0))
	_run_to_end(run)
	assert_true(run.hero_hp.cmp(run.hero_max_hp) <= 0, "Heilung übersteigt Maximum nie")


func test_defeat_keeps_loot_so_far() -> void:
	# Schwacher Held: schafft Raum 1 (HP 10 mit ATK 4 -> 3 Ticks, 2 Treffer
	# à 3 = -6, +4 Heilung), stirbt später am Boss oder davor – Beute bleibt.
	var run := RunState.start(_tiny_dungeon(), _stats(12.0, 4.0))
	_run_to_end(run)
	assert_eq(run.status, RunState.Status.DEFEAT)
	assert_almost(run.hero_hp.to_float(), 0.0, 1e-6, "HP klemmt bei 0")
	assert_true(run.gold_earned.to_float() >= 5.0, "Beute aus Raum 1 bleibt")
	assert_false(run.result()["victory"])


func test_instant_death_earns_nothing() -> void:
	var def := _tiny_dungeon()
	def.enemy_atk = 999.0
	var run := RunState.start(def, _stats(10.0, 1.0))
	_run_to_end(run)
	assert_eq(run.status, RunState.Status.DEFEAT)
	assert_true(run.gold_earned.is_zero())
	assert_eq(run.rooms_cleared, 0)


func test_flee_and_finished_runs_are_inert() -> void:
	var run := RunState.start(_tiny_dungeon(), _stats(30.0, 5.0))
	run.step()
	run.flee()
	assert_eq(run.status, RunState.Status.FLED)
	assert_true(run.step().is_empty(), "kein step() nach Ende")
	run.flee()
	assert_eq(run.status, RunState.Status.FLED, "flee() ist idempotent")


func test_events_are_emitted() -> void:
	var run := RunState.start(_tiny_dungeon(), _stats(50.0, 10.0))
	var first_tick := run.step()
	var types: Array = first_tick.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(types.has("hero_hit"))
	assert_true(types.has("enemy_defeated"))
	assert_true(types.has("doors_offered"), "nach dem Raum gabelt sich der Gang")
	assert_eq(run.phase, RunState.Phase.CHOOSING)
	assert_true(run.step().is_empty(), "während der Wahl ruht der Kampf")
	var choice_events := run.choose(RunState.RoomType.NORMAL)
	var choice_types: Array = choice_events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(choice_types.has("room_entered"))
	_run_to_end(run)


func test_elite_room() -> void:
	# Schatzkammer: Wächter ist stärker, zahlt aber doppelt.
	var run := RunState.start(_tiny_dungeon(), _stats(50.0, 20.0))
	run.step()  # Raum 1 fällt, Gabelung
	run.choose(RunState.RoomType.ELITE)
	assert_almost(run.enemy_max_hp.to_float(), 10.0 * Balance.ELITE_HP_MULT, 1e-6)
	assert_almost(run.enemy_atk.to_float(), 3.0 * Balance.ELITE_ATK_MULT, 1e-6)
	assert_true(run.enemy_name.begins_with("Schatzwächter"))
	_run_to_end(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	# Gold: Raum1 5 + Elite 5*2 + Boss 20 + Bonus 30 = 65.
	assert_almost(run.gold_earned.to_float(), 65.0, 1e-6)


func test_rest_room() -> void:
	# Rastplatz: große Heilung, aber der Raum bringt keine Beute.
	var run := RunState.start(_tiny_dungeon(), _stats(30.0, 5.0))
	_run_to_phase_choosing(run)
	var hp_before := run.hero_hp.to_float()
	var events := run.choose(RunState.RoomType.REST)
	var types: Array = events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(types.has("rested"))
	assert_true(run.hero_hp.to_float() >= hp_before, "Rast heilt")
	assert_eq(run.rooms_cleared, 2, "Rastplatz zählt als Raum")
	assert_true(types.has("room_entered"), "danach geht es direkt zum Boss")
	assert_true(run.is_boss_room())
	_run_to_end(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	# Gold: Raum1 5 + Rast 0 + Boss 20 + Bonus 30 = 55.
	assert_almost(run.gold_earned.to_float(), 55.0, 1e-6)


func _run_to_phase_choosing(run: RunState) -> void:
	var guard := 0
	while run.phase != RunState.Phase.CHOOSING and run.status == RunState.Status.ACTIVE and guard < 1000:
		run.step()
		guard += 1
	assert_true(guard < 1000, "Gabelung erreicht")


func test_strike_ability() -> void:
	var run := RunState.start(_tiny_dungeon(), _stats(30.0, 5.0))
	run.step()  # Gegner: 10 -> 5, Gegenschlag -3
	assert_true(run.can_strike())
	var events := run.use_strike()
	var types: Array = events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(types.has("strike"))
	assert_true(types.has("enemy_defeated"), "7.5 Extra-Schaden töten den 5-LP-Gegner")
	assert_almost(run.hero_hp.to_float(), 27.0, 1e-6, "Zuschlagen provoziert keinen Gegenschlag")
	assert_almost(run.gold_earned.to_float(), 5.0, 1e-6, "Beute wie bei normalem Kill")
	assert_eq(run.strike_cooldown, Balance.STRIKE_COOLDOWN_TICKS)
	assert_true(run.use_strike().is_empty(), "Cooldown/Gabelung blockiert")
	run.choose(RunState.RoomType.NORMAL)
	assert_false(run.can_strike(), "Cooldown läuft noch")
	for i in Balance.STRIKE_COOLDOWN_TICKS:
		run.step()
	assert_true(run.can_strike(), "Cooldown tickt im Kampf ab")
	_run_to_end(run)


func test_breather_ability() -> void:
	var def := _tiny_dungeon()
	def.enemy_hp = 100.0
	var run := RunState.start(def, _stats(30.0, 5.0))
	for i in 3:
		run.step()
	assert_almost(run.hero_hp.to_float(), 21.0, 1e-6)
	assert_true(run.can_breathe())
	var events := run.use_breather()
	assert_eq(str(events[0]["type"]), "breather")
	assert_almost(run.hero_hp.to_float(), 30.0, 1e-6, "+30% von 30 max, gedeckelt")
	assert_false(run.can_breathe(), "langer Cooldown")
	assert_true(run.use_breather().is_empty())


func test_drops_and_banking() -> void:
	var def := _tiny_dungeon()
	def.drops = [{"item_id": "test_zahn", "chance": 1.0}]
	def.boss_drops = [{"item_id": "test_krone", "chance": 1.0}]
	var run := RunState.start(def, _stats(50.0, 20.0))
	_run_to_end(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	assert_eq(int(run.items_found.get("test_zahn", 0)), 2, "jeder Raumgegner droppt bei Chance 1.0")
	assert_eq(int(run.items_found.get("test_krone", 0)), 1, "Boss würfelt gegen die Boss-Tabelle")
	assert_eq(int(run.result()["items"]["test_zahn"]), 2, "Beutel steht im Ergebnis")


func test_elite_drop_bonus_caps_at_certainty() -> void:
	# 0.4 Chance × 3 (Schatzkammer) = 1.2 -> gedeckelt auf sicher.
	var def := _tiny_dungeon()
	def.drops = [{"item_id": "test_zahn", "chance": 0.4}]
	var run := RunState.start(def, _stats(50.0, 20.0))
	run.step()
	run.choose(RunState.RoomType.ELITE)
	var before := int(run.items_found.get("test_zahn", 0))
	run.step()  # Elite fällt (20 ATK >= 16 LP)
	assert_eq(int(run.items_found.get("test_zahn", 0)), before + 1, "Schatzkammer-Drop ist sicher")
	_run_to_end(run)


func test_drops_are_seeded_and_reproducible() -> void:
	var def := _tiny_dungeon()
	def.drops = [{"item_id": "test_zahn", "chance": 0.5}]
	var first := RunState.start(def, _stats(50.0, 20.0), 1337)
	_run_to_end(first)
	var second := RunState.start(def, _stats(50.0, 20.0), 1337)
	_run_to_end(second)
	assert_eq(first.items_found, second.items_found, "gleicher Seed, gleiche Wege, gleiche Drops")
