class_name RunState
extends RefCounted

## Ein laufender Dungeon-Run als reine, deterministische Simulation.
## Ein step() = ein Kampf-Tick: der Held schlägt zuerst; stirbt der
## Gegner dadurch, schlägt er nicht mehr zurück.
##
## v1-Entscheidungen (siehe ARCHITECTURE.md):
## - Tod beendet den Run, bereits gesammelte Beute bleibt. Nur Boss-
##   Belohnung und Abschluss-Bonus entfallen. Fliehen geht jederzeit.
## - Runs laufen nicht offline weiter und überleben kein Beenden der
##   App – sie sind die aktive Schicht.

enum Status { ACTIVE, VICTORY, DEFEAT, FLED }

var dungeon: DungeonDef
var status: Status = Status.ACTIVE
var current_room := 1
var rooms_cleared := 0

var hero_hp: BigNum
var hero_max_hp: BigNum
var hero_atk: BigNum

var enemy_name := ""
var enemy_hp: BigNum
var enemy_max_hp: BigNum
var enemy_atk: BigNum

var gold_earned := BigNum.zero()


## hero_stats: {"hp": BigNum, "atk": BigNum} – kommt aus
## GameState.hero_stats(), damit Talente/Ausrüstung später dort
## andocken, nicht hier.
static func start(dungeon_def: DungeonDef, hero_stats: Dictionary) -> RunState:
	var run := RunState.new()
	run.dungeon = dungeon_def
	run.hero_max_hp = hero_stats["hp"]
	run.hero_hp = run.hero_max_hp.copy()
	run.hero_atk = hero_stats["atk"]
	run._spawn_enemy()
	return run


func is_boss_room() -> bool:
	return dungeon.is_boss_room(current_room)


## Führt einen Kampf-Tick aus und liefert die Ereignisse für UI/Log.
func step() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if status != Status.ACTIVE:
		return events

	# Der Held schlägt zuerst.
	enemy_hp = enemy_hp.sub(hero_atk)
	events.append({"type": "hero_hit", "damage": hero_atk, "enemy": enemy_name})
	if enemy_hp.signum() <= 0:
		var loot := dungeon.gold_for(current_room)
		gold_earned = gold_earned.add(loot)
		events.append({"type": "enemy_defeated", "enemy": enemy_name, "gold": loot})
		if is_boss_room():
			gold_earned = gold_earned.add(BigNum.from_float(dungeon.completion_bonus))
			status = Status.VICTORY
			events.append({"type": "run_complete", "dungeon": dungeon.id, "gold_total": gold_earned})
			return events
		rooms_cleared += 1
		current_room += 1
		_rest()
		_spawn_enemy()
		events.append({"type": "room_entered", "room": current_room, "enemy": enemy_name, "is_boss": is_boss_room()})
		return events

	# Der Gegner schlägt zurück.
	hero_hp = hero_hp.sub(enemy_atk)
	events.append({"type": "enemy_hit", "damage": enemy_atk, "enemy": enemy_name})
	if hero_hp.signum() <= 0:
		hero_hp = BigNum.zero()
		status = Status.DEFEAT
		events.append({"type": "hero_died", "room": current_room})
	return events


func flee() -> void:
	if status == Status.ACTIVE:
		status = Status.FLED


func result() -> Dictionary:
	return {
		"dungeon_id": dungeon.id,
		"status": status,
		"victory": status == Status.VICTORY,
		"gold": gold_earned,
		"rooms_cleared": rooms_cleared,
	}


## Verschnaufpause zwischen den Räumen, gedeckelt auf das Maximum.
func _rest() -> void:
	hero_hp = hero_hp.add(BigNum.from_float(dungeon.heal_per_room))
	if hero_hp.cmp(hero_max_hp) > 0:
		hero_hp = hero_max_hp.copy()


func _spawn_enemy() -> void:
	enemy_name = dungeon.enemy_name_for(current_room)
	enemy_max_hp = dungeon.enemy_hp_for(current_room)
	enemy_hp = enemy_max_hp.copy()
	enemy_atk = dungeon.enemy_atk_for(current_room)
