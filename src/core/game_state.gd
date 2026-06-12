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
var inventory := {}        # item_id -> int (Trophäen; vergänglich, weg beim Prestige)

# hero-Sektion: resettet beim Prestige.
var hero_hp_level := 0
var hero_atk_level := 0
var equipment := {}  # slot -> recipe_id (geschmiedete Ausrüstung; vergänglich)

# perma-Sektion: überlebt das Prestige ("alles im Hirn bleibt").
var dungeons_cleared := {}  # dungeon_id -> true
var fame := BigNum.zero()   # Ruhm / Legendenpunkte (Prestige-Währung)
var perma_levels := {}      # perma_upgrade_id -> int
var song_fragments := {}    # item_id -> int (Liedfragmente, Vorstufe zu Klassen)
var recipes_known := {}     # recipe_id -> true (gelerntes Schmiedewissen)

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
	if resource_id == Balance.PRIMARY_RESOURCE:
		total = total.mul(BigNum.from_float(1.0 + perma_bonus("gold_mult")))
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
	var hp := Balance.HERO_BASE_HP + Balance.HERO_HP_PER_TRAINING * float(hero_hp_level)
	var atk := Balance.HERO_BASE_ATK + Balance.HERO_ATK_PER_TRAINING * float(hero_atk_level)
	for slot: String in equipment:
		var recipe_def := ContentDB.recipe(str(equipment[slot]))
		if recipe_def != null:
			hp += recipe_def.hp_bonus
			atk += recipe_def.atk_bonus
	return {
		"hp": BigNum.from_float(hp * (1.0 + perma_bonus("hero_hp_mult"))),
		"atk": BigNum.from_float(atk * (1.0 + perma_bonus("hero_atk_mult"))),
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


func is_recipe_known(recipe_id: String) -> bool:
	var def := ContentDB.recipe(recipe_id)
	if def == null:
		return false
	return def.known_from_start or recipes_known.has(recipe_id)


func is_equipped(recipe_id: String) -> bool:
	var def := ContentDB.recipe(recipe_id)
	return def != null and str(equipment.get(def.slot, "")) == recipe_id


func can_craft(recipe_id: String) -> bool:
	var def := ContentDB.recipe(recipe_id)
	if def == null or not is_recipe_known(recipe_id) or is_equipped(recipe_id):
		return false
	if get_resource(Balance.PRIMARY_RESOURCE).lt(BigNum.from_float(def.cost_gold)):
		return false
	for item_id: String in def.cost_items:
		if item_count(item_id) < int(def.cost_items[item_id]):
			return false
	return true


## Schmieden: zahlt Gold + Material und legt das Stück in seinen Slot.
## Das alte Stück im Slot ist damit Geschichte (kein Lager – v1).
func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	var def := ContentDB.recipe(recipe_id)
	spend_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(def.cost_gold))
	for item_id: String in def.cost_items:
		var needed := int(def.cost_items[item_id])
		inventory[item_id] = item_count(item_id) - needed
		if inventory[item_id] == 0:
			inventory.erase(item_id)
	equipment[def.slot] = recipe_id
	return true


func is_dungeon_unlocked(def: DungeonDef) -> bool:
	return def.unlocked_by.is_empty() or dungeons_cleared.has(def.unlocked_by)


## Verbucht das Ergebnis eines beendeten Runs: Beute (Gold + Items)
## bleibt immer (auch bei Tod/Flucht), nur der Sieg schaltet den
## Dungeon dauerhaft frei – das ist die "im Hirn"-Regel aus dem GDD.
func bank_run_result(result: Dictionary) -> void:
	var gold: BigNum = result.get("gold", BigNum.zero())
	if not gold.is_zero():
		add_resource(Balance.PRIMARY_RESOURCE, gold)
	var items: Dictionary = result.get("items", {})
	for item_id: String in items:
		add_item(item_id, int(items[item_id]))
	if result.get("victory", false):
		dungeons_cleared[str(result.get("dungeon_id", ""))] = true
		runs_completed += 1


## Routet einen Drop in die richtige Welt: Trophäen ins (vergängliche)
## Dorf-Inventar, Liedfragmente und Rezept-Wissen in die perma-Sektion.
func add_item(item_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	var def := ContentDB.item(item_id)
	if def == null:
		push_error("GameState: unbekanntes Item '%s'" % item_id)
		return
	if def.is_song_fragment():
		song_fragments[item_id] = fragment_count(item_id) + count
	elif def.is_recipe():
		# Wissen stapelt nicht – Duplikate verpuffen (v1).
		recipes_known[item_id] = true
	else:
		inventory[item_id] = item_count(item_id) + count


func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func fragment_count(item_id: String) -> int:
	return int(song_fragments.get(item_id, 0))


## Trophäen beim Krämer versilbern. Gibt die tatsächlich verkaufte
## Anzahl zurück; der Erlös zählt als verdient (Lifetime → Ruhm).
func sell_item(item_id: String, count: int = 1) -> int:
	var def := ContentDB.item(item_id)
	if def == null or def.gold_value <= 0.0 or count <= 0:
		return 0
	var sold := mini(count, item_count(item_id))
	if sold <= 0:
		return 0
	inventory[item_id] = item_count(item_id) - sold
	if inventory[item_id] == 0:
		inventory.erase(item_id)
	add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(def.gold_value * float(sold)))
	return sold


