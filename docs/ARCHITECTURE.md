# Architektur

Technische Leitplanken für „Der Dorftrottel". Ziel: Die im GDD geplanten
Systeme (Dungeon-Runs, Talentbäume, Prestige) sollen später **additiv**
andocken können, ohne dass Fundament umgebaut werden muss.

## Schichtenmodell

```
src/core/      Reine Simulationslogik. RefCounted, keine Nodes, keine
               Signale, keine UI, kein Zugriff auf den SceneTree.
               → headless testbar, engine-unabhängig denkbar.
src/autoload/  Dünne Engine-Adapter (Singletons). Verdrahten core mit
               der Godot-Schleife: Ticken, Laden/Speichern, Signale.
src/ui/        Nur Darstellung. Liest Zustand, ruft Game-Methoden auf.
data/          Spielinhalte als JSON. Content ist Daten, kein Code.
tests/         Eigener schlanker Testrunner, keine Addon-Abhängigkeit.
```

**Eiserne Regel:** Spiellogik lebt in `src/core/`. Wenn eine Funktion
einen Node, ein Signal oder die UI braucht, gehört sie nicht in core –
und wenn sie Spielregeln enthält, gehört sie nicht in autoload/ui.

Abhängigkeitsrichtung: `ui → autoload → core`. Niemals umgekehrt.
Die UI erfährt Änderungen über den `EventBus` (Signale), nicht über
direkte Aufrufe aus der Simulation.

## BigNum (`src/core/big_num.gd`)

Floats werden ab ~10^15 ungenau, Idle-Zahlen sprengen das schnell.
Alle Spielwerte (Ressourcen, Kosten, Raten) sind deshalb `BigNum`:
Mantisse (`float` in [1,10)) + Exponent (`int`).

- Operationen sind **immutabel** (geben neue Instanzen zurück) – kein
  versehentliches Aliasing von Beständen.
- `cmp()` vergleicht mit Float-Toleranz, auch über Dekadengrenzen,
  damit Rundungsrauschen keine Fehlkäufe/Fehlanzeigen produziert.
- `from_log10()` für Formeln wie `growth^n`, die als Float überlaufen
  würden (Bulk-Kauf-Kosten!).
- `to_float()` ist verlustbehaftet und nur für Anzeige/Effekte erlaubt.

## Produktionsmodell: geschlossene Form

Produktion ist **Rate × Zeit** (`GameState.advance(seconds)`), kein
inkrementelles Aufsummieren pro Frame. Dadurch gilt: ein 0.1s-Tick und
12h Offline-Zeit laufen durch **denselben Code** und liefern exakt
dasselbe Ergebnis (per Test abgesichert). Offline-Progress ist damit
kein Sonderfall, sondern nur ein großer `advance()`-Aufruf mit Cap und
Wirkungsgrad (`GameState.apply_offline`).

Der feste Tick (`Balance.TICK_SECONDS`) existiert trotzdem, weil
künftige Mechaniken mit Dauer (Buffs, Run-Timer, Events) Determinismus
brauchen. Lange Frame-Pausen (App-Suspend) werden in einem Schritt
nachgebucht statt zu iterieren.

## Save-System (`src/core/save_io.gd`)

Drei Garantien:

1. **Atomares Schreiben:** erst `save.json.tmp`, dann Rename. Ein
   Absturz mitten im Schreiben kann den bestehenden Save nie zerstören.
2. **Backup-Rotation:** der vorherige Save bleibt als
   `save.backup.json` erhalten; `read()` probiert Save → Backup.
3. **Versionierung + Migration:** der Umschlag trägt `version`. Alte
   Saves werden beim Laden schrittweise migriert (`_migrate`), Saves
   aus *neueren* Spielversionen werden abgelehnt statt zerschrieben.

Save-Payload (`GameState.to_dict`) ist von Anfang an in Sektionen
aufgeteilt – die leeren Sektionen sind **reservierte Andockpunkte**:

