class_name TaleDef
extends RefCounted

## Eine Tavernenerzählung: eine Tat, die man sich abends beim
## Tavernenwirt erzählt. Qualitative Meilensteine statt grindbarer
## Währung – einmal verdient, für immer im Hirn (perma). Klassen
## werden später bestimmte Erzählungen voraussetzen.
##
## Die Bedingung ist eine reine Funktion über das Run-Ergebnis:
## - "victory":      Sieg (optional in einem bestimmten Dungeon)
## - "no_damage":    Sieg ohne einen einzigen Treffer
## - "all_elite":    Sieg, jede Gabelung führte in die Schatzkammer
## - "speed":        Sieg in höchstens max_ticks Kampf-Ticks
## - "no_abilities": Sieg ohne Zuschlagen/Verschnaufen (reines Zusehen)
## - "fled":         Flucht (der taktische Rückzug)
## - "defeat":       Niederlage (auch das gibt eine Geschichte)

const KNOWN_TYPES: Array[String] = [
	"victory", "no_damage", "all_elite", "speed", "no_abilities", "fled", "defeat",
]

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var type: String = ""
## Leer = gilt für jeden Dungeon.
var dungeon_id: String = ""
var max_ticks: int = 0


static func from_dict(data: Dictionary) -> TaleDef:
	var def := TaleDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.type = str(data.get("type", ""))
	def.dungeon_id = str(data.get("dungeon_id", ""))
	def.max_ticks = int(data.get("max_ticks", 0))
	return def


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if flavor.is_empty():
		problems.append("flavor fehlt – die Erzählung IST die Belohnung")
	if not KNOWN_TYPES.has(type):
		problems.append("unbekannter Typ '%s'" % type)
	if type == "speed" and max_ticks <= 0:
		problems.append("speed braucht max_ticks > 0")
	return problems


## Prüft die Tat gegen ein Run-Ergebnis (RunState.result()).
func matches(result: Dictionary) -> bool:
	if not dungeon_id.is_empty() and str(result.get("dungeon_id", "")) != dungeon_id:
		return false
	var victory: bool = result.get("victory", false)
	match type:
		"victory":
			return victory
		"no_damage":
			return victory and not bool(result.get("took_damage", true))
		"all_elite":
			var doors := int(result.get("doors_seen", 0))
			return victory and doors > 0 and int(result.get("elite_chosen", 0)) == doors
		"speed":
			return victory and int(result.get("ticks", 2147483647)) <= max_ticks
		"no_abilities":
			return victory and int(result.get("strikes_used", 1)) == 0 \
				and int(result.get("breathers_used", 1)) == 0
		"fled":
			return int(result.get("status", -1)) == RunState.Status.FLED
		"defeat":
			return int(result.get("status", -1)) == RunState.Status.DEFEAT
	return false
