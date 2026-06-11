extends RefCounted

## Minimale Test-Basisklasse. Bewusst ohne Addon-Abhängigkeit (GUT etc.),
## damit Tests überall laufen, wo ein Godot-Binary liegt.

var failures: PackedStringArray = []
var current_test := ""


func fail_test(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		fail_test("erwartet true. %s" % message)


func assert_false(condition: bool, message := "") -> void:
	if condition:
		fail_test("erwartet false. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if actual != expected:
		fail_test("erwartet %s, bekommen %s. %s" % [str(expected), str(actual), message])


func assert_almost(actual: float, expected: float, tolerance := 1e-6, message := "") -> void:
	if absf(actual - expected) > tolerance:
		fail_test("erwartet ~%s, bekommen %s. %s" % [expected, actual, message])


## Vergleicht BigNums über Exponent + Mantisse (mit Float-Toleranz).
func assert_big_eq(actual: BigNum, expected: BigNum, message := "") -> void:
	if actual.e != expected.e or absf(actual.m - expected.m) > 1e-6:
		fail_test("erwartet %se%d, bekommen %se%d. %s" % [expected.m, expected.e, actual.m, actual.e, message])
