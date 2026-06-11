class_name ContentDB
extends RefCounted

## Lädt und validiert Spielinhalte aus res://data/. Ungültige Einträge
## werden mit Fehlermeldung übersprungen statt das Spiel zu crashen.

const GENERATORS_PATH := "res://data/generators.json"
const DUNGEONS_PATH := "res://data/dungeons.json"

static var _generators: Array[GeneratorDef] = []
static var _generators_loaded := false
static var _dungeons: Array[DungeonDef] = []
static var _dungeons_loaded := false


static func generators() -> Array[GeneratorDef]:
	if not _generators_loaded:
		_generators = _load_generators(GENERATORS_PATH)
		_generators_loaded = true
	return _generators


static func generator(id: String) -> GeneratorDef:
	for def in generators():
		if def.id == id:
			return def
	return null


static func dungeons() -> Array[DungeonDef]:
	if not _dungeons_loaded:
		_dungeons = _load_dungeons(DUNGEONS_PATH)
		_dungeons_loaded = true
	return _dungeons


static func dungeon(id: String) -> DungeonDef:
	for def in dungeons():
		if def.id == id:
			return def
	return null


static func _load_generators(path: String) -> Array[GeneratorDef]:
	var result: Array[GeneratorDef] = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ContentDB: %s fehlt oder ist leer" % path)
		return result
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Array:
		push_error("ContentDB: %s ist kein gültiges JSON-Array" % path)
		return result
	var seen_ids := {}
	for entry: Variant in parsed:
		if not entry is Dictionary:
			push_error("ContentDB: Eintrag in %s ist kein Objekt: %s" % [path, entry])
			continue
		var def := GeneratorDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Generator '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Generator-ID '%s'" % def.id)
			continue
		seen_ids[def.id] = true
		result.append(def)
	return result


static func _load_dungeons(path: String) -> Array[DungeonDef]:
	var result: Array[DungeonDef] = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ContentDB: %s fehlt oder ist leer" % path)
		return result
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Array:
		push_error("ContentDB: %s ist kein gültiges JSON-Array" % path)
		return result
	var seen_ids := {}
	for entry: Variant in parsed:
		if not entry is Dictionary:
			push_error("ContentDB: Eintrag in %s ist kein Objekt: %s" % [path, entry])
			continue
		var def := DungeonDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Dungeon '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Dungeon-ID '%s'" % def.id)
			continue
		seen_ids[def.id] = true
		result.append(def)
	# Querverweis-Prüfung: unlocked_by muss auf einen existierenden
	# Dungeon zeigen, sonst wäre der Eintrag unerreichbar.
	for def in result:
		if not def.unlocked_by.is_empty() and not seen_ids.has(def.unlocked_by):
			push_error("ContentDB: Dungeon '%s' verweist auf unbekannten Dungeon '%s'" % [def.id, def.unlocked_by])
	return result
