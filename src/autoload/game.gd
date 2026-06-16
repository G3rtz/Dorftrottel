extends Node

## Dünner Engine-Adapter um den GameState: tickt die Simulation,
## lädt beim Start (inkl. Offline-Fortschritt), speichert automatisch
## und beim Beenden. Spiellogik gehört NICHT hierher, sondern in
## src/core/ – dieser Knoten verdrahtet nur.

var state := GameState.new()

## Der aktuelle (oder zuletzt beendete) Run. Kämpfe sind rundenbasiert
## und manuell – der Run wartet auf Spieleraktionen, läuft nicht
## offline weiter und überlebt kein Beenden der App.
var run: RunState = null

var _save_io := SaveIO.new()
var _tick_accumulator := 0.0
var _autosave_accumulator := 0.0


func _ready() -> void:
	_load_game()


func _process(delta: float) -> void:
	state.total_playtime += delta
	_tick_accumulator += delta
	if _tick_accumulator > Balance.MAX_CATCHUP_SECONDS:
		# Lange Pause (App-Suspend, Debugger): in einem Schritt nachbuchen.
		state.advance(_tick_accumulator)
		_tick_accumulator = 0.0
	while _tick_accumulator >= Balance.TICK_SECONDS:
		state.advance(Balance.TICK_SECONDS)
		_tick_accumulator -= Balance.TICK_SECONDS
	_autosave_accumulator += delta
	if _autosave_accumulator >= Balance.AUTOSAVE_INTERVAL_SECONDS:
		_autosave_accumulator = 0.0
		save_now()


func _notification(what: int) -> void:
	# Beim Schließen (Desktop) bzw. In-den-Hintergrund-Wechsel (Mobile)
	# synchron speichern – sonst wäre Fortschritt seit dem letzten
	# Autosave verloren.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()


func manual_work() -> void:
	state.do_manual_work()


func buy_generator(generator_id: String, count: int = 1) -> bool:
	var purchased := state.buy_generator(generator_id, count)
	if purchased:
		EventBus.generator_purchased.emit(generator_id, state.owned(generator_id))
	return purchased


func buy_generator_upgrade(upgrade_id: String) -> bool:
	return state.buy_generator_upgrade(upgrade_id)


func train(kind: String) -> bool:
	return state.train(kind)


func is_run_active() -> bool:
	return run != null and run.status == RunState.Status.ACTIVE


func start_run(dungeon_id: String) -> bool:
	if is_run_active():
		return false
	var def := ContentDB.dungeon(dungeon_id)
	if def == null or not state.is_dungeon_unlocked(def):
		return false
	run = RunState.start(def, state.hero_stats(), randi(), null, state.active_class_start_boons())
	EventBus.run_started.emit(def.id)
	return true


## Klasse wählen (nur außerhalb eines Runs sinnvoll). Persistiert sofort.
func set_active_class(class_id: String) -> bool:
	if is_run_active():
		return false
	var changed := state.set_active_class(class_id)
	if changed:
		save_now()
	return changed


## Ein Spielerzug im rundenbasierten Kampf. Kann den Run beenden
## (Todesstoß oder Gegenschlag), deshalb die Abschlussprüfung.
func run_action(action: RunState.Action) -> void:
	if not is_run_active():
		return
	_emit_and_check(run.take_action(action))


func choose_room(choice: RunState.RoomType) -> void:
	if not is_run_active():
		return
	_emit_and_check(run.choose(choice))


func choose_boon(boon_id: String) -> void:
	if not is_run_active():
		return
	_emit_and_check(run.choose_boon(boon_id))


func skip_boon() -> void:
	if not is_run_active():
		return
	_emit_and_check(run.skip_boon())


func sell_item(item_id: String, count: int = 1) -> int:
	return state.sell_item(item_id, count)


func craft(recipe_id: String) -> bool:
	var crafted := state.craft(recipe_id)
	if crafted:
		save_now()
	return crafted


func _emit_and_check(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	EventBus.run_tick.emit(events)
	if run.status != RunState.Status.ACTIVE:
		_finish_run()


func flee_run() -> void:
	if is_run_active():
		run.flee()
		_finish_run()


## Prestige: nicht mitten in einem Run – erst fliehen oder sterben.
func do_prestige() -> bool:
	if is_run_active():
		return false
	var report := state.prestige()
	if report.is_empty():
		return false
	run = null
	save_now()
	EventBus.prestige_performed.emit(report)
	return true


func buy_perma(upgrade_id: String) -> bool:
	var bought := state.buy_perma(upgrade_id)
	if bought:
		save_now()
	return bought


func buy_hero_talent(talent_id: String) -> bool:
	var bought := state.buy_hero_talent(talent_id)
	if bought:
		save_now()
	return bought


func buy_base_talent(talent_id: String) -> bool:
	var bought := state.buy_base_talent(talent_id)
	if bought:
		save_now()
	return bought


func _finish_run() -> void:
	var run_result := run.result()
	# Klassen-Freischaltung ist aus den Erzählungen abgeleitet: Stand
	# davor merken, um neu freigeschaltete danach zu melden.
	var classes_before := state.unlocked_class_ids()
	var new_tales := state.bank_run_result(run_result)
	save_now()
	EventBus.run_finished.emit(run_result)
	for tale_id in new_tales:
		EventBus.tale_earned.emit(tale_id)
	for class_id in state.unlocked_class_ids():
		if not classes_before.has(class_id):
			EventBus.class_unlocked.emit(class_id)


func save_now() -> void:
	if _save_io.write(state.to_dict()):
		EventBus.save_completed.emit()


func _load_game() -> void:
	var envelope := _save_io.read()
	if envelope.is_empty():
		EventBus.game_loaded.emit()
		return
	state = GameState.from_dict(envelope.get("state", {}))
	var saved_at := float(envelope.get("saved_at_unix", 0.0))
	var elapsed := Time.get_unix_time_from_system() - saved_at
	EventBus.game_loaded.emit()
	if saved_at > 0.0 and elapsed > 1.0:
		var report := GameState.apply_offline(state, elapsed)
		EventBus.offline_progress_applied.emit(report)
