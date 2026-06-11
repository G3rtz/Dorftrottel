class_name ContentDB
extends RefCounted

## Lädt und validiert Spielinhalte aus res://data/. Ungültige Einträge
## werden mit Fehlermeldung übersprungen statt das Spiel zu crashen.

const GENERATORS_PATH := "res://data/generators.json"

static var _generators: Array[GeneratorDef] = []
static var _loaded := false


static func generators() -> Array[GeneratorDef]:
	if not _loaded:
		_generators = _load_generators(GENERATORS_PATH)
		_loaded = true
	return _generators


static func generator(id: String) -> GeneratorDef:
	for def in generators():
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
