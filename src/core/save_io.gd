class_name SaveIO
extends RefCounted

## Persistenz mit drei Solidesitäts-Garantien:
## 1. Atomares Schreiben: erst in .tmp, dann umbenennen – ein Absturz
##    mitten im Schreiben kann den bestehenden Save nicht zerstören.
## 2. Backup-Rotation: der vorherige Save bleibt als Fallback erhalten,
##    Lesen probiert Save und Backup der Reihe nach.
## 3. Versionierung + Migrations-Kette: alte Saves werden beim Laden
##    Schritt für Schritt auf das aktuelle Format gehoben.

const SAVE_VERSION := 2

const SAVE_FILE := "save.json"
const BACKUP_FILE := "save.backup.json"
const TMP_FILE := "save.json.tmp"

var _dir: String


## Das Verzeichnis ist injizierbar, damit Tests nicht den echten
## Spielstand anfassen.
func _init(dir: String = "user://saves") -> void:
	_dir = dir


func save_path() -> String:
	return _dir.path_join(SAVE_FILE)


func backup_path() -> String:
	return _dir.path_join(BACKUP_FILE)


func tmp_path() -> String:
	return _dir.path_join(TMP_FILE)


func write(payload: Dictionary) -> bool:
	var envelope := {
		"version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"state": payload,
	}
	var dir_err := DirAccess.make_dir_recursive_absolute(_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_error("SaveIO: kann Verzeichnis %s nicht anlegen (%s)" % [_dir, error_string(dir_err)])
		return false
	var file := FileAccess.open(tmp_path(), FileAccess.WRITE)
	if file == null:
		push_error("SaveIO: kann %s nicht schreiben (%s)" % [tmp_path(), error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	file.close()
	if FileAccess.file_exists(save_path()):
		var copy_err := DirAccess.copy_absolute(save_path(), backup_path())
		if copy_err != OK:
			push_error("SaveIO: Backup-Rotation fehlgeschlagen (%s)" % error_string(copy_err))
	var rename_err := DirAccess.rename_absolute(tmp_path(), save_path())
	if rename_err != OK:
		push_error("SaveIO: kann %s nicht ersetzen (%s)" % [save_path(), error_string(rename_err)])
		return false
	return true


## Liefert den (bereits migrierten) Umschlag mit "version", "saved_at_unix"
## und "state" – oder {} wenn weder Save noch Backup lesbar sind.
func read() -> Dictionary:
	for path: String in [save_path(), backup_path()]:
		var envelope := _read_envelope(path)
		if not envelope.is_empty():
			return envelope
	return {}


func has_save() -> bool:
	return FileAccess.file_exists(save_path()) or FileAccess.file_exists(backup_path())


## Löscht Save, Backup und Tmp – für Tests und einen späteren
## "Spielstand löschen"-Knopf.
func clear() -> void:
	for path: String in [save_path(), backup_path(), tmp_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("SaveIO: %s ist beschädigt, versuche Fallback" % path)
		return {}
	var envelope: Dictionary = parsed
	var version := int(envelope.get("version", 0))
	if version <= 0:
		push_error("SaveIO: %s hat keine gültige Version" % path)
		return {}
	if version > SAVE_VERSION:
		push_error("SaveIO: %s stammt aus einer neueren Spielversion (%d > %d)" % [path, version, SAVE_VERSION])
		return {}
	return _migrate(envelope, version)


## Hebt einen Umschlag von `from_version` schrittweise auf SAVE_VERSION.
## Jede Versionserhöhung bekommt hier einen eigenen match-Zweig, der das
## state-Dictionary umbaut. Beispiel für später:
##     1:  # v1 -> v2: Talentbaum-Sektion eingeführt
##         state["hero"]["talents"] = {}
func _migrate(envelope: Dictionary, from_version: int) -> Dictionary:
	var version := from_version
	while version < SAVE_VERSION:
		match version:
			1:
				# v1 -> v2: Ruhm ("fame") ging in den Liedfragmenten auf.
				var state: Dictionary = envelope.get("state", {})
				var perma: Dictionary = state.get("perma", {})
				if perma.has("fame"):
					perma["fragments"] = perma["fame"]
					perma.erase("fame")
			_:
				push_error("SaveIO: keine Migration von Version %d definiert" % version)
				return {}
		version += 1
	envelope["version"] = SAVE_VERSION
	return envelope
