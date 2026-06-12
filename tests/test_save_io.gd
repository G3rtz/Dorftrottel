extends "res://tests/test_base.gd"

const TEST_DIR := "user://test_saves"


func _fresh_io() -> SaveIO:
	var io := SaveIO.new(TEST_DIR)
	io.clear()
	return io


func _payload(marker: String) -> Dictionary:
	return {"village": {"marker": marker}}


func test_write_and_read_roundtrip() -> void:
	var io := _fresh_io()
	assert_false(io.has_save())
	assert_true(io.write(_payload("erster")))
	assert_true(io.has_save())

	var envelope := io.read()
	assert_eq(int(envelope["version"]), SaveIO.SAVE_VERSION)
	assert_true(float(envelope["saved_at_unix"]) > 0.0)
	assert_eq(envelope["state"]["village"]["marker"], "erster")
	io.clear()


func test_corrupt_save_falls_back_to_backup() -> void:
	var io := _fresh_io()
	assert_true(io.write(_payload("alt")))
	assert_true(io.write(_payload("neu")))  # rotiert "alt" ins Backup

	# Hauptsave zerstören.
	var file := FileAccess.open(io.save_path(), FileAccess.WRITE)
	file.store_string("{kaputt!!!")
	file.close()

	var envelope := io.read()
	assert_false(envelope.is_empty(), "Backup rettet den Spielstand")
	assert_eq(envelope["state"]["village"]["marker"], "alt")
	io.clear()


func test_unknown_future_version_is_rejected() -> void:
	var io := _fresh_io()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open(io.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 9999, "state": {}}))
	file.close()
	assert_true(io.read().is_empty(), "Save aus der Zukunft wird nicht angefasst")
	io.clear()


func test_missing_save_reads_empty() -> void:
	var io := _fresh_io()
	assert_true(io.read().is_empty())


func test_migration_v1_fame_becomes_fragments() -> void:
	# Ein echter Version-1-Save: Ruhm hieß damals "fame".
	var io := _fresh_io()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open(io.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": 1,
		"saved_at_unix": 1000.0,
		"state": {"perma": {"fame": {"m": 4.2, "e": 1}, "dungeons_cleared": {"ratten_keller": true}}},
	}))
	file.close()

	var envelope := io.read()
	assert_false(envelope.is_empty(), "v1-Save wird migriert, nicht abgelehnt")
	assert_eq(int(envelope["version"]), SaveIO.SAVE_VERSION)
	var perma: Dictionary = envelope["state"]["perma"]
	assert_false(perma.has("fame"), "alter Schlüssel ist weg")
	assert_almost(float(perma["fragments"]["m"]), 4.2, 1e-9, "Ruhm wurde 1:1 zu Liedfragmenten")

	var state := GameState.from_dict(envelope["state"])
	assert_almost(state.fragments.to_float(), 42.0, 1e-6)
	assert_true(state.dungeons_cleared.has("ratten_keller"), "Rest des Saves unangetastet")
	io.clear()


func test_full_game_state_through_save() -> void:
	# Integration: GameState -> SaveIO -> GameState.
	var io := _fresh_io()
	var state := GameState.new()
	state.add_resource("gold", BigNum.from_parts(3.25, 77))
	var def: GeneratorDef = ContentDB.generators()[0]
	state.generators[def.id] = 42

	assert_true(io.write(state.to_dict()))
	var envelope := io.read()
	var restored := GameState.from_dict(envelope["state"])
	assert_big_eq(restored.get_resource("gold"), state.get_resource("gold"))
	assert_eq(restored.owned(def.id), 42)
	io.clear()
