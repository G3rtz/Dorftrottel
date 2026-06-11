extends Control

## Provisorische Debug-/Prototyp-UI: komplett aus Code gebaut, liest nur
## aus Game.state und ruft Game-Methoden auf. Wird später durch echte
## Szenen ersetzt – Logik darf hier nie landen.

var _resource_label: Label
var _rate_label: Label
var _buy_buttons := {}  # generator_id -> Button
var _generator_rows := {}  # generator_id -> Control (Zeile, für Sichtbarkeit)
var _offline_dialog: AcceptDialog


func _ready() -> void:
	_build_ui()
	EventBus.offline_progress_applied.connect(_on_offline_progress)


func _process(_delta: float) -> void:
	_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Der Dorftrottel"
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_resource_label = Label.new()
	_resource_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_resource_label)

	_rate_label = Label.new()
	vbox.add_child(_rate_label)

	var work_button := Button.new()
	work_button.text = "Arbeiten (+%s Gold)" % BigNum.from_float(Balance.MANUAL_WORK_AMOUNT).format()
	work_button.pressed.connect(Game.manual_work)
	vbox.add_child(work_button)

	vbox.add_child(HSeparator.new())

	for def in ContentDB.generators():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var buy_button := Button.new()
		buy_button.custom_minimum_size = Vector2(320, 0)
		buy_button.pressed.connect(_on_buy_pressed.bind(def.id))
		row.add_child(buy_button)
		var flavor := Label.new()
		flavor.text = def.flavor
		flavor.modulate = Color(1, 1, 1, 0.6)
		row.add_child(flavor)
		vbox.add_child(row)
		_buy_buttons[def.id] = buy_button
		_generator_rows[def.id] = row

	_offline_dialog = AcceptDialog.new()
	_offline_dialog.title = "Willkommen zurück!"
	add_child(_offline_dialog)


func _refresh() -> void:
	var gold := Game.state.get_resource(Balance.PRIMARY_RESOURCE)
	var rate := Game.state.production_per_second(Balance.PRIMARY_RESOURCE)
	_resource_label.text = "Gold: %s" % gold.format()
	_rate_label.text = "%s Gold/s" % rate.format()
	for def in ContentDB.generators():
		var row: Control = _generator_rows[def.id]
		row.visible = Game.state.is_generator_visible(def)
		if not row.visible:
			continue
		var button: Button = _buy_buttons[def.id]
		var cost := Game.state.cost_of(def.id, 1)
		button.text = "%s (%d) – %s Gold" % [def.display_name, Game.state.owned(def.id), cost.format()]
		button.disabled = gold.lt(cost)


func _on_buy_pressed(generator_id: String) -> void:
	Game.buy_generator(generator_id, 1)


func _on_offline_progress(report: Dictionary) -> void:
	var seconds := float(report.get("seconds", 0.0))
	if seconds < 1.0:
		return
	var lines: Array[String] = ["Du warst %s weg." % _format_duration(seconds), ""]
	var gains: Dictionary = report.get("gains", {})
	for resource_id: String in gains:
		lines.append("+%s %s" % [gains[resource_id].format(), resource_id.capitalize()])
	if report.get("capped", false):
		lines.append("")
		lines.append("(Offline-Limit erreicht – mehr wäre auch unglaubwürdig.)")
	_offline_dialog.dialog_text = "\n".join(lines)
	_offline_dialog.popup_centered()


func _format_duration(seconds: float) -> String:
	var total := int(seconds)
	if total < 60:
		return "%d Sekunden" % total
	if total < 3600:
		return "%d Minuten" % int(total / 60.0)
	return "%d Stunden %d Minuten" % [int(total / 3600.0), int(fmod(total, 3600.0) / 60.0)]
