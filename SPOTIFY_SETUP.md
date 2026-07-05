# Connect Daymark to Spotify Premium

Daymark uses Spotify’s Authorization Code flow with PKCE, the recommended approach for a browser app that cannot safely hold a client secret. Daymark requests permission to read your current playback, queue, recent tracks and short-term top tracks, and to control playback on an active Spotify device.

The refresh token stays in local storage on this device so Daymark can obtain new short-lived access tokens after the app closes. It is never committed to GitHub or synced by Daymark. Tap **Disconnect** in the Spotify card to remove it from the device. Spotify refresh tokens currently expire after six months, so occasional reauthorization is still expected.

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

   https://relytbytes.github.io/daymark/?v=15

7. Tap **Connect Spotify** and approve the requested playback permissions.

## What Daymark can do

- Read the current track and active device
- Show the next queued track
- Show recently played and short-term top tracks
- Play, pause, skip forward and go back on the active Spotify device
- List available playback devices and hand controls to the device you select

Daymark cannot edit playlists, change your saved library, follow artists, or access your Spotify password.

If playback controls say to open Spotify first, start playing something in the Spotify app on your phone, computer or speaker, then return to Daymark.

If the current track appears but playback buttons fail, choose a different device under **Playback device** if one is available. Daymark v15 refreshes Spotify’s active-player state before every command and normally targets the active player without relying on a saved device ID. If Spotify restricts that playback context, Daymark keeps the listening data current and directs you to the Spotify app instead of repeatedly suggesting reconnection.
