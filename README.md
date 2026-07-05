# Daymark

An iPhone-first personal assistant dashboard that shifts continuously through morning, afternoon, evening, and night.

## Preview locally

Serve this folder from any local web server, then open the shown address in a browser.

```sh
python3 -m http.server 4173
```

## Put it on an iPhone home screen

1. Publish this folder to any HTTPS static host (GitHub Pages, Netlify, Cloudflare Pages, or similar).
2. Open the published URL in Safari on the iPhone.
3. Tap **Share**, then **Add to Home Screen**.

When updating an existing Daymark deployment, preserve its configured `config.js`. The distributable source contains a placeholder client ID; replacing a working configured file would disconnect Google.

The web app manifest, offline cache, standalone display mode, safe-area spacing, and app icons are included.

## Notes

- The live phase, clock, framing, and refresh status update automatically throughout the day.
- Durham weather comes from Open-Meteo, and Diamondbacks games, NL West standings, and wild-card position come from MLB.
- While Daymark is open, live Durham Bulls scores refresh every 15 seconds, MLB every 30 seconds during live games, and both schedules refresh every minute otherwise; weather refreshes every five minutes; Calendar and Gmail refresh every two minutes while authorized.
- Returning to the app or regaining a connection triggers an immediate quiet refresh. iOS still suspends static Home Screen apps while they are closed.
- Cached public data always shows its age, and stale cards are visually marked instead of being presented as current.
- Baseball now includes official MLB team marks, a Diamondbacks team-focus card, richer form data, and switchable NL West / Wild Card tables.
- Source-oriented cards link to their real destination. Unconnected feeds are labeled rather than populated with invented updates.
- Google Calendar and priority Gmail can be connected after completing `GOOGLE_SETUP.md`. Calendar stays read-only; Gmail can mark a selected message read but cannot send, delete, or archive mail.
- Spotify Premium can be connected with browser-safe PKCE after completing `SPOTIFY_SETUP.md`. Daymark can show current/recent listening and control an active device without storing a client secret.
- Durham sports includes an official live Durham Bulls score card with inning, outs, base state and final results, plus direct Duke and NCCU all-sport calendars.
- Spotify listening includes a 50-play history, multi-period top-track statistics, top artists, rediscovery suggestions, a playback-device picker, direct device handoff, and visible control diagnostics.
- Playback commands refresh Spotify’s active-player state first, target the active player without a cached device ID, and respect Spotify’s action restrictions.
- Interface symbols use CSS or SVG artwork rather than platform-dependent emoji glyphs.
- Tasks, decisions, sprint progress, applications, quick captures, focus sessions, and saved reading are stored on the device.
- The **Now** rail pulls one open action forward and includes a persistent 25-minute focus timer.
- **Quick Capture** can add a task, reminder, job lead, or read-later link from anywhere in the app.
- The reading section includes working source links plus a personal read-later queue.
- The weekly scorecard is interactive, practical reminders surface in the Durham section, and tomorrow’s card only makes claims supported by the connected calendar.
- Daily actions roll over at midnight, weekly scores reset on Monday, and applications, captures, and reading items can be archived.
- Duke alerts, other teams, events, and individual housing alerts still need custom feeds.
