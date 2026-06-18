# Tessera Scanner — Arbitrage & Mispricing Scanner (Design Spec)

**Date:** 2026-06-17
**Status:** Approved for v1 implementation
**Flagship:** ② of 4 ("features Kalshi users wish Kalshi had")

---

## 1. Overview & thesis

A new **Scanner** sidebar tab that continuously hunts the Kalshi exchange for mispricing,
proves each opportunity survives **fees and orderbook depth**, and lets the user act on it.

The product thesis is **honesty as the differentiator**. Every naive scanner shows a gross
price gap and lies; ours shows the **net-of-fee, depth-aware, annualized** truth. Within-Kalshi
scope is a *feature, not a limitation* — it sidesteps the biggest cross-venue trap
(divergent resolution criteria) and lets us make trustworthiness the brand.

Two honestly-labeled lanes:

- **Locks** — *provable* arbitrage. Mutually-exclusive multi-outcome events where buying YES on
  every outcome (or NO on every outcome) costs less than the guaranteed $1 payout. Every row is real.
- **Edges** — *scored, not guaranteed* signals. Ladder-monotonicity violations within a series,
  wide spreads, and stale quotes.

### Ground-truth domain facts (govern the whole design)

1. **Kalshi runs a single reciprocal order book**: a YES bid at X *is* a NO ask at (100−X), so
   `yes_ask + no_ask ≥ 100¢` always holds. **Single-market YES+NO arbitrage is impossible** — we
   only use it as a `BookIntegrityCheck` sanity assertion (a `<100` sum means a corrupt snapshot).
2. **The real opportunity families** are (a) mutually-exclusive multi-outcome over/underround, and
   (b) cross-market logical inconsistencies (ladder monotonicity within a series for v1).
3. **Fees are a parabola that peaks where arbs appear.** Taker fee per fill =
   `⌈0.07 · C · P · (1−P)⌉` (rounded up to the next cent), peaking ~1.75¢/contract at P=0.50;
   maker rate 0.0175; S&P (`INX*`) / Nasdaq-100 (`NASDAQ100*`) series use 0.035. A displayed
   sub-100 sum near the middle is usually a **net loss**. We already have `KalshiFees.swift`.
4. **Depth matters.** Never trust top-of-book size. Walk the full Level-2 book to compute the
   achievable size at a profitable VWAP; flag the "1-contract mirage".
5. **Non-atomic legging risk.** Kalshi has no atomic multi-leg fill. Nothing is ever "guaranteed"
   at execution; every multi-leg opportunity carries a legging-risk descriptor and worst-case loss.
6. **Capital is locked until settlement**, but Kalshi pays ~3.25–4.05% APY on idle *and* locked
   collateral. The true hurdle is `(external T-bill − Kalshi APY)`; annualize and de-rank below it.
7. **Collateral return**: in a mutually-exclusive group, $1 is credited immediately (one NO must
   pay), which reduces capital required / max loss.

### Hard ethics rules

- **Never** "you would've made $X" — regulated hypothetical/backtested performance. Forward paper
  results only, accrued from now and labeled "no real money".
- **Never** gamify trade *frequency* (no confetti, streaks-for-trading, FOMO timers — Robinhood
  paid $7.5M for exactly that). Reward finding edge, learning, and consistency.
- **Never** the word "guaranteed" for *execution* (only for the settlement math of a provable lock,
  always paired with the loud non-atomic legging warning).
- **Color is never the only signal** (~8% red-green deficiency): text + glyph + color, always.

---

## 2. Architecture — "snapshot-scan + live-revalue the surfaced set" (Approach A)

A keyless `@MainActor @Observable ScannerStore` runs a periodic pass shaped as a strict funnel so
cost stays bounded regardless of how many markets exist:

```
~thousands of open events ──Discover──►  one paginated GET /events (withNestedMarkets) every ~45s
        ▼ PURE quote detectors (no I/O, Task.detached)
   ~5–50 candidates ──Confirm──►  orderbook() ONLY for candidate markets
        ▼ (bounded TaskGroup, ≤6 concurrent, depth-limited)
   PURE fee+depth pricing, reject below hurdle
   0–handful Opportunities ──Subscribe──►  ONE socket subscribe covers the surfaced set
        ▼ ticker/orderbook updates re-price in place, auto-expire dead edges
```

### Scan pipeline stages

