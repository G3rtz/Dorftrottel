extends "res://tests/test_base.gd"

## In-Run-Segen (Boons): der Build-Layer des Roguelite-Teils. Tests
## injizieren kontrollierte Pools, damit die Effekt-Mathematik exakt
## prüfbar bleibt.


func _dungeon(enemy_hp: float, enemy_atk: float, rooms := 3) -> DungeonDef:
	return DungeonDef.from_dict({
		"id": "boontest", "display_name": "Boontest", "rooms": rooms,
		"enemy_names": ["Gegner"], "boss_name": "Boss",
		"enemy_hp": enemy_hp, "enemy_atk": enemy_atk, "hp_growth": 1.0, "atk_growth": 1.0,
		"boss_hp_mult": 1.0, "boss_atk_mult": 1.0, "heal_per_room": 0.0,
		"gold_per_enemy": 10.0, "gold_growth": 1.0, "boss_gold": 50.0, "completion_bonus": 0.0,
	})


func _boon(id: String, effect: String, amount: float, max_stacks := 0) -> BoonDef:
	return BoonDef.from_dict({
		"id": id, "display_name": id, "flavor": "x",
		"effect": effect, "amount": amount, "max_stacks": max_stacks,
	})


func _stats(hp: float, atk: float) -> Dictionary:
	return {"hp": BigNum.from_float(hp), "atk": BigNum.from_float(atk)}


# --- Definition & Daten ---

func test_def_validate() -> void:
	assert_true(_boon("a", "atk_mult", 0.25).validate().is_empty())
	var bad_effect := _boon("a", "fliegen", 0.25)
	assert_false(bad_effect.validate().is_empty(), "unbekannter Effekt")
	var no_amount := _boon("a", "atk_mult", 0.0)
	assert_false(no_amount.validate().is_empty(), "amount muss > 0")


func test_boons_json_loads_and_is_valid() -> void:
	var defs := ContentDB.boons()
	assert_true(defs.size() >= 3, "ein Pool von mindestens 3 Segen")
	for def in defs:
		assert_true(def.validate().is_empty(), "Segen '%s' ist gültig" % def.id)
		assert_false(def.description().is_empty(), "Segen '%s' beschreibt sich" % def.id)
	assert_eq(ContentDB.boon("gibt_es_nicht"), null)


# --- Effekte (exakte Mathematik) ---

func test_atk_mult() -> void:
	var run := RunState.start(_dungeon(1000.0, 2.0), _stats(100.0, 10.0), 0, [_boon("rage", "atk_mult", 0.5)])
	run.boons_owned["rage"] = 1
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	assert_almost(run.enemy_hp.to_float(), 1000.0 - 15.0, 1e-6, "10 Angriff x1.5")


func test_block_bonus_and_cap() -> void:
	var run := RunState.start(_dungeon(1000.0, 10.0), _stats(100.0, 10.0), 0, [_boon("wall", "block_bonus", 0.1)])
	run.boons_owned["wall"] = 1
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.BLOCK)
	# Reduktion 0.7 + 0.1 = 0.8 -> 10 * 0.2 = 2 Schaden.
	assert_almost(run.hero_hp.to_float(), 98.0, 1e-6)

	var capped := RunState.start(_dungeon(1000.0, 10.0), _stats(100.0, 10.0), 0, [_boon("wall", "block_bonus", 0.5)])
	capped.boons_owned["wall"] = 1
	capped.enemy_intent = RunState.Intent.NORMAL
	capped.take_action(RunState.Action.BLOCK)
	# 0.7 + 0.5 = 1.2, gedeckelt auf 0.95 -> 10 * 0.05 = 0.5 Schaden.
	assert_almost(capped.hero_hp.to_float(), 99.5, 1e-6, "Block-Reduktion deckelt bei 95%")


func test_lifesteal() -> void:
	var run := RunState.start(_dungeon(1000.0, 2.0), _stats(100.0, 10.0), 0, [_boon("vamp", "lifesteal", 0.5)])
	run.boons_owned["vamp"] = 1
	run.hero_hp = BigNum.from_float(50.0)
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	# +5 Lebensraub (50% von 10), dann -2 Gegentreffer = 53.
	assert_almost(run.hero_hp.to_float(), 53.0, 1e-6)


