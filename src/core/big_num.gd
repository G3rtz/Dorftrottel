class_name BigNum
extends RefCounted

## Zahl beliebiger Größenordnung als Mantisse * 10^Exponent.
##
## Floats werden ab ~10^15 ungenau – für Idle-Wachstum brauchen wir mehr.
## Die Mantisse ist 0 oder hat einen Betrag in [1, 10); das Vorzeichen
## steckt in der Mantisse. Alle Operationen geben neue Instanzen zurück
## (Werte werden nie in-place verändert).

## Ab dieser Exponenten-Differenz geht der kleinere Summand in der
## Float-Präzision der Mantisse ohnehin unter und wird ignoriert.
const PRECISION_EXP := 17

const SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

var m: float = 0.0
var e: int = 0


static func zero() -> BigNum:
	return BigNum.new()


static func one() -> BigNum:
	return from_float(1.0)


static func from_float(value: float) -> BigNum:
	return from_parts(value, 0)


static func from_parts(mantissa: float, exponent: int) -> BigNum:
	var n := BigNum.new()
	n.m = mantissa
	n.e = exponent
	n._normalize()
	return n


## Baut 10^l. Nützlich, wenn pow() als Float überlaufen würde,
## z.B. für Wachstum^Anzahl bei großen Bulk-Käufen.
static func from_log10(l: float) -> BigNum:
	var exponent := floori(l)
	return from_parts(pow(10.0, l - float(exponent)), exponent)


static func from_dict(data: Dictionary) -> BigNum:
	return from_parts(float(data.get("m", 0.0)), int(data.get("e", 0)))


func to_dict() -> Dictionary:
	return {"m": m, "e": e}


func copy() -> BigNum:
	var n := BigNum.new()
	n.m = m
	n.e = e
	return n


func is_zero() -> bool:
	return m == 0.0


func signum() -> int:
	if m == 0.0:
		return 0
	return 1 if m > 0.0 else -1


func negated() -> BigNum:
	return BigNum.from_parts(-m, e)


func add(other: BigNum) -> BigNum:
	if is_zero():
		return other.copy()
	if other.is_zero():
		return copy()
	var diff := e - other.e
	if diff > PRECISION_EXP:
		return copy()
	if diff < -PRECISION_EXP:
		return other.copy()
	return BigNum.from_parts(m + other.m * pow(10.0, float(-diff)), e)


func sub(other: BigNum) -> BigNum:
	return add(other.negated())


func mul(other: BigNum) -> BigNum:
	if is_zero() or other.is_zero():
		return BigNum.zero()
	return BigNum.from_parts(m * other.m, e + other.e)


func div(other: BigNum) -> BigNum:
	if other.is_zero():
		push_error("BigNum: Division durch null")
		return BigNum.zero()
	if is_zero():
		return BigNum.zero()
	return BigNum.from_parts(m / other.m, e - other.e)


## Ganzzahlige Potenz über binäre Exponentiation (überlaufsicher).
func pow_int(n: int) -> BigNum:
	assert(n >= 0, "BigNum.pow_int unterstützt nur Exponenten >= 0")
	var result := BigNum.one()
	var base := copy()
	var k := n
	while k > 0:
		if k & 1:
			result = result.mul(base)
		base = base.mul(base)
		k >>= 1
	return result


## Quadratwurzel: Exponent halbieren (nach Begradigung auf gerade),
## Wurzel der Mantisse – funktioniert für jede Größenordnung.
func square_root() -> BigNum:
	if is_zero():
		return BigNum.zero()
	if m < 0.0:
		push_error("BigNum: Wurzel aus negativer Zahl")
		return BigNum.zero()
	var mm := m
	var ee := e
	if ee % 2 != 0:
		mm *= 10.0
		ee -= 1
	return BigNum.from_parts(sqrt(mm), int(ee / 2.0))


## Abrunden auf die nächste Ganzzahl. Jenseits von ~10^15 trägt die
## Mantisse ohnehin keine Nachkommastellen mehr.
func floored() -> BigNum:
	if is_zero() or e >= 15:
		return copy()
	return BigNum.from_float(floorf(to_float()))


## log10 als Float – für Skalen-Mathe wie den Max-Kauf-Löser.
## Passt für jeden Exponenten bequem in einen Float.
func log10f() -> float:
	if m <= 0.0:
		push_error("BigNum: log10 von 0 oder negativ")
		return 0.0
	return float(e) + log(m) / log(10.0)


## -1 / 0 / +1 wie ein klassischer Comparator. Mantissen werden
## näherungsweise verglichen, damit Float-Rauschen (99.999999999 vs 100)
## keine "kann ich mir nicht leisten"-Fehler produziert – auch über
## Dekadengrenzen hinweg, wo sich die Exponenten unterscheiden.
func cmp(other: BigNum) -> int:
	var sa := signum()
	var sb := other.signum()
	if sa != sb:
		return 1 if sa > sb else -1
	if sa == 0:
		return 0
	var diff := e - other.e
	if diff > 1:
		return sa
	if diff < -1:
		return -sa
	# Nah genug beieinander: auf gemeinsamen Exponenten skalieren und
	# die Mantissen (inkl. Vorzeichen) direkt vergleichen.
	var scaled := other.m * pow(10.0, float(-diff))
	if is_equal_approx(m, scaled):
		return 0
	return 1 if m > scaled else -1


func gte(other: BigNum) -> bool:
	return cmp(other) >= 0


func lt(other: BigNum) -> bool:
	return cmp(other) < 0


## Verlustbehaftet – nur für Anzeige, Sounds, Animationen etc. verwenden,
## nie für Spiellogik.
func to_float() -> float:
	if is_zero():
		return 0.0
	if e > 308:
		return INF * float(signum())
	if e < -308:
		return 0.0
	return m * pow(10.0, float(e))


## Anzeigeformat: 999 → "999", 1234 → "1.23K", danach M/B/T/...,
## jenseits der Suffixliste wissenschaftlich ("1.23e42").
func format(decimals: int = 2) -> String:
	if is_zero():
		return "0"
	if m < 0.0:
		return "-" + negated().format(decimals)
	if e < 0:
		return _trim(String.num(to_float(), decimals))
	var group := int(float(e) / 3.0)
	if group < SUFFIXES.size():
		var value := m * pow(10.0, float(e - group * 3))
		return _trim(String.num(value, decimals)) + SUFFIXES[group]
	return _trim(String.num(m, decimals)) + "e" + str(e)


func _to_string() -> String:
	return format()


static func _trim(s: String) -> String:
	if not s.contains("."):
		return s
	return s.rstrip("0").rstrip(".")


func _normalize() -> void:
	if is_nan(m) or is_inf(m):
		push_error("BigNum: ungültige Mantisse (%s), auf 0 zurückgesetzt" % m)
		m = 0.0
		e = 0
		return
	if m == 0.0:
		e = 0
		return
	var a := absf(m)
	if a >= 1.0 and a < 10.0:
		return
	var shift := floori(log(a) / log(10.0))
	m = m / pow(10.0, float(shift))
	e += shift
	if m == 0.0 or is_inf(m) or is_nan(m):
		# Extreme Größenordnungen jenseits des Float-Bereichs.
		push_error("BigNum: Normalisierung außerhalb des Float-Bereichs, auf 0 zurückgesetzt")
		m = 0.0
		e = 0
		return
	# Float-Randfälle an den Intervallgrenzen korrigieren.
	while absf(m) >= 10.0:
		m /= 10.0
		e += 1
	while absf(m) < 1.0:
		m *= 10.0
		e -= 1