## Summierter Effektwert aller Perma-Upgrades eines Typs
## (z.B. "gold_mult" -> 0.5 bei zwei Stufen à 0.25).
func perma_bonus(effect: String) -> float:
	var total := 0.0
	for def in ContentDB.perma_upgrades():
		if def.effect == effect:
			total += def.amount_per_level * float(perma_level(def.id))
	return total


func perma_level(upgrade_id: String) -> int:
	return int(perma_levels.get(upgrade_id, 0))


func perma_cost(upgrade_id: String) -> BigNum:
	var def := ContentDB.perma_upgrade(upgrade_id)
	if def == null:
		return BigNum.zero()
	return def.cost_for(perma_level(upgrade_id))


func buy_perma(upgrade_id: String) -> bool:
	var def := ContentDB.perma_upgrade(upgrade_id)
	if def == null:
		return false
	var cost := perma_cost(upgrade_id)
	if fame.lt(cost):
		return false
	fame = fame.sub(cost)
	perma_levels[upgrade_id] = perma_level(upgrade_id) + 1
	return true


## Ruhm, den die aktuelle Sage beim Prestige einbringen würde.
## Basis ist das je verdiente Gold dieser Sage (nicht der Bestand) –
## Ausgeben kostet keinen Ruhm.
func pending_fame() -> BigNum:
	var lifetime := get_lifetime(Balance.PRIMARY_RESOURCE)
	var ratio := lifetime.div(BigNum.from_float(Balance.FAME_BASE_GOLD))
	if ratio.cmp(BigNum.one()) < 0:
		return BigNum.zero()
	return ratio.square_root().floored()


func can_prestige() -> bool:
	return pending_fame().cmp(BigNum.one()) >= 0


## Die Barden erzählen die Sage neu: village- und hero-Sektion werden
## geleert, perma und meta bleiben. Gibt einen Bericht zurück, oder {}
## wenn noch nicht genug Ruhm zusammengekommen ist.
func prestige() -> Dictionary:
	var gained := pending_fame()
	if gained.cmp(BigNum.one()) < 0:
		return {}
	fame = fame.add(gained)
	prestige_count += 1
	# Ablegbares zurücksetzen (village + hero). Liedfragmente, Rezepte
	# und Dungeon-Wissen bleiben – die stecken in der perma-Sektion.
	resources = {}
	lifetime_earned = {}
	generators = {}
	inventory = {}
	hero_hp_level = 0
	hero_atk_level = 0
	equipment = {}
	# Startboni der neuen Sage ("beschleunigen, nie skippen").
	var start_gold := perma_bonus("start_gold")
	if start_gold > 0.0:
		add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(start_gold))
	return {
		"fame_gained": gained,
		"fame_total": fame,
		"prestige_count": prestige_count,
	}


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
			"inventory": inventory.duplicate(),
		},
		"hero": {
			"hp_level": hero_hp_level,
			"atk_level": hero_atk_level,
			"equipment": equipment.duplicate(),
		},
		"perma": {
			"dungeons_cleared": dungeons_cleared.duplicate(),
			"fame": fame.to_dict(),
			"perma_levels": perma_levels.duplicate(),
			"song_fragments": song_fragments.duplicate(),
			"recipes_known": recipes_known.duplicate(),
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
	var serialized_inventory: Dictionary = village.get("inventory", {})
	for id: String in serialized_inventory:
		state.inventory[id] = int(serialized_inventory[id])
	var hero: Dictionary = data.get("hero", {})
	state.hero_hp_level = int(hero.get("hp_level", 0))
	state.hero_atk_level = int(hero.get("atk_level", 0))
	var serialized_equipment: Dictionary = hero.get("equipment", {})
	for slot: String in serialized_equipment:
		state.equipment[slot] = str(serialized_equipment[slot])
	var perma: Dictionary = data.get("perma", {})
	var cleared: Dictionary = perma.get("dungeons_cleared", {})
	for id: String in cleared:
		state.dungeons_cleared[id] = true
	state.fame = BigNum.from_dict(perma.get("fame", {}))
	var levels: Dictionary = perma.get("perma_levels", {})
	for id: String in levels:
		state.perma_levels[id] = int(levels[id])
	var fragments: Dictionary = perma.get("song_fragments", {})
	for id: String in fragments:
		state.song_fragments[id] = int(fragments[id])
	var known: Dictionary = perma.get("recipes_known", {})
	for id: String in known:
		state.recipes_known[id] = true
	var meta: Dictionary = data.get("meta", {})
	state.total_playtime = float(meta.get("total_playtime", 0.0))
	state.prestige_count = int(meta.get("prestige_count", 0))
	state.runs_completed = int(meta.get("runs_completed", 0))
	return state
