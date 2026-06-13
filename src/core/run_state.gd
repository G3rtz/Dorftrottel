class_name RunState
extends RefCounted

## Ein laufender Dungeon-Run als reine, deterministische Simulation –
## und ein RUNDENBASIERTER, MANUELLER Kampf: Es passiert nichts, bis
## der Spieler handelt. Jede Aktion ist ein Zug:
##
## - ATTACK:   normaler Schlag; überlebt der Gegner, schlägt er zurück.
## - STRIKE:   schwerer Schlag (xSTRIKE_DAMAGE_MULT), Cooldown in Zügen.
## - BLOCK:    kein eigener Schaden, eingehender Schaden -BLOCK_REDUCTION.
## - BREATHER: heilt, aber der Gegner schlägt frei zu; langer Cooldown.
##
## Gegner TELEGRAFIEREN ihre Absicht (enemy_intent): normal oder
## schwerer Schlag (xHEAVY_INTENT_MULT, seeded RNG). Darum drehen sich
## die Entscheidungen: Schwere Schläge blockt man – oder man tötet
## vorher. Tödliche Treffer verhindern den Gegenschlag.
##
## Nach jedem erkämpften Raum (außer Boss) wählt der Spieler 1 aus
## mehreren zufälligen SEGEN (Boons), die nur für diesen Run gelten –
## daraus entstehen Builds. Danach die Raumwahl (außer vor dem Boss):
## Weitergehen / Schatzkammer / Rastplatz.
##
## v1-Entscheidungen: Tod beendet den Run, Beute bleibt; Runs laufen
## nicht offline und überleben kein Beenden der App.

enum Status { ACTIVE, VICTORY, DEFEAT, FLED }
enum Phase { FIGHTING, CHOOSING_BOON, CHOOSING }
enum RoomType { NORMAL, ELITE, REST }
enum Action { ATTACK, STRIKE, BLOCK, BREATHER }
enum Intent { NORMAL, HEAVY }

var dungeon: DungeonDef
var status: Status = Status.ACTIVE
var phase: Phase = Phase.FIGHTING
var current_room := 1
var room_type: RoomType = RoomType.NORMAL
var rooms_cleared := 0

var hero_hp: BigNum
var hero_max_hp: BigNum
var hero_atk: BigNum

# Segen (Boons): nur für diesen Run. boons_owned: boon_id -> Stapel,
# boon_offers: die aktuell angebotene Auswahl (boon_ids).
var boons_owned := {}
var boon_offers: Array[String] = []
## Aus welchem Pool Segen gezogen werden – injizierbar, damit Tests
## mit leerem Pool die exakte Kampfmathematik behalten.
var boon_pool: Array[BoonDef] = []
## Maximale LP vor max_hp-Segen; Basis für deren Neuberechnung.
var _base_max_hp: BigNum

var enemy_name := ""
var enemy_hp: BigNum
var enemy_max_hp: BigNum
var enemy_atk: BigNum
## Was der Gegner in seinem nächsten Zug vorhat – sichtbar für den
## Spieler, das ist die Information hinter jeder Entscheidung.
var enemy_intent: Intent = Intent.NORMAL

var gold_earned := BigNum.zero()
var items_found := {}  # item_id -> int

var strike_cooldown := 0
var breather_cooldown := 0

# Taten-Zähler: füttern nach dem Run die Tavernenerzählungen.
var turns := 0
var damage_taken := BigNum.zero()
var doors_seen := 0
var elite_chosen := 0
var rest_chosen := 0
var strikes_used := 0
var breathers_used := 0
var blocks_used := 0

var _rng := RandomNumberGenerator.new()


## hero_stats: {"hp": BigNum, "atk": BigNum} – kommt aus
## GameState.hero_stats(). rng_seed macht Drops, Absichten und
## Segens-Auswahl reproduzierbar. boon_pool == null → echter Pool aus
## ContentDB; Tests übergeben [] für einen segenlosen Run.
static func start(dungeon_def: DungeonDef, hero_stats: Dictionary, rng_seed: int = 0, boon_pool = null) -> RunState:
	var run := RunState.new()
	run.dungeon = dungeon_def
	run.hero_max_hp = hero_stats["hp"]
	run._base_max_hp = hero_stats["hp"].copy()
	run.hero_hp = run.hero_max_hp.copy()
	run.hero_atk = hero_stats["atk"]
	# .assign() coerciert auch untypisierte Arrays (z.B. [] aus Tests)
	# sauber in Array[BoonDef] – direkte Zuweisung würde dabei crashen.
	if boon_pool == null:
		run.boon_pool = ContentDB.boons()
	else:
		run.boon_pool.assign(boon_pool)
	run._rng.seed = rng_seed
	run._spawn_enemy()
	return run


