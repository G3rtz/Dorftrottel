extends "res://tests/test_base.gd"

## Talentbäume (GDD §3): Hero (Dungeon-Erfahrung) und Base/Dorf
## (Idle-Fortschritt). Beide resetten beim Prestige, anders als der
## Perma-Baum.


func _make_hero_def(requires: String = "") -> TalentDef:
	return TalentDef.from_dict({
		"id": "test_hero_talent",
		"display_name": "Test",
		"effect": "hero_atk_mult",
		"amount_per_level": 0.1,
		"max_level": 2,
		"base_cost_points": 1,
		"cost_growth_points": 1,
		"requires": requires,
	})


func test_cost_growth() -> void:
	var def := _make_hero_def()
	assert_eq(def.cost_for(0), 1)
	assert_eq(def.cost_for(1), 2)
	assert_eq(def.cost_for(3), 4)


func test_validate() -> void:
	assert_true(_make_hero_def().validate(ContentDB.HERO_TALENT_EFFECTS).is_empty(), "gültige Definition")

	var wrong_tree := _make_hero_def()
	wrong_tree.effect = "gold_mult"
	assert_false(wrong_tree.validate(ContentDB.HERO_TALENT_EFFECTS).is_empty(),
		"Effekte aus dem anderen Baum sind im Hero-Baum unbekannt")

	var self_requires := _make_hero_def()
	self_requires.requires = self_requires.id
	assert_false(self_requires.validate(ContentDB.HERO_TALENT_EFFECTS).is_empty(),
		"ein Talent kann nicht sein eigener Vorgänger sein")

	var no_max_level := _make_hero_def()
	no_max_level.max_level = 0
	assert_false(no_max_level.validate(ContentDB.HERO_TALENT_EFFECTS).is_empty())

	var negative_growth := _make_hero_def()
	negative_growth.cost_growth_points = -1
	assert_false(negative_growth.validate(ContentDB.HERO_TALENT_EFFECTS).is_empty())


func test_hero_talents_load() -> void:
	var defs := ContentDB.hero_talents()
	assert_true(defs.size() >= 1, "mindestens ein Hero-Talent definiert")
	var ids := {}
	for def in defs:
		assert_true(def.validate(ContentDB.HERO_TALENT_EFFECTS).is_empty(), "Hero-Talent '%s' ist gültig" % def.id)
		ids[def.id] = true
	for def in defs:
		assert_true(def.requires.is_empty() or ids.has(def.requires),
			"'%s' verlangt einen existierenden Vorgänger" % def.id)
	assert_true(ContentDB.hero_talent(defs[0].id) != null)
	assert_eq(ContentDB.hero_talent("gibt_es_nicht"), null)


func test_base_talents_load() -> void:
	var defs := ContentDB.base_talents()
	assert_true(defs.size() >= 1, "mindestens ein Base-Talent definiert")
	var ids := {}
	for def in defs:
		assert_true(def.validate(ContentDB.BASE_TALENT_EFFECTS).is_empty(), "Base-Talent '%s' ist gültig" % def.id)
		ids[def.id] = true
	for def in defs:
		assert_true(def.requires.is_empty() or ids.has(def.requires),
			"'%s' verlangt einen existierenden Vorgänger" % def.id)
	assert_true(ContentDB.base_talent(defs[0].id) != null)
	assert_eq(ContentDB.base_talent("gibt_es_nicht"), null)


func test_hero_talent_points_from_xp() -> void:
	var state := GameState.new()
	assert_eq(state.hero_talent_points_earned(), 0)
	state.hero_xp = Balance.HERO_XP_PER_POINT * 3
	assert_eq(state.hero_talent_points_earned(), 3)
	state.hero_xp += 1
	assert_eq(state.hero_talent_points_earned(), 3, "Rest unter der Schwelle bringt noch keinen Punkt")


func test_hero_talent_gating_and_purchase() -> void:
	var state := GameState.new()
	var root := ContentDB.hero_talent("robuster_anfang")
	var child := ContentDB.hero_talent("alte_kaempfernarben")
	assert_false(state.buy_hero_talent(root.id), "ohne Punkte kein Kauf")
	assert_false(state.buy_hero_talent("gibt_es_nicht"))

	state.hero_xp = Balance.HERO_XP_PER_POINT * 10
	assert_false(state.is_hero_talent_available(child), "Folgeknoten ohne Vorgänger gesperrt")
	assert_true(state.buy_hero_talent(root.id))
	assert_eq(state.hero_talent_level(root.id), 1)
	assert_true(state.hero_talent_points_available() < state.hero_talent_points_earned())

	while state.hero_talent_level(root.id) < root.max_level:
		state.buy_hero_talent(root.id)
	assert_false(state.buy_hero_talent(root.id), "am Stufenlimit kein weiterer Kauf")
	assert_true(state.is_hero_talent_available(child), "Vorgänger erfüllt: Folgeknoten frei")
	assert_true(state.buy_hero_talent(child.id))


func test_hero_talent_bonus_applies_to_hero_stats() -> void:
	var state := GameState.new()
	var base_atk: float = state.hero_stats()["atk"].to_float()
	var base_hp: float = state.hero_stats()["hp"].to_float()

	state.hero_xp = Balance.HERO_XP_PER_POINT * 10
	assert_true(state.buy_hero_talent("robuster_anfang"))
	assert_true(state.buy_hero_talent("fester_griff"))

	var hp_def := ContentDB.hero_talent("robuster_anfang")
	var atk_def := ContentDB.hero_talent("fester_griff")
	assert_almost(state.hero_stats()["hp"].to_float(), base_hp * (1.0 + hp_def.amount_per_level), 1e-6)
	assert_almost(state.hero_stats()["atk"].to_float(), base_atk * (1.0 + atk_def.amount_per_level), 1e-6)


