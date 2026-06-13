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
var generator_upgrades := {}  # upgrade_id -> true (Dorf-Ausbauten; weg beim Prestige)
var inventory := {}        # item_id -> int (Trophäen; vergänglich, weg beim Prestige)

# hero-Sektion: resettet beim Prestige.
var hero_hp_level := 0
var hero_atk_level := 0
var equipment := {}  # slot -> recipe_id (geschmiedete Ausrüstung; vergänglich)

# perma-Sektion: überlebt das Prestige ("alles im Hirn bleibt").
var dungeons_cleared := {}  # dungeon_id -> true
## Liedfragmente: DIE Prestige-Währung. Quellen: Prestige (die Barden
## dichten die Sage in Strophen) und Boss-Drops. Halten gibt passive
## Boni, Ausgeben füttert den Perma-Baum.
var fragments := BigNum.zero()
var perma_levels := {}      # perma_upgrade_id -> int
## Liederbuch: WELCHE Lieder je gefunden wurden (Sammlung, sinkt nie –
## Ausgeben verwebt Strophen, löscht aber kein gelerntes Lied).
var song_fragments := {}    # item_id -> int
var recipes_known := {}     # recipe_id -> true (gelerntes Schmiedewissen)
## Tavernenerzählungen: einmal verdiente Taten. Geschichten vergisst
## die Taverne nie – sie schalten Klassen frei.
var tales_earned := {}      # tale_id -> true
## Gewählte Klasse (Version der Sage). Welche Klassen freigeschaltet
## sind, ist rein aus tales_earned abgeleitet; nur die Auswahl wird
## gespeichert. Default: die kanonische Starter-Klasse.
var active_class := ""

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
			var rate := def.rate_for(owned(def.id))
			rate = rate.mul(BigNum.from_float(generator_multiplier(def.id)))
			total = total.add(rate)
	if resource_id == Balance.PRIMARY_RESOURCE:
		total = total.mul(BigNum.from_float(1.0 + perma_bonus("gold_mult")))
		total = total.mul(fragment_gold_multiplier())
	return total


## Ertrag eines "Arbeiten"-Klicks: Basis plus Anteil der laufenden
## Produktion (damit der Knopf nie bedeutungslos wird), multipliziert
## mit dem Perma-Buff. Der einzige Ort, an dem Klick-Ertrag berechnet
## wird – künftige Buffs docken hier an.
func manual_work_amount() -> BigNum:
	var amount := BigNum.from_float(Balance.MANUAL_WORK_AMOUNT)
	var share := production_per_second(Balance.PRIMARY_RESOURCE) \
		.mul(BigNum.from_float(Balance.WORK_PRODUCTION_SHARE))
	amount = amount.add(share)
	return amount.mul(BigNum.from_float(1.0 + perma_bonus("work_mult")))


func do_manual_work() -> BigNum:
	var amount := manual_work_amount()
	add_resource(Balance.PRIMARY_RESOURCE, amount)
	return amount


func max_affordable(generator_id: String) -> int:
	var def := ContentDB.generator(generator_id)
	if def == null:
		return 0
	return def.max_affordable(owned(generator_id), get_resource(def.resource_id))


## Passiv-Boni gehaltener Liedfragmente. Komplett in BigNum gerechnet,
## damit auch absurde Fragment-Mengen nicht als Float überlaufen.
func fragment_gold_multiplier() -> BigNum:
	return BigNum.one().add(fragments.mul(BigNum.from_float(Balance.FRAGMENT_GOLD_BONUS)))


func fragment_atk_multiplier() -> BigNum:
	return BigNum.one().add(fragments.mul(BigNum.from_float(Balance.FRAGMENT_ATK_BONUS)))


## Produkt aller gekauften Ausbauten eines Generators.
func generator_multiplier(generator_id: String) -> float:
	var mult := 1.0
	for def in ContentDB.generator_upgrades():
		if def.generator_id == generator_id and generator_upgrades.has(def.id):
			mult *= def.mult
	return mult


## Sichtbar/kaufbar, sobald genug Stück des Generators besessen werden
## und der Ausbau noch nicht gekauft ist.
func is_generator_upgrade_available(def: GeneratorUpgradeDef) -> bool:
	return not generator_upgrades.has(def.id) and owned(def.generator_id) >= def.unlock_at_owned


