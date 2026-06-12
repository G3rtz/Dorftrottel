class_name ItemDef
extends RefCounted

## Definition eines Drops. Drei Welten, wie im GDD:
## - "trophy": vergängliche Beute, landet im Dorf-Inventar, wird
##   verkauft oder verschmiedet (Crafting-Material). Weg beim Prestige.
## - "song_fragment": Liedfragmente – "im Hirn", landen in der
##   perma-Sektion und überleben das Prestige. Vorstufe zu Klassen.
## - "recipe": Rezept-Wissen – "im Hirn", schaltet das gleichnamige
##   Rezept aus data/recipes.json dauerhaft frei.

const KNOWN_TYPES: Array[String] = ["trophy", "song_fragment", "recipe"]

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var type: String = ""
var gold_value: float = 0.0


static func from_dict(data: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.type = str(data.get("type", ""))
	def.gold_value = float(data.get("gold_value", 0.0))
	return def


func is_song_fragment() -> bool:
	return type == "song_fragment"


func is_recipe() -> bool:
	return type == "recipe"


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if not KNOWN_TYPES.has(type):
		problems.append("unbekannter Typ '%s'" % type)
	if type == "trophy" and gold_value <= 0.0:
		problems.append("Trophäen brauchen einen gold_value > 0")
	if gold_value < 0.0:
		problems.append("gold_value darf nicht negativ sein")
	return problems
