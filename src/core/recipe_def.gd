class_name RecipeDef
extends RefCounted

## Ein Schmiede-Rezept – die Brücke der "goldenen Regel": das Rezept
## kommt aus dem Dungeon (perma, "im Hirn"), Gold und Material aus
## Dorf und Beute. Das Ergebnis ist Ausrüstung in einem Slot –
## vergänglich, weg beim Prestige.

const KNOWN_SLOTS: Array[String] = ["weapon", "armor"]

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var slot: String = ""
var atk_bonus: float = 0.0
var hp_bonus: float = 0.0
var cost_gold: float = 0.0
var cost_items := {}  # item_id -> int
## Start-Rezepte kennt der Trottel ohne Drop – der frühe Einstieg
## ins Crafting.
var known_from_start := false


static func from_dict(data: Dictionary) -> RecipeDef:
	var def := RecipeDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.slot = str(data.get("slot", ""))
	def.atk_bonus = float(data.get("atk_bonus", 0.0))
	def.hp_bonus = float(data.get("hp_bonus", 0.0))
	def.cost_gold = float(data.get("cost_gold", 0.0))
	var costs: Dictionary = data.get("cost_items", {})
	for item_id: String in costs:
		def.cost_items[item_id] = int(costs[item_id])
	def.known_from_start = bool(data.get("known_from_start", false))
	return def


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if not KNOWN_SLOTS.has(slot):
		problems.append("unbekannter Slot '%s'" % slot)
	if atk_bonus <= 0.0 and hp_bonus <= 0.0:
		problems.append("Rezept ohne Bonus ist sinnlos")
	if atk_bonus < 0.0 or hp_bonus < 0.0 or cost_gold < 0.0:
		problems.append("negative Werte sind nicht erlaubt")
	if cost_gold <= 0.0 and cost_items.is_empty():
		problems.append("Rezept muss etwas kosten")
	for item_id: String in cost_items:
		if int(cost_items[item_id]) <= 0:
			problems.append("Materialmenge von '%s' muss > 0 sein" % item_id)
	return problems
