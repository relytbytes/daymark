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
- Tasks, decisions, sprint progress, and applications are saved in browser storage.
- The brief content is intentionally sample data. Calendar, email, weather, sports, and local listings need live data connections before production use.
