extends SceneTree

## Headless-Testrunner:
##   godot --headless --script res://tests/run_tests.gd
## Findet in jedem registrierten Skript alle test_*-Methoden,
## führt sie aus und beendet mit Exit-Code != 0 bei Fehlschlägen.

const TEST_SCRIPTS: Array[String] = [
	"res://tests/test_big_num.gd",
	"res://tests/test_generator_def.gd",
	"res://tests/test_dungeon_def.gd",
	"res://tests/test_run_state.gd",
	"res://tests/test_perma_upgrade_def.gd",
	"res://tests/test_item_def.gd",
	"res://tests/test_crafting.gd",
	"res://tests/test_content_db.gd",
	"res://tests/test_game_state.gd",
	"res://tests/test_save_io.gd",
]


func _init() -> void:
	var total := 0
	var failed: PackedStringArray = []
	for path in TEST_SCRIPTS:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			# Auch Parse-Fehler landen hier – sonst würde der Runner
			# beim new() crashen und die CI hinge ohne Ergebnis.
			failed.append("%s: Skript konnte nicht geladen/instanziiert werden" % path)
			continue
		var instance: Variant = script.new()
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			instance.current_test = "%s::%s" % [path.get_file(), method_name]
			instance.call(method_name)
		failed.append_array(instance.failures)
	print("")
	if failed.is_empty():
		print("OK – %d Tests bestanden" % total)
	else:
		for failure in failed:
			printerr("FAIL  %s" % failure)
		printerr("%d von %d Tests fehlgeschlagen" % [failed.size(), total])
	quit(0 if failed.is_empty() else 1)
