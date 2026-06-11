extends "res://tests/test_base.gd"

## Validiert die echten Spieldaten – fängt kaputte Balance-Edits in CI ab.


func test_generators_load() -> void:
	var defs := ContentDB.generators()
	assert_true(defs.size() >= 1, "mindestens ein Generator definiert")
	for def in defs:
		assert_true(def.validate().is_empty(), "Generator '%s' ist gültig" % def.id)


func test_first_generator_is_immediately_available() -> void:
	var defs := ContentDB.generators()
	assert_true(defs.size() > 0)
	assert_eq(defs[0].unlock_at_lifetime, 0.0, "Der erste Generator darf nicht versteckt sein")


func test_progression_is_ascending() -> void:
	# Kosten und Freischaltschwellen müssen aufsteigen, sonst stimmt
	# die Progression nicht.
	var defs := ContentDB.generators()
	for i in range(1, defs.size()):
		assert_true(defs[i].base_cost > defs[i - 1].base_cost,
			"'%s' muss teurer sein als '%s'" % [defs[i].id, defs[i - 1].id])
		assert_true(defs[i].unlock_at_lifetime >= defs[i - 1].unlock_at_lifetime,
			"Freischaltreihenfolge von '%s'" % defs[i].id)


func test_lookup() -> void:
	var defs := ContentDB.generators()
	assert_eq(ContentDB.generator(defs[0].id).id, defs[0].id)
	assert_eq(ContentDB.generator("gibt_es_nicht"), null)
