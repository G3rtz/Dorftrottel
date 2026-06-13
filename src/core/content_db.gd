class_name ContentDB
extends RefCounted

## Lädt und validiert Spielinhalte aus res://data/. Ungültige Einträge
## werden mit Fehlermeldung übersprungen statt das Spiel zu crashen.

const GENERATORS_PATH := "res://data/generators.json"
const DUNGEONS_PATH := "res://data/dungeons.json"
const PERMA_UPGRADES_PATH := "res://data/perma_upgrades.json"
const SAGA_LINES_PATH := "res://data/saga_lines.json"
const ITEMS_PATH := "res://data/items.json"
const RECIPES_PATH := "res://data/recipes.json"
const TALES_PATH := "res://data/tales.json"
const BOONS_PATH := "res://data/boons.json"
const CLASSES_PATH := "res://data/classes.json"
const GENERATOR_UPGRADES_PATH := "res://data/generator_upgrades.json"

## Hohe Ausbau-Staffeln in althergebrachter Idle-Manier: werden für
## jeden Generator GENERIERT statt von Hand gepflegt. Die tiefen
## Schwellen sind ohne Prestige-Multiplikatoren praktisch
## unerreichbar – genau dadurch lohnt sich jedes weitere Prestige.
## IDs ("<generator>_tier_<schwelle>") müssen stabil bleiben: sie
## stecken in Spielständen.
const UPGRADE_TIER_THRESHOLDS: Array[int] = [50, 100, 150, 200, 250, 500, 1000]
const UPGRADE_TIER_FLAVOR: Array[String] = [
	"Das halbe Dorf hilft inzwischen mit.",
	"Man nennt es jetzt ein Familienunternehmen.",
	"Die Nachbardörfer schicken Praktikanten.",
	"Es gibt eine Warteliste.",
	"Der König ist neidisch geworden.",
	"Die Legende arbeitet höchstselbst mit.",
	"Mythisch. Einfach mythisch.",
]

static var _generators: Array[GeneratorDef] = []
static var _generators_loaded := false
static var _dungeons: Array[DungeonDef] = []
static var _dungeons_loaded := false
static var _perma_upgrades: Array[PermaUpgradeDef] = []
static var _perma_upgrades_loaded := false
static var _saga_lines: Array[String] = []
static var _saga_lines_loaded := false
static var _items: Array[ItemDef] = []
static var _items_loaded := false
static var _recipes: Array[RecipeDef] = []
static var _recipes_loaded := false
static var _tales: Array[TaleDef] = []
static var _tales_loaded := false
static var _boons: Array[BoonDef] = []
static var _boons_loaded := false
static var _classes: Array[ClassDef] = []
static var _classes_loaded := false
static var _generator_upgrades: Array[GeneratorUpgradeDef] = []
static var _generator_upgrades_loaded := false


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


static func items() -> Array[ItemDef]:
	if not _items_loaded:
		_items = _load_items(ITEMS_PATH)
		_items_loaded = true
	return _items


static func item(id: String) -> ItemDef:
	for def in items():
		if def.id == id:
			return def
	return null


static func generator_upgrades() -> Array[GeneratorUpgradeDef]:
	if not _generator_upgrades_loaded:
		_generator_upgrades = _load_generator_upgrades(GENERATOR_UPGRADES_PATH)
		_generator_upgrades.append_array(_generate_upgrade_tiers())
		_generator_upgrades_loaded = true
	return _generator_upgrades


## Erzeugt die hohen Staffeln (×2 ab 50/100/.../1000 Stück) für jeden
## Generator. Kosten ankern am Preis des Generators an der Schwelle –
## wer dort ankommt, kann sich den Ausbau bald leisten.
static func _generate_upgrade_tiers() -> Array[GeneratorUpgradeDef]:
	var result: Array[GeneratorUpgradeDef] = []
	for generator_def in generators():
		for i in UPGRADE_TIER_THRESHOLDS.size():
			var threshold := UPGRADE_TIER_THRESHOLDS[i]
			var def := GeneratorUpgradeDef.new()
			def.id = "%s_tier_%d" % [generator_def.id, threshold]
			def.generator_id = generator_def.id
			def.display_name = "%s: Ausbaustufe %d" % [generator_def.display_name, i + 3]
			def.flavor = UPGRADE_TIER_FLAVOR[i % UPGRADE_TIER_FLAVOR.size()]
			def.cost = generator_def.base_cost * pow(generator_def.cost_growth, float(threshold)) * 10.0
			def.mult = 2.0
			def.unlock_at_owned = threshold
			var problems := def.validate()
			if not problems.is_empty():
				push_error("ContentDB: generierter Ausbau '%s' ungültig: %s" % [def.id, ", ".join(problems)])
				continue
			result.append(def)
	return result


