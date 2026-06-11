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


func _run_to_end(run: RunState) -> int:
	var ticks := 0
	while run.status == RunState.Status.ACTIVE and ticks < 100000:
		run.step()
		ticks += 1
	assert_true(ticks < 100000, "Kampf terminiert")
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
	assert_true(types.has("room_entered"))
	_run_to_end(run)
