extends Control

## Provisorische Debug-/Prototyp-UI: komplett aus Code gebaut, liest nur
## aus Game.state und ruft Game-Methoden auf. Wird später durch echte
## Szenen ersetzt – Logik darf hier nie landen.

const LOG_LINES := 7

var _resource_label: Label
var _rate_label: Label
var _buy_buttons := {}  # generator_id -> Button
var _generator_rows := {}  # generator_id -> Control (Zeile, für Sichtbarkeit)
var _offline_dialog: AcceptDialog

var _hero_label: Label
var _train_hp_button: Button
var _train_atk_button: Button

var _dungeon_buttons := {}  # dungeon_id -> Button
var _dungeon_rows := {}  # dungeon_id -> Control
var _run_panel: VBoxContainer
var _run_status_label: Label
var _run_log_label: Label
var _flee_button: Button
var _strike_button: Button
var _breather_button: Button
var _door_row: HBoxContainer
var _bag_label: Label
var _log_lines: Array[String] = []

var _loot_section: VBoxContainer
var _sell_buttons := {}  # item_id -> Button
var _sell_all_buttons := {}  # item_id -> Button
var _loot_rows := {}  # item_id -> Control
var _songbook_label: Label

var _craft_buttons := {}  # recipe_id -> Button
var _craft_rows := {}  # recipe_id -> Control
var _equipment_label: Label

var _upgrade_buttons := {}  # upgrade_id -> Button
var _upgrade_rows := {}  # upgrade_id -> Control

var _tavern_section: VBoxContainer
var _tavern_count_label: Label
var _tale_rows := {}  # tale_id -> Control

var _saga_section: VBoxContainer
var _fragments_label: Label
var _prestige_button: Button
var _prestige_confirm: ConfirmationDialog
var _prestige_result: AcceptDialog
var _perma_buttons := {}  # upgrade_id -> Button
var _perma_rows := {}  # upgrade_id -> Control


func _ready() -> void:
	_build_ui()
	EventBus.offline_progress_applied.connect(_on_offline_progress)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_tick.connect(_on_run_tick)
	EventBus.run_finished.connect(_on_run_finished)
	EventBus.prestige_performed.connect(_on_prestige_performed)
	EventBus.tale_earned.connect(_on_tale_earned)