func test_heal_on_kill() -> void:
	var run := RunState.start(_dungeon(5.0, 10.0), _stats(100.0, 10.0), 0, [_boon("feast", "heal_on_kill", 0.5)])
	run.boons_owned["feast"] = 1
	run.hero_hp = BigNum.from_float(40.0)
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)  # 10 >= 5: Kill ohne Gegenschlag
	assert_almost(run.hero_hp.to_float(), 90.0, 1e-6, "+50% Max-LP bei Kill")


func test_max_hp_mult_heals_the_gain() -> void:
	var run := RunState.start(_dungeon(1000.0, 2.0), _stats(100.0, 10.0), 0, [_boon("tough", "max_hp_mult", 0.3)])
	run.hero_hp = BigNum.from_float(50.0)
	run.phase = RunState.Phase.CHOOSING_BOON
	run.boon_offers = ["tough"]
	run.choose_boon("tough")
	assert_almost(run.hero_max_hp.to_float(), 130.0, 1e-6, "+30% Max-LP")
	assert_almost(run.hero_hp.to_float(), 80.0, 1e-6, "Zugewinn (+30) sofort geheilt")


func test_strike_cd_reduction_with_floor() -> void:
	var run := RunState.start(_dungeon(1000.0, 2.0), _stats(100.0, 10.0), 0, [_boon("swift", "strike_cd", 1.0)])
	run.boons_owned["swift"] = 1
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.STRIKE)
	assert_eq(run.strike_cooldown, Balance.STRIKE_COOLDOWN_TURNS - 1, "Cooldown -1 Zug")

	var floored := RunState.start(_dungeon(1000.0, 2.0), _stats(100.0, 10.0), 0, [_boon("swift", "strike_cd", 9.0)])
	floored.boons_owned["swift"] = 1
	floored.enemy_intent = RunState.Intent.NORMAL
	floored.take_action(RunState.Action.STRIKE)
	assert_eq(floored.strike_cooldown, 1, "Cooldown nie unter 1")


func test_gold_mult() -> void:
	var run := RunState.start(_dungeon(5.0, 2.0), _stats(100.0, 10.0), 0, [_boon("greed", "gold_mult", 0.5)])
	run.boons_owned["greed"] = 1
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)  # Raum 1 Kill: 10 Gold x1.5
	assert_almost(run.gold_earned.to_float(), 15.0, 1e-6)


func test_drop_mult_can_guarantee() -> void:
	var def := _dungeon(5.0, 2.0)
	def.drops = [{"item_id": "x", "chance": 0.7}]
	var run := RunState.start(def, _stats(100.0, 10.0), 0, [_boon("loot", "drop_mult", 0.5)])
	run.boons_owned["loot"] = 1
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	# 0.7 * (1 + 0.5) = 1.05 -> gedeckelt sicher.
	assert_eq(int(run.items_found.get("x", 0)), 1, "Drop-Segen über 100% ist garantiert")


func test_thorns_damages_and_can_kill() -> void:
	var run := RunState.start(_dungeon(1000.0, 2.0), _stats(100.0, 10.0), 0, [_boon("spikes", "thorns", 0.5)])
	run.boons_owned["spikes"] = 1
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)  # 1000 -10 Angriff, -5 Dornen
	assert_almost(run.enemy_hp.to_float(), 985.0, 1e-6, "Angreifer nimmt 50% des Angriffs")

	# Dornen können den letzten Treffer setzen.
	var lethal := RunState.start(_dungeon(4.0, 2.0), _stats(100.0, 10.0), 0, [_boon("spikes", "thorns", 0.5)])
	lethal.boons_owned["spikes"] = 1
	lethal.enemy_intent = RunState.Intent.NORMAL
	lethal.take_action(RunState.Action.BLOCK)  # kein eigener Schaden; Dornen 5 > 4 LP
	assert_eq(lethal.rooms_cleared, 1, "Dornen erledigen den Gegner")


# --- Auswahl-Mechanik ---

func test_offer_after_kill_respects_count_and_pool() -> void:
	var pool: Array[BoonDef] = [
		_boon("a", "atk_mult", 0.1), _boon("b", "atk_mult", 0.1),
		_boon("c", "atk_mult", 0.1), _boon("d", "atk_mult", 0.1), _boon("e", "atk_mult", 0.1),
	]
	var run := RunState.start(_dungeon(5.0, 2.0), _stats(100.0, 10.0), 0, pool)
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	assert_eq(run.phase, RunState.Phase.CHOOSING_BOON)
	assert_eq(run.boon_offers.size(), Balance.BOON_OFFER_COUNT)
	var unique := {}
	for id: String in run.boon_offers:
		unique[id] = true
		assert_true(["a", "b", "c", "d", "e"].has(id), "Angebot stammt aus dem Pool")
	assert_eq(unique.size(), run.boon_offers.size(), "keine Dubletten im Angebot")