```json
{
  "village": { "resources": {}, "lifetime_earned": {}, "generators": {} },
  "hero":    {},   // später: Run-Zustand, Hero-Talentbaum
  "perma":   {},   // später: Perma-Baum, Rezepte, Klassen, Ruhm
  "meta":    { "total_playtime": 0, "prestige_count": 0 }
}
```

Das spiegelt die Prestige-Regel aus dem GDD: Beim Prestige wird
`village` + `hero` geleert, `perma` + `meta` überleben („alles im
Hirn bleibt").

`lifetime_earned` (je verdient, sinkt nie) ist getrennt vom Bestand –
Freischaltungen hängen daran, damit Ausgeben nichts wieder versteckt.

## Content als Daten (`data/*.json`)

Generatoren (und später Dungeons, Klassen, …) sind JSON-Einträge, die
`ContentDB` lädt und **validiert** – kaputte Einträge werden mit
Fehlermeldung übersprungen, nicht gecrasht. Ein CI-Test prüft
zusätzlich die Progression der echten Daten (Kosten/Unlocks
aufsteigend). Balance-Konstanten liegen zentral in
`src/core/balance.gd`, nie verstreut im Code.

Die Kernressource heißt vorläufig `gold` und wird ausschließlich über
`Balance.PRIMARY_RESOURCE` referenziert – die Benennung ist laut GDD
noch offen und damit eine Ein-Zeilen-Änderung.

## Dungeon-Runs (v1)

`RunState` (core) ist eine rein deterministische Simulation: ein
`step()` = ein Kampf-Tick, der Held schlägt zuerst, ein sterbender
Gegner schlägt nicht mehr zurück. Die Engine (`Game`) ruft `step()`
nur im Takt von `Balance.COMBAT_TICK_SECONDS` auf – Tempo ist
Darstellung, nicht Logik. Dadurch sind komplette Runs in Tests
nachrechenbar.

**v1-Entscheidungen** (offene Fragen aus dem GDD §8):

- **Run-Länge:** kurz – `rooms` Räume + Bossraum, beim ersten Dungeon
  ~10–15 Sekunden. Aktives Spielen soll snackbar sein.
- **Tod:** beendet den Run, gesammelte Beute **bleibt** (kein
  Frust-Reset), nur Boss-Belohnung und Abschluss-Bonus entfallen.
  Fliehen geht jederzeit mit demselben Effekt.
- **Permanenz:** nur der **Sieg** schreibt in die perma-Sektion
  (`dungeons_cleared`) – das schaltet per `unlocked_by`-Kette weitere
  Dungeons frei (Rattenkeller → Eishöhle, das GDD-Beispiel) und
  überlebt später das Prestige ("im Hirn").
- **Kein Persistieren laufender Runs:** App zu = Run vorbei. Runs sind
  die aktive Schicht; sie laufen auch nicht offline weiter.

**Training** ist die v1-Brücke "Idle finanziert Runs": Gold gegen
Heldenwerte (`hero_hp_level`/`hero_atk_level`, hero-Sektion, resettet
beim Prestige). `GameState.hero_stats()` ist der einzige Ort, an dem
Heldenwerte berechnet werden – Talente und Ausrüstung docken später
dort an, analog zu `production_per_second()` auf der Idle-Seite.

### Kampf im Run (v3): rundenbasiert und manuell

Der Kampf spielt sich wie ein eigenständiges Roguelite: **nichts
passiert, bis der Spieler handelt.** Kein Auto-Tick – jede Aktion ist
ein Zug (`RunState.take_action`), Cooldowns zählen in Zügen:

- **Angriff** – normaler Schlag; überlebt der Gegner, schlägt er zurück.
- **Zuschlagen** – ×2 Schaden, 3 Züge Cooldown. Tödliche Treffer
  verhindern den Gegenschlag → Finisher-Timing ist Skill.
- **Blocken** – kein eigener Schaden, −70% eingehender Schaden.
- **Verschnaufen** – +30% LP, aber der Gegner schlägt frei zu;
  10 Züge Cooldown.

Der taktische Kern: Gegner **telegrafieren ihre Absicht**
(`enemy_intent`, seeded RNG) – normal oder schwerer Schlag (×2,
25% Chance). Schwere Schläge blockt man, oder man tötet vorher.
Tests erzwingen die Absicht vor jedem Zug, wo exakte Mathematik
geprüft wird; die Balance-Wächter simulieren mit einem Bot, der
minimale Spielintelligenz modelliert (Heavy + wenig LP → Block) über
mehrere Seeds.

- **Raumwahl** wie gehabt: Nach jedem Raum (außer vor dem Boss) ruht
  der Run in `Phase.CHOOSING`: *Weitergehen* / *Schatzkammer*
  (Wächter ×1.6 LP / ×1.3 ATK, dafür ×2 Gold und ×3 Drop-Chance) /
  *Rastplatz* (+40% LP, keine Beute).
- Da der Run auf den Spieler wartet, gibt es keinerlei Zeitdruck –
  Idle-Schicht und Run-Schicht koexistieren konfliktfrei.

### In-Run-Segen (Boons): der Build-Layer

Nach jedem erkämpften Raum (außer Boss) wählt der Spieler 1 aus
`BOON_OFFER_COUNT` zufälligen Segen (`Phase.CHOOSING_BOON`), die nur
für DIESEN Run gelten – daraus entstehen Builds. `BoonDef`
(`data/boons.json`) deklariert Effekt + Betrag + `max_stacks`; neun
Effekte sind verdrahtet: `atk_mult`, `block_bonus` (Deckel 95%),
`lifesteal`, `heal_on_kill`, `max_hp_mult` (Zugewinn sofort geheilt),
`strike_cd` (Boden 1), `gold_mult`, `drop_mult`, `thorns` (kann
töten). Summiert über `boon_amount(effect)`; `effective_atk()` ist der
einzige Schadensursprung.

- **Reihenfolge pro Raum:** Kill → Segenswahl → Türwahl → nächster
  Raum. Vor dem Boss entfällt die Türwahl, der Segen kommt aber noch.
- **Pool injizierbar:** `RunState.start(..., boon_pool)` – die
  Combat-Tests übergeben `[]` (segenlos), damit ihre Mathematik exakt
  bleibt; Segen haben ihre eigene Suite (`test_boons.gd`). Das Spiel
  zieht aus `ContentDB.boons()`. (Untypisierte Pools werden via
  `Array.assign()` nach `Array[BoonDef]` coerciert – direkte Zuweisung
  würde zur Laufzeit crashen.)
- **Auswahl ist seeded** (Fisher-Yates mit dem Run-RNG): gleicher Seed
  → gleiches Angebot. Segen am Stapellimit fallen aus dem Angebot;
  ist nichts mehr übrig, geht es ohne Auswahl weiter.
- Boons sind reiner Run-Zustand – nichts davon wird persistiert.

### Drops & Beuteverwaltung (v2)

Gegner würfeln beim Tod gegen die Drop-Tabelle des Dungeons
(`drops` pro Raumgegner, `boss_drops` für den Boss; Einträge
`{item_id, chance}`). Der Zufall ist **geseedet** (`RunState.start`
nimmt einen Seed) – gleicher Seed, gleiche Wege, gleiche Drops; Tests
nutzen das. Items sind Content (`data/items.json`, von ContentDB
validiert inkl. Querverweis aus den Drop-Tabellen) und zerfallen in
zwei Welten, exakt entlang der GDD-Regel "Ausrüstung vergänglich,
Wissen bleibt":

- **Trophäen** → Dorf-Inventar (village-Sektion), beim Krämer
  verkaufbar (Erlös zählt als verdient → Ruhm), weg beim Prestige.
  Später werden sie Crafting-Material.
- **Liedfragmente** → Liederbuch (perma-Sektion), überleben das
  Prestige; als Boss-Drops der Wiederholungsgrund für Dungeons und
  die Vorstufe zur Klassen-Freischaltung (GDD §5).

**Balance-Wächter in CI:** Tests simulieren echte Runs mit den echten
Daten aus `data/dungeons.json` und beweisen: Dungeon 1 ist mit
Basiswerten schaffbar, Dungeon 2 erst mit Training (aber mit
vertretbar viel). Balance-Edits, die das brechen, scheitern in CI.

### Crafting (v1)

Die "goldene Regel" als System: `RecipeDef` (`data/recipes.json`)
braucht Gold (Dorf) + Trophäen (Beute) und setzt das Ergebnis in
einen Ausrüstungs-Slot (weapon/armor, flache ATK/LP-Boni über
`hero_stats()`). Rezept-Wissen ist perma (Start-Rezepte oder
Boss-Drops vom Item-Typ "recipe", Duplikate verpuffen), die
geschmiedete Ausrüstung ist hero-Sektion und damit weg beim
Prestige – "Ausrüstung vergänglich, Wissen bleibt". Verkaufen
oder verschmieden ist die Beutestand-Entscheidung.

### Dorf-Ausbauten

`GeneratorUpgradeDef` (`data/generator_upgrades.json`): einmalige
Raten-Multiplikatoren pro Generator, freigeschaltet ab
`unlock_at_owned` Stück – der klassische "Kauf mich!"-Moment.
Multiplikatoren stapeln multiplikativ in
`GameState.generator_multiplier()`, village-Sektion (weg beim
Prestige). Das Dorf hat die vollen 10 Bewohner-Generatoren aus der
GDD-Checkliste.

Die frühen Stufen (5/25) sind handgeschrieben mit Flavor; die hohen
Staffeln (**50/100/150/200/250/500/1000**, je ×2) **generiert
ContentDB** pro Generator (`_generate_upgrade_tiers`), Kosten
verankert am Generatorpreis an der Schwelle. Die tiefen Schwellen
sind ohne Prestige-Multiplikatoren praktisch unerreichbar – genau
dadurch lohnt sich jedes weitere Prestige. Generierte IDs
(`<generator>_tier_<schwelle>`) sind save-relevant und müssen stabil
bleiben.

## Prestige: Die Barden-Sage (v2: Liedfragmente)

**Liedfragmente sind DIE Prestige-Währung** (der frühere "Ruhm" ging
darin auf; Save-Migration v1→v2 benennt `perma.fame` um). Zwei
Quellen, damit beide Loops einzahlen:

1. **Prestige:** `floor(sqrt(Lifetime-Gold der Sage / FRAGMENT_BASE_GOLD))`
   – sublinear, Lifetime statt Bestand.
2. **Boss-Drops:** Lied-Items zahlen beim Verbuchen zusätzlich in den
   Pool ein (und stehen dauerhaft im Liederbuch – Ausgeben verwebt
   Strophen, löscht aber kein gelerntes Lied).

**Halten vs. Ausgeben:** Gehaltene Fragmente geben passiv
+2% Gold / +1% Helden-ATK pro Stück (`fragment_*_multiplier()`,
komplett in BigNum gerechnet). Ausgeben füttert den Perma-Baum.
Linearer Halte-Bonus gegen geometrische Baumkosten → früh lohnt der
Baum, später wird Halten attraktiv; balanciert sich selbst.

`GameState.prestige()` setzt um, was das Save-Format von Anfang an
versprochen hat: `village` (Ressourcen, Lifetime, Generatoren) und
`hero` (Training) werden geleert; `perma` (Ruhm, Perma-Stufen,
Dungeon-Freischaltungen) und `meta` (Zähler, Spielzeit) bleiben.

**Perma-Upgrades** (`data/perma_upgrades.json`) sind der "Mehr, mehr,
mehr"-Baum: Gold-Multiplikator, Helden-Multiplikatoren, Startgold.
Die Designregel "beschleunigen, nie skippen" ist technisch erzwungen:
`PermaUpgradeDef.validate()` lehnt jeden Effekt ab, der nicht in der
Whitelist der Multiplikator-/Startbonus-Typen steht. Die Effekte
docken genau an den zwei vorgesehenen Stellen an
(`production_per_second()` und `hero_stats()`).

**Gestaffeltes Freischalten** (GDD §3) lebt in der UI: Der
Sage-Bereich ist unsichtbar, bis das erste Prestige in Reichweite
ist; der Perma-Baum zeigt sich erst *nach* dem ersten Prestige –
der Offenbarungsmoment. Die Barden-Zitate der Nacherzählungen
eskalieren über `data/saga_lines.json`.

## Tests & CI

```sh
godot --headless --import                            # einmalig / nach Klassenänderungen
godot --headless --script res://tests/run_tests.gd   # Suite ausführen
```

Eigener Mini-Runner (`tests/run_tests.gd`) statt Addon: läuft überall,
wo ein Godot-Binary liegt. GitHub Actions führt die Suite bei jedem
Push aus (`.github/workflows/ci.yml`). Neue Testdateien in
`TEST_SCRIPTS` registrieren; jede `test_*`-Methode wird ausgeführt.

Konvention: Die Simulation in `src/core/` ist vollständig testbar –
neue Spiellogik kommt **mit Tests**, sonst ist sie nicht fertig.

### Arbeiten & Mehrfachkauf

`GameState.manual_work_amount()` ist der einzige Ort, an dem
Klick-Ertrag berechnet wird (Basis + Anteil der Produktion/s ×
Perma-Buff "work_mult") – Buffs docken dort an, analog zu
`production_per_second()`. Der Mehrfachkauf (1/5/10/100/Max) nutzt
die geometrische Reihe aus `GeneratorDef.cost_for()`;
`max_affordable()` invertiert sie logarithmisch mit Randkorrektur,
die Kerninvariante `cost(n) <= Budget < cost(n+1)` ist über viele
Größenordnungen getestet.

### Tatentracking: Tavernenerzählungen

`RunState` zählt während des Runs mit (Ticks, erlittener Schaden,
Gabelungen/Türwahlen, Fähigkeits-Einsätze); `result()` liefert die
Zähler. `TaleDef` (`data/tales.json`) ist eine reine Bedingung über
dieses Ergebnis – Typen: victory (optional je Dungeon), no_damage,
all_elite, speed, no_abilities, fled, defeat. Auch Flucht und
Niederlage geben Geschichten – sehr Dorftrottel.

`bank_run_result()` prüft alle offenen Taten und gibt die neu
verdienten zurück (`EventBus.tale_earned` je Stück). Erzählungen sind
**einmalig und perma** ("die Taverne vergisst nichts") und die
qualitative Vorstufe zu Klassen: Die verlangen später bestimmte
Erzählungen plus Mindestanzahl. Ein Datenwächter-Test erzwingt, dass
jeder Dungeon eine Sieg-Erzählung hat.

## Bewusst noch nicht gebaut

- **Klassen:** Versionen der Sage, freigeschaltet über
  Tavernenerzählungen (bestimmte + Mindestanzahl). Das Tracking
  steht; es fehlen ClassDef, Auswahl beim Sagenbeginn und
  klassenspezifische Modifikatoren über `hero_stats()`.
- **Talentbäume:** Multiplikatoren docken an `GeneratorDef.rate_for()` /
  `production_per_second()` (Idle-Seite) bzw. `hero_stats()` (Run-Seite)
  an – das sind bereits die einzigen Orte, an denen Raten und Werte
  berechnet werden.
- **Crafting/Rezepte:** Drops aus Runs landen in der perma-Sektion,
  Material kommt aus dem Dorf – die "goldene Regel" der
  Loop-Verzahnung. Training ist nur der Platzhalter dafür.
- **Die UI** ist ein bewusst hässlicher Code-Prototyp; sie wird durch
  echte Szenen ersetzt, sobald Gameplay steht.
