# Tessera + KalshiKit — Launch Plan

Public launch of **Tessera** (native macOS app) and **KalshiKit** (Swift SDK), both at v1.0.0.

- **App:** https://github.com/IvanKuria/tessera (notarized `.dmg` on the v1.0.0 release)
- **SDK:** https://github.com/IvanKuria/KalshiKit (`.package(url: "https://github.com/IvanKuria/KalshiKit.git", from: "1.0.0")`)

## Decisions (locked)

- **Goal:** balanced — GitHub stars + real users + portfolio credibility. Sequence channels over launch day to hit all three.
- **Approach:** Coordinated launch day (one Tue/Wed), everything pre-staged, channels fired in sequence at their optimal times, present in every thread.
- **Risk posture:** go big day one (Hacker News + Product Hunt included in the opening wave).
- **Identity:**
  - **Real name (Ivan Kuria):** Product Hunt, Show HN, r/swift, r/SideProjects, Kalshi Discord, GitHub.
  - **Pseudonymous Reddit handle:** Kalshi subreddit, r/algotrading, r/macapps (trader / financial-facing).
- **Framing everywhere:** unofficial, not affiliated with / endorsed by Kalshi, not financial advice, bring-your-own-key (Keychain-only, talks only to Kalshi), read-only by default.
- **Style:** short titles, no emojis, no em dashes, casual and concrete. Each post written natively for its sub — never copy-paste the same text across subs (that triggers auto-removal / shadowbans).

---

## 0. Pre-launch gate — ALL true before posting anything

- [ ] **Kalshi API Developer Agreement skimmed** and the BYO-key / no-redistribution / non-commercial posture confirmed compliant. (HN and PH will ask "is this allowed.")
- [ ] **DMG smoke-tested by you:** download from the Release, drag-install, launch clean (no Gatekeeper warning), connect a demo key, relaunch, key persists.
- [ ] **Disclaimers airtight** on both repos, the app About box, and the landing page: unofficial / not affiliated / not financial advice / BYO key (Keychain-only) / read-only by default.
- [ ] **Both repos polished:** README screenshots render, `brew` + SPM install lines correct, repo description + topics set, a pinned "start here."
- [ ] **Product Hunt assets ready:** 240x240 logo/thumbnail, 2-4 gallery images (scanner + candlestick shots), tagline (<= 60 chars), topics, maker first-comment pre-written.
- [ ] *(Optional, recommended)* **GitHub Pages landing page** (hero, two screenshots, Download / brew / SPM, disclaimer). Converts HN + PH traffic far better than a raw repo.

---

## 1. Launch-day timeline (pick a Tuesday or Wednesday)

| Time (PT) | Channel | Identity | Notes |
|---|---|---|---|
| 12:01 am | Product Hunt | real name | 24h leaderboard; post at 00:01 for the full day |
| 6:30-8:00 am | Show HN | real name | HN front-page sweet spot, Tue-Thu AM. No upvote asks. |
| ~9 am | Kalshi Discord #dev | real name | warm dev crowd, lightest touch |
| ~10 am | r/swift | real name | SDK-framed |
| ~11 am | r/SideProjects | real name | maker-story framed; sends real stars |
| ~12 pm | Kalshi subreddit | pseudonymous | traders; app + scanner framed |
| ~2 pm | r/algotrading | pseudonymous | substance-first; strict sub, read rules |
| ~4 pm | r/macapps | pseudonymous | native-app craft framing |

Then **be present in every comment thread** until late. Presence is the #1 ranking lever on HN and PH.

**Optional extra dev reach:** r/SwiftUI, r/opensource (same day or day 2, lightly).

---

## 2. Draft posts

### Product Hunt (real name)
**Tagline (<= 60):** `Native macOS app + Swift SDK for Kalshi prediction markets`
**Topics:** Mac, Developer Tools, Open Source, Fintech

