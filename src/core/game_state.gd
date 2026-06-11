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

# hero-Sektion: resettet beim Prestige.
var hero_hp_level := 0
var hero_atk_level := 0

# perma-Sektion: überlebt das Prestige ("alles im Hirn bleibt").
var dungeons_cleared := {}  # dungeon_id -> true

# meta-Sektion.
var total_playtime := 0.0
var prestige_count := 0
var runs_completed := 0


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


## Heldenwerte aus Basis + Training. Der einzige Ort, an dem Werte für
## Runs berechnet werden – Talente, Ausrüstung und Perma-Boni docken
## später hier an (analog zu production_per_second für die Idle-Seite).
func hero_stats() -> Dictionary:
	return {
		"hp": BigNum.from_float(Balance.HERO_BASE_HP + Balance.HERO_HP_PER_TRAINING * float(hero_hp_level)),
		"atk": BigNum.from_float(Balance.HERO_BASE_ATK + Balance.HERO_ATK_PER_TRAINING * float(hero_atk_level)),
	}


func training_level(kind: String) -> int:
	return hero_hp_level if kind == "hp" else hero_atk_level


func training_cost(kind: String) -> BigNum:
	var level := training_level(kind)
	var log_growth := log(Balance.TRAINING_COST_GROWTH) / log(10.0)
	return BigNum.from_float(Balance.TRAINING_BASE_COST).mul(BigNum.from_log10(float(level) * log_growth))


## v1-Brücke "Idle finanziert Runs": Gold gegen permanente (bis zum
## Prestige) Heldenwerte.
func train(kind: String) -> bool:
	if kind != "hp" and kind != "atk":
		return false
	if not spend_resource(Balance.PRIMARY_RESOURCE, training_cost(kind)):
		return false
	if kind == "hp":
		hero_hp_level += 1
	else:
		hero_atk_level += 1
	return true


func is_dungeon_unlocked(def: DungeonDef) -> bool:
	return def.unlocked_by.is_empty() or dungeons_cleared.has(def.unlocked_by)


## Verbucht das Ergebnis eines beendeten Runs: Beute bleibt immer
## (auch bei Tod/Flucht), nur der Sieg schaltet den Dungeon dauerhaft
## frei – das ist die "im Hirn"-Regel aus dem GDD.
func bank_run_result(result: Dictionary) -> void:
	var gold: BigNum = result.get("gold", BigNum.zero())
	if not gold.is_zero():
		add_resource(Balance.PRIMARY_RESOURCE, gold)
	if result.get("victory", false):
		dungeons_cleared[str(result.get("dungeon_id", ""))] = true
		runs_completed += 1


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
		"hero": {
			"hp_level": hero_hp_level,
			"atk_level": hero_atk_level,
		},
		"perma": {
			"dungeons_cleared": dungeons_cleared.duplicate(),
		},
		"meta": {
			"total_playtime": total_playtime,
			"prestige_count": prestige_count,
			"runs_completed": runs_completed,
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
	var hero: Dictionary = data.get("hero", {})
	state.hero_hp_level = int(hero.get("hp_level", 0))
	state.hero_atk_level = int(hero.get("atk_level", 0))
	var perma: Dictionary = data.get("perma", {})
	var cleared: Dictionary = perma.get("dungeons_cleared", {})
	for id: String in cleared:
		state.dungeons_cleared[id] = true
	var meta: Dictionary = data.get("meta", {})
	state.total_playtime = float(meta.get("total_playtime", 0.0))
	state.prestige_count = int(meta.get("prestige_count", 0))
	state.runs_completed = int(meta.get("runs_completed", 0))
	return state