func _process(_delta: float) -> void:
	_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

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
	vbox.add_child(_section_label("Das Dorf"))

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

	# Dorf-Ausbauten: einmalige Multiplikatoren, tauchen auf, sobald
	# genug Bewohner mithelfen.
	for def in ContentDB.generator_upgrades():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.visible = false
		var upgrade_button := Button.new()
		upgrade_button.custom_minimum_size = Vector2(320, 0)
		upgrade_button.pressed.connect(_on_upgrade_pressed.bind(def.id))
		row.add_child(upgrade_button)
		var flavor := Label.new()
		flavor.text = def.flavor
		flavor.modulate = Color(1, 1, 1, 0.6)
		row.add_child(flavor)
		vbox.add_child(row)
		_upgrade_buttons[def.id] = upgrade_button
		_upgrade_rows[def.id] = row

	# Beutestand: Trophäen aus Runs verkaufen. Erscheint erst, wenn es
	# etwas zu verwalten gibt.
	_loot_section = VBoxContainer.new()
	_loot_section.visible = false
	_loot_section.add_theme_constant_override("separation", 10)
	_loot_section.add_child(HSeparator.new())
	_loot_section.add_child(_section_label("Der Beutestand"))
	for def in ContentDB.items():
		if def.is_song_fragment():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var sell_button := Button.new()
		sell_button.custom_minimum_size = Vector2(320, 0)
		sell_button.pressed.connect(_on_sell_pressed.bind(def.id, 1))
		row.add_child(sell_button)
		var sell_all_button := Button.new()
		sell_all_button.text = "Alle"
		sell_all_button.pressed.connect(_on_sell_pressed.bind(def.id, 999999))
		row.add_child(sell_all_button)
		var flavor := Label.new()
		flavor.text = def.flavor
		flavor.modulate = Color(1, 1, 1, 0.6)
		row.add_child(flavor)
		_loot_section.add_child(row)
		_sell_buttons[def.id] = sell_button
		_sell_all_buttons[def.id] = sell_all_button
		_loot_rows[def.id] = row
	vbox.add_child(_loot_section)

	# Die Werkstatt: bekannte Rezepte schmieden. Material kommt aus
	# der Beute, Gold aus dem Dorf – die goldene Regel der Loops.
	vbox.add_child(HSeparator.new())
	vbox.add_child(_section_label("Die Werkstatt"))
	for def in ContentDB.recipes():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var craft_button := Button.new()
		craft_button.custom_minimum_size = Vector2(420, 0)
		craft_button.pressed.connect(_on_craft_pressed.bind(def.id))
		row.add_child(craft_button)
		var flavor := Label.new()
		flavor.text = def.flavor
		flavor.modulate = Color(1, 1, 1, 0.6)
		row.add_child(flavor)
		vbox.add_child(row)
		_craft_buttons[def.id] = craft_button
		_craft_rows[def.id] = row

	vbox.add_child(HSeparator.new())
	vbox.add_child(_section_label("Der Held"))

	_hero_label = Label.new()
	vbox.add_child(_hero_label)

	_equipment_label = Label.new()
	_equipment_label.modulate = Color(1, 1, 1, 0.7)
	_equipment_label.visible = false
	vbox.add_child(_equipment_label)

	var train_row := HBoxContainer.new()
	train_row.add_theme_constant_override("separation", 12)
	_train_hp_button = Button.new()
	_train_hp_button.pressed.connect(func() -> void: Game.train("hp"))
	train_row.add_child(_train_hp_button)
	_train_atk_button = Button.new()
	_train_atk_button.pressed.connect(func() -> void: Game.train("atk"))
	train_row.add_child(_train_atk_button)
	vbox.add_child(train_row)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_section_label("Dungeons"))

	for def in ContentDB.dungeons():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var start_button := Button.new()
		start_button.custom_minimum_size = Vector2(320, 0)
		start_button.pressed.connect(_on_start_run_pressed.bind(def.id))
		row.add_child(start_button)
		var flavor := Label.new()
		flavor.text = def.flavor
		flavor.modulate = Color(1, 1, 1, 0.6)
		row.add_child(flavor)
		vbox.add_child(row)
		_dungeon_buttons[def.id] = start_button
		_dungeon_rows[def.id] = row

	_songbook_label = Label.new()
	_songbook_label.modulate = Color(1, 1, 1, 0.7)
	_songbook_label.visible = false
	vbox.add_child(_songbook_label)

	_run_panel = VBoxContainer.new()
	_run_panel.visible = false
	_run_status_label = Label.new()
	_run_panel.add_child(_run_status_label)

	# Aktive Fähigkeiten: selbst eingreifen statt nur zuzusehen.
	var ability_row := HBoxContainer.new()
	ability_row.add_theme_constant_override("separation", 12)
	_strike_button = Button.new()
	_strike_button.pressed.connect(Game.run_strike)
	ability_row.add_child(_strike_button)
	_breather_button = Button.new()
	_breather_button.pressed.connect(Game.run_breather)
	ability_row.add_child(_breather_button)
	_flee_button = Button.new()
	_flee_button.text = "Fliehen (Beute bleibt)"
	_flee_button.pressed.connect(Game.flee_run)
	ability_row.add_child(_flee_button)
	_run_panel.add_child(ability_row)

	# Türwahl an der Gabelung.
	_door_row = HBoxContainer.new()
	_door_row.add_theme_constant_override("separation", 12)
	_door_row.visible = false
	var door_normal := Button.new()
	door_normal.text = "Weitergehen"
	door_normal.pressed.connect(func() -> void: Game.choose_room(RunState.RoomType.NORMAL))
	_door_row.add_child(door_normal)
	var door_elite := Button.new()
	door_elite.text = "Schatzkammer (härter, doppelte Beute, 3x Drops)"
	door_elite.pressed.connect(func() -> void: Game.choose_room(RunState.RoomType.ELITE))
	_door_row.add_child(door_elite)
	var door_rest := Button.new()
	door_rest.text = "Rastplatz (+%d%% LP, keine Beute)" % int(Balance.REST_HEAL_FRACTION * 100.0)
	door_rest.pressed.connect(func() -> void: Game.choose_room(RunState.RoomType.REST))
	_door_row.add_child(door_rest)
	_run_panel.add_child(_door_row)

	_bag_label = Label.new()
	_bag_label.modulate = Color(1, 1, 1, 0.7)
	_run_panel.add_child(_bag_label)

	_run_log_label = Label.new()
	_run_log_label.modulate = Color(1, 1, 1, 0.75)
	_run_panel.add_child(_run_log_label)
	vbox.add_child(_run_panel)

	# Die Taverne: hier sammelt der Tavernenwirt deine Geschichten.
	# Erscheint mit der ersten verdienten Erzählung.
	_tavern_section = VBoxContainer.new()
	_tavern_section.visible = false
	_tavern_section.add_theme_constant_override("separation", 10)
	_tavern_section.add_child(HSeparator.new())
	_tavern_section.add_child(_section_label("Die Taverne"))
	_tavern_count_label = Label.new()
	_tavern_count_label.modulate = Color(1, 1, 1, 0.7)
	_tavern_section.add_child(_tavern_count_label)
	for def in ContentDB.tales():
		var row := VBoxContainer.new()
		row.visible = false
		var title := Label.new()
		title.text = "„%s“" % def.display_name
		row.add_child(title)
		var story := Label.new()
		story.text = def.flavor
		story.modulate = Color(1, 1, 1, 0.6)
		row.add_child(story)
		_tavern_section.add_child(row)
		_tale_rows[def.id] = row
	vbox.add_child(_tavern_section)

	# Die Sage: unsichtbar, bis das erste Prestige in Reichweite ist –
	# der Offenbarungsmoment aus dem GDD.
	_saga_section = VBoxContainer.new()
	_saga_section.visible = false
	_saga_section.add_theme_constant_override("separation", 10)
	_saga_section.add_child(HSeparator.new())
	_saga_section.add_child(_section_label("Die Sage"))

	_fragments_label = Label.new()
	_saga_section.add_child(_fragments_label)

	_prestige_button = Button.new()
	_prestige_button.pressed.connect(_on_prestige_pressed)
	_saga_section.add_child(_prestige_button)

	for def in ContentDB.perma_upgrades():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var buy_button := Button.new()
		buy_button.custom_minimum_size = Vector2(320, 0)
		buy_button.pressed.connect(_on_buy_perma_pressed.bind(def.id))
		row.add_child(buy_button)
		var flavor := Label.new()
		flavor.text = def.flavor
		flavor.modulate = Color(1, 1, 1, 0.6)
		row.add_child(flavor)
		_saga_section.add_child(row)
		_perma_buttons[def.id] = buy_button
		_perma_rows[def.id] = row

	vbox.add_child(_saga_section)

	_prestige_confirm = ConfirmationDialog.new()
	_prestige_confirm.title = "Die Sage neu erzählen?"
	_prestige_confirm.ok_button_text = "Erzählt sie!"
	_prestige_confirm.cancel_button_text = "Noch nicht"
	_prestige_confirm.confirmed.connect(func() -> void: Game.do_prestige())
	add_child(_prestige_confirm)

	_prestige_result = AcceptDialog.new()
	_prestige_result.title = "Die Legende wächst"
	add_child(_prestige_result)

	_offline_dialog = AcceptDialog.new()
	_offline_dialog.title = "Willkommen zurück!"
	add_child(_offline_dialog)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	return label


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

	# Ausbauten: nur verfügbare zeigen; gekaufte verschwinden.
	for def in ContentDB.generator_upgrades():
		var upgrade_row: Control = _upgrade_rows[def.id]
		upgrade_row.visible = Game.state.is_generator_upgrade_available(def)
		if not upgrade_row.visible:
			continue
		var upgrade_button: Button = _upgrade_buttons[def.id]
		var generator_def := ContentDB.generator(def.generator_id)
		upgrade_button.text = "Ausbau: %s (%s ×%s) – %s Gold" % [
			def.display_name, generator_def.display_name,
			String.num(def.mult, 1), BigNum.from_float(def.cost).format(),
		]
		upgrade_button.disabled = gold.lt(BigNum.from_float(def.cost))

	# Beutestand: nur Zeilen mit Bestand, Sektion nur wenn nicht leer.
	var any_loot := false
	for def in ContentDB.items():
		if def.is_song_fragment():
			continue
		var held := Game.state.item_count(def.id)
		var row: Control = _loot_rows[def.id]
		row.visible = held > 0
		if held > 0:
			any_loot = true
			var sell_button: Button = _sell_buttons[def.id]
			sell_button.text = "%s ×%d – verkaufen (+%s Gold)" % [
				def.display_name, held, BigNum.from_float(def.gold_value).format(),
			]
	_loot_section.visible = any_loot

	# Liederbuch: gesammelte Fragmente (perma).
	var song_parts: Array[String] = []
	for def in ContentDB.items():
		if def.is_song_fragment() and Game.state.fragment_count(def.id) > 0:
			song_parts.append("%s ×%d" % [def.display_name, Game.state.fragment_count(def.id)])
	_songbook_label.visible = not song_parts.is_empty()
	if _songbook_label.visible:
		_songbook_label.text = "Liederbuch: " + " · ".join(song_parts)

	# Werkstatt: nur bekannte Rezepte zeigen.
	for def in ContentDB.recipes():
		var craft_row: Control = _craft_rows[def.id]
		craft_row.visible = Game.state.is_recipe_known(def.id)
		if not craft_row.visible:
			continue
		var craft_button: Button = _craft_buttons[def.id]
		if Game.state.is_equipped(def.id):
			craft_button.text = "%s – angelegt" % def.display_name
			craft_button.disabled = true
		else:
			var bonus_parts: Array[String] = []
			if def.atk_bonus > 0.0:
				bonus_parts.append("+%s ATK" % BigNum.from_float(def.atk_bonus).format())
			if def.hp_bonus > 0.0:
				bonus_parts.append("+%s LP" % BigNum.from_float(def.hp_bonus).format())
			var cost_parts: Array[String] = ["%s Gold" % BigNum.from_float(def.cost_gold).format()]
			for item_id: String in def.cost_items:
				var material := ContentDB.item(item_id)
				if material != null:
					cost_parts.append("%s ×%d" % [material.display_name, int(def.cost_items[item_id])])
			craft_button.text = "Schmieden: %s (%s) – %s" % [
				def.display_name, ", ".join(bonus_parts), ", ".join(cost_parts),
			]
			craft_button.disabled = not Game.state.can_craft(def.id)

	var stats := Game.state.hero_stats()
	_hero_label.text = "LP %s · Angriff %s" % [stats["hp"].format(), stats["atk"].format()]
	var equipped_parts: Array[String] = []
	for slot: String in Game.state.equipment:
		var equipped := ContentDB.recipe(str(Game.state.equipment[slot]))
		if equipped != null:
			equipped_parts.append(equipped.display_name)
	_equipment_label.visible = not equipped_parts.is_empty()
	if _equipment_label.visible:
		_equipment_label.text = "Ausrüstung: " + " · ".join(equipped_parts)
	var hp_cost := Game.state.training_cost("hp")
	var atk_cost := Game.state.training_cost("atk")
	_train_hp_button.text = "Zäher werden (+%s LP) – %s Gold" % [BigNum.from_float(Balance.HERO_HP_PER_TRAINING).format(), hp_cost.format()]
	_train_atk_button.text = "Härter zuschlagen (+%s) – %s Gold" % [BigNum.from_float(Balance.HERO_ATK_PER_TRAINING).format(), atk_cost.format()]
	_train_hp_button.disabled = gold.lt(hp_cost)
	_train_atk_button.disabled = gold.lt(atk_cost)

	var run_active := Game.is_run_active()
	for def in ContentDB.dungeons():
		var row: Control = _dungeon_rows[def.id]
		row.visible = Game.state.is_dungeon_unlocked(def)
		if not row.visible:
			continue
		var button: Button = _dungeon_buttons[def.id]
		var cleared := "✓ " if Game.state.dungeons_cleared.has(def.id) else ""
		button.text = "%s%s betreten" % [cleared, def.display_name]
		button.disabled = run_active

	# Taverne: verdiente Erzählungen zeigen.
	_tavern_section.visible = Game.state.tale_count() > 0
	if _tavern_section.visible:
		_tavern_count_label.text = "Der Tavernenwirt kennt %d Geschichten über dich." % Game.state.tale_count()
		for def in ContentDB.tales():
			_tale_rows[def.id].visible = Game.state.has_tale(def.id)

	var pending := Game.state.pending_fragments()
	var revealed: bool = Game.state.prestige_count > 0 or not Game.state.fragments.is_zero() or Game.state.can_prestige()
	_saga_section.visible = revealed
	if revealed:
		var gold_bonus := Game.state.fragments.mul(BigNum.from_float(Balance.FRAGMENT_GOLD_BONUS * 100.0))
		var atk_bonus := Game.state.fragments.mul(BigNum.from_float(Balance.FRAGMENT_ATK_BONUS * 100.0))
		_fragments_label.text = "Liedfragmente: %s (gehalten: +%s%% Gold, +%s%% Angriff)" % [
			Game.state.fragments.format(), gold_bonus.format(), atk_bonus.format(),
		]
		_prestige_button.text = "Die Sage neu erzählen (+%s Liedfragmente)" % pending.format()
		_prestige_button.disabled = not Game.state.can_prestige() or run_active
		# Der Perma-Baum selbst zeigt sich erst nach dem ersten Prestige.
		var tree_unlocked: bool = Game.state.prestige_count > 0
		for def in ContentDB.perma_upgrades():
			var row: Control = _perma_rows[def.id]
			row.visible = tree_unlocked
			if not tree_unlocked:
				continue
			var button: Button = _perma_buttons[def.id]
			var cost := Game.state.perma_cost(def.id)
			button.text = "%s (Stufe %d) – %s Liedfragmente" % [def.display_name, Game.state.perma_level(def.id), cost.format()]
			button.disabled = Game.state.fragments.lt(cost)

	_flee_button.visible = run_active
	_strike_button.visible = run_active
	_breather_button.visible = run_active
	_door_row.visible = run_active and Game.run.phase == RunState.Phase.CHOOSING
	if run_active:
		var run := Game.run
		if run.phase == RunState.Phase.CHOOSING:
			_run_status_label.text = "%s – der Gang gabelt sich. | Held: %s/%s LP | Beute: %s Gold" % [
				run.dungeon.display_name,
				run.hero_hp.format(), run.hero_max_hp.format(),
				run.gold_earned.format(),
			]
		else:
			var room_text := "Bossraum" if run.is_boss_room() else "Raum %d/%d" % [run.current_room, run.dungeon.rooms]
			_run_status_label.text = "%s – %s | Held: %s/%s LP | %s: %s/%s LP | Beute: %s Gold" % [
				run.dungeon.display_name, room_text,
				run.hero_hp.format(), run.hero_max_hp.format(),
				run.enemy_name, run.enemy_hp.format(), run.enemy_max_hp.format(),
				run.gold_earned.format(),
			]
		if run.strike_cooldown == 0:
			_strike_button.text = "Zuschlagen (×%s)" % String.num(Balance.STRIKE_DAMAGE_MULT, 1)
		else:
			_strike_button.text = "Zuschlagen (%.1fs)" % (run.strike_cooldown * Balance.COMBAT_TICK_SECONDS)
		_strike_button.disabled = not run.can_strike()
		if run.breather_cooldown == 0:
			_breather_button.text = "Verschnaufen (+%d%% LP)" % int(Balance.BREATHER_HEAL_FRACTION * 100.0)
		else:
			_breather_button.text = "Verschnaufen (%.1fs)" % (run.breather_cooldown * Balance.COMBAT_TICK_SECONDS)
		_breather_button.disabled = not run.can_breathe()
		var bag_parts: Array[String] = []
		for item_id: String in run.items_found:
			var item_def := ContentDB.item(item_id)
			if item_def != null:
				bag_parts.append("%s ×%d" % [item_def.display_name, run.items_found[item_id]])
		_bag_label.visible = not bag_parts.is_empty()
		if _bag_label.visible:
			_bag_label.text = "Beutel: " + " · ".join(bag_parts)