func buy_generator_upgrade(upgrade_id: String) -> bool:
	var def := ContentDB.generator_upgrade(upgrade_id)
	if def == null or not is_generator_upgrade_available(def):
		return false
	if not spend_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(def.cost)):
		return false
	generator_upgrades[upgrade_id] = true
	return true


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
## Runs berechnet werden – Ausrüstung, Perma-Boni, Liedfragmente und
## die gewählte Klasse docken hier an (analog zu production_per_second
## für die Idle-Seite).
func hero_stats() -> Dictionary:
	var hp := Balance.HERO_BASE_HP + Balance.HERO_HP_PER_TRAINING * float(hero_hp_level)
	var atk := Balance.HERO_BASE_ATK + Balance.HERO_ATK_PER_TRAINING * float(hero_atk_level)
	for slot: String in equipment:
		var recipe_def := ContentDB.recipe(str(equipment[slot]))
		if recipe_def != null:
			hp += recipe_def.hp_bonus
			atk += recipe_def.atk_bonus
	var cls := active_class_def()
	var cls_hp_mult := cls.hp_mult if cls != null else 1.0
	var cls_atk_mult := cls.atk_mult if cls != null else 1.0
	var atk_total := BigNum.from_float(atk * (1.0 + perma_bonus("hero_atk_mult")) * cls_atk_mult)
	return {
		"hp": BigNum.from_float(hp * (1.0 + perma_bonus("hero_hp_mult")) * cls_hp_mult),
		"atk": atk_total.mul(fragment_atk_multiplier()),
	}


## Die aktive Klasse, mit Rückfall auf die erste Starter-Klasse, wenn
## nichts (Gültiges) gewählt ist – so ist immer eine Sage erzählbar.
func active_class_def() -> ClassDef:
	var def := ContentDB.class_def(active_class)
	if def != null:
		return def
	for candidate in ContentDB.classes():
		if candidate.is_starter():
			return candidate
	return null


func is_class_unlocked(def: ClassDef) -> bool:
	return def != null and def.is_unlocked_by(tales_earned)


## Liste der freigeschalteten Klassen-IDs – abgeleitet, nicht gespeichert.
func unlocked_class_ids() -> Array[String]:
	var ids: Array[String] = []
	for def in ContentDB.classes():
		if is_class_unlocked(def):
			ids.append(def.id)
	return ids


## Klasse wählen – nur wenn freigeschaltet. Gibt Erfolg zurück.
func set_active_class(class_id: String) -> bool:
	var def := ContentDB.class_def(class_id)
	if def == null or not is_class_unlocked(def):
		return false
	active_class = class_id
	return true


## Start-Segen der aktiven Klasse (boon_ids) für den nächsten Run.
func active_class_start_boons() -> Array:
	var def := active_class_def()
	return def.start_boons.duplicate() if def != null else []


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
	# Einmal geschafft = für immer offen. Schützt alte Saves, wenn die
	# Kette nachträglich ein Glied dazwischen bekommt.
	if dungeons_cleared.has(def.id):
		return true
	return def.unlocked_by.is_empty() or dungeons_cleared.has(def.unlocked_by)


## Verbucht das Ergebnis eines beendeten Runs: Beute (Gold + Items)
## bleibt immer (auch bei Tod/Flucht), nur der Sieg schaltet den
## Dungeon dauerhaft frei – das ist die "im Hirn"-Regel aus dem GDD.
## Gibt die neu verdienten Tavernenerzählungen zurück.
func bank_run_result(result: Dictionary) -> Array[String]:
	var gold: BigNum = result.get("gold", BigNum.zero())
	if not gold.is_zero():
		add_resource(Balance.PRIMARY_RESOURCE, gold)
	var items: Dictionary = result.get("items", {})
	for item_id: String in items:
		add_item(item_id, int(items[item_id]))
	if result.get("victory", false):
		dungeons_cleared[str(result.get("dungeon_id", ""))] = true
		runs_completed += 1
	return _evaluate_tales(result)


func has_tale(tale_id: String) -> bool:
	return tales_earned.has(tale_id)


func tale_count() -> int:
	return tales_earned.size()


