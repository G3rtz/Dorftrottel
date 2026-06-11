class_name GameState
extends RefCounted

## Der komplette Spielzustand als reine Logik – keine Nodes, keine Signale,
## keine UI. Dadurch headless testbar und unabhängig von der Engine-Schleife.
##
## Die Save-Struktur ist bereits in Sektionen aufgeteilt (village / hero /
## perma / meta), damit Dungeon-Runs, Talentbäume und Prestige später
## additiv andocken können, ohne das Format umzubauen.

var resources := {}        # resource_id -> BigNum (aktueller Bestand)
var lifetime_earned := {}  # resource_id -> BigNum (insgesamt je verdient; treibt Freischaltungen)
var generators := {}       # generator_id -> int (Anzahl besessen)
var total_playtime := 0.0
var prestige_count := 0


func get_resource(id: String) -> BigNum:
	return resources.get(id, BigNum.zero())


func get_lifetime(id: String) -> BigNum:
	return lifetime_earned.get(id, BigNum.zero())


func add_resource(id: String, amount: BigNum) -> void:
	if amount.signum() <= 0:
		return
	resources[id] = get_resource(id).add(amount)
	lifetime_earned[id] = get_lifetime(id).add(amount)


func spend_resource(id: String, amount: BigNum) -> bool:
	var current := get_resource(id)
	if current.lt(amount):
		return false
	resources[id] = current.sub(amount)
	return true


func owned(generator_id: String) -> int:
	return int(generators.get(generator_id, 0))


func production_per_second(resource_id: String) -> BigNum:
	var total := BigNum.zero()
	for def in ContentDB.generators():
		if def.resource_id == resource_id:
			total = total.add(def.rate_for(owned(def.id)))
	return total


## Buchung der Produktion in geschlossener Form (Rate * Zeit) – funktioniert
## für einen 0.1s-Tick genauso wie für 12h Offline-Zeit, ohne zu iterieren.
## Gibt die Zugewinne je Ressource zurück.
func advance(seconds: float, efficiency: float = 1.0) -> Dictionary:
	var gains := {}
	if seconds <= 0.0 or efficiency <= 0.0:
		return gains
	var factor := BigNum.from_float(seconds * efficiency)
	var resource_ids := {}
	for def in ContentDB.generators():
		resource_ids[def.resource_id] = true
	for resource_id: String in resource_ids:
		var rate := production_per_second(resource_id)
		if rate.is_zero():
			continue
		var gain := rate.mul(factor)
		add_resource(resource_id, gain)
		gains[resource_id] = gain
	return gains


func cost_of(generator_id: String, count: int = 1) -> BigNum:
	var def := ContentDB.generator(generator_id)
	if def == null:
		return BigNum.zero()
	return def.cost_for(owned(generator_id), count)


func buy_generator(generator_id: String, count: int = 1) -> bool:
	var def := ContentDB.generator(generator_id)
	if def == null or count <= 0:
		return false
	var cost := def.cost_for(owned(generator_id), count)
	if not spend_resource(def.resource_id, cost):
		return false
	generators[generator_id] = owned(generator_id) + count
	return true


## Sichtbar, sobald je genug von der Ressource verdient wurde (oder schon
## einer gekauft ist). Lifetime statt Bestand, damit Ausgeben nichts versteckt.
func is_generator_visible(def: GeneratorDef) -> bool:
	if owned(def.id) > 0:
		return true
	return get_lifetime(def.resource_id).gte(BigNum.from_float(def.unlock_at_lifetime))


## Offline-Fortschritt: gedeckelt und mit konfigurierbarem Wirkungsgrad.
## Negative Zeitdifferenzen (Systemuhr zurückgestellt) werden ignoriert.
static func apply_offline(state: GameState, elapsed_seconds: float) -> Dictionary:
	var credited: float = clampf(elapsed_seconds, 0.0, float(Balance.OFFLINE_CAP_SECONDS))
	var gains := state.advance(credited, Balance.OFFLINE_EFFICIENCY)
	return {
		"seconds": credited,
		"capped": elapsed_seconds > float(Balance.OFFLINE_CAP_SECONDS),
		"gains": gains,
	}


func to_dict() -> Dictionary:
	var serialized_resources := {}
	for id: String in resources:
		serialized_resources[id] = resources[id].to_dict()
	var serialized_lifetime := {}
	for id: String in lifetime_earned:
		serialized_lifetime[id] = lifetime_earned[id].to_dict()
	return {
		"village": {
			"resources": serialized_resources,
			"lifetime_earned": serialized_lifetime,
			"generators": generators.duplicate(),
		},
		"hero": {},
		"perma": {},
		"meta": {
			"total_playtime": total_playtime,
			"prestige_count": prestige_count,
		},
	}


static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	var village: Dictionary = data.get("village", {})
	var serialized_resources: Dictionary = village.get("resources", {})
	for id: String in serialized_resources:
		state.resources[id] = BigNum.from_dict(serialized_resources[id])
	var serialized_lifetime: Dictionary = village.get("lifetime_earned", {})
	for id: String in serialized_lifetime:
		state.lifetime_earned[id] = BigNum.from_dict(serialized_lifetime[id])
	var serialized_generators: Dictionary = village.get("generators", {})
	for id: String in serialized_generators:
		state.generators[id] = int(serialized_generators[id])
	var meta: Dictionary = data.get("meta", {})
	state.total_playtime = float(meta.get("total_playtime", 0.0))
	state.prestige_count = int(meta.get("prestige_count", 0))
	return state
