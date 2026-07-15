# Daymark for iOS — native SwiftUI edition

A full native rewrite of Daymark as a personal **executive assistant**: the turn-6
editorial design (Fraunces masthead, At-a-Glance ribbon, warm paper + ink + one
coral accent) rebuilt in SwiftUI, with more depth than the web app:

- **Today** — greeting masthead, At a Glance, an auto-composed lead story, the
  25-minute focus block, the Essential Three, a **day timeline** built from your
  real calendar (with suggested open blocks), **meeting prep** (attendees, join
  links, optional drive time), **priority-mail triage**, a **waiting-on** ledger,
  your capture inbox, and — after 5pm — the **evening review** with a week-ahead ledger.
- **Work** — applications pipeline (add/edit/status chips), Veraya sprint board,
  open decisions, waiting-on follow-ups with reminders, weekly scorecard.
- **Life** — Durham weather feature with a 12-hour strip, around town, Google-Maps
  quick searches, the Bulls box score, practical reminders.
- **More** — a morning **news brief** from your RSS feeds, a **markets watchlist**,
  D-backs box score + NL West/Wild Card standings, Spotify now-playing with device
  controls, and your reading queue.
- Local notifications: morning brief (7:30), evening review (8:30), focus-block
  completion, and follow-up nudges.

Everything persists on-device (JSON in Application Support; OAuth refresh tokens
in the Keychain). Feeds are stamped **live / cached / unavailable** — never invented.

## Requirements

- **Xcode 16 or newer** (the project uses Xcode 16's folder-synchronized format).
- iOS 17.0+ device or simulator.

## Run it

1. Open `ios/Daymark.xcodeproj` in Xcode.
2. Select the **Daymark** target → *Signing & Capabilities* → pick your **Team**
   (and change the bundle id from `com.relytbytes.daymark` if you like).
3. Choose your iPhone as the destination and **Run**.

On first launch it will ask for **calendar access** (the timeline/meeting prep is
built from it; nothing leaves the device) and **notifications**. Location is only
requested if you enable *Travel time to next meeting* in Settings.

Weather, MLB/Bulls, news, and markets work immediately — no accounts needed.

## Connect Spotify (2 minutes)

The app reuses the web app's public PKCE client id (already in
`Daymark/Support/DaymarkConfig.plist`).

1. Open [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
   → your Daymark app → **Settings**.
2. Add a Redirect URI: `daymark://spotify-callback` and save.
3. In the app: **More → Connect Spotify** (or Settings).

## Connect Gmail (5 minutes)

A native app cannot use the web client id, so create an **iOS** OAuth client in
the same Google Cloud project you set up for the web app (see `GOOGLE_SETUP.md`
at the repo root):

1. Google Cloud Console → *APIs & Services → Credentials* →
   **Create credentials → OAuth client ID → iOS**.
2. Bundle ID: whatever you chose in Xcode (default `com.relytbytes.daymark`).
3. Copy the client id (`…apps.googleusercontent.com`) into
   `Daymark/Support/DaymarkConfig.plist` under **GoogleiOSClientID**.
4. In the app: **Settings → Google → Connect**.

Scope is `gmail.modify` — read + mark-as-read only; Daymark cannot send or delete
mail. Calendar intentionally does **not** use Google OAuth: it reads the calendars
already on your iPhone via EventKit (which includes your Google calendar if the
account is on the phone).

## Customize

**Settings** (gear in the masthead): your name, VIP senders (pinned in mail
triage), RSS feeds for the news brief, the markets watchlist (Stooq symbols:
`^spx`, `^dji`, `aapl.us`, …), notification editions, and travel-time ETA.

Home coordinates for weather default to Durham and live in `DaymarkConfig.plist`.

## Architecture

```
Daymark/
  DaymarkApp.swift          app entry, notification delegate
  DesignSystem/             Theme (palette, Fraunces/Newsreader via CoreText
                            variation axes, system-serif fallback), Components
                            (masthead, glance ribbon, rules, chips)
  Models/                   domain models, AppState (@Observable root store),
                            JSON persistence with day/week rollover
  Services/                 Open-Meteo, EventKit + MapKit ETA, Gmail (PKCE),
                            Spotify (PKCE), MLB statsapi, RSS news, Stooq
                            markets, local notifications, BriefEngine
                            (editorial copy composition)
  Views/                    Today / Work / Life / More / Settings / Capture
  Fonts/                    Fraunces + Newsreader variable TTFs (OFL licensed)
```

No third-party dependencies — URLSession, EventKit, MapKit, CryptoKit,
AuthenticationServices, and UserNotifications only.

## Notes & roadmap

- The state schema is v1; a future field change resets local state (tasks,
  pipeline, queue). Export/import and a tolerant decoder are natural next steps.
- Good candidates for v1.1: a WidgetKit At-a-Glance widget, a Live Activity for
  the focus timer, and an App Intent for capture from the Action button.
