class_name TalentDef
extends RefCounted

## Ein Knoten in einem Talentbaum (Hero oder Base/Dorf, siehe GDD §3).
## Mehrstufig wie der Perma-Baum, aber bezahlt mit Talentpunkten statt
## Liedfragmenten. "requires" verkettet Knoten zu einem Baum: ohne
## mindestens eine Stufe im Vorgänger bleibt ein Knoten gesperrt.

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var effect: String = ""
var amount_per_level: float = 0.0
var max_level: int = 1
var base_cost_points: int = 1
var cost_growth_points: int = 0
var requires: String = ""


static func from_dict(data: Dictionary) -> TalentDef:
	var def := TalentDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.effect = str(data.get("effect", ""))
	def.amount_per_level = float(data.get("amount_per_level", 0.0))
	def.max_level = int(data.get("max_level", 1))
	def.base_cost_points = int(data.get("base_cost_points", 1))
	def.cost_growth_points = int(data.get("cost_growth_points", 0))
	def.requires = str(data.get("requires", ""))
	return def


## allowed_effects kommt von ContentDB – Hero- und Base-Baum erlauben
## unterschiedliche Effekte (docken an hero_stats() bzw.
## production_per_second()/manual_work_amount() an).
func validate(allowed_effects: Array[String]) -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if not allowed_effects.has(effect):
		problems.append("unbekannter Effekt '%s'" % effect)
	if amount_per_level <= 0.0:
		problems.append("amount_per_level muss > 0 sein")
	if max_level <= 0:
		problems.append("max_level muss > 0 sein")
	if base_cost_points <= 0:
		problems.append("base_cost_points muss > 0 sein")
	if cost_growth_points < 0:
		problems.append("cost_growth_points darf nicht negativ sein")
	if requires == id and not id.is_empty():
		problems.append("ein Talent kann nicht sein eigener Vorgänger sein")
	return problems


## Punktekosten für die nächste Stufe bei aktuellem Level (0-basiert).
func cost_for(level: int) -> int:
	return base_cost_points + cost_growth_points * level
