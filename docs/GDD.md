---
tags:
  - gamedev
  - konzept
  - idle-game
  - roguelite
status: Konzept
engine: Godot (geplant)
erstellt: 2026-06-11
---

# GDD: „Der Dorftrottel" (Arbeitstitel)

> Idle/Rogue-lite-Hybrid. Ein Dorftrottel will sich beweisen – und Barden erzählen seine Geschichte immer weiter, immer übertriebener.

---

## 1. Elevator Pitch

Ein Idle Game (angelehnt an Cookie Clicker & Active-Idle-Hybride wie FAPI/NGU Idle), in dem die Idle-Schicht ein **Dorf** ist, das langsam an seinen Trottel zu glauben beginnt. Aktive **Dungeon-Runs** (Rogue-lite) erspielen permanente Freischaltungen und Boosts für die Idle-Schicht – und die Idle-Schicht rüstet umgekehrt die Runs aus. Prestige ist erzählerisch verankert: **Barden erzählen die Sage weiter**, jede Nacherzählung macht die Legende stärker.

**Kerngefühl:** "Ich idle, um besser zu runnen. Ich runne, um besser zu idlen. Und mit jeder Nacherzählung wird die Geschichte absurder."

---

## 2. Die zwei Loops

### 2.1 Idle-Schicht: Das Dorf
- Generiert **Währung & Rohmaterial** (das Quantitative, Skalierende – läuft auch offline weiter).
- Generatoren sind **Dorfbewohner, die anfangen zu helfen**: Anfangs nur die mitleidige Oma; später repariert der Schmied Ausrüstung, der Wirt sponsert Proviant, der Krämer eröffnet einen Beutestand.
- Idle-Ausbau = erzählerisch "das Dorf gewinnt Vertrauen".
- Finanziert Run-Vorbereitung: Tränke, Verbrauchsmaterial, Crafting von Basis-Ausrüstung.

### 2.2 Aktive Schicht: Dungeon-Runs (Rogue-lite)
- Liefert das **Qualitative**: einzigartige Ausrüstung, Talentpunkte, permanente Freischaltungen.
- Droppt **Baupläne, Rezepte & Freischaltungen** – die sind "im Hirn" und überleben das Prestige. Die Ausrüstung selbst ist vergänglich, das *Wissen* bleibt.
- Beispiel-Freischaltung: "Eisgolem besiegt → Eis-Dungeon dauerhaft verfügbar."
- **Verschiedene Dungeons** als permanente Freischaltungen über Run-Erfolge.

### 2.3 Goldene Regel der Loop-Verzahnung
- Jede Schicht liefert etwas, **das nur sie liefern kann** – sonst kannibalisieren sich die Loops.
- **Crafting als Brücke:** Idle liefert Material, Dungeon liefert Rezepte. Für das beste Zeug braucht man zwingend beide.
- Runs sind **optional, aber lohnend**: Aktiv spielen beschleunigt massiv, reines Idlen kommt langsamer auch ans Ziel. Aktives Spielen darf nie Pflicht werden.

---

## 3. Talentbäume (3 Stück)

| Baum | Gefüttert durch | Reset bei Prestige? | Inhalt |
|---|---|---|---|
| **Hero** | Dungeon-Erfahrung | ✅ ja | Kampf-Talente, Run-Stärke |
| **Base/Dorf** | Idle-Fortschritt | ✅ ja | Generator-Boosts, Dorf-Ausbau |
| **Perma** | Prestige-Währung ("Ruhm"/"Legendenpunkte") | ❌ nein | "Mehr, mehr, mehr": ATK, Gold, Startboni, QoL |

**Perma-Baum-Designregel:** Beschleunigen, **nie skippen**. Kein "Start in Dungeon 5". Der Ruhm macht nicht klüger, nur bekannter – bessere Preise, mehr Startvertrauen, härtere Schläge, weil die Legende vorauseilt. Das "Durchfräsen" durch früher zähe Abschnitte *ist* die Prestige-Belohnung.

**Gestaffeltes Freischalten:**
1. Base-Baum: sofort (Idle ist der Einstieg)
2. Hero-Baum: mit dem ersten Dungeon
3. Perma-Baum: erst beim ersten Prestige → Offenbarungsmoment ("Da war die ganze Zeit noch eine Ebene?!")

---

