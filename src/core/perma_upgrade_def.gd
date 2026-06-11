class_name PermaUpgradeDef
extends RefCounted

## Ein Perma-Baum-Eintrag: wird mit Ruhm bezahlt und überlebt das
## Prestige. Designregel aus dem GDD: beschleunigen, nie skippen –
## erlaubte Effekte sind deshalb nur Multiplikatoren und kleine
## Startboni, niemals "überspringe X".

const KNOWN_EFFECTS: Array[String] = ["gold_mult", "hero_hp_mult", "hero_atk_mult", "start_gold"]

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var effect: String = ""
var amount_per_level: float = 0.0
var base_cost: float = 0.0
var cost_growth: float = 1.0


static func from_dict(data: Dictionary) -> PermaUpgradeDef:
	var def := PermaUpgradeDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.effect = str(data.get("effect", ""))
	def.amount_per_level = float(data.get("amount_per_level", 0.0))
	def.base_cost = float(data.get("base_cost", 0.0))
	def.cost_growth = float(data.get("cost_growth", 1.0))
	return def


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if not KNOWN_EFFECTS.has(effect):
		problems.append("unbekannter Effekt '%s'" % effect)
	if amount_per_level <= 0.0:
		problems.append("amount_per_level muss > 0 sein")
	if base_cost <= 0.0:
		problems.append("base_cost muss > 0 sein")
	if cost_growth < 1.0:
		problems.append("cost_growth muss >= 1 sein")
	return problems


## Ruhm-Kosten für die nächste Stufe bei aktuellem Level.
func cost_for(level: int) -> BigNum:
	var log_growth := log(cost_growth) / log(10.0)
	return BigNum.from_float(base_cost).mul(BigNum.from_log10(float(level) * log_growth))
