# Contributing to Tessera & KalshiKit

Thanks for your interest in contributing! This repository ships **two
deliverables** — the native macOS app (**Tessera**) and a standalone Swift SDK
(**KalshiKit**) — so most contributions land in one or the other. This guide
covers how to build both, the conventions we follow, and how to open a good PR.

> **Before anything else, please read [`DISCLAIMER.md`](DISCLAIMER.md) and
> [`NAMING.md`](NAMING.md).** This is an **unofficial, non-affiliated** project.
> Contributions must keep it that way (see [Legal & Branding](#legal--branding)).

## Getting Started

### Requirements

- **macOS 14+** (Sonoma or later)
- **Xcode 16+** with the **Swift 6** toolchain (strict concurrency)
- [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) for the app target:
  `brew install xcodegen`
- No third-party runtime dependencies — the project is intentionally
  dependency-free (see the PR guidelines).

### Build & Run

**KalshiKit (the SDK)** is a Swift Package — build and test it directly:

```sh
cd KalshiKit
swift build
swift test
```

**Tessera (the app)** is generated from `project.yml` with XcodeGen:

```sh
cd Tessera
xcodegen generate                 # writes Tessera.xcodeproj from project.yml
open Tessera.xcodeproj             # then Run (⌘R), or build from the CLI:
xcodebuild -scheme Tessera -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Market data is read-only and needs **no credentials**. You only need a Kalshi
API key to exercise the portfolio and trading paths — and that key stays in the
macOS Keychain (never commit one).

## Project Structure

```
mac-app/
├── Tessera/          # the macOS app (SwiftUI; project generated via XcodeGen)
│   ├── Sources/      # views, stores, and engines
│   ├── project.yml   # XcodeGen project definition (edit this, not the .xcodeproj)
│   └── README.md     # app architecture
├── KalshiKit/        # the open-source Swift SDK (SwiftPM package)
│   ├── Sources/KalshiKit/   # the library
│   ├── Tests/               # XCTest suite (`swift test`)
│   └── README.md            # SDK usage and API surface
├── DISCLAIMER.md     # disclaimer + pre-release legal checklist
├── NAMING.md         # branding / nominative-fair-use notes
└── docs/             # README imagery, design notes
```

> The app's `.xcodeproj` is **generated**. Make project changes in
> `Tessera/project.yml` and re-run `xcodegen generate` — don't hand-edit the
> Xcode project.

## Architecture

### High-Level Overview

KalshiKit does all the networking; Tessera is a thin, observable UI on top.

- **`KalshiClient`** (KalshiKit) is an `actor` — all HTTP and websocket work runs
  off the main thread behind it. Authentication uses a `KalshiSigner` built from
  your `KalshiCredentials` (key id + RSA private key).
- **Stores & engines** (Tessera) are `@MainActor @Observable` types that consume
  `KalshiClient` and drive the UI. They only touch UI state:

  | Type | Role |
  | --- | --- |
  | `WatchlistStore` | Markets dashboard (active markets, categories, live refresh + disk cache). |
  | `DetailStore` | Price history, order book, and recent trades for a selected market. |
  | `AccountStore` | Holds credentials + the authenticated client; gates portfolio and trading. |
  | `PortfolioStore` | Balance, positions, orders, fills, settlements. |
  | `AlertEngine` | Watches prices and fires native notifications on thresholds. |
  | `TriggerEngine` | Evaluates automation rules and can place orders. |

- **`RootView`** is the shell: a `NavigationSplitView` with Markets / Portfolio /
  Alerts & Triggers and the account at the bottom.

### Keep KalshiKit usable on its own

KalshiKit is published as a standalone library — **it must not depend on the
app.** Anything app-specific (UI, stores, design) stays in `Tessera/`. If you add
API surface to the SDK, keep it general-purpose and documented in
`KalshiKit/README.md`.

## Coding Guidelines

### Modern SwiftUI APIs

- Use `.foregroundStyle(…)`, not the deprecated `.foregroundColor(…)`.
- Use `NavigationSplitView` / `NavigationStack`, not `NavigationView`.
- Use `@Observable` (Observation framework), not `ObservableObject`/`@Published`.

### Swift 6 Concurrency

- The project builds with **strict concurrency**. Keep it warning-free.
- Use `async`/`await` and `actor` isolation. **Do not** reach for `DispatchQueue`
  or completion handlers for new code.
- Networking belongs behind the `KalshiClient` actor; UI state stays
  `@MainActor`.

### Design system

- Pull colors, fonts, and metrics from `Theme` (`Tessera/Sources/Theme.swift`) —
  don't hardcode `Color.white`, `Color.black`, or ad-hoc hex values in views.
  Category and chart-line accents are the documented exceptions.
- This keeps theming (including light/dark adaptation) centralized.

### Security & credentials

- API keys (key id + RSA private key) live **only in the macOS Keychain**, and
  are sent **nowhere except directly to Kalshi**. Never log them, sync them, add
  telemetry around them, or write them to disk.
- Never commit credentials, tokens, or a real key — not even in tests or
  fixtures.

## Legal & Branding

This project relies on **nominative fair use** to describe Kalshi compatibility.
Contributions must preserve that posture:

- **No Kalshi trademarks or artwork** — do not add Kalshi's logo, wordmark, brand
  colors, fonts, or screenshots to the app, icon, marketing, or repo.
- **Don't imply affiliation** — keep wording descriptive ("an unofficial app
  **for** Kalshi"). Carry the unaffiliated disclaimer where user-facing.
- **Informational, not advice** — don't add language that presents market data as
  financial advice.

See [`DISCLAIMER.md`](DISCLAIMER.md) and [`NAMING.md`](NAMING.md) for the full
rationale.

## Pull Request Guidelines

Before submitting:

1. **No third-party dependencies** — the project is dependency-free. Open an
   issue to discuss before introducing one.
2. **Build must pass** — `swift build` (KalshiKit) and the app build
   (`xcodebuild -scheme Tessera … build`).
3. **Tests must pass** — `swift test` for KalshiKit. Add tests for new SDK
   behavior.
4. **No new concurrency warnings** under Swift 6 strict mode.
5. **Match the surrounding style** — we follow the
   [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/);
   keep diffs focused and consistent with nearby code.
6. **Small, reviewable PRs** — one logical change per PR. Open an issue first for
   anything large.
7. **Respect the disclaimer & branding** (see above).
8. **Share your AI prompts** if you used AI assistance (see below).

## AI-Assisted Contributions & Prompt Requests

This project is built in the open with AI assistance, and we welcome
contributions made with GitHub Copilot, Claude, Cursor, or similar tools.

### What is a Prompt Request?

A **prompt request** is a contribution where you share the AI prompt that
generated the change, rather than (or in addition to) the code itself. It:

- **Captures intent** — the prompt often explains *why* better than a diff.
- **Enables review before implementation** — maintainers can validate the
  approach before code is written.
- **Supports iteration** — prompts can be refined cheaply.
- **Improves reproducibility** — anyone can re-run the prompt to verify.

### Contributing with AI assistance

You can contribute either way:

- **Traditional PR** — open a PR with the code, and include the prompt(s) you
  used in the description.
- **Prompt request** — open an issue with the `prompt-request` label describing
  the change and the prompt you'd run, so maintainers can review the approach
  first.

Either way, **you are responsible for the code you submit**: read it, build it,
test it, and confirm it follows these guidelines. AI output that hasn't been
verified by a human won't be merged.

### Best practices for AI prompts

- Give the model the relevant context: which deliverable (app vs SDK), the file
  paths, and the Swift 6 / `@Observable` / `Theme` conventions above.
- Constrain it: no third-party deps, no `DispatchQueue`, no Kalshi trademarks,
  keys stay in the Keychain.
- Ask for tests alongside SDK changes.

### Example prompt

> "In `KalshiKit`, add an `async` method `KalshiClient.orderbook(ticker:)` that
> calls the v2 market order-book endpoint and returns a typed `Orderbook` model.
> Keep it on the `KalshiClient` actor, no third-party dependencies, and add an
> XCTest that decodes a sample response. Follow the existing request/decoding
> patterns in the file."

## Testing

- **KalshiKit:** `cd KalshiKit && swift test`. Add or update tests for any SDK
  change; prefer decoding tests against representative sample payloads over tests
  that hit the live API.
- **Tessera:** verify the app builds (`xcodebuild … build`) and launches, and
  manually exercise the views your change touches (Markets, Detail, Portfolio,
  Alerts & Triggers) in both light and dark appearance.

---

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
