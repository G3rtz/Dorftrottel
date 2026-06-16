class_name Balance
extends RefCounted

## Zentrale Stellschrauben. Alles, was Balancing ist, gehört hierher –
## nicht verstreut in Logik oder UI.

## Simulationstakt. Die Produktion ist geschlossen berechenbar
## (Rate * Zeit), der feste Takt existiert für künftige Mechaniken
## mit Dauer (Buffs, Events), die Determinismus brauchen.
const TICK_SECONDS := 0.1

## Ab dieser aufgelaufenen Zeit (z.B. nach App-Suspend) wird in einem
## Schritt nachgebucht statt Tick für Tick zu iterieren.
const MAX_CATCHUP_SECONDS := 10.0

const AUTOSAVE_INTERVAL_SECONDS := 30.0

## Offline-Fortschritt: maximal angerechnete Abwesenheit und Wirkungsgrad.
const OFFLINE_CAP_SECONDS := 60 * 60 * 24
const OFFLINE_EFFICIENCY := 1.0

## Platzhalter-Kernressource – Benennung ist laut GDD noch offen.
## Die ID ist überall nur über diese Konstante referenziert.
const PRIMARY_RESOURCE := "gold"

const MANUAL_WORK_AMOUNT := 1.0
## Jeder Klick bringt zusätzlich diesen Anteil der Goldproduktion/s –
## so bleibt "Arbeiten" auch spät relevant, ohne früh zu dominieren.
const WORK_PRODUCTION_SHARE := 0.05

## Kampf: rundenbasiert und manuell – der Kampf wartet auf den
## Spieler, jede Aktion ist ein Zug. Cooldowns zählen in Zügen.
const STRIKE_DAMAGE_MULT := 2.0
const STRIKE_COOLDOWN_TURNS := 3
const BREATHER_HEAL_FRACTION := 0.3
const BREATHER_COOLDOWN_TURNS := 10
## Blocken: verhindert diesen Anteil des eingehenden Schadens.
const BLOCK_REDUCTION := 0.7
## Gegner telegrafieren ihre Absicht: Chance auf einen schweren
## Schlag (x Mult) – die Information, um die sich Blocken dreht.
const HEAVY_INTENT_CHANCE := 0.25
const HEAVY_INTENT_MULT := 2.0

## Segen (Boons): Auswahlgröße nach jedem erkämpften Raum.
const BOON_OFFER_COUNT := 3

## Raumwahl: Schatzkammer = härterer Wächter gegen mehr Beute,
## Rastplatz = Heilung statt Beute.
const ELITE_HP_MULT := 1.6
const ELITE_ATK_MULT := 1.3
const ELITE_GOLD_MULT := 2.0
const ELITE_DROP_MULT := 3.0
const REST_HEAL_FRACTION := 0.4

## Held: Basiswerte plus linearer Zuwachs pro Trainingsstufe.
## Training ist die v1-Brücke "Idle finanziert Runs" und resettet
## beim Prestige (hero-Sektion).
const HERO_BASE_HP := 72.0
const HERO_BASE_ATK := 8.0
const HERO_HP_PER_TRAINING := 12.0
const HERO_ATK_PER_TRAINING := 2.0
const TRAINING_BASE_COST := 30.0
const TRAINING_COST_GROWTH := 1.18

## Prestige: Liedfragmente = floor(sqrt(Lifetime-Gold der Sage / Basis)).
## Sublinear, damit häufiges Prestigen ohne Fortschritt nichts bringt:
## 1 Fragment bei Basis, 2 bei 4x, 3 bei 9x, 10 bei 100x.
## Zweite Quelle: Boss-Drops (Bonus für aktives Spielen).
const FRAGMENT_BASE_GOLD := 50000.0

## Passiv-Bonus pro GEHALTENEM Liedfragment: Halten inspiriert das
## Dorf und den Helden, Ausgeben füttert den Perma-Baum – diese
## Abwägung ist gewollt. Linear pro Fragment gegen geometrisch
## wachsende Baumkosten balanciert sich selbst.
const FRAGMENT_GOLD_BONUS := 0.02
const FRAGMENT_ATK_BONUS := 0.01

## Talentbäume (GDD §3): Hero (Dungeon-Erfahrung) und Base/Dorf
## (Idle-Fortschritt). Beide resetten beim Prestige (hero- bzw.
## village-Sektion) – anders als der Perma-Baum, der überlebt.
## Hero-XP: jeder erkämpfte Raum zählt, ein Sieg gibt Bonus obendrauf.
const HERO_XP_PER_ROOM := 1
const HERO_XP_VICTORY_BONUS := 3
const HERO_XP_PER_POINT := 4
## Base-Talentpunkte kommen aus dem Lifetime-Gold der laufenden Sage –
## wie bei Liedfragmenten (sqrt-Formel), aber mit niedrigerer Schwelle,
## damit der kleine Baum schon vor dem ersten Prestige etwas zu tun gibt.
const BASE_TALENT_POINT_GOLD := 200.0
## Obergrenze für die gebundene Suche in GameState.base_talent_points_earned():
## weit über der Summe aller Knotenkosten, verhindert aber, dass absurd
## hohes Lifetime-Gold BigNum zwingt, sich in einen Float zu verwandeln.
const BASE_TALENT_POINT_SEARCH_CAP := 64