| Stage | Domain | Notes |
|---|---|---|
| 0 Gate | `@MainActor` | exchange open? coalesce manual refresh; set `isScanning` |
| 1 Discover | `KalshiClient` actor | `collect { events(status:"open", withNestedMarkets:true, limit:200, cursor:) }`, capped at `maxEventsScanned` |
| 2 Group | `Task.detached(.utility)` | raw `[Event]` → `[ScanGroup]` (keeps `mutuallyExclusive`); drop settled/parlay/filtered |
| 3 Detect | `Task.detached`, PURE | quote detectors → lightweight `[Candidate]` (recall-favoring pre-filter) |
| 4 Confirm | `KalshiClient` actor | distinct candidate tickers → `orderbook()` via **sliding-window TaskGroup, cap 6**, `depth`-limited, `try?` partial-failure-tolerant |
| 5 Price | `Task.detached`, PURE | fee+depth net-edge → `[Opportunity]`; reject below hurdle |
| 6 Publish | `@MainActor` | diff into `oppsByID` by stable id (update, not churn); project to `locks`/`edges`; alerts |
| 7 Resubscribe | `@MainActor → actor` | drive socket watch-set to surfaced markets **only when the set changed** |

### Live-revalue subsystem (reuses `AlertEngine.restartFeed`)

- Watch-set = all leg tickers in current `oppsByID`. One `socket.subscribe(to:[.ticker] (+ optional
  .orderbookDelta), markets:)` covers all N markets; auto-reconnect+resubscribe is built in.
- On a ticker/book update: update cached quote/book, re-run **only that opportunity's** detector+price
  from cached state (no new REST), then update-in-place or **expire** if it falls below hurdle.
- **Auto-expiry sweeper** (~5s `Task`): expire opps not refreshed by REST and not live-backed past
  `maxStaleSeconds` (~90s); demote `isLive` after `maxLiveSilenceSeconds` (~30s). On socket
  `.disconnected`, do **not** expire (REST snapshot remains the floor).

### Scale & rate-limit safety

- Discovery is one cursor walk per pass (SDK caps 100 pages; we add `maxEventsScanned`).
- Orderbook fetches = distinct *candidate* markets only, ≤6 concurrent — independent of universe size;
  detector selectivity (`minQuoteEdge`) is the knob.
- Socket cost is one subscription regardless of N.
- 429: SDK already retries with backoff; the store adds **scan-cadence backoff** (extend interval,
  decay after a clean pass) and treats it as a soft pass-level failure.
- Skip passes when the exchange is closed.

### Wiring

- `RootView.Section` gains `case scanner` (title "Scanner", SF Symbol `scope`), detail switch adds
  `ScannerView(store: scanner, account: account)`.
- `TesseraApp` creates `ScannerStore(account:)` from the shared `AccountStore` (like `TriggerEngine`)
  and calls `await scanner.start()` in `.task`. Keyless-capable: scans before sign-in; signing in only
  lets the live socket share the authenticated handshake and enables real-order execution.

---

## 3. Detection engine (pure, unit-testable)

All money is `Decimal`/`KalshiDecimal`, never `Double`. Detectors are `nonisolated static` pure funcs
over value-type snapshots with an injected `now` clock (deterministic tests), matching `KalshiFees`.

### Detectors (v1)

- **MultiOutcomeLock** — precondition `event.mutuallyExclusive == true`, ≥2 active children.
  Underround (buy YES all): profitable iff `Σ bestYesAsk < 100`, gross = `100 − Σ vwap`.
  Overround (buy NO all): inverse; profitable iff `Σ yesBid > 100`. Uses executable VWAP per leg.
  Capital accounts for the collateral-return credit. Emits `.possibleNonTiling` when the sum is
  suspiciously far from 100 (hidden "other/none" bucket), always `.settlementDiscretion`.
- **LadderMonotonicity** — markets in one series forming an ordered threshold/date ladder. Threshold:
  YES non-increasing as threshold rises; date: YES non-decreasing as date advances. A *crossed* pair
  (`yesAsk_loose < yesBid_tight`) → buy YES looser + NO tighter; guaranteed floor =
  `yesBid_tight − yesAsk_loose`, plus an unguaranteed "between-band" upside → Edge lane.
- **Spread/Stale** — flag-only Edge signals (`netEdge = 0`, scored by magnitude/age).
- **BookIntegrityCheck** — `yes_ask + no_ask < 100` ⇒ `.bookIntegrity` warning, never a tradable row.

### `Opportunity` model (fields)

