extends "res://tests/test_base.gd"


func _make_def() -> GeneratorDef:
	return GeneratorDef.from_dict({
		"id": "test",
		"display_name": "Test",
		"resource_id": "gold",
		"base_rate": 0.5,
		"base_cost": 15.0,
		"cost_growth": 1.15,
		"unlock_at_lifetime": 0.0,
	})


func test_cost_matches_naive_sum() -> void:
	# Geschlossene Formel gegen naive Schleife prüfen.
	var def := _make_def()
	for owned_count in [0, 3, 50]:
		for count in [1, 5, 25]:
			var expected := 0.0
			for i in count:
				expected += def.base_cost * pow(def.cost_growth, float(owned_count + i))
			var actual := def.cost_for(owned_count, count).to_float()
			assert_almost(actual / expected, 1.0, 1e-9,
				"Kosten bei owned=%d count=%d" % [owned_count, count])


func test_cost_handles_huge_counts() -> void:
	# growth^10000 würde jeden Float sprengen – BigNum nicht.
	var def := _make_def()
	var cost := def.cost_for(10000, 1)
	assert_true(cost.e > 600, "Kosten nach 10000 Käufen sind astronomisch (e=%d)" % cost.e)
	assert_true(cost.cmp(def.cost_for(9999, 1)) > 0, "Kosten steigen monoton")


func test_cost_edge_cases() -> void:
	var def := _make_def()
	assert_true(def.cost_for(0, 0).is_zero(), "0 Stück kosten nichts")
	var flat := _make_def()
	flat.cost_growth = 1.0
	assert_almost(flat.cost_for(7, 4).to_float(), flat.base_cost * 4.0, 1e-9, "growth=1 ist linear")


func test_rate_for() -> void:
	var def := _make_def()
	assert_true(def.rate_for(0).is_zero())
	assert_almost(def.rate_for(8).to_float(), 4.0, 1e-9, "8 * 0.5/s")


func test_max_affordable_invariant() -> void:
	# Kerninvariante: cost(n) <= Budget < cost(n+1) – über viele
	# Größenordnungen, inklusive BigNum-Territorium.
	var def := _make_def()
	for owned_count in [0, 7, 120]:
		for budget_value in [0.0, 10.0, 15.0, 100.0, 12345.6, 1e9, 1e30]:
			var budget := BigNum.from_float(budget_value)
			var n := def.max_affordable(owned_count, budget)
			if n == 0:
				assert_true(budget.lt(def.cost_for(owned_count, 1)),
					"0 nur, wenn nicht mal eins drin ist (owned=%d, budget=%s)" % [owned_count, budget_value])
				continue
			assert_true(budget.gte(def.cost_for(owned_count, n)),
				"n=%d ist bezahlbar (owned=%d, budget=%s)" % [n, owned_count, budget_value])
			assert_true(budget.lt(def.cost_for(owned_count, n + 1)),
				"n+1=%d wäre zu teuer (owned=%d, budget=%s)" % [n + 1, owned_count, budget_value])


func test_max_affordable_exact_boundary() -> void:
	var def := _make_def()
	# Budget exakt auf die Summe von 5 Stück legen.
	var budget := def.cost_for(3, 5)
	assert_eq(def.max_affordable(3, budget), 5, "exaktes Budget kauft genau 5")
	var slightly_less := budget.sub(BigNum.from_float(0.01))
	assert_eq(def.max_affordable(3, slightly_less), 4, "ein Hauch weniger kauft 4")


func test_max_affordable_linear_growth() -> void:
	var flat := _make_def()
	flat.cost_growth = 1.0
	assert_eq(flat.max_affordable(50, BigNum.from_float(flat.base_cost * 7.5)), 7,
		"growth=1: Budget / Stückpreis, abgerundet")
	assert_eq(flat.max_affordable(0, BigNum.zero()), 0)


func test_validate() -> void:
	assert_true(_make_def().validate().is_empty(), "gültige Definition hat keine Probleme")
	var broken := GeneratorDef.from_dict({"id": "", "base_cost": -5})
	var problems := broken.validate()
	assert_false(problems.is_empty(), "kaputte Definition wird erkannt")