func test_base_talent_points_from_lifetime_gold() -> void:
	var state := GameState.new()
	assert_eq(state.base_talent_points_earned(), 0)
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.BASE_TALENT_POINT_GOLD))
	assert_eq(state.base_talent_points_earned(), 1, "1 Punkt bei der Basisschwelle")
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.BASE_TALENT_POINT_GOLD * 3.0))
	assert_eq(state.base_talent_points_earned(), 2, "2 Punkte bei 4x Basis (sqrt-Formel)")


func test_base_talent_gating_and_purchase() -> void:
	var state := GameState.new()
	var root := ContentDB.base_talent("fruehe_voegel")
	var child := ContentDB.base_talent("marktkenntnis")
	assert_false(state.buy_base_talent(root.id), "ohne Punkte kein Kauf")
	assert_false(state.buy_base_talent("gibt_es_nicht"))

	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.BASE_TALENT_POINT_GOLD * 100.0))
	assert_false(state.is_base_talent_available(child), "Folgeknoten ohne Vorgänger gesperrt")
	assert_true(state.buy_base_talent(root.id))
	assert_eq(state.base_talent_level(root.id), 1)

	while state.base_talent_level(root.id) < root.max_level:
		state.buy_base_talent(root.id)
	assert_false(state.buy_base_talent(root.id), "am Stufenlimit kein weiterer Kauf")
	assert_true(state.is_base_talent_available(child), "Vorgänger erfüllt: Folgeknoten frei")
	assert_true(state.buy_base_talent(child.id))


func test_base_talent_bonus_applies_to_production() -> void:
	var state := GameState.new()
	var gen := ContentDB.generators()[0]
	state.generators[gen.id] = 10
	var base_rate: float = state.production_per_second(Balance.PRIMARY_RESOURCE).to_float()

	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.BASE_TALENT_POINT_GOLD * 100.0))
	assert_true(state.buy_base_talent("fruehe_voegel"))

	var gold_def := ContentDB.base_talent("fruehe_voegel")
	assert_almost(state.production_per_second(Balance.PRIMARY_RESOURCE).to_float(),
		base_rate * (1.0 + gold_def.amount_per_level), 1e-6)


func test_base_talent_bonus_applies_to_manual_work() -> void:
	var state := GameState.new()
	var gen := ContentDB.generators()[0]
	state.generators[gen.id] = 10
	var base_work: float = state.manual_work_amount().to_float()

	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.BASE_TALENT_POINT_GOLD * 100.0))
	assert_true(state.buy_base_talent("fleiss_lernt_man"))

	var work_def := ContentDB.base_talent("fleiss_lernt_man")
	assert_almost(state.manual_work_amount().to_float(),
		base_work * (1.0 + work_def.amount_per_level), 1e-6)


func test_bank_run_result_grants_hero_xp() -> void:
	var state := GameState.new()
	state.bank_run_result({
		"dungeon_id": "ratten_keller",
		"victory": false,
		"gold": BigNum.zero(),
		"rooms_cleared": 4,
	})
	assert_eq(state.hero_xp, 4 * Balance.HERO_XP_PER_ROOM, "Erfahrung zählt auch ohne Sieg")

	state.bank_run_result({
		"dungeon_id": "ratten_keller",
		"victory": true,
		"gold": BigNum.zero(),
		"rooms_cleared": 3,
	})
	assert_eq(state.hero_xp,
		4 * Balance.HERO_XP_PER_ROOM + 3 * Balance.HERO_XP_PER_ROOM + Balance.HERO_XP_VICTORY_BONUS,
		"Sieg gibt Bonus obendrauf")


func test_prestige_resets_talents() -> void:
	var state := GameState.new()
	state.hero_xp = Balance.HERO_XP_PER_POINT * 10
	state.buy_hero_talent("robuster_anfang")
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.BASE_TALENT_POINT_GOLD * 100.0))
	state.buy_base_talent("fruehe_voegel")
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.FRAGMENT_BASE_GOLD))

	state.prestige()
	assert_eq(state.hero_xp, 0)
	assert_true(state.hero_talent_levels.is_empty())
	assert_true(state.base_talent_levels.is_empty())


func test_serialization_roundtrip() -> void:
	var state := GameState.new()
	state.hero_xp = 17
	state.hero_talent_levels["robuster_anfang"] = 2
	state.base_talent_levels["fruehe_voegel"] = 1

	var restored := GameState.from_dict(state.to_dict())
	assert_eq(restored.hero_xp, 17)
	assert_eq(restored.hero_talent_level("robuster_anfang"), 2)
	assert_eq(restored.base_talent_level("fruehe_voegel"), 1)

	# Durch JSON hindurch muss es ebenfalls überleben.
	var json_text := JSON.stringify(state.to_dict())
	var from_json := GameState.from_dict(JSON.parse_string(json_text))
	assert_eq(from_json.hero_xp, 17)
	assert_eq(from_json.hero_talent_level("robuster_anfang"), 2)
	assert_eq(from_json.base_talent_level("fruehe_voegel"), 1)
