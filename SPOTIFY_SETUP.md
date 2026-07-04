# Connect Daymark to Spotify Premium

Daymark uses Spotify’s Authorization Code flow with PKCE, the recommended approach for a browser app that cannot safely hold a client secret. Daymark requests permission to read your current playback, queue, recent tracks and short-term top tracks, and to control playback on an active Spotify device.

Tokens stay in this browser’s session storage. They are never committed to GitHub. Closing the browser session may require reconnecting Spotify later.

## 1. Create a Spotify app

1. Open https://developer.spotify.com/dashboard
2. Sign in with the Spotify Premium account you use on your iPhone.
3. Choose **Create app**.
4. Name it `Daymark Personal`.
5. Select **Web API**.
6. Keep the app in development mode for personal use.

## 2. Add the redirect URI

In the Spotify app settings, add this exact redirect URI, including the final slash:

`https://relytbytes.github.io/daymark/`

Save the settings, then copy the app’s public **Client ID**. Do not copy or publish the client secret; Daymark does not use it.

Spotify’s PKCE documentation: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow

## 3. Add the client ID to Daymark

The Daymark v11 upload archive deliberately excludes `config.js` so it does not overwrite your existing Google client ID.

1. Upload the Daymark v11 archive to the repository.
2. In GitHub, open `config.js` and tap the pencil icon.
3. Keep your existing `googleClientId` line.
4. Add the Spotify line so the file follows this shape:

```js
window.DAYMARK_CONFIG = Object.freeze({
  googleClientId: "YOUR_EXISTING_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
  spotifyClientId: "YOUR_SPOTIFY_CLIENT_ID",
});
```

5. Commit the change.
6. Wait for GitHub Pages to redeploy, then open:

   https://relytbytes.github.io/daymark/?v=11

7. Tap **Connect Spotify** and approve the requested playback permissions.

## What Daymark can do

- Read the current track and active device
- Show the next queued track
- Show recently played and short-term top tracks
- Play, pause, skip forward and go back on the active Spotify device

Daymark cannot edit playlists, change your saved library, follow artists, or access your Spotify password.

If playback controls say to open Spotify first, start playing something in the Spotify app on your phone, computer or speaker, then return to Daymark.
