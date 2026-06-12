extends "res://tests/test_base.gd"


func test_construction_and_normalization() -> void:
	var n := BigNum.from_float(1234.0)
	assert_almost(n.m, 1.234, 1e-9, "Mantisse von 1234")
	assert_eq(n.e, 3, "Exponent von 1234")

	var denormalized := BigNum.from_parts(123.456, 2)
	assert_almost(denormalized.m, 1.23456, 1e-9)
	assert_eq(denormalized.e, 4)

	var small := BigNum.from_float(0.05)
	assert_almost(small.m, 5.0, 1e-9)
	assert_eq(small.e, -2)

	var negative := BigNum.from_float(-250.0)
	assert_almost(negative.m, -2.5, 1e-9)
	assert_eq(negative.e, 2)

	assert_true(BigNum.from_float(0.0).is_zero(), "0 ist zero")
	assert_eq(BigNum.zero().e, 0, "zero hat Exponent 0")


func test_beyond_float_range() -> void:
	# Genau der Fall, für den BigNum existiert: jenseits von ~1e308.
	var huge := BigNum.from_float(1e300).mul(BigNum.from_float(1e300))
	assert_almost(huge.m, 1.0, 1e-9)
	assert_eq(huge.e, 600)
	var huger := huge.mul(huge)
	assert_eq(huger.e, 1200)
	assert_true(huger.cmp(huge) > 0, "1e1200 > 1e600")


func test_add_and_sub() -> void:
	assert_big_eq(BigNum.from_float(2.0).add(BigNum.from_float(3.0)), BigNum.from_float(5.0))
	assert_big_eq(BigNum.from_float(950.0).add(BigNum.from_float(50.0)), BigNum.from_float(1000.0))
	assert_big_eq(BigNum.from_float(100.0).sub(BigNum.from_float(1.0)), BigNum.from_float(99.0))
	assert_true(BigNum.from_float(5.0).sub(BigNum.from_float(5.0)).is_zero(), "x - x = 0")
	assert_big_eq(BigNum.from_float(3.0).sub(BigNum.from_float(10.0)), BigNum.from_float(-7.0))

	# Addition weit unterhalb der Präzisionsgrenze ändert nichts.
	var big := BigNum.from_parts(1.0, 100)
	assert_big_eq(big.add(BigNum.one()), big, "1e100 + 1 = 1e100")
	assert_big_eq(BigNum.one().add(big), big, "1 + 1e100 = 1e100")


func test_mul_and_div() -> void:
	assert_big_eq(BigNum.from_float(4.0).mul(BigNum.from_float(250.0)), BigNum.from_float(1000.0))
	assert_big_eq(BigNum.from_float(1000.0).div(BigNum.from_float(8.0)), BigNum.from_float(125.0))
	assert_true(BigNum.from_float(5.0).mul(BigNum.zero()).is_zero())
	# Division durch null: definierter Rückgabewert statt Crash.
	assert_true(BigNum.one().div(BigNum.zero()).is_zero())


func test_pow_int_and_from_log10() -> void:
	assert_big_eq(BigNum.from_float(2.0).pow_int(10), BigNum.from_float(1024.0))
	assert_big_eq(BigNum.from_float(7.0).pow_int(0), BigNum.one())
	var via_log := BigNum.from_log10(3.5)
	assert_almost(via_log.to_float(), pow(10.0, 3.5), 1e-3)


func test_cmp() -> void:
	assert_true(BigNum.from_float(2.0).cmp(BigNum.from_float(3.0)) < 0)
	assert_true(BigNum.from_float(300.0).cmp(BigNum.from_float(3.0)) > 0)
	assert_eq(BigNum.from_float(5.0).cmp(BigNum.from_float(5.0)), 0)
	assert_true(BigNum.from_float(-1.0).cmp(BigNum.one()) < 0)
	# Bei negativen Zahlen bedeutet größerer Betrag "kleiner".
	assert_true(BigNum.from_float(-1000.0).cmp(BigNum.from_float(-1.0)) < 0)
	assert_true(BigNum.zero().cmp(BigNum.from_float(-1.0)) > 0)
	assert_true(BigNum.from_float(99.999999999).gte(BigNum.from_float(100.0)), "Float-Rauschen zählt als gleich")


func test_format() -> void:
	assert_eq(BigNum.zero().format(), "0")
	assert_eq(BigNum.from_float(7.0).format(), "7")
	assert_eq(BigNum.from_float(999.0).format(), "999")
	assert_eq(BigNum.from_float(1234.0).format(), "1.23K")
	assert_eq(BigNum.from_float(1500000.0).format(), "1.5M")
	assert_eq(BigNum.from_float(-1234.0).format(), "-1.23K")
	assert_eq(BigNum.from_parts(1.23, 42).format(), "1.23e42")
	assert_eq(BigNum.from_float(0.5).format(), "0.5")


func test_square_root() -> void:
	assert_big_eq(BigNum.from_float(4.0).square_root(), BigNum.from_float(2.0))
	assert_big_eq(BigNum.from_float(2500.0).square_root(), BigNum.from_float(50.0))
	# Ungerader Exponent muss begradigt werden: sqrt(2.5e7) = 5000.
	assert_big_eq(BigNum.from_parts(2.5, 7).square_root(), BigNum.from_float(5000.0))
	# Jenseits des Float-Bereichs – der eigentliche Zweck.
	assert_big_eq(BigNum.from_parts(1.0, 100).square_root(), BigNum.from_parts(1.0, 50))
	assert_almost(BigNum.from_float(0.001).square_root().to_float(), sqrt(0.001), 1e-9)
	assert_true(BigNum.zero().square_root().is_zero())
	assert_true(BigNum.from_float(-4.0).square_root().is_zero(), "negativ -> definierte Null")


func test_floored() -> void:
	assert_big_eq(BigNum.from_float(3.7).floored(), BigNum.from_float(3.0))
	assert_big_eq(BigNum.from_float(1234.99).floored(), BigNum.from_float(1234.0))
	assert_true(BigNum.from_float(0.9).floored().is_zero())
	assert_big_eq(BigNum.from_float(5.0).floored(), BigNum.from_float(5.0))
	# Riesige Zahlen tragen keine Nachkommastellen mehr: unverändert.
	var huge := BigNum.from_parts(1.23456, 40)
	assert_big_eq(huge.floored(), huge)


func test_log10f() -> void:
	assert_almost(BigNum.one().log10f(), 0.0, 1e-9)
	assert_almost(BigNum.from_float(1000.0).log10f(), 3.0, 1e-9)
	assert_almost(BigNum.from_float(0.01).log10f(), -2.0, 1e-9)
	assert_almost(BigNum.from_parts(5.0, 100).log10f(), 100.0 + log(5.0) / log(10.0), 1e-9)
	assert_almost(BigNum.zero().log10f(), 0.0, 1e-9, "0 -> definierter Rückgabewert")


func test_serialization_roundtrip() -> void:
	var original := BigNum.from_parts(4.2, 1337)
	var restored := BigNum.from_dict(original.to_dict())
	assert_big_eq(restored, original)
	# JSON macht aus Ints Floats – muss trotzdem funktionieren.
	var from_json := BigNum.from_dict({"m": 2.5, "e": 10.0})
	assert_big_eq(from_json, BigNum.from_parts(2.5, 10))
	# Kaputte/leere Daten ergeben eine definierte Null.
	assert_true(BigNum.from_dict({}).is_zero())