## Prüft alle noch offenen Taten gegen das Run-Ergebnis.
func _evaluate_tales(result: Dictionary) -> Array[String]:
	var new_tales: Array[String] = []
	for def in ContentDB.tales():
		if tales_earned.has(def.id):
			continue
		if def.matches(result):
			tales_earned[def.id] = true
			new_tales.append(def.id)
	return new_tales


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
		# Ins Liederbuch (Sammlung) UND in den Strophen-Pool (Währung).
		song_fragments[item_id] = fragment_count(item_id) + count
		fragments = fragments.add(BigNum.from_float(float(count)))
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
	if fragments.lt(cost):
		return false
	fragments = fragments.sub(cost)
	perma_levels[upgrade_id] = perma_level(upgrade_id) + 1
	return true


## Liedfragmente, die die Barden beim Prestige aus dieser Sage dichten
## würden. Basis ist das je verdiente Gold der Sage (nicht der
## Bestand) – Ausgeben kostet keine Strophen.
func pending_fragments() -> BigNum:
	var lifetime := get_lifetime(Balance.PRIMARY_RESOURCE)
	var ratio := lifetime.div(BigNum.from_float(Balance.FRAGMENT_BASE_GOLD))
	if ratio.cmp(BigNum.one()) < 0:
		return BigNum.zero()
	return ratio.square_root().floored()


func can_prestige() -> bool:
	return pending_fragments().cmp(BigNum.one()) >= 0


## Die Barden erzählen die Sage neu: village- und hero-Sektion werden
## geleert, perma und meta bleiben. Gibt einen Bericht zurück, oder {}
## wenn noch nicht genug Ruhm zusammengekommen ist.
func prestige() -> Dictionary:
	var gained := pending_fragments()
	if gained.cmp(BigNum.one()) < 0:
		return {}
	fragments = fragments.add(gained)
	prestige_count += 1
	# Ablegbares zurücksetzen (village + hero). Liedfragmente, Rezepte
	# und Dungeon-Wissen bleiben – die stecken in der perma-Sektion.
	resources = {}
	lifetime_earned = {}
	generators = {}
	generator_upgrades = {}
	inventory = {}
	hero_hp_level = 0
	hero_atk_level = 0
	equipment = {}
	# Startboni der neuen Sage ("beschleunigen, nie skippen").
	var start_gold := perma_bonus("start_gold")
	if start_gold > 0.0:
		add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(start_gold))
	return {
		"fragments_gained": gained,
		"fragments_total": fragments,
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
			"generator_upgrades": generator_upgrades.duplicate(),
			"inventory": inventory.duplicate(),
		},
		"hero": {
			"hp_level": hero_hp_level,
			"atk_level": hero_atk_level,
			"equipment": equipment.duplicate(),
		},
		"perma": {
			"dungeons_cleared": dungeons_cleared.duplicate(),
			"fragments": fragments.to_dict(),
			"perma_levels": perma_levels.duplicate(),
			"song_fragments": song_fragments.duplicate(),
			"recipes_known": recipes_known.duplicate(),
			"tales_earned": tales_earned.duplicate(),
			"active_class": active_class,
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
	var serialized_upgrades: Dictionary = village.get("generator_upgrades", {})
	for id: String in serialized_upgrades:
		state.generator_upgrades[id] = true
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
	# "fame" als Fallback: Saves der Version 1 nannten die Währung Ruhm.
	state.fragments = BigNum.from_dict(perma.get("fragments", perma.get("fame", {})))
	var levels: Dictionary = perma.get("perma_levels", {})
	for id: String in levels:
		state.perma_levels[id] = int(levels[id])
	var fragments: Dictionary = perma.get("song_fragments", {})
	for id: String in fragments:
		state.song_fragments[id] = int(fragments[id])
	var known: Dictionary = perma.get("recipes_known", {})
	for id: String in known:
		state.recipes_known[id] = true
	var earned_tales: Dictionary = perma.get("tales_earned", {})
	for id: String in earned_tales:
		state.tales_earned[id] = true
	state.active_class = str(perma.get("active_class", ""))
	var meta: Dictionary = data.get("meta", {})
	state.total_playtime = float(meta.get("total_playtime", 0.0))
	state.prestige_count = int(meta.get("prestige_count", 0))
	state.runs_completed = int(meta.get("runs_completed", 0))
	return state
