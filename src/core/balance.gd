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
