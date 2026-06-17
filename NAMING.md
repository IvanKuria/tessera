# Naming & branding

> **Chosen app name: Tessera** (decided 2026-06-17) — tagline *"Tessera — an unofficial app for Kalshi."* The SDK keeps the descriptive name **KalshiKit**.

This project must be branded so it is clearly **unofficial** and **not affiliated** with Kalshi. The guiding principle is **nominative fair use**.

## Nominative fair use (the rule we follow)

You may use someone else's trademark to **refer to the trademarked thing itself** — here, to say the app is **compatible with Kalshi** — as long as:

1. You use only **as much of the mark as needed** to identify it (the word "Kalshi", not its logo, wordmark styling, or brand colors).
2. You do **not** suggest **sponsorship, endorsement, or affiliation**.
3. The thing isn't readily identifiable another way.

In practice, that means:

- **Coin a distinct brand name** for the app — one that does **not** start with or revolve around "Kalshi".
- **Describe** compatibility instead of implying ownership: *"an unofficial app for Kalshi."*
- Never use Kalshi's **logo, wordmark, brand colors, or artwork**.
- Carry an **"not affiliated / not endorsed"** disclaimer prominently.
- Don't claim to be "the only" or "the official" anything (a read-only menu-bar app like PredictBar already exists).

## Candidate names for the app

Each is distinct, does not embed "Kalshi", and pairs with a descriptive tagline. (Check availability — domain, App Store, trademark — before committing.)

| Name | Tagline |
| --- | --- |
| **Tessera** | *Tessera — an unofficial app for Kalshi* |
| **Foretell** | *Foretell — an unofficial app for Kalshi* |
| **Wagerlight** | *Wagerlight — an unofficial app for Kalshi* |
| **Oddsmith** | *Oddsmith — an unofficial app for Kalshi* |
| **Prospect** | *Prospect — an unofficial app for Kalshi* |
| **Marketwise** | *Marketwise — an unofficial app for Kalshi* |
| **Bellwether** | *Bellwether — an unofficial app for Kalshi* |
| **Likelys** | *Likelys — an unofficial app for Kalshi* |

**Recommendation:** **Tessera** — a clean, distinctive word (a small tile in a mosaic, evoking many markets composing a picture) with no semantic tie to Kalshi, so trademark risk is low and the descriptive tagline does the compatibility work.

## SDK name: `KalshiKit`

The SDK keeps the **descriptive** name **`KalshiKit`** because developers searching for a Kalshi Swift library will look for exactly that, and `…Kit` is the conventional Swift suffix for an API client.

**Caveat:** even `KalshiKit` **embeds the "Kalshi" mark**. This is defensible as nominative/descriptive use for a compatibility library, but it raises the affiliation risk, so:

- The SDK README **must** carry the prominent **unaffiliated disclaimer** (it does).
- Do not pair the name with Kalshi's logo, wordmark, or colors.
- Keep the README's compatibility language descriptive ("a Swift SDK **for** the Kalshi API").

**Fallback (neutral) SDK names** — if a cleaner mark is preferred or trademark concerns arise, rename to something non-infringing such as **`PredictKit`**, **`MarketKit`** (note: collides with Apple's MarketKit-style naming — verify), **`ContractKit`**, or **`ForecastKit`**, and describe Kalshi compatibility in the README rather than in the package name.
