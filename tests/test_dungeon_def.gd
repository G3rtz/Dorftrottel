extends "res://tests/test_base.gd"


func _make_def() -> DungeonDef:
	return DungeonDef.from_dict({
		"id": "test_dungeon",
		"display_name": "Testdungeon",
		"rooms": 3,
		"enemy_names": ["A", "B"],
		"boss_name": "Boss",
		"enemy_hp": 10.0,
		"enemy_atk": 2.0,
		"hp_growth": 2.0,
		"atk_growth": 1.5,
		"boss_hp_mult": 3.0,
		"boss_atk_mult": 2.0,
		"heal_per_room": 5.0,
		"gold_per_enemy": 4.0,
		"gold_growth": 2.0,
		"boss_gold": 100.0,
		"completion_bonus": 50.0,
	})


func test_enemy_scaling() -> void:
	var def := _make_def()
	assert_almost(def.enemy_hp_for(1).to_float(), 10.0)
	assert_almost(def.enemy_hp_for(3).to_float(), 40.0, 1e-6, "hp * growth^2")
	assert_almost(def.enemy_atk_for(2).to_float(), 3.0)
	# Bossraum = Raum rooms+1, skaliert weiter und multipliziert.
	assert_true(def.is_boss_room(4))
	assert_false(def.is_boss_room(3))
	assert_almost(def.enemy_hp_for(4).to_float(), 10.0 * 8.0 * 3.0, 1e-6, "Boss-HP")
	assert_almost(def.enemy_atk_for(4).to_float(), 2.0 * pow(1.5, 3.0) * 2.0, 1e-6, "Boss-ATK")


func test_gold_scaling() -> void:
	var def := _make_def()
	assert_almost(def.gold_for(1).to_float(), 4.0)
	assert_almost(def.gold_for(3).to_float(), 16.0)
	assert_almost(def.gold_for(4).to_float(), 100.0, 1e-6, "Boss zahlt boss_gold")


func test_enemy_names_cycle() -> void:
	var def := _make_def()
	assert_eq(def.enemy_name_for(1), "A")
	assert_eq(def.enemy_name_for(2), "B")
	assert_eq(def.enemy_name_for(3), "A", "Namen rotieren")
	assert_eq(def.enemy_name_for(4), "Boss")


func test_validate() -> void:
	assert_true(_make_def().validate().is_empty(), "gültige Definition")
	var broken := DungeonDef.from_dict({"id": "x", "rooms": 0, "enemy_hp": -1})
	assert_false(broken.validate().is_empty(), "kaputte Definition wird erkannt")