func _on_buy_pressed(generator_id: String) -> void:
	Game.buy_generator(generator_id, 1)


func _on_start_run_pressed(dungeon_id: String) -> void:
	Game.start_run(dungeon_id)


func _on_run_started(dungeon_id: String) -> void:
	_log_lines.clear()
	var def := ContentDB.dungeon(dungeon_id)
	_append_log("Du betrittst %s…" % def.display_name)
	_run_panel.visible = true


func _on_run_tick(events: Array) -> void:
	for event: Dictionary in events:
		match event.get("type", ""):
			"enemy_defeated":
				_append_log("%s besiegt! +%s Gold" % [event["enemy"], event["gold"].format()])
			"room_entered":
				if event.get("is_boss", false):
					_append_log("Der Bossraum… %s wartet!" % event["enemy"])
				elif int(event.get("room_type", RunState.RoomType.NORMAL)) == RunState.RoomType.ELITE:
					_append_log("Die Schatzkammer! %s bewacht sie." % event["enemy"])
				else:
					_append_log("Raum %d: %s stellt sich dir." % [event["room"], event["enemy"]])
			"doors_offered":
				_append_log("Der Gang gabelt sich. Wohin?")
			"rested":
				_append_log("Rastplatz: Du verschnaufst (+%s LP)." % event["amount"].format())
			"strike":
				_append_log("Du holst aus: %s Extra-Schaden!" % event["damage"].format())
			"breather":
				_append_log("Kurz durchatmen: +%s LP." % event["amount"].format())
			"item_dropped":
				var item_def := ContentDB.item(str(event.get("item_id", "")))
				if item_def != null:
					_append_log("Gefunden: %s!" % item_def.display_name)
			"hero_died":
				_append_log("Du gehst zu Boden. Die Beute nimmst du trotzdem mit.")
			"run_complete":
				_append_log("Dungeon geschafft! Gesamtbeute: %s Gold" % event["gold_total"].format())