## Aufsummierter Effektwert aller gehaltenen Segen eines Typs
## (z.B. "atk_mult" -> 0.5 bei zwei Stapeln à 0.25).
func boon_amount(effect: String) -> float:
	var total := 0.0
	for boon_id: String in boons_owned:
		var def := _boon_def(boon_id)
		if def != null and def.effect == effect:
			total += def.amount * float(boons_owned[boon_id])
	return total


func boon_stacks(boon_id: String) -> int:
	return int(boons_owned.get(boon_id, 0))


## Angriff inklusive Segens-Multiplikator – der einzige Ort, an dem der
## ausgeteilte Schaden bestimmt wird.
func effective_atk() -> BigNum:
	return hero_atk.mul(BigNum.from_float(1.0 + boon_amount("atk_mult")))


func _boon_def(boon_id: String) -> BoonDef:
	for def in boon_pool:
		if def.id == boon_id:
			return def
	return null


func is_boss_room() -> bool:
	return dungeon.is_boss_room(current_room)


func can_act(action: Action) -> bool:
	if status != Status.ACTIVE or phase != Phase.FIGHTING:
		return false
	match action:
		Action.STRIKE:
			return strike_cooldown == 0
		Action.BREATHER:
			return breather_cooldown == 0
	return true


## Führt einen Spielerzug aus und liefert die Ereignisse für UI/Log.
func take_action(action: Action) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not can_act(action):
		return events
	turns += 1
	strike_cooldown = maxi(0, strike_cooldown - 1)
	breather_cooldown = maxi(0, breather_cooldown - 1)
	match action:
		Action.ATTACK:
			if _attack_enemy(effective_atk(), events):
				return events
			_enemy_acts(events, 1.0)
		Action.STRIKE:
			strike_cooldown = maxi(1, Balance.STRIKE_COOLDOWN_TURNS - int(boon_amount("strike_cd")))
			strikes_used += 1
			var damage := effective_atk().mul(BigNum.from_float(Balance.STRIKE_DAMAGE_MULT))
			events.append({"type": "strike", "damage": damage})
			if _attack_enemy(damage, events):
				return events
			_enemy_acts(events, 1.0)
		Action.BLOCK:
			blocks_used += 1
			events.append({"type": "block"})
			var reduction: float = minf(0.95, Balance.BLOCK_REDUCTION + boon_amount("block_bonus"))
			_enemy_acts(events, 1.0 - reduction)
		Action.BREATHER:
			breather_cooldown = Balance.BREATHER_COOLDOWN_TURNS
			breathers_used += 1
			var amount := hero_max_hp.mul(BigNum.from_float(Balance.BREATHER_HEAL_FRACTION))
			_heal(amount)
			events.append({"type": "breather", "amount": amount})
			_enemy_acts(events, 1.0)
	return events


## Raumwahl auflösen. Nur gültig, wenn der Run gerade an einer
## Gabelung steht (phase == CHOOSING).
func choose(choice: RoomType) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if status != Status.ACTIVE or phase != Phase.CHOOSING:
		return events
	phase = Phase.FIGHTING
	current_room += 1
	room_type = choice
	match choice:
		RoomType.ELITE:
			elite_chosen += 1
		RoomType.REST:
			rest_chosen += 1
	# Kleine Verschnaufpause beim Weitergehen.
	_heal(BigNum.from_float(dungeon.heal_per_room))
	if choice == RoomType.REST:
		var amount := hero_max_hp.mul(BigNum.from_float(Balance.REST_HEAL_FRACTION))
		_heal(amount)
		events.append({"type": "rested", "amount": amount, "room": current_room})
		rooms_cleared += 1
		_advance(events)
		return events
	_spawn_enemy()
	events.append({
		"type": "room_entered",
		"room": current_room,
		"enemy": enemy_name,
		"is_boss": false,
		"room_type": room_type,
	})
	return events


