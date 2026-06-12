extends "res://tests/test_base.gd"


func test_from_dict_and_validate() -> void:
	var trophy := ItemDef.from_dict({
		"id": "zahn",
		"display_name": "Zahn",
		"type": "trophy",
		"gold_value": 8.0,
	})
	assert_true(trophy.validate().is_empty(), "gültige Trophäe")
	assert_false(trophy.is_song_fragment())

	var fragment := ItemDef.from_dict({
		"id": "lied",
		"display_name": "Lied",
		"type": "song_fragment",
		"gold_value": 0.0,
	})
	assert_true(fragment.validate().is_empty(), "Fragmente brauchen keinen Verkaufswert")
	assert_true(fragment.is_song_fragment())


func test_validate_rejects_broken_items() -> void:
	var worthless := ItemDef.from_dict({"id": "x", "display_name": "X", "type": "trophy", "gold_value": 0})
	assert_false(worthless.validate().is_empty(), "Trophäe ohne Wert ist sinnlos")
	var unknown := ItemDef.from_dict({"id": "x", "display_name": "X", "type": "ausruestung"})
	assert_false(unknown.validate().is_empty(), "unbekannter Typ wird abgelehnt")
	var nameless := ItemDef.from_dict({"type": "trophy", "gold_value": 5})
	assert_false(nameless.validate().is_empty())