Identity (`id` = stable hash of kind + sorted leg tickers/sides, for in-place update + alert de-dup),
`lane`, `kind`, `eventTicker`, `seriesTicker`, `title`, `category`, `legs[]` (each: `marketTicker`,
`side`, `action`, `priceCents`, `qty`, `feeCents`, `depthAvailable`, `vwapCents`).
Economics (all `Decimal` cents): `grossEdgeCents`, `totalFeesCents`, `netEdgeCents`,
`netEdgePerContractCents`, `netEdgePct`, `maxContractsAtPositiveEdge`, `capitalRequiredCents`,
`maxLossIfLeggedOutCents`. Time/yield: `daysToSettlement`, `annualizedPct`, `freshnessTimestamp`,
`freshnessAgeSeconds`, `source`/`isLive`. Honesty: `confidence`/`score`, `leggingRisk`, `warnings[]`.

### Net-edge pipeline primitives

- Per-leg fee (fractional-aware): `⌈ rate · C · P · (100−P) / 100 ⌉` cents; rate from a series-keyed
  selector (0.035 for INX*/NASDAQ100*, else taker 0.07). Whole-contract paths call
  `KalshiFees.tradingFeeCents` (single source of truth for the ceiling logic).
- Depth walk / VWAP: greedily fill cheapest levels to target Q; `vwap = Σ(price·qty)/Σqty`;
  `maxContractsAtPositiveEdge` = largest Q with net > 0 (monotone in Q), bounded by min leg depth.
- Capital with collateral return; `daysToSettlement = max(0.5, (expiry−now)/86400)`;
  `annualizedPct = netEdgePct × 365 / days`.

### Edge-lane scoring

Locks (positive net) always rank above Edges. Edge score (0…1) weights fee-net **floor** dominant,
unguaranteed upside discounted, plus yield, minus stale/spread/depth-mirage penalties. An edge with
non-positive floor never scores above 0.3. Below-hurdle opportunities get `.belowHurdle` and sink
(greyed, not hidden).

### Tests (≥22 cases) — must include

Fee-killed thin lock (97¢ sum → net negative, dropped); extreme-price lock that survives; mid-price
fee peak kills a 2¢ lock; non-tiling flag; 1-contract mirage via L2 (not top-of-book); below-hurdle
de-rank; overround buy-NO-all; `mutuallyExclusive==false` emits nothing; crossed ladder positive
floor; 1¢ ladder "violation" fee-negative; series fee override (INX → 0.035); book-integrity `<100`;
VWAP walk over laddered levels; annualization sanitization for near-expiry.

---

## 4. UI/UX

### Placement & modes

- Sidebar Section "Scanner", SF Symbol `scope`, with live `Locks`/`Edges` count badges.
- **Two modes via the existing Line/Candles pill toggle**, default **Simple** (remembered): Simple =
  whitespace, net-edge hero, "why it's mispriced" + worked $-example + honest ceiling, glossary
  tooltips; Pro = dense sortable table (VWAP/depth/annualized/score columns, keyboardable).
- **Lane toggle** (same pill style) with inline counts; header shows `LiveDot` + freshness +
  Filters + mode toggle.

### Opportunity rows

Net-of-fee edge is the hero (green for Locks via `Theme.yes`; neutral `Theme.info` + "est." for
Edges). Auto-expiring **freshness stamp** (`NEW · 4s` → `updated 8s 🟢` → `updated 34s 🟡` →
`stale ⚠`); the word always accompanies the dot. Bound-legs grouping; warning chips
(`⚠ thin depth`, `⚠ legging risk`, `◷ closes 9d`, `↺ quote moved`).

### Expanded panel = the execution loop

Inline disclosure (Simple) / expand-under-row (Pro). Contains: pre-filled **dutching calculator**
(editable stake → live net-of-fee qty/profit/ROI/annualized, **clamped to fillable depth** with a
`beyond depth — edge turns negative` guard); the N legs bound as one trade (per-leg depth ✓/⚠, price,
fee); and three actions:

- **Place all N legs** (filled) → mandatory **non-atomic legging-risk modal** (checkbox-gated) →
  deep-link into the existing order ticket pre-filled per leg, thinnest leg first.
- **Paper-trade this** (outline) → forward paper P&L at current prices.
- **Track & alert me** (ghost) → net-edge-threshold watch (reuses `AlertEngine`/`alertBar`).

Edges flip the result block to "Est. profit if it holds" + real `maxLossIfLeggedOut` + confidence
meter. An opportunity that expires while its panel is open locks inputs and shows a "re-scan" guard —
a stale-priced order never proceeds.

### Education (no multi-step tour — completion craters)

