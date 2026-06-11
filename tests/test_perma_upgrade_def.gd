extends "res://tests/test_base.gd"


func _make_def() -> PermaUpgradeDef:
	return PermaUpgradeDef.from_dict({
		"id": "test_upgrade",
		"display_name": "Test",
		"effect": "gold_mult",
		"amount_per_level": 0.25,
		"base_cost": 2.0,
		"cost_growth": 1.5,
	})


func test_cost_growth() -> void:
	var def := _make_def()
	assert_almost(def.cost_for(0).to_float(), 2.0)
	assert_almost(def.cost_for(1).to_float(), 3.0)
	assert_almost(def.cost_for(4).to_float(), 2.0 * pow(1.5, 4.0), 1e-6)


func test_validate() -> void:
	assert_true(_make_def().validate().is_empty(), "gültige Definition")
	var broken := _make_def()
	broken.effect = "skip_dungeon_5"
	assert_false(broken.validate().is_empty(),
		"unbekannte Effekte werden abgelehnt – 'beschleunigen, nie skippen' ist auch technisch erzwungen")
	var no_amount := _make_def()
	no_amount.amount_per_level = 0.0
	assert_false(no_amount.validate().is_empty())
