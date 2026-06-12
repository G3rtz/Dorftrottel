extends Node

## Globaler Signal-Hub. Simulation und UI kennen sich nicht direkt –
## alles läuft über diese Signale. Neue Systeme (Dungeon, Prestige)
## bekommen hier ihre eigenen Signale.
##
## Die Signale werden nicht von diesem Skript selbst emittiert, daher
## die unused_signal-Ignores.

@warning_ignore("unused_signal")
signal game_loaded()
@warning_ignore("unused_signal")
signal offline_progress_applied(report: Dictionary)
@warning_ignore("unused_signal")
signal generator_purchased(generator_id: String, new_count: int)
@warning_ignore("unused_signal")
signal save_completed()
@warning_ignore("unused_signal")
signal run_started(dungeon_id: String)
@warning_ignore("unused_signal")
signal run_tick(events: Array)
@warning_ignore("unused_signal")
signal run_finished(result: Dictionary)
@warning_ignore("unused_signal")
signal prestige_performed(report: Dictionary)
@warning_ignore("unused_signal")
signal tale_earned(tale_id: String)
