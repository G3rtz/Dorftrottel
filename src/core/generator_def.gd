class_name GeneratorDef
extends RefCounted

## Definition eines Dorf-Generators ("Dorfbewohner, der hilft").
## Wird aus res://data/generators.json geladen – Content ist Daten,
## kein Code.

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var resource_id: String = ""
var base_rate: float = 0.0
var base_cost: float = 0.0
var cost_growth: float = 1.0
var unlock_at_lifetime: float = 0.0


static func from_dict(data: Dictionary) -> GeneratorDef:
	var def := GeneratorDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.resource_id = str(data.get("resource_id", ""))
	def.base_rate = float(data.get("base_rate", 0.0))
	def.base_cost = float(data.get("base_cost", 0.0))
	def.cost_growth = float(data.get("cost_growth", 1.0))
	def.unlock_at_lifetime = float(data.get("unlock_at_lifetime", 0.0))
	return def


## Liefert eine Liste von Problemen; leer = gültig.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if resource_id.is_empty():
		problems.append("resource_id fehlt")
	if base_rate <= 0.0:
		problems.append("base_rate muss > 0 sein")
	if base_cost <= 0.0:
		problems.append("base_cost muss > 0 sein")
	if cost_growth < 1.0:
		problems.append("cost_growth muss >= 1 sein")
	if unlock_at_lifetime < 0.0:
		problems.append("unlock_at_lifetime muss >= 0 sein")
	return problems


## Gesamtkosten für `count` Stück, wenn bereits `owned` besessen werden.
## Geometrische Reihe: base * growth^owned * (growth^count - 1) / (growth - 1).
## Läuft über from_log10, damit growth^n auch bei riesigen n nicht als
## Float überläuft.
func cost_for(owned_count: int, count: int = 1) -> BigNum:
	if count <= 0:
		return BigNum.zero()
	var base := BigNum.from_float(base_cost)
	if is_equal_approx(cost_growth, 1.0):
		return base.mul(BigNum.from_float(float(count)))
	var log_growth := log(cost_growth) / log(10.0)
	var growth_owned := BigNum.from_log10(float(owned_count) * log_growth)
	var growth_count := BigNum.from_log10(float(count) * log_growth)
	var numerator := growth_count.sub(BigNum.one())
	var denominator := BigNum.from_float(cost_growth - 1.0)
	return base.mul(growth_owned).mul(numerator).div(denominator)


## Produktionsrate pro Sekunde bei `owned` Stück (noch ohne Multiplikatoren –
## Talente/Boosts docken später hier an).
func rate_for(owned_count: int) -> BigNum:
	if owned_count <= 0:
		return BigNum.zero()
	return BigNum.from_float(base_rate * float(owned_count))