func _on_sell_pressed(item_id: String, count: int) -> void:
	Game.sell_item(item_id, count)


func _on_craft_pressed(recipe_id: String) -> void:
	Game.craft(recipe_id)


func _on_upgrade_pressed(upgrade_id: String) -> void:
	Game.buy_generator_upgrade(upgrade_id)


func _on_run_finished(run_result: Dictionary) -> void:
	match int(run_result.get("status", RunState.Status.FLED)):
		RunState.Status.VICTORY:
			_append_log("Die Barden haben das gesehen. Die Geschichte wächst.")
		RunState.Status.DEFEAT:
			_append_log("Zurück im Dorf. Die Oma verbindet deine Wunden.")
		RunState.Status.FLED:
			_append_log("Rückzug! Kann ja jedem mal passieren.")
	_run_status_label.text = "Run beendet – Beute: %s Gold" % run_result.get("gold", BigNum.zero()).format()


func _append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > LOG_LINES:
		_log_lines.remove_at(0)
	_run_log_label.text = "\n".join(_log_lines)


func _on_prestige_pressed() -> void:
	_prestige_confirm.dialog_text = (
		"Die Barden dichten deine Sage in Strophen – und erzählen sie von vorn, aber besser.\n\n"
		+ "Es bleibt: Liedfragmente (+%s), der Perma-Baum, Rezepte, freigeschaltete Dungeons.\n" % Game.state.pending_fragments().format()
		+ "Es geht: Gold, Dorfhelfer, Ausbauten, Training, Ausrüstung, Beute."
	)
	_prestige_confirm.popup_centered()


func _on_buy_perma_pressed(upgrade_id: String) -> void:
	Game.buy_perma(upgrade_id)


func _on_prestige_performed(report: Dictionary) -> void:
	var retelling := int(report.get("prestige_count", 1)) - 1
	_prestige_result.dialog_text = "„%s“\n\n+%s Liedfragmente (gesamt: %s)" % [
		ContentDB.saga_line(retelling),
		report.get("fragments_gained", BigNum.zero()).format(),
		report.get("fragments_total", BigNum.zero()).format(),
	]
	_prestige_result.popup_centered()
	_run_panel.visible = false
	_log_lines.clear()
	_run_log_label.text = ""


func _on_tale_earned(tale_id: String) -> void:
	var def := ContentDB.tale(tale_id)
	if def != null:
		_append_log("Neue Tavernenerzählung: „%s“" % def.display_name)


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