static func generator_upgrade(id: String) -> GeneratorUpgradeDef:
	for def in generator_upgrades():
		if def.id == id:
			return def
	return null


static func recipes() -> Array[RecipeDef]:
	if not _recipes_loaded:
		_recipes = _load_recipes(RECIPES_PATH)
		_recipes_loaded = true
	return _recipes


static func recipe(id: String) -> RecipeDef:
	for def in recipes():
		if def.id == id:
			return def
	return null


static func tales() -> Array[TaleDef]:
	if not _tales_loaded:
		_tales = _load_tales(TALES_PATH)
		_tales_loaded = true
	return _tales


static func tale(id: String) -> TaleDef:
	for def in tales():
		if def.id == id:
			return def
	return null


static func boons() -> Array[BoonDef]:
	if not _boons_loaded:
		_boons = _load_boons(BOONS_PATH)
		_boons_loaded = true
	return _boons


static func boon(id: String) -> BoonDef:
	for def in boons():
		if def.id == id:
			return def
	return null


static func classes() -> Array[ClassDef]:
	if not _classes_loaded:
		_classes = _load_classes(CLASSES_PATH)
		_classes_loaded = true
	return _classes


static func class_def(id: String) -> ClassDef:
	for def in classes():
		if def.id == id:
			return def
	return null


static func perma_upgrades() -> Array[PermaUpgradeDef]:
	if not _perma_upgrades_loaded:
		_perma_upgrades = _load_perma_upgrades(PERMA_UPGRADES_PATH)
		_perma_upgrades_loaded = true
	return _perma_upgrades


static func perma_upgrade(id: String) -> PermaUpgradeDef:
	for def in perma_upgrades():
		if def.id == id:
			return def
	return null


## Barden-Zitate für die Prestige-Momente; eskalieren mit der Anzahl
## der Nacherzählungen, die letzte Zeile trägt alles darüber hinaus.
static func saga_line(retelling: int) -> String:
	if not _saga_lines_loaded:
		_saga_lines = _load_saga_lines(SAGA_LINES_PATH)
		_saga_lines_loaded = true
	if _saga_lines.is_empty():
		return ""
	return _saga_lines[clampi(retelling, 0, _saga_lines.size() - 1)]


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
	# Querverweis-Prüfungen: unlocked_by muss auf einen existierenden
	# Dungeon zeigen, Drop-Tabellen auf existierende Items.
	for def in result:
		if not def.unlocked_by.is_empty() and not seen_ids.has(def.unlocked_by):
			push_error("ContentDB: Dungeon '%s' verweist auf unbekannten Dungeon '%s'" % [def.id, def.unlocked_by])
		for table: Array in [def.drops, def.boss_drops]:
			for entry: Variant in table:
				var item_id := str(entry.get("item_id", ""))
				if item(item_id) == null:
					push_error("ContentDB: Dungeon '%s' droppt unbekanntes Item '%s'" % [def.id, item_id])
	return result


static func _load_generator_upgrades(path: String) -> Array[GeneratorUpgradeDef]:
	var result: Array[GeneratorUpgradeDef] = []
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
		var def := GeneratorUpgradeDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Ausbau '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Ausbau-ID '%s'" % def.id)
			continue
		if generator(def.generator_id) == null:
			push_error("ContentDB: Ausbau '%s' gehört zu unbekanntem Generator '%s'" % [def.id, def.generator_id])
			continue
		seen_ids[def.id] = true
		result.append(def)
	return result


