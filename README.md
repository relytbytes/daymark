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

The web app manifest, offline cache, standalone display mode, safe-area spacing, and app icons are included.

## Notes

- The live phase, clock, framing, and refresh status update automatically throughout the day.
- Durham weather comes from Open-Meteo, and Diamondbacks games, NL West standings, and wild-card position come from MLB.
- Live feeds refresh quietly every 15 minutes and fall back to the most recently cached response when temporarily offline.
- Baseball now includes official MLB team marks, a Diamondbacks team-focus card, richer form data, and switchable NL West / Wild Card tables.
- Source-oriented cards link to their real destination. Unconnected feeds are labeled rather than populated with invented updates.
- Google Calendar and Gmail can be connected with read-only OAuth access after completing `GOOGLE_SETUP.md`.
- Tasks, decisions, sprint progress, applications, quick captures, focus sessions, and saved reading are stored on the device.
- The **Now** rail pulls one open action forward and includes a persistent 25-minute focus timer.
- **Quick Capture** can add a task, reminder, job lead, or read-later link from anywhere in the app.
- The reading section includes working source links plus a personal read-later queue.
- The weekly scorecard is interactive, practical reminders surface in the Durham section, and tomorrow’s card only makes claims supported by the connected calendar.
- Duke alerts, other teams, events, and individual housing alerts still need custom feeds.
