extends "res://tests/test_base.gd"

## Rundenbasierter, manueller Kampf. Die Absichten der Gegner sind
## seeded RNG – wo exakte Mathematik geprüft wird, erzwingen die Tests
## die Absicht vor jeder Aktion.


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


## Startet einen Run OHNE Segen – hält die Kampfmathematik exakt.
## Segen haben ihre eigene Test-Suite (test_boons.gd).
func _start(def: DungeonDef, stats: Dictionary, rng_seed: int = 0) -> RunState:
	return RunState.start(def, stats, rng_seed, [])


## Angriff, bis der Gegner vom normalen Schlag stirbt – Absicht wird
## vor jedem Zug auf NORMAL gezwungen (deterministische Mathematik).
func _attack_normal(run: RunState) -> void:
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)


func _run_to_end_normal(run: RunState) -> int:
	var actions := 0
	var guard := 0
	while run.status == RunState.Status.ACTIVE and guard < 100000:
		guard += 1
		if run.phase == RunState.Phase.CHOOSING:
			run.choose(RunState.RoomType.NORMAL)
			continue
		_attack_normal(run)
		actions += 1
	assert_true(guard < 100000, "Kampf terminiert")
	return actions


func test_one_shot_clear_takes_no_damage() -> void:
	# ATK >= Gegner-HP (auch Boss: 10 * 2 = 20): jeder Gegner stirbt am
	# ersten Schlag und kommt nie zum Zug.
	var run := _start(_tiny_dungeon(), _stats(50.0, 20.0))
	var turns := _run_to_end_normal(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	assert_eq(turns, 3, "ein Zug pro Gegner")
	assert_almost(run.hero_hp.to_float(), 50.0, 1e-6, "kein Schaden genommen")
	assert_almost(run.gold_earned.to_float(), 60.0, 1e-6)
	assert_eq(run.rooms_cleared, 2)


func test_exact_combat_math() -> void:
	# ATK 5 gegen HP 10: 2 Züge pro Gegner, je 1 Gegentreffer à 3.
	# Raum 1: -3, dann +4 Heilung (Cap 30). Raum 2: -3, +4.
	# Boss (HP 20): 4 Züge, 3 Gegentreffer à 3 = -9.
	var run := _start(_tiny_dungeon(), _stats(30.0, 5.0))
	var turns := _run_to_end_normal(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	assert_eq(turns, 2 + 2 + 4)
	assert_almost(run.hero_hp.to_float(), 30.0 - 3.0 + 3.0 - 3.0 + 3.0 - 9.0, 1e-6)
	assert_almost(run.result()["damage_taken"].to_float(), 15.0, 1e-6)


func test_heavy_intent_and_block() -> void:
	var run := _start(_tiny_dungeon(), _stats(30.0, 5.0))
	# Schwerer Schlag angekündigt: Blocken lässt nur 30% durch.
	run.enemy_intent = RunState.Intent.HEAVY
	var enemy_hp_before := run.enemy_hp.to_float()
	var events := run.take_action(RunState.Action.BLOCK)
	var types: Array = events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(types.has("block"))
	assert_almost(run.enemy_hp.to_float(), enemy_hp_before, 1e-6, "Blocken macht keinen Schaden")
	assert_almost(run.hero_hp.to_float(), 30.0 - 3.0 * 2.0 * 0.3, 1e-6, "6 Schaden, 70% geblockt")
	assert_eq(run.blocks_used, 1)

	# Ungeblockt trifft der schwere Schlag voll.
	run.enemy_intent = RunState.Intent.HEAVY
	run.take_action(RunState.Action.ATTACK)
	assert_almost(run.hero_hp.to_float(), 28.2 - 6.0, 1e-6, "voller schwerer Treffer")


func test_lethal_hit_prevents_retaliation() -> void:
	# Gegner auf 5 LP bringen, schwerer Schlag steht an – aber der
	# Todesstoß verhindert ihn.
	var run := _start(_tiny_dungeon(), _stats(30.0, 5.0))
	_attack_normal(run)  # Gegner: 10 -> 5, Gegentreffer -3
	run.enemy_intent = RunState.Intent.HEAVY
	run.take_action(RunState.Action.ATTACK)  # tötet: kein Gegenschlag
	assert_almost(run.hero_hp.to_float(), 27.0, 1e-6)
	assert_eq(run.phase, RunState.Phase.CHOOSING)


func test_strike_cooldown_in_turns() -> void:
	var def := _tiny_dungeon()
	def.enemy_hp = 1000.0
	var run := _start(def, _stats(100.0, 5.0))
	run.enemy_intent = RunState.Intent.NORMAL
	var events := run.take_action(RunState.Action.STRIKE)
	var types: Array = events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(types.has("strike"))
	assert_almost(run.enemy_hp.to_float(), 1000.0 - 10.0, 1e-6, "x2 Schaden")
	assert_eq(run.strikes_used, 1)
	assert_false(run.can_act(RunState.Action.STRIKE), "Cooldown läuft")
	for i in 3:
		assert_false(run.can_act(RunState.Action.STRIKE), "noch %d Züge Cooldown" % (3 - i))
		_attack_normal(run)
	assert_true(run.can_act(RunState.Action.STRIKE), "nach 3 Zügen wieder bereit")


func test_breather_heals_but_exposes() -> void:
	var def := _tiny_dungeon()
	def.enemy_hp = 1000.0
	var run := _start(def, _stats(100.0, 5.0))
	for i in 3:
		_attack_normal(run)
	assert_almost(run.hero_hp.to_float(), 91.0, 1e-6)
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.BREATHER)
	# +30 geheilt (Cap 100), dann freier Gegentreffer -3.
	assert_almost(run.hero_hp.to_float(), 97.0, 1e-6)
	assert_eq(run.breathers_used, 1)
	assert_false(run.can_act(RunState.Action.BREATHER), "langer Cooldown")


func test_rest_room() -> void:
	var run := _start(_tiny_dungeon(), _stats(30.0, 5.0))
	_attack_normal(run)
	_attack_normal(run)
	assert_eq(run.phase, RunState.Phase.CHOOSING)
	var hp_before := run.hero_hp.to_float()
	var events := run.choose(RunState.RoomType.REST)
	var types: Array = events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(types.has("rested"))
	assert_true(run.hero_hp.to_float() >= hp_before, "Rast heilt")
	assert_eq(run.rooms_cleared, 2, "Rastplatz zählt als Raum")
	assert_true(types.has("room_entered"), "danach geht es direkt zum Boss")
	assert_true(run.is_boss_room())
	_run_to_end_normal(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	# Gold: Raum1 5 + Rast 0 + Boss 20 + Bonus 30 = 55.
	assert_almost(run.gold_earned.to_float(), 55.0, 1e-6)


func test_elite_room() -> void:
	var run := _start(_tiny_dungeon(), _stats(50.0, 20.0))
	_attack_normal(run)  # Raum 1 fällt, Gabelung
	run.choose(RunState.RoomType.ELITE)
	assert_almost(run.enemy_max_hp.to_float(), 10.0 * Balance.ELITE_HP_MULT, 1e-6)
	assert_almost(run.enemy_atk.to_float(), 3.0 * Balance.ELITE_ATK_MULT, 1e-6)
	assert_true(run.enemy_name.begins_with("Schatzwächter"))
	_run_to_end_normal(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	# Gold: Raum1 5 + Elite 5*2 + Boss 20 + Bonus 30 = 65.
	assert_almost(run.gold_earned.to_float(), 65.0, 1e-6)
	assert_eq(run.elite_chosen, 1)


func test_defeat_keeps_loot_and_clamps_hp() -> void:
	var def := _tiny_dungeon()
	def.enemy_atk = 999.0
	var run := _start(def, _stats(10.0, 5.0))
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	assert_eq(run.status, RunState.Status.DEFEAT)
	assert_almost(run.hero_hp.to_float(), 0.0, 1e-6, "LP klemmt bei 0")
	assert_false(run.result()["victory"])


func test_flee_and_finished_runs_are_inert() -> void:
	var run := _start(_tiny_dungeon(), _stats(30.0, 5.0))
	_attack_normal(run)
	run.flee()
	assert_eq(run.status, RunState.Status.FLED)
	assert_true(run.take_action(RunState.Action.ATTACK).is_empty(), "keine Züge nach Ende")
	assert_false(run.can_act(RunState.Action.ATTACK))
	run.flee()
	assert_eq(run.status, RunState.Status.FLED, "flee() ist idempotent")


func test_actions_blocked_during_choice() -> void:
	var run := _start(_tiny_dungeon(), _stats(50.0, 20.0))
	_attack_normal(run)
	assert_eq(run.phase, RunState.Phase.CHOOSING)
	assert_true(run.take_action(RunState.Action.ATTACK).is_empty(), "an der Gabelung wird nicht gekämpft")


func test_drops_and_banking() -> void:
	var def := _tiny_dungeon()
	def.drops = [{"item_id": "test_zahn", "chance": 1.0}]
	def.boss_drops = [{"item_id": "test_krone", "chance": 1.0}]
	var run := _start(def, _stats(50.0, 20.0))
	_run_to_end_normal(run)
	assert_eq(run.status, RunState.Status.VICTORY)
	assert_eq(int(run.items_found.get("test_zahn", 0)), 2, "jeder Raumgegner droppt bei Chance 1.0")
	assert_eq(int(run.items_found.get("test_krone", 0)), 1, "Boss würfelt gegen die Boss-Tabelle")
	assert_eq(int(run.result()["items"]["test_zahn"]), 2, "Beutel steht im Ergebnis")


func test_elite_drop_bonus_caps_at_certainty() -> void:
	# 0.4 Chance × 3 (Schatzkammer) = 1.2 -> gedeckelt auf sicher.
	var def := _tiny_dungeon()
	def.drops = [{"item_id": "test_zahn", "chance": 0.4}]
	var run := _start(def, _stats(50.0, 20.0))
	_attack_normal(run)
	run.choose(RunState.RoomType.ELITE)
	var before := int(run.items_found.get("test_zahn", 0))
	_attack_normal(run)  # Elite fällt (20 ATK >= 16 LP)
	assert_eq(int(run.items_found.get("test_zahn", 0)), before + 1, "Schatzkammer-Drop ist sicher")
	_run_to_end_normal(run)


func test_runs_are_seeded_and_reproducible() -> void:
	var def := _tiny_dungeon()
	def.drops = [{"item_id": "test_zahn", "chance": 0.5}]
	var first := _start(def, _stats(50.0, 20.0), 1337)
	_run_to_end_normal(first)
	var second := _start(def, _stats(50.0, 20.0), 1337)
	_run_to_end_normal(second)
	assert_eq(first.items_found, second.items_found, "gleicher Seed, gleiche Züge, gleiche Drops")
	assert_almost(first.hero_hp.to_float(), second.hero_hp.to_float(), 1e-9)