**Description:**
> Tessera is a free, open source, fully native macOS app for Kalshi (the CFTC-regulated prediction market): live markets, candlestick charts, a portfolio view, price alerts, and an honest arbitrage/mispricing scanner. Under it sits KalshiKit, a reusable Swift SDK. Bring your own API key (stored only in your Mac's Keychain); read only by default. Unofficial, not affiliated with Kalshi.

**Maker first comment:**
> Hi PH, I'm Ivan, the dev. There is no official native Mac app for Kalshi, and no Swift SDK for its API, so I built both. The app is the showcase; KalshiKit (MIT, SwiftPM) is the reusable piece. The feature I'm proudest of is the scanner: most "arbitrage" tools lie because they ignore fees and order book depth, so mine computes net of fee, depth aware edges and is honest that real locks are rare. Your key lives only in your Keychain and talks only to Kalshi; trading is opt in. Not affiliated with Kalshi, and nothing here is financial advice. Happy to answer anything.

---

### Show HN (real name) — the centerpiece
**Title:** `Show HN: Tessera, a native macOS app and Swift SDK for Kalshi (unofficial)`
**URL:** the landing page (or https://github.com/IvanKuria/tessera)

**First comment:**
> I built a native macOS client for Kalshi (the regulated prediction market) and, underneath it, KalshiKit, an MIT-licensed Swift SDK for the Kalshi API (typed models with Decimal money, a WebSocket feed, RSA-PSS request signing, exact fee math). The app: live markets, candlestick charts, alerts, BYO-key trading (key stored only in the Keychain, read only by default).
>
> The interesting part is the mispricing scanner. I went in expecting to find arbitrage; I came out building something that is mostly honest about why you cannot. Kalshi runs a single reciprocal order book, so single-market YES+NO arb is structurally impossible. The real opportunities are multi-outcome over/underrounds and ladder inconsistencies, and Kalshi's fee is a parabola that peaks exactly where the edges appear, so a displayed "1 cent arb" is usually a real loss after fees. The scanner computes net of fee, depth aware, annualized vs hurdle numbers and cheerfully shows "no locks right now, and that's normal."
>
> Unofficial, not affiliated with Kalshi, not financial advice. Code: app [link], SDK [link]. Happy to go deep on the Swift 6 concurrency, the orderbook math, or the fee model.

(HN rules: no asking for upvotes, no seeding. Post and engage.)

---

### r/swift (real name)
**Title:** `I made an open source Swift SDK for Kalshi because none existed`

**Body:**
> There was no Swift client for Kalshi's trade API (the ecosystem has Python and Rust ones, nothing for us), so I wrote KalshiKit. MIT, SwiftPM.
>
> It's not a thin URLSession wrapper. It's a real SDK:
> - All money is Decimal, never Double. These are 1 to 99 cent probability contracts, so floating point rounding is a bug.
> - actor based async client, Swift 6 strict concurrency throughout, off main by construction.
> - Live URLSessionWebSocketTask feed (ticker, orderbook, trade) with backoff and auto resubscribe.
> - RSA-PSS request signing via the Security framework. The PKCS#1 strip that trips everyone up is handled.
> - A pure, unit tested fee and mispricing detection engine, 62 tests.
>
> `.package(url: "https://github.com/IvanKuria/KalshiKit.git", from: "1.0.0")`
>
> The macOS app (Tessera) is the showcase, same repo family. Would genuinely love API design feedback. Unofficial, not affiliated with Kalshi.

---

### r/SideProjects (real name)
**Title:** `I built a free, open source Mac app and Swift SDK for Kalshi prediction markets`

**Body:**
> Kalshi (the regulated prediction market) has no native Mac app and there was no Swift SDK for its API, so I built both as an open source portfolio project.
>
> Two pieces:
> - Tessera, a fully native SwiftUI app: live markets, candlestick charts, price alerts, portfolio, and opt in trading with your own API key (stored only in your Keychain).
> - KalshiKit, the reusable Swift SDK underneath it (MIT, SwiftPM): typed models, a WebSocket feed, RSA-PSS request signing, and fee math.
>
> The most fun part was a mispricing scanner. I started out trying to find arbitrage and ended up building something that is mostly honest about why you cannot. Kalshi's fee curve peaks exactly where the apparent edges are, so a lot of "free money" is actually a loss after fees, and the scanner says so instead of faking it.
>
> Everything is free and open source. Built with Swift 6 strict concurrency, notarized, no telemetry. Unofficial, not affiliated with Kalshi, not financial advice.
>
> Would love feedback, especially on the SDK design. [GitHub links]

---

### Kalshi subreddit (pseudonymous)
**Title:** `I made a free, open source Mac app for Kalshi (charts, alerts, mispricing scanner)`

**Body:**
> Kalshi has no Mac app, so I built one. It is free and open source.
>
> This is not a browser wrapper, it is fully native, and it has a few things the website does not:
> - Candlestick charts with volume and a moving average, not just a line.
> - Native price alerts that fire a real macOS notification when a market crosses your level.
> - A mispricing scanner that looks for arbitrage but is honest about fees and order book depth, so it will not show you fake free money (spoiler: real locks are rare).
> - Portfolio, order book, and trade tape in one window.
>
> You connect your own API key. It is stored only in your Mac's Keychain, only ever talks to Kalshi, and is read only unless you opt into trading.
>
> Not affiliated with Kalshi, and nothing here is financial advice. Verify everything on Kalshi. Would love feedback from people who actually trade here: [link]

---

### r/algotrading (pseudonymous)
**Title:** `I built a Kalshi arbitrage scanner and most of the free money dies to fees`

**Body:**
> Open sourced a scanner (plus a Swift SDK) for Kalshi. The interesting part wasn't finding arbitrage, it was understanding why you mostly can't.
>
> - Single market YES+NO arb is structurally impossible. Kalshi runs one reciprocal book, so a YES bid at X is a NO ask at (100 - X), which means yes_ask + no_ask is always at least 100.
> - The fee is a parabola that peaks right where the edges are. Taker fee is about ceil(0.07 * C * P * (1 - P)) per fill, maxing around 1.75 cents per contract at 50 cents. A displayed "1 cent arb" near the middle is a roughly 3 cent loss after both legs.
> - Top of book is a mirage. The scanner walks the full L2 book for VWAP and reports the size you can actually fill at a positive edge.
> - It then nets fees, accounts for depth, and annualizes against a hurdle, since capital is locked until settlement and Kalshi pays APY on it.
>
> Running it live, provable locks are rare and usually fee negative. The real opportunities are multi outcome over/underrounds and ladder inconsistencies, and even those are thin. The SDK has all the fee and orderbook math if it is useful (MIT): [link]. Not financial advice, unofficial, not affiliated with Kalshi.

(r/algotrading is strict and anti-promo. Read the rules, post from a real participating account, lead with the substance.)

---

### r/macapps (pseudonymous)
**Title:** `I made a free, open source native Mac app for Kalshi because there wasn't one`

**Body:**
> Kalshi (the prediction market) has no Mac app. The desktop experience is just a browser tab, so I built a real one.
>
> This is not a browser wrapper. It's 100% native SwiftUI, macOS 14+, dark mode, notarized (or install with brew), no Electron, no telemetry.
>
> What it does:
> - Candlestick charts with volume and a moving average. The Kalshi site only gives you a line.
> - Native price alerts, so you get a real macOS notification when a market crosses your level.
> - A mispricing scanner that hunts for arbitrage but is honest about fees and order book depth, so it never shows you fake free money.
> - Portfolio, order book, trade tape, and opt in trading.
> - Bring your own API key. It's stored only in your Mac's Keychain and only ever talks to Kalshi.
>
> Free and open source (MIT), and it will stay that way. Unofficial, not affiliated with Kalshi, and nothing in it is financial advice.
>
> [GitHub + download]. Would love feature requests.

---

### Kalshi Discord #dev (real name, light)
> Hey all, built an open source Swift SDK for the Kalshi API (KalshiKit, MIT) and a native Mac app on top of it. If you're doing anything in Swift against the API, the SDK might save you time: [link]. Feedback welcome.

---

## 3. Post-launch follow-through (first 72h)

- Reply to every comment fast and non-defensively, especially "is this legal" (BYO key + unofficial + not advice) and bug reports.
- Ship a point release for any real launch-day bug. "Fixed in v1.0.1" is great PR. Release flow: `./scripts/release.sh` then `gh release create` then bump the cask.
- Triage GitHub issues same day. Pin the best testimonial/issue.
- If something pops, a short follow-up devlog on the scanner / fee math sustains momentum and feeds the credibility goal.
- Submit the Homebrew cask once there are a few non-you installs.

## 4. Reusable link block (fill in once)

- App: https://github.com/IvanKuria/tessera
- SDK: https://github.com/IvanKuria/KalshiKit
- Direct DMG: https://github.com/IvanKuria/tessera/releases/latest
- Landing page: (optional) ____