One first-run intro card; ambient inline `ⓘ` glossary popovers (overround, dutching, net edge,
annualized, legging risk, depth, confidence); progressive disclosure (advanced numbers one click
deeper). Time-to-first-value < 15 min: first interaction auto-expands the top Lock (or top Edge) with
the worked $-example pre-filled at a friendly default.

### States

Loading/first-scan skeletons; **honest empty** copy ("No locks right now — and that's normal…");
offline/stale dimming with CTAs disabled; error + retry; graceful "expired" row transition.

### New components

`LaneTag`, `FreshnessStamp`, `NetEdgeHero`, `ConfidenceMeter`, `WarningChip`, `OpportunityRow`
(Simple), `OpportunityTableRow` (Pro), `BoundLegsGroup`, `DutchingCalculator`, `LeggingRiskModal`,
`WhyMispricedExplainer`, `GlossaryTip`, `LaneModeToggle`, `ScannerEmptyState` — each reusing Theme
tokens + existing components (EventCardView chrome, OutcomeAvatar, ProbabilityBar, DetailView toggle
& steppers, StatBlock).

---

## 5. Stickiness (ethical)

Secondary strip inside Scanner: **Live · Watching · Paper P&L · Digest**. Tracked-opportunity history
with honest fate labels; forward-only paper ledger ("started today, no real money") rewarding
edge-found/accuracy/consistency (not trade count); opt-in daily "Top mispricings" digest (one
notification/day, cadence-capped); custom net-edge alert thresholds. Explicit non-goals: no frequency
gamification, no hypothetical-performance claims.

### Alerts

`ScannerNotifier` (reuses `AlertEngine`'s `UNUserNotificationCenter` approach) fires only when:
alerts enabled, net edge ≥ actionable threshold, the opp **just crossed up** into actionable
(edge-triggered, not every pass), and cooldown elapsed. De-dup key = `opp.id`.

### Settings (persisted via `AppGroup.scannerSettingsURL`)

Cadence (`scanIntervalSeconds` 45), scale caps (`maxEventsScanned`, `maxConcurrentBookFetches`,
`bookDepth`), economics (`minNetEdgeCents`, `minQuoteEdgeCents`, `minSpreadCents`), lane toggles,
category allow-list, `useOrderbookDelta`, liveness (`maxStaleSeconds`, `maxLiveSilenceSeconds`),
alerts (`alertMinNetEdgeCents`, `alertCooldownSeconds`, `alertLocksOnly`).

---

## 6. Scope

**v1 (this spec):** MultiOutcomeLock + LadderMonotonicity + Spread/Stale + BookIntegrityCheck; full
honesty math (fee + depth + annualized + hurdle); `ScannerStore` funnel + live revalue + auto-expiry;
both Simple/Pro modes; full execution loop (calculator + deep-link + paper + track); alerts;
persistence; the four-tab stickiness strip; ≥22 engine unit tests.

**Deferred ("Dream"):** free-form cross-*event* logical inference via resolution-text NLP; maker-fee
modeling toggle; shared raw-event cache between WatchlistStore and ScannerStore; backtested
"exitability" scoring; sub-second alerting / API + CSV export pro tier.

---

## 7. Implementation slices (each independently shippable & verifiable)

1. **Engine + tests** — `Opportunity` model, detectors, fee/depth pricing (pure). Unit tests green.
2. **Store + scan loop** — `ScannerStore` REST funnel, settings, persistence, RootView/TesseraApp
   wiring; read-only console logging of found opportunities.
3. **Read-only Scanner UI** — lanes, rows, both modes, empty/loading/error states.
4. **Live revalue** — socket watch-set, in-place updates, freshness, auto-expiry.
5. **Execution loop** — expanded panel, dutching calculator, legging modal, ticket deep-link, paper.
6. **Stickiness + alerts** — Watching/Paper/Digest strip, `ScannerNotifier`.

---

## 8. Verification / definition of done

- Engine: all ≥22 unit tests pass (fee-killed, depth-mirage, ladder cross, non-tiling, series fee,
  book-integrity, annualization). `swift test` green.
- App builds via `xcodebuild … -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`.
- A scan pass discovers events, confirms only candidate orderbooks (bounded concurrency), and surfaces
  fee+depth-aware net-edge opportunities; live socket revalues and auto-expires them.
- No opportunity ever displays a positive edge that is negative after fees; every multi-leg row shows
  legging risk; below-hurdle opps are greyed; color is never the only signal.
- Honesty rails hold: no "would've made $X", no frequency gamification, no "guaranteed" execution.