func test_choose_applies_then_advances() -> void:
	var run := RunState.start(_dungeon(5.0, 2.0), _stats(100.0, 10.0), 0, [_boon("rage", "atk_mult", 0.25)])
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	assert_eq(run.phase, RunState.Phase.CHOOSING_BOON)
	assert_true(run.choose_boon("nicht_im_angebot").is_empty(), "ungültige Wahl tut nichts")
	assert_eq(run.phase, RunState.Phase.CHOOSING_BOON)
	run.choose_boon("rage")
	assert_eq(run.boon_stacks("rage"), 1)
	assert_eq(run.phase, RunState.Phase.CHOOSING, "danach die Türwahl")


func test_skip_boon_advances_without_applying() -> void:
	var run := RunState.start(_dungeon(5.0, 2.0), _stats(100.0, 10.0), 0, [_boon("rage", "atk_mult", 0.25)])
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	run.skip_boon()
	assert_eq(run.boons_owned.size(), 0, "übersprungen = kein Segen")
	assert_eq(run.phase, RunState.Phase.CHOOSING)


func test_maxed_boon_is_not_offered() -> void:
	# Einziger Segen im Pool, max 1 Stapel: nach der ersten Wahl gibt es
	# nichts mehr anzubieten -> es geht direkt weiter.
	var run := RunState.start(_dungeon(5.0, 2.0), _stats(100.0, 10.0), 0, [_boon("once", "atk_mult", 0.25, 1)])
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	run.choose_boon("once")
	# Raum 2 (vor Boss bei rooms=3 ist Raum 3 normal, dann Boss).
	run.choose(RunState.RoomType.NORMAL)
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	assert_eq(run.phase, RunState.Phase.CHOOSING, "kein Segen mehr -> direkt Türwahl")
	assert_eq(run.boon_stacks("once"), 1)


func test_no_boon_after_boss() -> void:
	# 1-Raum-Dungeon: Raum 1 normal, Raum 2 Boss. Boss-Kill -> Sieg,
	# kein Segensangebot mehr.
	var run := RunState.start(_dungeon(5.0, 2.0, 1), _stats(100.0, 10.0), 0, [_boon("rage", "atk_mult", 0.25)])
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)  # Raum 1 -> Segen
	run.choose_boon("rage")  # -> direkt zum Boss (kein Tür-Schritt)
	assert_true(run.is_boss_room())
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)  # Boss fällt
	assert_eq(run.status, RunState.Status.VICTORY)


func test_offers_are_seeded() -> void:
	var pool: Array[BoonDef] = [
		_boon("a", "atk_mult", 0.1), _boon("b", "atk_mult", 0.1),
		_boon("c", "atk_mult", 0.1), _boon("d", "atk_mult", 0.1), _boon("e", "atk_mult", 0.1),
	]
	var first := RunState.start(_dungeon(5.0, 2.0), _stats(100.0, 10.0), 99, pool)
	first.enemy_intent = RunState.Intent.NORMAL
	first.take_action(RunState.Action.ATTACK)
	var second := RunState.start(_dungeon(5.0, 2.0), _stats(100.0, 10.0), 99, pool)
	second.enemy_intent = RunState.Intent.NORMAL
	second.take_action(RunState.Action.ATTACK)
	assert_eq(first.boon_offers, second.boon_offers, "gleicher Seed, gleiches Angebot")


func test_stacking_accumulates_effect() -> void:
	var run := RunState.start(_dungeon(1000.0, 2.0), _stats(100.0, 10.0), 0, [_boon("rage", "atk_mult", 0.25, 3)])
	run.boons_owned["rage"] = 2
	assert_almost(run.boon_amount("atk_mult"), 0.5, 1e-9, "zwei Stapel à 0.25")
	run.enemy_intent = RunState.Intent.NORMAL
	run.take_action(RunState.Action.ATTACK)
	assert_almost(run.enemy_hp.to_float(), 1000.0 - 15.0, 1e-6, "10 x (1 + 0.5)")
