# Der Dorftrottel (Arbeitstitel)

> Idle/Rogue-lite-Hybrid: Ein Dorftrottel will sich beweisen – und Barden erzählen seine Geschichte immer weiter, immer übertriebener.

Ein Idle Game, in dem das **Dorf** die Idle-Schicht ist und aktive **Dungeon-Runs** (Rogue-lite) permanente Freischaltungen liefern. Prestige = die Barden erzählen die Sage neu, jede Nacherzählung macht die Legende stärker.

**Status:** Grundgerüst spielbar (Idle-Loop) · **Engine:** Godot 4.3

## Loslegen

Projekt in Godot 4.3+ öffnen und starten – oder headless:

```sh
godot --headless --import                            # einmalig: Projekt importieren
godot --headless --script res://tests/run_tests.gd   # Testsuite
godot                                                # Spiel starten
```

## Struktur

| Pfad | Inhalt |
|---|---|
| `src/core/` | Reine Simulationslogik (BigNum, GameState, SaveIO) – headless testbar |
| `src/autoload/` | Engine-Anbindung: Game-Loop, EventBus |
| `src/ui/` | Prototyp-UI (wird später durch echte Szenen ersetzt) |
| `data/` | Spielinhalte als JSON (Generatoren etc.) |
| `tests/` | Testsuite mit eigenem Headless-Runner, läuft in CI |

## Dokumentation

- [Game Design Document](docs/GDD.md) – Loops, Talentbäume, Prestige-System, Klassen
- [Architektur](docs/ARCHITECTURE.md) – Schichtenmodell, BigNum, Save-System, Konventionen