## 4. Prestige: Die Barden-Sage

### Mechanik
- Reset: alles "Ablegbare" – Währung, Material, Ausrüstung, Hero- & Base-Baum.
- Bleibt: Perma-Baum, Baupläne/Rezepte, freigeschaltete Dungeons, freigeschaltete Klassen ("alles im Hirn").
- Prestige-Währung: **Ruhm / Legendenpunkte**.

### Erzählerischer Rahmen
Nach jedem Durchlauf wird die Geschichte des Dorftrottels **als Legende weitererzählt**. Jede Nacherzählung macht den Helden der Sage stärker. Der Neustart bei 1:1 ist dieselbe Geschichte – nur besser erzählt.

### Tonlage
Mit steigendem Prestige werden die Nacherzählungen **immer übertriebener und alberner** ("…und dann, ich schwöre es euch, ritt er auf dem Drachen!"). Augenzwinkerndes Eskalieren als Genre-Markenzeichen (vgl. Cookie-Clicker-Grandmas).

---

## 5. Klassen (Rogue-lite-Teil)

### Konzept
Klassen sind **verschiedene Versionen der Sage**. Derselbe Dorftrottel, von verschiedenen Barden anders erzählt:
- **First Run (kanonisch):** der dumme Krieger – die ursprüngliche, *wahre* Geschichte. Alles danach ist Ausschmückung.
- Spätere Versionen: Magier, Paladin, Jäger, …

### Freischaltlogik (Ideen)
- Taten im Run: "Besiege den Boss nur mit Zaubern → die Magier-Version der Sage entsteht."
- Prestige-Meilensteine.
- **Liedfragmente** als Sammelobjekte in Dungeons → noch ein Grund, Dungeons zu betreten.
- UI-Flavor statt trockenem Unlock: "Ein Barde in einer fernen Taverne erzählt die Geschichte anders…"

### ⚠️ Scope-Warnung
Klassen sind teuer (eigene Talente, Ausrüstungslogik, Balancing – multipliziert sich). **Start mit 2, max. 3 Klassen** (Krieger + eine erste Freischaltung). Der Rahmen erklärt das sogar: Die Geschichte ist noch jung, es existieren erst wenige Versionen der Sage.

---

## 6. Technik

### Engine: Godot
- GDScript zum Einstieg, erstklassiger 2D-Workflow.
- Export: Desktop, Mobile, **Web** – Browser-Builds auf itch.io sind die klassische Teststrecke fürs Idle-Genre.

### Früh in der Architektur mitdenken
- **Offline-Progress:** Beim Spielstart Zeitdifferenz berechnen und Erträge nachbuchen. Gehört von Anfang an in die Save-Architektur.
- **Große Zahlen:** Floats werden ab ~10^15 ungenau. Wenn die Zahlen Cookie-Clicker-artig explodieren sollen → BigNumber-Lösung einplanen.

---

## 7. Referenzen / Recherche

| Spiel | Warum relevant |
|---|---|
| Cookie Clicker | Idle-Klassiker, Eskalations-Tonlage |
| Farmer Against Potatoes Idle (FAPI) | Active-Idle-Hybrid; "aktiv beschleunigt, idle kommt auch ans Ziel" |
| NGU Idle | Prestige-Aufbau (alles Ablegbare resettet, Meta bleibt) |
| Wizard and Minion Idle | Hybrid-Struktur |
| Nodebuster | Beweis, dass reduzierte Hybride ein Publikum finden |

---

## 8. Offene Fragen / Nächste Schritte

- [ ] Kernressourcen konkret benennen (Währung? Material-Typen?) – *Platzhalter „Gold" läuft, Umbenennung ist eine Ein-Zeilen-Änderung*
- [x] Ersten Dungeon-Loop skizzieren → *v1 gebaut: Räume + Boss, Tod = Run endet & Beute bleibt, Sieg schaltet dauerhaft frei (Details in ARCHITECTURE.md)*
- [ ] Erste 10 Dorf-Generatoren mit Bewohner-Flavor auflisten – *4 von 10 in data/generators.json*
- [ ] Prestige-Formel (Ruhm-Gewinn) grob festlegen
- [x] Godot-Projekt aufsetzen, Save-System mit Offline-Progress als erstes Modul
- [ ] Namens-Brainstorming (Arbeitstitel: „Der Dorftrottel")
