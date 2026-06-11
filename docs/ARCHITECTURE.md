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

## Bewusst noch nicht gebaut

- **Dungeon-Runs:** bekommen ein eigenes core-Modul (`run_state.gd` o.ä.),
  das in die `hero`-Sektion serialisiert.
- **Talentbäume:** Multiplikatoren docken an `GeneratorDef.rate_for()` /
  `production_per_second()` an – die Stellen sind bereits die einzigen
  Orte, an denen Raten berechnet werden.
- **Prestige:** `GameState.prestige()` = `village`/`hero` neu aufbauen,
  `perma`/`meta` behalten. Das Save-Format kann das schon.
- **Die UI** ist ein bewusst hässlicher Code-Prototyp; sie wird durch
  echte Szenen ersetzt, sobald Gameplay steht.
