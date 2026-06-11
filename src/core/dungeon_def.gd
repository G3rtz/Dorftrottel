class_name DungeonDef
extends RefCounted

## Definition eines Dungeons. Wie Generatoren: Content ist Daten
## (res://data/dungeons.json), kein Code. Gegner skalieren pro Raum
## geometrisch, der Boss ist ein Vielfaches des letzten Raums.

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var rooms: int = 0
var enemy_names: Array = []
var boss_name: String = ""
var enemy_hp: float = 0.0
var enemy_atk: float = 0.0
var hp_growth: float = 1.0
var atk_growth: float = 1.0
var boss_hp_mult: float = 1.0
var boss_atk_mult: float = 1.0
var heal_per_room: float = 0.0
var gold_per_enemy: float = 0.0
var gold_growth: float = 1.0
var boss_gold: float = 0.0
var completion_bonus: float = 0.0
## ID des Dungeons, der zuerst abgeschlossen sein muss ("" = sofort verfügbar).
var unlocked_by: String = ""


static func from_dict(data: Dictionary) -> DungeonDef:
	var def := DungeonDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.rooms = int(data.get("rooms", 0))
	def.enemy_names = data.get("enemy_names", [])
	def.boss_name = str(data.get("boss_name", ""))
	def.enemy_hp = float(data.get("enemy_hp", 0.0))
	def.enemy_atk = float(data.get("enemy_atk", 0.0))
	def.hp_growth = float(data.get("hp_growth", 1.0))
	def.atk_growth = float(data.get("atk_growth", 1.0))
	def.boss_hp_mult = float(data.get("boss_hp_mult", 1.0))
	def.boss_atk_mult = float(data.get("boss_atk_mult", 1.0))
	def.heal_per_room = float(data.get("heal_per_room", 0.0))
	def.gold_per_enemy = float(data.get("gold_per_enemy", 0.0))
	def.gold_growth = float(data.get("gold_growth", 1.0))
	def.boss_gold = float(data.get("boss_gold", 0.0))
	def.completion_bonus = float(data.get("completion_bonus", 0.0))
	def.unlocked_by = str(data.get("unlocked_by", ""))
	return def


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if rooms < 1:
		problems.append("rooms muss >= 1 sein")
	if enemy_names.is_empty():
		problems.append("enemy_names fehlt")
	if boss_name.is_empty():
		problems.append("boss_name fehlt")
	if enemy_hp <= 0.0:
		problems.append("enemy_hp muss > 0 sein")
	if enemy_atk <= 0.0:
		problems.append("enemy_atk muss > 0 sein")
	if hp_growth < 1.0 or atk_growth < 1.0 or gold_growth < 1.0:
		problems.append("Wachstumsfaktoren müssen >= 1 sein")
	if boss_hp_mult < 1.0 or boss_atk_mult < 1.0:
		problems.append("Boss-Multiplikatoren müssen >= 1 sein")
	if heal_per_room < 0.0 or gold_per_enemy < 0.0 or boss_gold < 0.0 or completion_bonus < 0.0:
		problems.append("Beträge dürfen nicht negativ sein")
	return problems


## room ist 1-basiert; rooms + 1 ist der Bossraum.
func is_boss_room(room: int) -> bool:
	return room > rooms


func enemy_hp_for(room: int) -> BigNum:
	var scaled := BigNum.from_float(enemy_hp).mul(BigNum.from_log10(float(room - 1) * (log(hp_growth) / log(10.0))))
	if is_boss_room(room):
		return scaled.mul(BigNum.from_float(boss_hp_mult))
	return scaled


func enemy_atk_for(room: int) -> BigNum:
	var scaled := BigNum.from_float(enemy_atk).mul(BigNum.from_log10(float(room - 1) * (log(atk_growth) / log(10.0))))
	if is_boss_room(room):
		return scaled.mul(BigNum.from_float(boss_atk_mult))
	return scaled


func gold_for(room: int) -> BigNum:
	if is_boss_room(room):
		return BigNum.from_float(boss_gold)
	return BigNum.from_float(gold_per_enemy).mul(BigNum.from_log10(float(room - 1) * (log(gold_growth) / log(10.0))))


func enemy_name_for(room: int) -> String:
	if is_boss_room(room):
		return boss_name
	return str(enemy_names[(room - 1) % enemy_names.size()])
