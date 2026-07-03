# Connect Daymark to Google Calendar and Gmail

Daymark uses Google Identity Services and requests read-only access. The access token remains in the open browser session; it is not written to the repository or browser storage.

## 1. Create a Google Cloud project

1. Open https://console.cloud.google.com/
2. Create a project named `Daymark Personal`.

## 2. Enable the APIs

In **APIs & Services → Library**, enable:

- Google Calendar API
- Gmail API

## 3. Configure Google Auth

1. Open **Google Auth Platform → Branding**.
2. Name the app `Daymark`.
3. Use your Google account as the support and contact email.
4. Under **Audience**, choose **External** unless you use a Google Workspace organization.
5. Add your own Google account as a test user.
6. Under **Data Access**, add:
   - `https://www.googleapis.com/auth/calendar.readonly`
   - `https://www.googleapis.com/auth/gmail.readonly`

Gmail read-only is a restricted scope. Keep the app in testing and use only your own account unless you later complete Google's verification requirements.

## 4. Create the OAuth client

1. Open **Google Auth Platform → Clients**.
2. Click **Create client**.
3. Select **Web application**.
4. Name it `Daymark GitHub Pages`.
5. Under **Authorized JavaScript origins**, add exactly:

   `https://relytbytes.github.io`

6. Create the client and copy the client ID ending in `.apps.googleusercontent.com`.

Do not create or publish a client secret. This browser integration needs only the public client ID.

## 5. Add the client ID to Daymark

1. In the GitHub repository, open `config.js`.
2. Click the pencil icon.
3. Replace `PASTE_GOOGLE_OAUTH_CLIENT_ID_HERE.apps.googleusercontent.com` with your copied client ID.
4. Commit the change.
5. Wait for GitHub Pages to redeploy, then open:

   https://relytbytes.github.io/daymark/?v=7

6. Tap **Connect Google securely** and approve read-only Calendar and Gmail access.