## Einen angebotenen Segen wählen (oder mit "" überspringen). Danach
## geht es weiter zur Raumwahl bzw. zum Boss.
func choose_boon(boon_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if status != Status.ACTIVE or phase != Phase.CHOOSING_BOON:
		return events
	if not boon_id.is_empty():
		if not boon_offers.has(boon_id):
			return events
		_apply_boon(boon_id, events)
	boon_offers = []
	_advance(events)
	return events


func skip_boon() -> Array[Dictionary]:
	return choose_boon("")


func _apply_boon(boon_id: String, events: Array[Dictionary]) -> void:
	boons_owned[boon_id] = boon_stacks(boon_id) + 1
	events.append({"type": "boon_taken", "boon_id": boon_id})
	# Max-LP-Segen: Maximum neu aus der Basis berechnen und den Zugewinn
	# sofort gutschreiben.
	var def := _boon_def(boon_id)
	if def != null and def.effect == "max_hp_mult":
		var old_max := hero_max_hp
		hero_max_hp = _base_max_hp.mul(BigNum.from_float(1.0 + boon_amount("max_hp_mult")))
		hero_hp = hero_hp.add(hero_max_hp.sub(old_max))


## Stellt nach einem Kill eine zufällige Segens-Auswahl zusammen.
## Segen am Stapellimit fallen raus; ist nichts (mehr) übrig, geht es
## direkt weiter.
func _offer_boon(events: Array[Dictionary]) -> void:
	var candidates: Array[String] = []
	for def in boon_pool:
		if def.max_stacks == 0 or boon_stacks(def.id) < def.max_stacks:
			candidates.append(def.id)
	# Deterministischer Fisher-Yates mit dem Run-RNG (seeded).
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	boon_offers = []
	for boon_id in candidates:
		if boon_offers.size() >= Balance.BOON_OFFER_COUNT:
			break
		boon_offers.append(boon_id)
	if boon_offers.is_empty():
		_advance(events)
		return
	phase = Phase.CHOOSING_BOON
	events.append({"type": "boons_offered", "offers": boon_offers.duplicate(), "room": current_room})


func flee() -> void:
	if status == Status.ACTIVE:
		status = Status.FLED


func result() -> Dictionary:
	return {
		"dungeon_id": dungeon.id,
		"status": status,
		"victory": status == Status.VICTORY,
		"gold": gold_earned,
		"items": items_found.duplicate(),
		"rooms_cleared": rooms_cleared,
		# Taten-Zähler für die Tavernenerzählungen.
		"turns": turns,
		"took_damage": not damage_taken.is_zero(),
		"damage_taken": damage_taken,
		"doors_seen": doors_seen,
		"elite_chosen": elite_chosen,
		"rest_chosen": rest_chosen,
		"strikes_used": strikes_used,
		"breathers_used": breathers_used,
		"blocks_used": blocks_used,
	}


## Schaden austeilen inkl. Lebensraub und kompletter Kill-Abwicklung.
## Gibt true zurück, wenn der Gegner fiel.
func _attack_enemy(damage: BigNum, events: Array[Dictionary]) -> bool:
	enemy_hp = enemy_hp.sub(damage)
	events.append({"type": "hero_hit", "damage": damage, "enemy": enemy_name})
	var lifesteal := boon_amount("lifesteal")
	if lifesteal > 0.0:
		_heal(damage.mul(BigNum.from_float(lifesteal)))
	if enemy_hp.signum() > 0:
		return false
	_on_enemy_killed(events)
	return true


## Beute, Drops, Heilung-bei-Kill, dann Sieg oder Weiterziehen. Kann
## sowohl vom Helden-Schlag als auch von Dornen-Schaden ausgelöst werden.
func _on_enemy_killed(events: Array[Dictionary]) -> void:
	# Beute: Gold (Schatzkammer zahlt doppelt, Segen obendrauf) …
	var loot := dungeon.gold_for(current_room)
	if room_type == RoomType.ELITE and not is_boss_room():
		loot = loot.mul(BigNum.from_float(Balance.ELITE_GOLD_MULT))
	loot = loot.mul(BigNum.from_float(1.0 + boon_amount("gold_mult")))
	gold_earned = gold_earned.add(loot)
	events.append({"type": "enemy_defeated", "enemy": enemy_name, "gold": loot})
	var heal_on_kill := boon_amount("heal_on_kill")
	if heal_on_kill > 0.0:
		_heal(hero_max_hp.mul(BigNum.from_float(heal_on_kill)))
	# … und Drops gegen die Tabelle würfeln.
	_roll_drops(events)

	if is_boss_room():
		gold_earned = gold_earned.add(BigNum.from_float(dungeon.completion_bonus))
		status = Status.VICTORY
		events.append({"type": "run_complete", "dungeon": dungeon.id, "gold_total": gold_earned})
		return
	rooms_cleared += 1
	_offer_boon(events)


## Der Gegner führt seine telegrafierte Absicht aus; danach wird die
## nächste Absicht gewürfelt. damage_factor < 1 = geblockt.
func _enemy_acts(events: Array[Dictionary], damage_factor: float) -> void:
	var damage := enemy_atk
	var heavy := enemy_intent == Intent.HEAVY
	if heavy:
		damage = damage.mul(BigNum.from_float(Balance.HEAVY_INTENT_MULT))
	damage = damage.mul(BigNum.from_float(damage_factor))
	hero_hp = hero_hp.sub(damage)
	damage_taken = damage_taken.add(damage)
	events.append({"type": "enemy_hit", "damage": damage, "enemy": enemy_name, "heavy": heavy,
		"blocked": damage_factor < 1.0})
	if hero_hp.signum() <= 0:
		hero_hp = BigNum.zero()
		status = Status.DEFEAT
		events.append({"type": "hero_died", "room": current_room})
		return
	# Dornen: Wer den Helden trifft, blutet selbst – kann den Gegner töten.
	var thorns := boon_amount("thorns")
	if thorns > 0.0:
		var thorn_damage := effective_atk().mul(BigNum.from_float(thorns))
		enemy_hp = enemy_hp.sub(thorn_damage)
		events.append({"type": "thorns", "damage": thorn_damage, "enemy": enemy_name})
		if enemy_hp.signum() <= 0:
			_on_enemy_killed(events)
			return
	_roll_intent()


## Nach einem erledigten Raum weiterziehen: Vor dem Boss gibt es keine
## Gabelung (der Weg ist eindeutig), sonst ruht der Run bis zur Wahl.
func _advance(events: Array[Dictionary]) -> void:
	if dungeon.is_boss_room(current_room + 1):
		# Direkt in den Bosskampf – wichtig nach der Segenswahl, von der
		# aus die Phase sonst auf CHOOSING_BOON hängen bliebe.
		phase = Phase.FIGHTING
		current_room += 1
		room_type = RoomType.NORMAL
		_heal(BigNum.from_float(dungeon.heal_per_room))
		_spawn_enemy()
		events.append({
			"type": "room_entered",
			"room": current_room,
			"enemy": enemy_name,
			"is_boss": true,
			"room_type": room_type,
		})
		return
	phase = Phase.CHOOSING
	doors_seen += 1
	events.append({"type": "doors_offered", "room": current_room})


func _roll_drops(events: Array[Dictionary]) -> void:
	var table := dungeon.boss_drops if is_boss_room() else dungeon.drops
	var chance_mult := 1.0
	if room_type == RoomType.ELITE and not is_boss_room():
		chance_mult = Balance.ELITE_DROP_MULT
	chance_mult += boon_amount("drop_mult")
	for entry: Dictionary in table:
		var item_id := str(entry.get("item_id", ""))
		var chance: float = minf(float(entry.get("chance", 0.0)) * chance_mult, 1.0)
		if _rng.randf() < chance:
			items_found[item_id] = int(items_found.get(item_id, 0)) + 1
			events.append({"type": "item_dropped", "item_id": item_id})


func _roll_intent() -> void:
	if _rng.randf() < Balance.HEAVY_INTENT_CHANCE:
		enemy_intent = Intent.HEAVY
	else:
		enemy_intent = Intent.NORMAL


func _heal(amount: BigNum) -> void:
	hero_hp = hero_hp.add(amount)
	if hero_hp.cmp(hero_max_hp) > 0:
		hero_hp = hero_max_hp.copy()


func _spawn_enemy() -> void:
	enemy_name = dungeon.enemy_name_for(current_room)
	enemy_max_hp = dungeon.enemy_hp_for(current_room)
	enemy_atk = dungeon.enemy_atk_for(current_room)
	if room_type == RoomType.ELITE and not is_boss_room():
		enemy_name = "Schatzwächter (%s)" % enemy_name
		enemy_max_hp = enemy_max_hp.mul(BigNum.from_float(Balance.ELITE_HP_MULT))
		enemy_atk = enemy_atk.mul(BigNum.from_float(Balance.ELITE_ATK_MULT))
	enemy_hp = enemy_max_hp.copy()
	_roll_intent()
