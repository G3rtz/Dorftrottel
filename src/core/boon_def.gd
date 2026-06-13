class_name BoonDef
extends RefCounted

## Ein Segen: temporärer Buff für GENAU EINEN Run – daraus entstehen
## Builds. Nach jedem erkämpften Raum (nicht Rast, nicht Boss) wird
## eine Auswahl aus dem Pool angeboten; Stapeln ist erlaubt, bis
## max_stacks erreicht ist (0 = unbegrenzt).

const KNOWN_EFFECTS: Array[String] = [
	"atk_mult",      # +X Angriff (multiplikativ auf den Run)
	"block_bonus",   # Blocken verhindert +X mehr (Deckel 95%)
	"lifesteal",     # heilt X des ausgeteilten Schadens
	"heal_on_kill",  # heilt X der Max-LP pro Kill
	"max_hp_mult",   # +X maximale LP, Differenz sofort geheilt
	"strike_cd",     # Zuschlagen-Cooldown -X Züge (min. 1)
	"gold_mult",     # +X Gold im Run
	"drop_mult",     # +X Drop-Chance (Deckel: sicher)
	"thorns",        # Gegner erleidet X deines Angriffs, wenn er trifft
]

var id: String = ""
var display_name: String = ""
var flavor: String = ""
var effect: String = ""
var amount: float = 0.0
var max_stacks: int = 0


static func from_dict(data: Dictionary) -> BoonDef:
	var def := BoonDef.new()
	def.id = str(data.get("id", ""))
	def.display_name = str(data.get("display_name", ""))
	def.flavor = str(data.get("flavor", ""))
	def.effect = str(data.get("effect", ""))
	def.amount = float(data.get("amount", 0.0))
	def.max_stacks = int(data.get("max_stacks", 0))
	return def


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id fehlt")
	if display_name.is_empty():
		problems.append("display_name fehlt")
	if not KNOWN_EFFECTS.has(effect):
		problems.append("unbekannter Effekt '%s'" % effect)
	if amount <= 0.0:
		problems.append("amount muss > 0 sein")
	if max_stacks < 0:
		problems.append("max_stacks muss >= 0 sein")
	return problems


## Menschenlesbare Wirkung für die UI.
func description() -> String:
	var percent := int(round(amount * 100.0))
	match effect:
		"atk_mult":
			return "+%d%% Angriff" % percent
		"block_bonus":
			return "Blocken verhindert +%d%% mehr" % percent
		"lifesteal":
			return "%d%% Lebensraub" % percent
		"heal_on_kill":
			return "+%d%% LP pro Kill" % percent
		"max_hp_mult":
			return "+%d%% maximale LP, sofort geheilt" % percent
		"strike_cd":
			return "Zuschlagen-Cooldown -%d" % int(amount)
		"gold_mult":
			return "+%d%% Gold in diesem Run" % percent
		"drop_mult":
			return "+%d%% Drop-Chance" % percent
		"thorns":
			return "Angreifer erleiden %d%% deines Angriffs" % percent
	return ""
