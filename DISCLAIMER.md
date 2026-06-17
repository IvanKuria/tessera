# Disclaimer

This is an independent, open-source, **non-commercial** portfolio project: a native macOS app (working name *Tessera*, final name TBD) and a Swift SDK (`KalshiKit`) that are **compatible with** [Kalshi](https://kalshi.com), the CFTC-regulated prediction market.

## Not affiliated

This project is **not** affiliated with, authorized, endorsed by, sponsored by, or connected to **Kalshi** or **KalshiEX LLC** in any way. It is an unofficial, third-party tool.

- The word "Kalshi" is used **only descriptively**, to indicate that this software is compatible with Kalshi's public API (nominative fair use).
- This project does **not** use Kalshi's logo, wordmark, brand colors, fonts, screenshots, or any other Kalshi trademarks or copyrighted artwork.
- "Kalshi" and any related marks are the property of their respective owner(s).

## Informational only — not financial advice

Any odds, prices, probabilities, balances, or other data displayed are provided for **informational purposes only** and may be **delayed, incomplete, cached, or incorrect**. Nothing produced by this software is financial, investment, legal, accounting, or tax advice, or a recommendation to buy, sell, or hold any contract. Prediction-market trading carries risk of loss.

## AS IS — no warranty

The software is provided **"AS IS", without warranty of any kind**, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, and non-infringement. You use it entirely at your own risk. The authors are not liable for any losses, damages, missed trades, erroneous orders, or other harm arising from its use. See the [LICENSE](LICENSE) (MIT).

## Trading is opt-in — you supply your own key

- Read-only features require no credentials.
- Trade execution is **strictly opt-in** and requires **your own** Kalshi API key (a key id plus an RSA private key).
- Your key is stored **only in the macOS Keychain** on your machine. It is **never transmitted to any server except Kalshi's own API**. The project has no backend and collects no telemetry tied to your key.
- You are solely responsible for safeguarding your key and for **every order** placed with it.

## Always verify on Kalshi

Before relying on or acting on anything shown by this software, **verify it directly** on [kalshi.com](https://kalshi.com) or via the official Kalshi API.

---

# Before public release — legal checklist

Complete every item below before publishing the repository, distributing a build, or otherwise releasing publicly. Items are marked where verification is still **outstanding**.

- [ ] **Read the Kalshi API Developer Agreement in a browser.**
      As of the last attempt, `https://kalshi.com/developer-agreement` could **not** be fetched programmatically (HTTP 429 / bot protection), so its contents are **unverified**. Its terms **must be read manually before release** — do not assume any clause.
- [ ] **Confirm the Developer Agreement's clauses on:**
  - [ ] **Commercial vs. non-commercial use** — confirm a free, non-commercial open-source tool is permitted.
  - [ ] **Data redistribution / caching / display** — confirm what API data may be shown, stored, or redistributed, and under what conditions.
  - [ ] **Required disclaimers / attributions** — confirm whether Kalshi requires specific disclaimer or attribution language, and add it verbatim if so.
  - [ ] **Trademark / branding restrictions** — confirm acceptable descriptive use of the name and that no marks/art may be bundled.
  - [ ] **Rate limits and acceptable use** — confirm the client's backoff/retry behavior complies.
  - [ ] **Termination / liability terms** — note anything that affects redistribution of the SDK.
- [ ] **Note the separate website Data Terms of Use.**
      A separate, more restrictive **"Data Terms of Use"**
      (`https://kalshi-public-docs.s3.amazonaws.com/kalshi-data-terms-of-service.pdf`)
      governs **website** data, which is **not** the same as the API. This project targets the **API** under the **Developer Agreement**. Confirm which document applies to each data source and do **not** mix website-scraped data into an API-governed tool. *(The full PDF text was not reliably machine-readable and should also be reviewed manually.)*
- [ ] **Pick a final, non-infringing app name.**
      The working name "Tessera" is a placeholder. Choose a distinct brand that does **not** begin with or center on "Kalshi" and does not imply affiliation. See [`NAMING.md`](NAMING.md).
- [ ] **Do not bundle Kalshi trademarks or artwork.**
      No Kalshi logo, wordmark, brand colors, fonts, or screenshots in the app, icon, marketing, or repo.
- [ ] **Keep user keys in the Keychain only.**
      Verify the key id + RSA private key are stored exclusively in the macOS Keychain and are never logged, synced, or sent anywhere except directly to Kalshi.
- [ ] **Carry the unaffiliated disclaimer prominently** in the app's About screen, both READMEs, and the App Store / release listing (since the SDK name `KalshiKit` embeds the mark).
