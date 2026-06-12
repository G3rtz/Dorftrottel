extends "res://tests/test_base.gd"

## Crafting = die goldene Regel der Loop-Verzahnung: Rezept aus dem
## Dungeon, Gold aus dem Dorf, Material aus der Beute.


func test_recipe_def_validate() -> void:
	var valid := RecipeDef.from_dict({
		"id": "r", "display_name": "R", "slot": "weapon",
		"atk_bonus": 5.0, "cost_gold": 100.0,
	})
	assert_true(valid.validate().is_empty())
	var no_bonus := RecipeDef.from_dict({
		"id": "r", "display_name": "R", "slot": "weapon", "cost_gold": 100.0,
	})
	assert_false(no_bonus.validate().is_empty(), "Rezept ohne Bonus ist sinnlos")
	var bad_slot := RecipeDef.from_dict({
		"id": "r", "display_name": "R", "slot": "hut", "atk_bonus": 1.0, "cost_gold": 1.0,
	})
	assert_false(bad_slot.validate().is_empty(), "unbekannter Slot wird abgelehnt")
	var free := RecipeDef.from_dict({
		"id": "r", "display_name": "R", "slot": "weapon", "atk_bonus": 1.0,
	})
	assert_false(free.validate().is_empty(), "Rezept muss etwas kosten")


func test_recipes_load_and_are_wired() -> void:
	var defs := ContentDB.recipes()
	assert_true(defs.size() >= 1, "mindestens ein Rezept definiert")
	var any_starter := false
	for def in defs:
		assert_true(def.validate().is_empty(), "Rezept '%s' ist gültig" % def.id)
		for item_id: String in def.cost_items:
			assert_true(ContentDB.item(item_id) != null,
				"Material '%s' von '%s' existiert" % [item_id, def.id])
		if def.known_from_start:
			any_starter = true
		else:
			var teach := ContentDB.item(def.id)
			assert_true(teach != null and teach.is_recipe(),
				"Rezept '%s' muss als Drop lernbar sein" % def.id)
	assert_true(any_starter, "mindestens ein Start-Rezept für den frühen Einstieg")


func test_recipe_knowledge() -> void:
	var state := GameState.new()
	assert_true(state.is_recipe_known("rezept_knueppel"), "Start-Rezepte sind sofort bekannt")
	assert_false(state.is_recipe_known("rezept_rattenfaenger"), "Drop-Rezepte erst nach dem Fund")
	assert_false(state.is_recipe_known("gibt_es_nicht"))

	# Rezept-Drop wird zu Wissen geroutet, nicht ins Inventar.
	state.add_item("rezept_rattenfaenger")
	assert_true(state.is_recipe_known("rezept_rattenfaenger"))
	assert_eq(state.item_count("rezept_rattenfaenger"), 0, "Wissen liegt nicht im Beutestand")
	state.add_item("rezept_rattenfaenger")  # Duplikat verpufft
	assert_true(state.is_recipe_known("rezept_rattenfaenger"))


func test_craft_requires_everything() -> void:
	var state := GameState.new()
	var def := ContentDB.recipe("rezept_knueppel")
	assert_false(state.can_craft("rezept_knueppel"), "ohne Gold und Material kein Schmieden")

	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(def.cost_gold))
	assert_false(state.can_craft("rezept_knueppel"), "Gold allein reicht nicht")

	state.add_item("rattenzahn", 3)
	assert_true(state.can_craft("rezept_knueppel"))
	assert_false(state.can_craft("rezept_rattenfaenger"), "unbekanntes Rezept bleibt gesperrt")
	assert_false(state.craft("gibt_es_nicht"))


func test_craft_pays_equips_and_boosts() -> void:
	var state := GameState.new()
	var def := ContentDB.recipe("rezept_knueppel")
	var base_atk: float = state.hero_stats()["atk"].to_float()
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(def.cost_gold + 50.0))
	state.add_item("rattenzahn", 5)

	assert_true(state.craft("rezept_knueppel"))
	assert_almost(state.get_resource(Balance.PRIMARY_RESOURCE).to_float(), 50.0, 1e-6, "Gold bezahlt")
	assert_eq(state.item_count("rattenzahn"), 2, "Material verbraucht")
	assert_true(state.is_equipped("rezept_knueppel"))
	assert_almost(state.hero_stats()["atk"].to_float(), base_atk + def.atk_bonus, 1e-6, "Bonus wirkt")
	assert_false(state.can_craft("rezept_knueppel"), "dasselbe Stück doppelt schmieden ist sinnlos")


func test_crafting_through_slots_replaces() -> void:
	var state := GameState.new()
	state.recipes_known["rezept_rattenfaenger"] = true
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(100000.0))
	state.add_item("rattenzahn", 20)
	state.add_item("rattenkrone", 1)

	assert_true(state.craft("rezept_knueppel"))
	var knueppel_atk: float = state.hero_stats()["atk"].to_float()
	assert_true(state.craft("rezept_rattenfaenger"), "besseres Stück ersetzt den Knüppel")
	assert_true(state.is_equipped("rezept_rattenfaenger"))
	assert_false(state.is_equipped("rezept_knueppel"))
	assert_true(state.hero_stats()["atk"].to_float() > knueppel_atk)

	# Anderer Slot bleibt unberührt nutzbar.
	state.add_item("rattenzahn", 2)
	assert_true(state.craft("rezept_wams"))
	assert_true(state.is_equipped("rezept_rattenfaenger"))
	assert_true(state.is_equipped("rezept_wams"))


func test_prestige_clears_equipment_keeps_recipes() -> void:
	var state := GameState.new()
	state.recipes_known["rezept_rattenfaenger"] = true
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.FRAGMENT_BASE_GOLD))
	state.add_item("rattenzahn", 3)
	assert_true(state.craft("rezept_knueppel"))

	state.prestige()
	assert_true(state.equipment.is_empty(), "Ausrüstung ist vergänglich")
	assert_true(state.is_recipe_known("rezept_rattenfaenger"), "Wissen bleibt im Hirn")
	# Das Prestige hat Fragmente gedichtet – deren Passiv-Bonus wirkt.
	var expected_atk: float = Balance.HERO_BASE_ATK \
		* (1.0 + Balance.FRAGMENT_ATK_BONUS * state.fragments.to_float())
	assert_almost(state.hero_stats()["atk"].to_float(), expected_atk, 1e-6)


func test_equipment_serialization_roundtrip() -> void:
	var state := GameState.new()
	state.recipes_known["rezept_eispanzer"] = true
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(1000.0))
	state.add_item("rattenzahn", 3)
	assert_true(state.craft("rezept_knueppel"))

	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_true(restored.is_equipped("rezept_knueppel"))
	assert_true(restored.is_recipe_known("rezept_eispanzer"))
	assert_almost(restored.hero_stats()["atk"].to_float(), state.hero_stats()["atk"].to_float(), 1e-6)