static func _load_recipes(path: String) -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
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
		var def := RecipeDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Rezept '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Rezept-ID '%s'" % def.id)
			continue
		seen_ids[def.id] = true
		result.append(def)
	# Querverweise: Material muss existieren, und jedes Rezept, das
	# nicht von Anfang an bekannt ist, braucht ein gleichnamiges
	# Rezept-Item, über das es droppen kann.
	for def in result:
		for item_id: String in def.cost_items:
			if item(item_id) == null:
				push_error("ContentDB: Rezept '%s' braucht unbekanntes Material '%s'" % [def.id, item_id])
		if not def.known_from_start:
			var teach := item(def.id)
			if teach == null or not teach.is_recipe():
				push_error("ContentDB: Rezept '%s' ist nicht lernbar (kein Rezept-Item)" % def.id)
	# Gegenrichtung: jedes Rezept-Item muss ein echtes Rezept lehren.
	for item_def in items():
		if item_def.is_recipe() and not seen_ids.has(item_def.id):
			push_error("ContentDB: Rezept-Item '%s' lehrt ein unbekanntes Rezept" % item_def.id)
	return result


static func _load_boons(path: String) -> Array[BoonDef]:
	var result: Array[BoonDef] = []
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
		var def := BoonDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Segen '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Segen-ID '%s'" % def.id)
			continue
		seen_ids[def.id] = true
		result.append(def)
	return result


static func _load_classes(path: String) -> Array[ClassDef]:
	var result: Array[ClassDef] = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ContentDB: %s fehlt oder ist leer" % path)
		return result
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Array:
		push_error("ContentDB: %s ist kein gültiges JSON-Array" % path)
		return result
	var seen_ids := {}
	var has_starter := false
	for entry: Variant in parsed:
		if not entry is Dictionary:
			push_error("ContentDB: Eintrag in %s ist kein Objekt: %s" % [path, entry])
			continue
		var def := ClassDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Klasse '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Klassen-ID '%s'" % def.id)
			continue
		# Querverweise: Freischalt-Erzählungen und Start-Segen müssen
		# existieren, sonst wäre die Klasse unerreichbar oder kaputt.
		var broken := false
		for tale_id: String in def.unlock_tales:
			if tale(tale_id) == null:
				push_error("ContentDB: Klasse '%s' verlangt unbekannte Erzählung '%s'" % [def.id, tale_id])
				broken = true
		for boon_id: String in def.start_boons:
			if boon(boon_id) == null:
				push_error("ContentDB: Klasse '%s' startet mit unbekanntem Segen '%s'" % [def.id, boon_id])
				broken = true
		if broken:
			continue
		if def.is_starter():
			has_starter = true
		seen_ids[def.id] = true
		result.append(def)
	if not result.is_empty() and not has_starter:
		push_error("ContentDB: keine Starter-Klasse definiert – der Einstieg wäre gesperrt")
	return result


static func _load_tales(path: String) -> Array[TaleDef]:
	var result: Array[TaleDef] = []
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
		var def := TaleDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Erzählung '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Erzählungs-ID '%s'" % def.id)
			continue
		if not def.dungeon_id.is_empty() and dungeon(def.dungeon_id) == null:
			push_error("ContentDB: Erzählung '%s' verweist auf unbekannten Dungeon '%s'" % [def.id, def.dungeon_id])
			continue
		seen_ids[def.id] = true
		result.append(def)
	return result


static func _load_items(path: String) -> Array[ItemDef]:
	var result: Array[ItemDef] = []
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
		var def := ItemDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Item '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Item-ID '%s'" % def.id)
			continue
		seen_ids[def.id] = true
		result.append(def)
	return result


static func _load_perma_upgrades(path: String) -> Array[PermaUpgradeDef]:
	var result: Array[PermaUpgradeDef] = []
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
		var def := PermaUpgradeDef.from_dict(entry)
		var problems := def.validate()
		if not problems.is_empty():
			push_error("ContentDB: Perma-Upgrade '%s' ungültig: %s" % [def.id, ", ".join(problems)])
			continue
		if seen_ids.has(def.id):
			push_error("ContentDB: doppelte Perma-Upgrade-ID '%s'" % def.id)
			continue
		seen_ids[def.id] = true
		result.append(def)
	return result


static func _load_saga_lines(path: String) -> Array[String]:
	var result: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("ContentDB: %s fehlt oder ist leer" % path)
		return result
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Array:
		push_error("ContentDB: %s ist kein gültiges JSON-Array" % path)
		return result
	for entry: Variant in parsed:
		if entry is String and not str(entry).is_empty():
			result.append(str(entry))
		else:
			push_error("ContentDB: Saga-Zeile in %s ist kein Text: %s" % [path, entry])
	return result
