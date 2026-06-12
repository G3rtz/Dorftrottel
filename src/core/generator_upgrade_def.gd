class_name GeneratorUpgradeDef
extends RefCounted

## Ein einmaliger Dorf-Ausbau: multipliziert die Rate eines Generators.
## Schaltet sich frei, sobald genug Stück des Generators besessen
## werden – der klassische "Kauf mich!"-Moment des Genres.
## Gehört zur village-Sektion und resettet beim Prestige.

var id: String = ""
var generator_id: String = ""
var display_name: String = ""
var flavor: String = ""
var cost: float = 0.0
var mult: float = 1.0
var unlock_at_owned: int = 0


static func from_dict(data: Dictionary) -> GeneratorUpgradeDef:
	var def := GeneratorUpgradeDef.new()
	def.id = str(data.get("id", ""))
	def.generator_id = str(data.get("generator_id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.cost = float(data.get("cost", 0.0))
	def.mult = float(data.get("mult", 1.0))
	def.unlock_at_owned = int(data.get("unlock_at_owned", 0))
	return def


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if generator_id.is_empty():
		problems.append("generator_id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if cost <= 0.0:
		problems.append("cost muss > 0 sein")
	if mult <= 1.0:
		problems.append("mult muss > 1 sein, sonst ist der Ausbau sinnlos")
	if unlock_at_owned < 0:
		problems.append("unlock_at_owned muss >= 0 sein")
	return problems
