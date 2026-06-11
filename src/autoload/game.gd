extends Node

## Dünner Engine-Adapter um den GameState: tickt die Simulation,
## lädt beim Start (inkl. Offline-Fortschritt), speichert automatisch
## und beim Beenden. Spiellogik gehört NICHT hierher, sondern in
## src/core/ – dieser Knoten verdrahtet nur.

var state := GameState.new()

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
	state.add_resource(Balance.PRIMARY_RESOURCE, BigNum.from_float(Balance.MANUAL_WORK_AMOUNT))


func buy_generator(generator_id: String, count: int = 1) -> bool:
	var purchased := state.buy_generator(generator_id, count)
	if purchased:
		EventBus.generator_purchased.emit(generator_id, state.owned(generator_id))
	return purchased


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
