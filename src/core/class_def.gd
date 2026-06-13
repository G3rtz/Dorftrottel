class_name ClassDef
extends RefCounted

## Eine Klasse = eine Version der Sage. Derselbe Dorftrottel, von
## verschiedenen Barden anders erzählt. Klassen sind perma ("im Hirn")
## und werden über Tavernenerzählungen freigeschaltet – die
## Freischaltung ist rein aus tales_earned abgeleitet, nichts Extra zu
## speichern.
##
## Mechanisch bewusst schlank gehalten (GDD-Scope-Warnung): Klassen
## sind Helden-Stat-Multiplikatoren plus optionale Start-Segen, die das
## bestehende Boon-System wiederverwenden – keine neue Kampfmechanik.

var id: String = ""
var display_name: String = ""
var flavor: String = ""
## Freischaltung: ALLE diese Erzählungen müssen verdient sein UND die
## Gesamtzahl >= unlock_tale_count. Leer + 0 = von Anfang an offen.
var unlock_tales: Array = []
var unlock_tale_count: int = 0
var hp_mult: float = 1.0
var atk_mult: float = 1.0
## Segen (boon_ids), die ein Run dieser Klasse von Beginn an mitbringt.
var start_boons: Array = []


static func from_dict(data: Dictionary) -> ClassDef:
	var def := ClassDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.unlock_tales = data.get("unlock_tales", [])
	def.unlock_tale_count = int(data.get("unlock_tale_count", 0))
	def.hp_mult = float(data.get("hp_mult", 1.0))
	def.atk_mult = float(data.get("atk_mult", 1.0))
	def.start_boons = data.get("start_boons", [])
	return def


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if flavor.is_empty():
		problems.append("flavor fehlt – die Sage IST die Klasse")
	if hp_mult <= 0.0:
		problems.append("hp_mult muss > 0 sein")
	if atk_mult <= 0.0:
		problems.append("atk_mult muss > 0 sein")
	if unlock_tale_count < 0:
		problems.append("unlock_tale_count muss >= 0 sein")
	return problems


## Von Anfang an verfügbar (die kanonische Sage)?
func is_starter() -> bool:
	return unlock_tales.is_empty() and unlock_tale_count <= 0


## Ist die Klasse mit den bisher verdienten Erzählungen freigeschaltet?
## tales_earned: das Dictionary aus GameState (tale_id -> true).
func is_unlocked_by(tales_earned: Dictionary) -> bool:
	if tales_earned.size() < unlock_tale_count:
		return false
	for tale_id: String in unlock_tales:
		if not tales_earned.has(tale_id):
			return false
	return true
