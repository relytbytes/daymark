const STORAGE_KEY = "daymark-state-v1";
const WEATHER_CACHE_KEY = "daymark-weather-cache-v1";
const BASEBALL_CACHE_KEY = "daymark-baseball-cache-v1";
const DURHAM_SPORTS_CACHE_KEY = "daymark-durham-sports-cache-v1";
const GOOGLE_SESSION_KEY = "daymark-google-session-v1";
const SPOTIFY_SESSION_KEY = "daymark-spotify-session-v1";
const SPOTIFY_PKCE_KEY = "daymark-spotify-pkce-v1";
const GOOGLE_SCOPE_VERSION = "sheets-v1";
const DESK_SETTINGS_KEY = "daymark-desk-settings-v1";
const GOOGLE_SCOPE_VERSION_STORAGE_KEY = "daymark-google-scope-version";
const STATE_SCHEMA_VERSION = 16;
const WEATHER_REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const BASEBALL_REFRESH_INTERVAL_MS = 60 * 1000;
const BASEBALL_LIVE_REFRESH_INTERVAL_MS = 30 * 1000;
const DURHAM_SPORTS_REFRESH_INTERVAL_MS = 60 * 1000;
const DURHAM_SPORTS_LIVE_REFRESH_INTERVAL_MS = 15 * 1000;
const GOOGLE_REFRESH_INTERVAL_MS = 2 * 60 * 1000;
const SPOTIFY_REFRESH_INTERVAL_MS = 15 * 1000;
const SPOTIFY_LIBRARY_REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const REFRESH_SCHEDULER_INTERVAL_MS = 15 * 1000;
const GOOGLE_SCOPES = [
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/gmail.modify",
  "https://www.googleapis.com/auth/spreadsheets.readonly",
].join(" ");

// Device-local desk settings (never committed: the repo is public).
// { landedSheetId, aiProvider, aiKey, soundcloudUser, soundcloudArtists }
function loadDeskSettings() {
  try {
    return JSON.parse(localStorage.getItem(DESK_SETTINGS_KEY)) || {};
  } catch {
    return {};
  }
}

function saveDeskSettings(partial) {
  const merged = { ...loadDeskSettings(), ...partial };
  localStorage.setItem(DESK_SETTINGS_KEY, JSON.stringify(merged));
  return merged;
}
const SPOTIFY_SCOPES = [
  "user-read-private",
  "user-read-currently-playing",
  "user-read-playback-state",
  "user-read-recently-played",
  "user-top-read",
  "user-modify-playback-state",
].join(" ");
const DEMO_APPLICATION_IDS = new Set(["duke-policy", "public-affairs", "foundation", "dataworks"]);
const DAILY_TASK_IDS = new Set([
  "duke-followup",
  "veraya-pricing",
  "submit-application",
  "log-duke",
  "veraya-decision",
  "tomorrow-first",
]);
const initialApplications = [];

const defaultState = {
  schemaVersion: STATE_SCHEMA_VERSION,
  dayKey: "",
  weekKey: "",
  tasks: {},
  decisions: {},
  applications: initialApplications,
  captures: [],
  readingQueue: [],
  clearedMailIds: [],
  focusTaskId: "",
  focusEndsAt: 0,
  weeklyScores: {
    jobs: 0,
    veraya: 0,
    writing: 0,
    fitness: 0,
    household: 0,
  },
};

let state = loadState();
let toastTimer;
let lastWeatherRefreshAt = 0;
let lastBaseballRefreshAt = 0;
let lastDurhamSportsRefreshAt = 0;
let lastGoogleRefreshAt = 0;
let lastSpotifyRefreshAt = 0;
let lastSpotifyLibraryRefreshAt = 0;
let weatherRefreshInFlight = false;
let baseballRefreshInFlight = false;
let durhamSportsRefreshInFlight = false;
let durhamBullsGameIsLive = false;
let publicFeedStatus = { weather: "checking", baseball: "checking", durhamSports: "checking" };
let googleAccessToken = "";
let googleTokenExpiresAt = 0;
let spotifyAccessToken = "";
let spotifyRefreshToken = "";
let spotifyTokenExpiresAt = 0;
let spotifyGrantedScopes = "";
let spotifyRefreshInFlight = false;
let spotifyLibraryView = "recent";
let lastSpotifyData = {
  playback: null,
  devices: [],
  queue: [],
  recent: [],
  top: [],
  topMedium: [],
  topLong: [],
  topArtists: [],
  profile: null,
};
let spotifyProgressBaseMs = 0;
let spotifyProgressFetchedAt = 0;
let spotifyDurationMs = 0;
let spotifyIsPlaying = false;
let focusCompletionAnnounced = false;
let baseballGameIsLive = false;
let currentStandingsView = "division";
let divisionStandingsRecords = [];
let wildCardStandingsRecords = [];
let lastPriorityEmailMessages = [];
const body = document.body;
const taskInputs = [...document.querySelectorAll(".task-check")];
const navButtons = [...document.querySelectorAll(".nav-button")];
const applicationDialog = document.querySelector("#applicationDialog");
const applicationForm = document.querySelector("#applicationForm");
const captureDialog = document.querySelector("#captureDialog");
const captureForm = document.querySelector("#captureForm");
const VIEW_CONFIG = Object.freeze({
  today: {
    tag: "Morning Brief",
    title: "Good morning, Ty.",
    glance: ["weather", "now", "daylight", "open"],
    shortcuts: [],
  },
  work: {
    tag: "Section B",
    title: "Work",
    glance: ["active", "interviews", "followups", "sprint"],
    shortcuts: [
      ["Applications", "jobs"],
      ["Veraya", "veraya"],
      ["Decisions", "decisions"],
      ["Scorecard", "scorecard"],
    ],
  },
  life: {
    tag: "Section C · Durham",
    title: "Life",
    glance: ["weather", "now", "sunset", "daylight"],
    shortcuts: [
      ["Weather", "durham"],
      ["Events", "durham"],
      ["Homes", "durham"],
      ["Bulls", "durhamBullsGame"],
    ],
  },
  more: {
    tag: "Section D · Arts & Media",
    title: "More",
    glance: ["dbacks", "saved", "playing", "now"],
    shortcuts: [
      ["Sports", "sports"],
      ["Spotify", "listen"],
      ["Reading", "reading"],
      ["YouTube", "watch"],
    ],
  },
});

// Labels + presentation for the At-a-Glance ribbon cells. Values are filled
// live by syncGlances() from the canonical elements each already maintains.
const GLANCE_CELLS = Object.freeze({
  weather: { label: "Weather", glyph: "☀", accent: false },
  now: { label: "Now", accent: false },
  daylight: { label: "Daylight", accent: false },
  open: { label: "Open", accent: true },
  active: { label: "Active", accent: false },
  interviews: { label: "Interviews", accent: true },
  followups: { label: "Follow-ups", accent: false },
  sprint: { label: "Sprint", accent: false },
  sunset: { label: "Sunset", accent: false },
  dbacks: { label: "D-backs", accent: true },
  saved: { label: "Saved", accent: false },
  playing: { label: "Playing", accent: false },
});

function mastheadGreeting(date = new Date()) {
  const phase = getDayPhase(date);
  const word =
    phase === "morning"
      ? "Good morning"
      : phase === "afternoon"
        ? "Good afternoon"
        : "Good evening";
  return `${word}, <i>Ty.</i>`;
}

function glanceShortDate(date = new Date()) {
  return new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  })
    .format(date)
    .replace(",", " ·");
}

function stripMeridiem(value) {
  return String(value || "").replace(/\s?(AM|PM)$/i, "").trim();
}

function readText(id) {
  const el = document.getElementById(id);
  return el ? el.textContent.trim() : "";
}

function glanceValue(key) {
  switch (key) {
    case "weather": {
      const val = readText("weatherCurrent");
      const summary = readText("weatherSummary").split("·")[0].trim();
      return { val: val && val !== "—°" ? val : "—", sub: summary || "Durham" };
    }
    case "now":
      return { val: stripMeridiem(readText("currentTime")) || "—", sub: glanceShortDate() };
    case "daylight":
      return {
        val: document.body.dataset.daylight || "—",
        sub: document.body.dataset.sunwindow || "Durham",
      };
    case "open":
      return { val: readText("openCount") || "0", sub: "loops" };
    case "active":
      return { val: readText("activeApps") || "0", sub: "apps" };
    case "interviews":
      return { val: readText("interviewApps") || "0", sub: "scheduled" };
    case "followups":
      return { val: readText("followupApps") || "0", sub: "due" };
    case "sprint":
      return { val: readText("sprintPercent") || "0%", sub: "complete" };
    case "sunset":
      return { val: document.body.dataset.sunset || "—", sub: "Durham" };
    case "saved":
      return { val: (readText("readingQueueCount").match(/\d+/) || ["0"])[0], sub: "to read" };
    case "dbacks":
      return { val: readText("widgetGame") || "—", sub: readText("widgetGameNote") || "MLB" };
    case "playing": {
      const item =
        typeof lastSpotifyData !== "undefined" && lastSpotifyData.playback
          ? lastSpotifyData.playback.item
          : null;
      if (item && item.name) {
        const artist =
          Array.isArray(item.artists) && item.artists[0] ? item.artists[0].name : "Spotify";
        return { val: spotifyIsPlaying ? "On" : "Paused", sub: item.name || artist };
      }
      return { val: "—", sub: "Spotify" };
    }
    default:
      return { val: "—", sub: "" };
  }
}

function syncGlances() {
  const grid = document.querySelector("#glanceGrid");
  if (!grid) return;
  grid.querySelectorAll(".glance-cell").forEach((cell) => {
    const { val, sub } = glanceValue(cell.dataset.glance);
    const valEl = cell.querySelector("[data-glance-val]");
    const subEl = cell.querySelector("[data-glance-sub]");
    if (valEl) valEl.textContent = val;
    if (subEl) subEl.textContent = sub;
  });
}

function setMastheadTitle(view) {
  const el = document.querySelector("#viewTitle");
  if (!el) return;
  if (view === "today") el.innerHTML = mastheadGreeting();
  else el.textContent = VIEW_CONFIG[view] ? VIEW_CONFIG[view].title : "Daymark";
}

function buildGlanceGrid(view) {
  const grid = document.querySelector("#glanceGrid");
  if (!grid) return;
  const keys = VIEW_CONFIG[view] ? VIEW_CONFIG[view].glance : [];
  grid.innerHTML = keys
    .map((key) => {
      const cell = GLANCE_CELLS[key] || { label: key };
      const glyph = cell.glyph
        ? `<span class="glance-cell-glyph" aria-hidden="true">${cell.glyph}</span>`
        : "";
      const accent = cell.accent ? " is-accent" : "";
      return (
        `<div class="glance-cell" data-glance="${escapeHtml(key)}">` +
        `<div class="glance-cell-label">${escapeHtml(cell.label)}</div>` +
        `<div class="glance-cell-value${accent}">${glyph}<span data-glance-val>—</span></div>` +
        `<div class="glance-cell-sub" data-glance-sub>—</div>` +
        `</div>`
      );
    })
    .join("");
}

function renderMasthead(view) {
  const nextView = VIEW_CONFIG[view] ? view : "today";
  const tag = document.querySelector("#viewKicker");
  if (tag) tag.textContent = VIEW_CONFIG[nextView].tag;
  setMastheadTitle(nextView);
  buildGlanceGrid(nextView);
  syncGlances();
}

document.addEventListener(
  "error",
  (event) => {
    if (!(event.target instanceof HTMLImageElement)) return;
    if (
      !event.target.hasAttribute("data-team-logo") &&
      !event.target.src.includes("mlbstatic.com/team-logos")
    ) return;
    const shell = event.target.closest("[data-abbr]");
    if (shell) shell.classList.add("is-missing");
    event.target.remove();
  },
  true,
);

function getDayPhase(date = new Date()) {
  const hour = date.getHours();
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 17) return "afternoon";
  if (hour >= 17 && hour < 21) return "evening";
  return "night";
}

function loadState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    const hydrated = {
      ...defaultState,
      ...saved,
      schemaVersion: STATE_SCHEMA_VERSION,
      tasks: { ...defaultState.tasks, ...(saved?.tasks || {}) },
      decisions: { ...defaultState.decisions, ...(saved?.decisions || {}) },
      applications: Array.isArray(saved?.applications)
        ? saved.applications.filter((application) => !DEMO_APPLICATION_IDS.has(application.id))
        : initialApplications,
      captures: Array.isArray(saved?.captures) ? saved.captures : [],
      readingQueue: Array.isArray(saved?.readingQueue) ? saved.readingQueue : [],
      clearedMailIds: Array.isArray(saved?.clearedMailIds) ? saved.clearedMailIds : [],
      focusTaskId: typeof saved?.focusTaskId === "string" ? saved.focusTaskId : "",
      focusEndsAt: Number(saved?.focusEndsAt) || 0,
      weeklyScores: {
        ...defaultState.weeklyScores,
        ...(saved?.weeklyScores || {}),
      },
    };
    return rollStatePeriods(hydrated, Number(saved?.schemaVersion) || 0);
  } catch {
    return rollStatePeriods({ ...defaultState }, 0);
  }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function getWeekKey(date = new Date()) {
  const monday = new Date(date);
  const day = monday.getDay();
  monday.setDate(monday.getDate() - ((day + 6) % 7));
  monday.setHours(0, 0, 0, 0);
  return formatApiDate(monday);
}

function rollStatePeriods(candidate, previousSchemaVersion = STATE_SCHEMA_VERSION) {
  const todayKey = formatApiDate(new Date());
  const weekKey = getWeekKey();

  if (previousSchemaVersion < STATE_SCHEMA_VERSION) {
    delete candidate.tasks["veraya-interviews"];
    delete candidate.tasks["veraya-draft"];
  }

  if (candidate.dayKey !== todayKey) {
    DAILY_TASK_IDS.forEach((id) => {
      delete candidate.tasks[id];
    });
    candidate.captures = candidate.captures.filter((item) => !item.done && !item.archived);
    candidate.focusTaskId = "";
    candidate.focusEndsAt = 0;
    candidate.dayKey = todayKey;
  }

  if (candidate.weekKey !== weekKey) {
    const hadScores = Object.values(candidate.weeklyScores || {}).some((value) => value > 0);
    if (hadScores) {
      candidate.scoreHistory = candidate.scoreHistory || {};
      candidate.scoreHistory[candidate.weekKey] = { ...candidate.weeklyScores };
      const keys = Object.keys(candidate.scoreHistory).sort();
      while (keys.length > 60) delete candidate.scoreHistory[keys.shift()];
    }
    candidate.weeklyScores = { ...defaultState.weeklyScores };
    candidate.decisions = {};
    candidate.weekKey = weekKey;
  }

  return candidate;
}

function normalizeUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  try {
    const candidate = new URL(/^https?:\/\//i.test(raw) ? raw : `https://${raw}`);
    return ["http:", "https:"].includes(candidate.protocol) ? candidate.href : "";
  } catch {
    return "";
  }
}

function openMapSearch(query) {
  const terms = String(query || "").trim();
  if (!terms) {
    document.querySelector("#mapSearchInput").focus();
    showToast("What should Maps find near Durham?");
    return;
  }
  const locationQuery = `${terms}, Durham NC`;
  window.open(
    `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(locationQuery)}`,
    "_blank",
    "noopener,noreferrer",
  );
}

function openYouTubeSearch(query) {
  const terms = String(query || "").trim();
  if (!terms) {
    document.querySelector("#youtubeSearchInput").focus();
    showToast("What do you want to watch?");
    return;
  }
  window.open(
    `https://www.youtube.com/results?search_query=${encodeURIComponent(terms)}`,
    "_blank",
    "noopener,noreferrer",
  );
}

function getOpenFocusItems() {
  const priorityItems = getVisiblePriorityInputs()
    .filter((input) => !input.checked)
    .map((input) => {
      const card = input.closest("[data-task]");
      const taskId = card?.dataset.task || "";
      const category = card?.querySelector(".action-topline span")?.textContent || "PRIORITY";
      const estimate = card?.querySelector(".action-topline time")?.textContent || "25 min";
      return {
        id: `task:${taskId}`,
        kind: "task",
        taskId,
        title: card?.querySelector(".action-content strong")?.textContent || "Open priority",
        context: `${category} · ${estimate}`,
        estimate,
      };
    });

  const capturedItems = state.captures
    .filter((item) => !item.done && !item.archived)
    .map((item) => ({
      id: `capture:${item.id}`,
      kind: "capture",
      captureId: item.id,
      title: item.title,
      context: `${item.type === "reminder" ? "REMINDER" : "INBOX"} · ${item.note || "captured today"}`,
      estimate: item.type === "reminder" ? "5 min" : "25 min",
    }));

  return [...priorityItems, ...capturedItems];
}

function getFocusedItem() {
  const items = getOpenFocusItems();
  if (!items.length) return null;
  return items.find((item) => item.id === state.focusTaskId) || items[0];
}

function renderFocusRail() {
  const item = getFocusedItem();
  const doneButton = document.querySelector("#focusDoneButton");
  const nextButton = document.querySelector("#focusNextButton");
  if (!item) {
    state.focusTaskId = "";
    document.querySelector("#focusTitle").textContent = "The runway is clear";
    document.querySelector("#focusContext").textContent =
      "Capture something new, or enjoy the rare pleasure of an empty queue.";
    document.querySelector("#focusEstimate").textContent = "CLEAR";
    doneButton.disabled = true;
    nextButton.disabled = true;
    return;
  }

  if (state.focusTaskId !== item.id) {
    state.focusTaskId = item.id;
    saveState();
  }
  document.querySelector("#focusTitle").textContent = item.title;
  document.querySelector("#focusContext").textContent = item.context;
  document.querySelector("#focusEstimate").textContent = item.estimate.toUpperCase();
  doneButton.disabled = false;
  nextButton.disabled = getOpenFocusItems().length < 2;
}

function showNextFocusItem() {
  const items = getOpenFocusItems();
  if (items.length < 2) return;
  const currentIndex = Math.max(
    0,
    items.findIndex((item) => item.id === state.focusTaskId),
  );
  state.focusTaskId = items[(currentIndex + 1) % items.length].id;
  saveState();
  renderFocusRail();
}

function completeFocusedItem() {
  const item = getFocusedItem();
  if (!item) return;
  if (item.kind === "task") {
    state.tasks[item.taskId] = true;
    const input = document.querySelector(`[data-task="${item.taskId}"] .task-check`);
    if (input) input.checked = true;
  } else {
    const capture = state.captures.find((entry) => entry.id === item.captureId);
    if (capture) capture.done = true;
  }
  state.focusTaskId = "";
  state.focusEndsAt = 0;
  saveState();
  renderCaptureInbox();
  renderFocusRail();
  updateBriefProgress();
  updateSprintProgress();
  updateFocusTimer();
  showToast("Done. Daymark pulled the next open move.");
}

function updateFocusTimer() {
  const label = document.querySelector("#focusTimerLabel");
  const button = document.querySelector("#focusTimerButton");
  const progress = document.querySelector("#focusProgress");
  const duration = 25 * 60 * 1000;
  const remaining = state.focusEndsAt ? state.focusEndsAt - Date.now() : 0;

  if (remaining > 0) {
    const totalSeconds = Math.ceil(remaining / 1000);
    const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, "0");
    const seconds = String(totalSeconds % 60).padStart(2, "0");
    label.textContent = `${minutes}:${seconds}`;
    button.classList.add("is-running");
    progress.style.width = `${Math.min(100, ((duration - remaining) / duration) * 100)}%`;
    focusCompletionAnnounced = false;
    return;
  }

  if (state.focusEndsAt) {
    state.focusEndsAt = 0;
    saveState();
    if (!focusCompletionAnnounced) {
      showToast("Focus block complete. Take a breath.");
      focusCompletionAnnounced = true;
    }
  }
  label.textContent = "Focus 25:00";
  button.classList.remove("is-running");
  progress.style.width = "0%";
}

function toggleFocusTimer() {
  if (!getFocusedItem()) {
    showToast("Capture an action before starting focus.");
    return;
  }
  if (state.focusEndsAt > Date.now()) {
    state.focusEndsAt = 0;
    showToast("Focus timer stopped.");
  } else {
    state.focusEndsAt = Date.now() + 25 * 60 * 1000;
    focusCompletionAnnounced = false;
    showToast("Twenty-five quiet minutes. Go.");
    startFocusSoundtrack();
  }
  saveState();
  updateFocusTimer();
}

function renderCaptureInbox() {
  renderPracticalReminder();
  const container = document.querySelector("#captureItems");
  const visibleCaptures = state.captures.filter((item) => !item.archived);
  container.replaceChildren();
  if (!visibleCaptures.length) {
    const empty = document.createElement("p");
    empty.className = "capture-empty";
    empty.textContent = "Nothing waiting. Use Capture whenever a loose end appears.";
    container.append(empty);
    return;
  }

  visibleCaptures.forEach((item) => {
    const row = document.createElement("div");
    row.className = `capture-row${item.done ? " is-done" : ""}`;
    row.innerHTML = `
      <label class="capture-toggle">
        <input type="checkbox" ${item.done ? "checked" : ""} />
        <span class="mini-check"><svg viewBox="0 0 20 20"><path d="m5 10 3 3 7-7" /></svg></span>
        <span>
          <strong>${escapeHtml(item.title)}</strong>
          <small>${escapeHtml(item.type === "reminder" ? "Reminder" : "Task")}${item.note ? ` · ${escapeHtml(item.note)}` : ""}</small>
        </span>
      </label>
      <button class="item-archive" type="button" aria-label="Archive ${escapeHtml(item.title)}">Remove</button>
    `;
    row.querySelector("input").addEventListener("change", (event) => {
      item.done = event.target.checked;
      if (item.done && state.focusTaskId === `capture:${item.id}`) state.focusTaskId = "";
      saveState();
      renderCaptureInbox();
      renderFocusRail();
      updateBriefProgress();
    });
    row.querySelector(".item-archive").addEventListener("click", () => {
      item.archived = true;
      if (state.focusTaskId === `capture:${item.id}`) state.focusTaskId = "";
      saveState();
      renderCaptureInbox();
      renderFocusRail();
      updateBriefProgress();
      showToast("Archived. Your active list stays clean.");
    });
    container.append(row);
  });
}

function renderPracticalReminder() {
  const reminder = state.captures.find(
    (item) => item.type === "reminder" && !item.done && !item.archived,
  );
  document.querySelector("#practicalReminderTitle").textContent =
    reminder?.title || "Add a practical reminder";
  document.querySelector("#practicalReminderNote").textContent =
    reminder?.note || "Tap to add a reminder.";
  document
    .querySelector("#practicalReminder")
    .classList.toggle("has-reminder", Boolean(reminder));
}

function renderReadingQueue() {
  const container = document.querySelector("#readingQueueItems");
  const visibleItems = state.readingQueue.filter((item) => !item.archived);
  const openItems = visibleItems.filter((item) => !item.read);
  document.querySelector("#readingQueueCount").textContent =
    `${openItems.length} saved`;
  container.replaceChildren();

  if (!visibleItems.length) {
    const empty = document.createElement("p");
    empty.className = "reading-queue-empty";
    empty.textContent = "Save an article here and it will wait without nagging you.";
    container.append(empty);
    return;
  }

  visibleItems.forEach((item) => {
    const row = document.createElement("div");
    row.className = `reading-queue-row${item.read ? " is-read" : ""}`;
    const host = item.url ? new URL(item.url).hostname.replace(/^www\./, "") : "Saved note";
    row.innerHTML = `
      <a href="${escapeHtml(item.url || "#")}" ${item.url ? 'target="_blank" rel="noreferrer"' : ""}>
        <span>
          <small>${escapeHtml(host.toUpperCase())}</small>
          <strong>${escapeHtml(item.title)}</strong>
        </span>
      </a>
      <div class="reading-row-actions">
        <button class="reading-toggle" type="button">${item.read ? "Unread" : "Read"}</button>
        <button class="item-archive" type="button" aria-label="Archive ${escapeHtml(item.title)}">Remove</button>
      </div>
    `;
    row.querySelector(".reading-toggle").addEventListener("click", () => {
      item.read = !item.read;
      saveState();
      renderReadingQueue();
      showToast(item.read ? "Moved to read." : "Back in the reading queue.");
    });
    row.querySelector(".item-archive").addEventListener("click", () => {
      item.archived = true;
      saveState();
      renderReadingQueue();
      showToast("Article archived.");
    });
    container.append(row);
  });
}

function setCaptureType(type) {
  const input = captureForm.querySelector(`input[name="captureType"][value="${type}"]`);
  if (input) input.checked = true;
  const titleInput = captureForm.elements.title;
  const placeholders = {
    task: "What needs your attention?",
    job: "Role or opportunity",
    reading: "Article title",
    reminder: "What should not slip?",
  };
  titleInput.placeholder = placeholders[type] || placeholders.task;
  captureForm.querySelector(".capture-url-field span").textContent =
    type === "reading" ? "required" : "optional";
  captureDialog.dataset.captureType = type;
}

function openCaptureDialog(type = "task") {
  captureForm.reset();
  setCaptureType(type);
  captureDialog.showModal();
  window.setTimeout(() => captureForm.elements.title.focus(), 80);
}

function formatDate(date = new Date()) {
  const label = new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  })
    .format(date)
    .replace(",", " ·");
  document.querySelector("#dateLabel").textContent = label.toUpperCase();

  const tomorrow = new Date(date);
  tomorrow.setDate(date.getDate() + 1);
  const tomorrowName = new Intl.DateTimeFormat("en-US", { weekday: "long" }).format(tomorrow);
  document.querySelector("#tomorrowTitle").textContent = `${tomorrowName}, without guesswork.`;

  const startOfYear = new Date(date.getFullYear(), 0, 1);
  const week = Math.ceil(((date - startOfYear) / 86400000 + startOfYear.getDay() + 1) / 7);
  document.querySelector("#weekLabel").textContent = `WEEK ${week}`;
}

function updateClock(date = new Date()) {
  const currentTime = document.querySelector("#currentTime");
  currentTime.textContent = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
  currentTime.dateTime = date.toISOString();
  syncGlances();
}

function updateLiveDay(date = new Date()) {
  const needsRollover =
    state.dayKey !== formatApiDate(date) || state.weekKey !== getWeekKey(date);
  if (needsRollover) {
    state = rollStatePeriods(state);
    saveState();
    formatDate(date);
    taskInputs.forEach((input) => {
      const taskId = input.closest("[data-task]")?.dataset.task;
      if (taskId) input.checked = Boolean(state.tasks[taskId]);
    });
    renderCaptureInbox();
    renderWeeklyScorecard();
    updateSprintProgress();
  }

  const phase = getDayPhase(date);
  const isWeekend = date.getDay() === 0 || date.getDay() === 6;
  const phaseContent = {
    morning: {
      label: "Morning edition",
      title: "The morning brief.",
      note: "Today’s priorities, the calendar, and what came in overnight.",
      priorityKicker: "PRIORITIES",
      priorityTitle: "Today’s three",
      signalKicker: "IN MOTION",
      signalTitle: "Calendar + priority mail",
      readingKicker: "SAVED READING · 28 MIN",
    },
    afternoon: {
      label: "Midday edition",
      title: "The midday check.",
      note: "What moved this morning, and what the afternoon holds.",
      priorityKicker: "PRIORITIES",
      priorityTitle: "This afternoon’s three",
      signalKicker: "NEXT UP",
      signalTitle: "Calendar + priority mail",
      readingKicker: "SAVED READING · 28 MIN",
    },
    evening: {
      label: "Evening edition",
      title: "The evening edition.",
      note: "The day’s results, open items, and tomorrow’s first event.",
      priorityKicker: "OPEN ITEMS",
      priorityTitle: "Still open today",
      signalKicker: "THE LEDGER",
      signalTitle: "Day in review",
      readingKicker: "SAVED READING · 28 MIN",
    },
    night: {
      label: "Late edition",
      title: "The late edition.",
      note: "Tomorrow’s schedule is set. Nothing here needs attention tonight.",
      priorityKicker: "TOMORROW",
      priorityTitle: "Tomorrow’s setup",
      signalKicker: "TOMORROW",
      signalTitle: "Tomorrow’s schedule",
      readingKicker: "SAVED READING · 28 MIN",
    },
  }[phase];

  body.dataset.phase = phase;
  if (body.dataset.view === "today") setMastheadTitle("today");
  document.querySelector("#phaseLabel").textContent = phaseContent.label;
  document.querySelector("#heroTitle").textContent = phaseContent.title;
  document.querySelector("#heroNote").textContent = phaseContent.note;
  document.querySelector("#priorityKicker").textContent = phaseContent.priorityKicker;
  document.querySelector("#priorityTitle").textContent = phaseContent.priorityTitle;
  document.querySelector("#signalKicker").textContent = phaseContent.signalKicker;
  document.querySelector("#signalTitle").textContent = phaseContent.signalTitle;
  document.querySelector("#readingKicker").textContent = phaseContent.readingKicker;
  updateClock(date);

  const dayStart = new Date(date);
  dayStart.setHours(5, 0, 0, 0);
  const dayEnd = new Date(date);
  dayEnd.setHours(23, 0, 0, 0);
  const progress = Math.max(0, Math.min(100, ((date - dayStart) / (dayEnd - dayStart)) * 100));
  document.querySelector("#dayProgress").style.width = `${progress}%`;

  updateBriefProgress();
  renderFocusRail();
}

function formatApiDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

async function fetchJson(url) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(url, { cache: "no-store", signal: controller.signal });
    if (!response.ok) throw new Error(`Request failed: ${response.status}`);
    return await response.json();
  } finally {
    window.clearTimeout(timeout);
  }
}

function hasGoogleClientId() {
  const clientId = window.DAYMARK_CONFIG?.googleClientId?.trim() || "";
  return clientId.endsWith(".apps.googleusercontent.com") && !clientId.startsWith("PASTE_");
}

function googleConnectMarkup(title = "Connect Google securely", copy = "Allow read-only access.") {
  return `
    <button class="connection-empty google-connect-button" type="button" data-google-connect>
      <span aria-hidden="true">+</span>
      <strong>${escapeHtml(title)}</strong>
      <p>${escapeHtml(copy)}</p>
    </button>
  `;
}

function bindGoogleConnectButtons() {
  document.querySelectorAll("[data-google-connect]").forEach((button) => {
    if (button.dataset.bound === "true") return;
    button.dataset.bound = "true";
    button.addEventListener("click", connectGoogle);
  });
}

function setGoogleButtonsDisabled(disabled) {
  document.querySelectorAll("[data-google-connect]").forEach((button) => {
    button.disabled = disabled;
  });
}

function persistGoogleSession() {
  try {
    localStorage.setItem(
      GOOGLE_SESSION_KEY,
      JSON.stringify({
        accessToken: googleAccessToken,
        expiresAt: googleTokenExpiresAt,
      }),
    );
  } catch {
    // The live panels still work for the current page session.
  }
}

function clearGoogleSession() {
  googleAccessToken = "";
  googleTokenExpiresAt = 0;
  try {
    localStorage.removeItem(GOOGLE_SESSION_KEY);
  } catch {
    // Nothing else to clear.
  }
  const disconnectButton = document.querySelector("#disconnectGoogle");
  if (disconnectButton) disconnectButton.hidden = true;
}

function restoreGoogleSession() {
  try {
    const saved = JSON.parse(localStorage.getItem(GOOGLE_SESSION_KEY));
    const hasCurrentScope =
      localStorage.getItem(GOOGLE_SCOPE_VERSION_STORAGE_KEY) === GOOGLE_SCOPE_VERSION;
    if (saved?.accessToken && hasCurrentScope && Number(saved.expiresAt) > Date.now() + 30000) {
      googleAccessToken = saved.accessToken;
      googleTokenExpiresAt = Number(saved.expiresAt);
      return true;
    }
  } catch {
    // Invalid or unavailable local storage means reconnecting manually.
  }
  clearGoogleSession();
  return false;
}

function connectGoogle() {
  if (!hasGoogleClientId()) {
    showToast("Google OAuth setup is required first.");
    window.open(
      new URL("./GOOGLE_SETUP.md", window.location.href).href,
      "_blank",
      "noopener,noreferrer",
    );
    return;
  }

  if (!window.google?.accounts?.oauth2) {
    showToast("Google sign-in is still loading. Try once more.");
    return;
  }

  setGoogleButtonsDisabled(true);
  const tokenClient = window.google.accounts.oauth2.initTokenClient({
    client_id: window.DAYMARK_CONFIG.googleClientId.trim(),
    scope: GOOGLE_SCOPES,
    callback: async (response) => {
      if (response.error || !response.access_token) {
        setGoogleButtonsDisabled(false);
        showToast("Google connection was not completed.");
        return;
      }
      googleAccessToken = response.access_token;
      googleTokenExpiresAt = Date.now() + Number(response.expires_in || 3600) * 1000;
      localStorage.setItem("daymark-google-was-connected", "1");
      localStorage.setItem(GOOGLE_SCOPE_VERSION_STORAGE_KEY, GOOGLE_SCOPE_VERSION);
      persistGoogleSession();
      await loadGoogleData();
    },
    error_callback: () => {
      setGoogleButtonsDisabled(false);
      showToast("Google sign-in was closed or blocked.");
    },
  });

  const hasCurrentScope =
    localStorage.getItem(GOOGLE_SCOPE_VERSION_STORAGE_KEY) === GOOGLE_SCOPE_VERSION;
  tokenClient.requestAccessToken({ prompt: hasCurrentScope ? "" : "consent" });
}

async function waitForGoogleIdentityServices(timeoutMs = 4000, intervalMs = 200) {
  const start = Date.now();
  while (!window.google?.accounts?.oauth2) {
    if (Date.now() - start >= timeoutMs) return false;
    await new Promise((resolve) => window.setTimeout(resolve, intervalMs));
  }
  return true;
}

let googleSilentTokenClient = null;
let googleTokenRefreshPromise = null;

async function requestSilentGoogleToken() {
  const ready = await waitForGoogleIdentityServices();
  if (!ready) return false;
  try {
    if (!googleSilentTokenClient) {
      googleSilentTokenClient = window.google.accounts.oauth2.initTokenClient({
        client_id: window.DAYMARK_CONFIG.googleClientId.trim(),
        scope: GOOGLE_SCOPES,
        callback: () => {},
      });
    }
    const response = await new Promise((resolve) => {
      googleSilentTokenClient.callback = (resp) => resolve(resp);
      googleSilentTokenClient.error_callback = () => resolve({ error: "silent_reauth_failed" });
      googleSilentTokenClient.requestAccessToken({ prompt: "" });
    });
    if (response.error || !response.access_token) return false;
    googleAccessToken = response.access_token;
    googleTokenExpiresAt = Date.now() + Number(response.expires_in || 3600) * 1000;
    localStorage.setItem(GOOGLE_SCOPE_VERSION_STORAGE_KEY, GOOGLE_SCOPE_VERSION);
    persistGoogleSession();
    return true;
  } catch {
    return false;
  }
}

async function ensureGoogleAccessToken() {
  if (googleAccessToken && Date.now() < googleTokenExpiresAt) return true;
  if (!hasGoogleClientId()) return false;

  const hasCurrentScope =
    localStorage.getItem(GOOGLE_SCOPE_VERSION_STORAGE_KEY) === GOOGLE_SCOPE_VERSION;
  if (!hasCurrentScope) {
    clearGoogleSession();
    return false;
  }

  if (!googleTokenRefreshPromise) {
    googleTokenRefreshPromise = requestSilentGoogleToken().finally(() => {
      googleTokenRefreshPromise = null;
    });
  }

  const renewed = await googleTokenRefreshPromise;
  if (!renewed) clearGoogleSession();
  return renewed;
}

async function fetchGoogleJson(url) {
  if (!(await ensureGoogleAccessToken())) {
    throw new Error("Google access has expired.");
  }
  const response = await fetch(url, {
    cache: "no-store",
    headers: { Authorization: `Bearer ${googleAccessToken}` },
  });
  if (response.status === 401) clearGoogleSession();
  if (!response.ok) throw new Error(`Google request failed: ${response.status}`);
  return await response.json();
}

async function modifyGmailMessage(messageId, body) {
  if (!(await ensureGoogleAccessToken())) {
    throw new Error("Google access has expired.");
  }
  const response = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${encodeURIComponent(messageId)}/modify`,
    {
      method: "POST",
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${googleAccessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
  if (response.status === 401) clearGoogleSession();
  if (!response.ok) throw new Error(`Gmail update failed: ${response.status}`);
  return await response.json();
}

async function fetchCalendarData() {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 2);
  const params = new URLSearchParams({
    timeMin: start.toISOString(),
    timeMax: end.toISOString(),
    singleEvents: "true",
    orderBy: "startTime",
    maxResults: "10",
  });
  return await fetchGoogleJson(
    `https://www.googleapis.com/calendar/v3/calendars/primary/events?${params}`,
  );
}

function formatCalendarTime(event) {
  if (event.start?.date && !event.start?.dateTime) return "ALL DAY";
  const start = new Date(event.start?.dateTime);
  const today = formatApiDate(new Date());
  const eventDay = formatApiDate(start);
  if (today === eventDay) {
    return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(start);
  }
  return new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    hour: "numeric",
    minute: "2-digit",
  })
    .format(start)
    .toUpperCase();
}

function renderTomorrowFromCalendar(events) {
  const tomorrow = new Date();
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowKey = formatApiDate(tomorrow);
  const tomorrowName = new Intl.DateTimeFormat("en-US", { weekday: "long" }).format(tomorrow);
  const tomorrowEvents = (events || [])
    .filter((event) => event.status !== "cancelled")
    .filter((event) => {
      if (event.start?.date) return event.start.date === tomorrowKey;
      return event.start?.dateTime && formatApiDate(new Date(event.start.dateTime)) === tomorrowKey;
    })
    .sort((a, b) => {
      const aStart = new Date(a.start?.dateTime || `${a.start?.date}T00:00:00`);
      const bStart = new Date(b.start?.dateTime || `${b.start?.date}T00:00:00`);
      return aStart - bStart;
    });

  if (!tomorrowEvents.length) {
    document.querySelector("#tomorrowTitle").textContent = `${tomorrowName} is open.`;
    document.querySelector("#tomorrowSummary").textContent =
      "No events are currently on your primary calendar.";
    document.querySelector("#tomorrowFirstLabel").textContent = "CALENDAR";
    document.querySelector("#tomorrowFirstValue").textContent = "NO EVENTS";
    return;
  }

  const first = tomorrowEvents[0];
  const firstTime = first.start?.date
    ? "ALL DAY"
    : new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(
        new Date(first.start.dateTime),
      );
  document.querySelector("#tomorrowTitle").textContent = `${tomorrowName} has shape.`;
  document.querySelector("#tomorrowSummary").textContent =
    `${tomorrowEvents.length} calendar ${tomorrowEvents.length === 1 ? "event" : "events"}. First: ${first.summary || "Untitled event"}.`;
  document.querySelector("#tomorrowFirstLabel").textContent = "FIRST EVENT";
  document.querySelector("#tomorrowFirstValue").textContent = firstTime;
}

function renderCalendar(data) {
  const now = new Date();
  const events = (data.items || [])
    .filter((event) => event.status !== "cancelled")
    .filter((event) => {
      const endValue = event.end?.dateTime || event.end?.date;
      return !endValue || new Date(endValue) >= now;
    })
    .slice(0, 4);

  document.querySelector("#calendarStatus").textContent = `LIVE · ${events.length}`;
  document.querySelector("#calendarStatus").classList.remove("disconnected-status");
  renderTomorrowFromCalendar(data.items || []);

  if (events.length === 0) {
    document.querySelector("#widgetNext").textContent = "Open day";
    document.querySelector("#widgetNextNote").textContent = "No remaining events";
    document.querySelector("#calendarContent").innerHTML =
      '<div class="google-empty">No remaining events on your primary calendar.</div>';
    return;
  }

  document.querySelector("#widgetNext").textContent = formatCalendarTime(events[0]);
  document.querySelector("#widgetNextNote").textContent =
    events[0].summary || "Untitled event";
  document.querySelector("#calendarContent").innerHTML = `
    <div class="timeline">
      ${events
        .map(
          (event) => `
            <a class="timeline-row" href="${escapeHtml(event.htmlLink || "https://calendar.google.com/")}" target="_blank" rel="noreferrer">
              <time>${escapeHtml(formatCalendarTime(event))}</time>
              <div>
                <strong>${escapeHtml(event.summary || "Untitled event")}</strong>
                <small>${escapeHtml(event.location || "Google Calendar")}</small>
              </div>
            </a>
          `,
        )
        .join("")}
    </div>
  `;
}

function getMessageHeader(message, name) {
  return (
    message.payload?.headers?.find(
      (header) => header.name.toLowerCase() === name.toLowerCase(),
    )?.value || ""
  );
}

function getSenderName(from) {
  const named = from.replace(/<[^>]+>/g, "").replaceAll('"', "").trim();
  if (named) return named;
  return from.split("@")[0] || "Sender";
}

function getSenderInitials(sender) {
  return sender
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || "")
    .join("");
}

async function fetchPriorityEmailData() {
  const query =
    "in:inbox is:unread newer_than:7d (is:important OR is:starred) -category:promotions -category:social";
  const list = await fetchGoogleJson(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=6&q=${encodeURIComponent(query)}`,
  );
  const messages = list.messages || [];
  return await Promise.all(
    messages.map((message) =>
      fetchGoogleJson(
        `https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}` +
          "?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date",
      ),
    ),
  );
}

function renderPriorityEmails(messages) {
  lastPriorityEmailMessages = messages;
  const cleared = new Set(state.clearedMailIds);
  const visibleMessages = messages.filter((message) => !cleared.has(message.id));
  document.querySelector("#emailStatus").textContent = `UNREAD · ${visibleMessages.length}`;
  document.querySelector("#emailStatus").classList.remove("disconnected-status");
  document.querySelector("#refreshMail").hidden = false;
  document.querySelector("#widgetMail").textContent =
    visibleMessages.length ? `${visibleMessages.length} unread` : "All clear";
  document.querySelector("#widgetMailNote").textContent =
    visibleMessages.length ? "Priority inbox" : "Nothing needs action";

  if (visibleMessages.length === 0) {
    document.querySelector("#emailContent").innerHTML =
      '<div class="google-empty">No unread priority messages need action.</div>';
    return;
  }

  document.querySelector("#emailContent").innerHTML = `
    ${visibleMessages
      .map((message, index) => {
        const sender = getSenderName(getMessageHeader(message, "From"));
        const subject = getMessageHeader(message, "Subject") || "(No subject)";
        const sentAt = new Date(getMessageHeader(message, "Date"));
        const time = Number.isNaN(sentAt.getTime())
          ? ""
          : new Intl.DateTimeFormat("en-US", {
              month: sentAt.toDateString() === new Date().toDateString() ? undefined : "short",
              day: sentAt.toDateString() === new Date().toDateString() ? undefined : "numeric",
              hour: "numeric",
              minute: "2-digit",
            }).format(sentAt);
        return `
          <div class="mail-item">
            <span class="sender-avatar${index % 2 ? " sender-avatar--blue" : ""}">${escapeHtml(getSenderInitials(sender))}</span>
            <a class="mail-main" href="https://mail.google.com/mail/u/0/#inbox/${escapeHtml(message.threadId)}" target="_blank" rel="noreferrer">
              <span class="mail-copy">
                <span><strong>${escapeHtml(sender)}</strong><time>${escapeHtml(time)}</time></span>
                <b>${escapeHtml(subject)}</b>
                <small>${escapeHtml(message.snippet || "Open in Gmail")}</small>
              </span>
            </a>
            <span class="mail-actions">
              <button type="button" data-mail-read="${escapeHtml(message.id)}">Mark read</button>
              <button type="button" data-mail-clear="${escapeHtml(message.id)}">Clear here</button>
            </span>
          </div>
        `;
      })
      .join("")}
    <div class="mail-summary">Read updates Gmail · Clear only hides it in Daymark</div>
  `;
  bindPriorityMailActions();
}

function bindPriorityMailActions() {
  document.querySelectorAll("[data-mail-read]").forEach((button) => {
    button.addEventListener("click", () => markPriorityEmailRead(button.dataset.mailRead, button));
  });
  document.querySelectorAll("[data-mail-clear]").forEach((button) => {
    button.addEventListener("click", () => clearPriorityEmail(button.dataset.mailClear));
  });
}

function clearPriorityEmail(messageId) {
  if (!state.clearedMailIds.includes(messageId)) {
    state.clearedMailIds.unshift(messageId);
    state.clearedMailIds = state.clearedMailIds.slice(0, 150);
    saveState();
  }
  renderPriorityEmails(lastPriorityEmailMessages);
  showToast("Cleared from Daymark. Gmail was not changed.");
}

async function markPriorityEmailRead(messageId, button) {
  const actions = button.closest(".mail-actions");
  actions?.querySelectorAll("button").forEach((item) => {
    item.disabled = true;
  });
  button.textContent = "Updating…";
  try {
    await modifyGmailMessage(messageId, { removeLabelIds: ["UNREAD"] });
    lastPriorityEmailMessages = lastPriorityEmailMessages.filter(
      (message) => message.id !== messageId,
    );
    renderPriorityEmails(lastPriorityEmailMessages);
    showToast("Marked read in Gmail.");
  } catch {
    button.textContent = "Try again";
    actions?.querySelectorAll("button").forEach((item) => {
      item.disabled = false;
    });
    showToast("Gmail could not update that message.");
  }
}

function renderGooglePanelError(type, message) {
  const isCalendar = type === "calendar";
  const status = document.querySelector(isCalendar ? "#calendarStatus" : "#emailStatus");
  const content = document.querySelector(isCalendar ? "#calendarContent" : "#emailContent");
  status.textContent = "CONNECT AGAIN";
  status.classList.add("disconnected-status");
  if (isCalendar) {
    document.querySelector("#widgetNext").textContent = "Reconnect";
    document.querySelector("#widgetNextNote").textContent = "Calendar needs attention";
  } else {
    document.querySelector("#refreshMail").hidden = true;
    document.querySelector("#widgetMail").textContent = "Reconnect";
    document.querySelector("#widgetMailNote").textContent = "Gmail needs attention";
  }
  content.innerHTML = googleConnectMarkup("Reconnect Google", message);
  bindGoogleConnectButtons();
}

function renderGoogleDisconnected() {
  document.querySelector("#calendarStatus").textContent = "NOT CONNECTED";
  document.querySelector("#calendarStatus").classList.add("disconnected-status");
  document.querySelector("#emailStatus").textContent = "NOT CONNECTED";
  document.querySelector("#emailStatus").classList.add("disconnected-status");
  document.querySelector("#refreshMail").hidden = true;
  document.querySelector("#widgetNext").textContent = "Calendar";
  document.querySelector("#widgetNextNote").textContent = "Not connected";
  document.querySelector("#widgetMail").textContent = "Connect";
  document.querySelector("#widgetMailNote").textContent = "Priority unread";
  document.querySelector("#calendarContent").innerHTML = googleConnectMarkup(
    "Connect Google securely",
    "Allow read-only access to your calendar.",
  );
  document.querySelector("#emailContent").innerHTML = googleConnectMarkup(
    "Connect Google securely",
    "See unread priority mail and mark messages read.",
  );
  bindGoogleConnectButtons();
  formatDate();
  document.querySelector("#tomorrowSummary").textContent =
    "Connect Google and Daymark will build this from your real schedule.";
  document.querySelector("#tomorrowFirstLabel").textContent = "FIRST EVENT";
  document.querySelector("#tomorrowFirstValue").textContent = "NOT CONNECTED";
}

async function refreshLanded() {
  const sheetId = loadDeskSettings().landedSheetId;
  const section = document.querySelector("#landed");
  if (!sheetId || !section) {
    if (section) section.hidden = true;
    return;
  }
  try {
    const data = await fetchGoogleJson(
      `https://sheets.googleapis.com/v4/spreadsheets/${encodeURIComponent(sheetId)}/values/Tracker!A2:L`,
    );
    const rows = (data.values || [])
      .map((row, index) => ({
        id: `r${index}`,
        company: (row[0] || "").trim(),
        role: (row[1] || "").trim(),
        track: (row[6] || "").trim(),
        status: (row[7] || "").trim() || "Interested",
        priority: (row[8] || "").trim(),
        next: (row[10] || "").trim(),
      }))
      .filter((role) => role.company);
    lastLandedRows = rows;
    renderLanded(rows);
  } catch {
    const summary = document.querySelector("#landedSummary");
    if (summary) summary.textContent = "Could not reach the Landed sheet — check access and the sheet ID.";
    section.hidden = false;
  }
}

function landedStageRank(status) {
  const stage = status.toLowerCase();
  if (stage.includes("offer")) return 0;
  if (stage.includes("interview")) return 1;
  if (stage.includes("screen")) return 2;
  if (stage.includes("progress")) return 3;
  if (stage.includes("applied")) return 4;
  return 5;
}

function renderLanded(rows) {
  const section = document.querySelector("#landed");
  const summary = document.querySelector("#landedSummary");
  const list = document.querySelector("#landedList");
  if (!section || !summary || !list) return;
  section.hidden = false;

  const hot = rows
    .filter((role) => landedStageRank(role.status) <= 2 || role.priority.toLowerCase() === "high")
    .sort((a, b) => landedStageRank(a.status) - landedStageRank(b.status))
    .slice(0, 5);
  summary.textContent = `${rows.length} open roles · ${hot.length} worth attention today`;
  list.innerHTML = hot
    .map((role) => {
      const green = landedStageRank(role.status) <= 1;
      return `
        <div class="application-row">
          <div>
            <strong>${escapeHtml(role.company)} — ${escapeHtml(role.role)}</strong>
            <small>${escapeHtml(role.next || role.track || "")}</small>
          </div>
          <span class="landed-chip ${green ? "is-hot" : ""}">${escapeHtml(role.status)}</span>
        </div>
      `;
    })
    .join("");
}

async function loadGoogleData() {
  document.querySelector("#calendarStatus").textContent = "SYNCING";
  document.querySelector("#emailStatus").textContent = "SYNCING";
  const [calendarResult, emailResult] = await Promise.allSettled([
    fetchCalendarData(),
    fetchPriorityEmailData(),
    refreshLanded(),
  ]);

  if (calendarResult.status === "fulfilled") renderCalendar(calendarResult.value);
  else renderGooglePanelError("calendar", "Calendar access needs attention.");

  if (emailResult.status === "fulfilled") renderPriorityEmails(emailResult.value);
  else renderGooglePanelError("email", "Gmail access needs attention.");
  refreshAIDesk();

  lastGoogleRefreshAt = Date.now();
  document.querySelector("#disconnectGoogle").hidden =
    calendarResult.status !== "fulfilled" && emailResult.status !== "fulfilled";
  setGoogleButtonsDisabled(false);
}

async function refreshPriorityMail() {
  if (!(await ensureGoogleAccessToken())) {
    renderGoogleDisconnected();
    return;
  }
  const button = document.querySelector("#refreshMail");
  button.classList.add("is-spinning");
  document.querySelector("#emailStatus").textContent = "SYNCING";
  try {
    renderPriorityEmails(await fetchPriorityEmailData());
    lastGoogleRefreshAt = Date.now();
  } catch {
    renderGooglePanelError("email", "Gmail access needs attention.");
  } finally {
    button.classList.remove("is-spinning");
  }
}

// =====================================================================
// The AI desk (web): provider-agnostic completion + editorial features.
// =====================================================================

const AI_VOICE =
  "You are the desk editor of Daymark, Ty's personal morning-paper app. Write in a " +
  "literate, warm, concise editorial voice — a great local columnist, not an assistant. " +
  "Never invent facts that are not in the briefing data. Keep dates and times exactly as given.";

function aiConfigured() {
  const desk = loadDeskSettings();
  return Boolean(desk.aiKey);
}

async function aiComplete(system, user, maxTokens = 500) {
  const desk = loadDeskSettings();
  if (!desk.aiKey) throw new Error("no-key");
  if ((desk.aiProvider || "openai") === "anthropic") {
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": desk.aiKey,
        "anthropic-version": "2023-06-01",
        "anthropic-dangerous-direct-browser-access": "true",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: maxTokens,
        system,
        messages: [{ role: "user", content: user }],
      }),
    });
    if (!response.ok) throw new Error(`ai-${response.status}`);
    const data = await response.json();
    return (data.content || [])
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join("")
      .trim();
  }
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${desk.aiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      max_tokens: maxTokens,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
  });
  if (!response.ok) throw new Error(`ai-${response.status}`);
  const data = await response.json();
  return (data.choices?.[0]?.message?.content || "").trim();
}

function renderAIDeskCard(mountId, kicker, emptyPrompt, buildPrompt) {
  const mount = document.querySelector(`#${mountId}`);
  if (!mount) return;
  if (!aiConfigured()) {
    mount.hidden = true;
    return;
  }
  mount.hidden = false;
  if (!mount.dataset.built) {
    mount.dataset.built = "true";
    mount.innerHTML = `
      <article class="panel ai-desk-card">
        <div class="ai-desk-head">
          <span>${escapeHtml(kicker.toUpperCase())}</span>
          <button type="button" class="ai-desk-run">WRITE IT</button>
        </div>
        <p class="ai-desk-body">${escapeHtml(emptyPrompt)}</p>
      </article>
    `;
    const button = mount.querySelector(".ai-desk-run");
    const body = mount.querySelector(".ai-desk-body");
    button.addEventListener("click", async () => {
      button.disabled = true;
      button.textContent = "WRITING…";
      try {
        const { system, user } = buildPrompt();
        const text = await aiComplete(system, user);
        body.textContent = text;
        body.classList.add("is-written");
        button.textContent = "REWRITE";
      } catch {
        showToast("The AI desk didn't answer — check the key in Desk settings.");
        button.textContent = "WRITE IT";
      } finally {
        button.disabled = false;
      }
    });
  }
}

function refreshAIDesk() {
  renderAIDeskCard(
    "aiPlanMount",
    "The AI desk · today's plan",
    "Have the desk read your open items and propose today's three priorities plus a first move.",
    () => {
      const captures = state.captures.filter((item) => !item.done).map((item) => item.title).join("\n");
      const apps = state.applications
        .filter((app) => !app.archived && app.status !== "Closed")
        .map((app) => `${app.status}: ${app.organization} — ${app.role} (next: ${app.nextStep || "?"})`)
        .join("\n");
      return {
        system: AI_VOICE,
        user: `Open captures:\n${captures || "(none)"}\n\nJob pipeline:\n${apps || "(none)"}\n\nPropose today's plan: exactly three priorities (one line each, imperative), then one "First move" — the single most specific 9 AM action.`,
      };
    },
  );
  const phase = getDayPhase();
  const triageMount = document.querySelector("#aiTriageMount");
  if (triageMount && (!lastPriorityEmailMessages.length || !aiConfigured())) triageMount.hidden = true;
  if (lastPriorityEmailMessages.length) {
    renderAIDeskCard(
      "aiTriageMount",
      "The AI desk · mail triage",
      "One line per message: why it matters and the next step.",
      () => ({
        system: AI_VOICE,
        user:
          "Priority inbox (sender · subject · snippet):\n" +
          lastPriorityEmailMessages
            .slice(0, 8)
            .map((m) => `${getSenderName(getMessageHeader(m, "From"))} · ${getMessageHeader(m, "Subject")} · ${(m.snippet || "").slice(0, 140)}`)
            .join("\n") +
          "\n\nFor each message, one line: why it matters and the suggested next step. Format each as \"Sender — action.\" Skip anything that needs no action.",
      }),
    );
  }
  const eveningMount = document.querySelector("#aiEveningMount");
  if (eveningMount && (phase === "morning" || phase === "afternoon")) eveningMount.hidden = true;
  if (phase === "evening" || phase === "night") {
    renderAIDeskCard(
      "aiEveningMount",
      "The AI desk · evening column",
      "A short column about how the day actually went.",
      () => {
        const doneTasks = Object.entries(state.tasks).filter(([, v]) => v).length;
        const scores = Object.entries(state.weeklyScores)
          .map(([k, v]) => `${k}: ${v}`)
          .join(", ");
        return {
          system: AI_VOICE,
          user:
            `The day's ledger:\nTasks checked: ${doneTasks}\nScorecard: ${scores}\n` +
            `Open captures: ${state.captures.filter((c) => !c.done && !c.archived).length}\n\n` +
            "Write a 3-4 sentence evening column about how the day actually went — honest, a little wry, ending with one line about tomorrow's first move.",
        };
      },
    );
  }
  renderAIDeskCard(
    "aiCoachMount",
    "The AI desk · job coach",
    "Which roles deserve attention today, and what exactly to do for each.",
    () => {
      const landed = lastLandedRows.length
        ? lastLandedRows
            .map((role) => `${role.status} · ${role.company} · ${role.role} · priority ${role.priority || "—"} · next: ${role.next || "—"}`)
            .join("\n")
        : state.applications
            .filter((app) => !app.archived && app.status !== "Closed")
            .map((app) => `${app.status} · ${app.organization} · ${app.role} · next: ${app.nextStep || "—"}`)
            .join("\n");
      return {
        system: AI_VOICE,
        user: `Ty's job pipeline:\n${landed || "(empty)"}\n\nAs his job-search coach, name the 2-3 roles that most deserve attention today and say exactly what to do for each (one sentence per role). Flag anything going stale. Be direct.`,
      };
    },
  );
}

// =====================================================================
// The Discovery Wire (web): Deezer graph via JSONP (their API has no
// CORS header), seeded by Spotify listening + thumbs feedback.
// =====================================================================

let lastLandedRows = [];
const DISCOVERY_CACHE_KEY = "daymark-discovery-web-v1";
let discoveryAudio = null;
let discoveryPlayingId = null;

function deezer(path) {
  return new Promise((resolve) => {
    const callback = `dz${Math.random().toString(36).slice(2)}`;
    const script = document.createElement("script");
    const cleanup = () => {
      delete window[callback];
      script.remove();
    };
    const timer = window.setTimeout(() => {
      cleanup();
      resolve(null);
    }, 8000);
    window[callback] = (data) => {
      window.clearTimeout(timer);
      cleanup();
      resolve(data);
    };
    script.src = `https://api.deezer.com/${path}${path.includes("?") ? "&" : "?"}output=jsonp&callback=${callback}`;
    script.onerror = () => {
      window.clearTimeout(timer);
      cleanup();
      resolve(null);
    };
    document.head.append(script);
  });
}

function discoveryFeedback() {
  try {
    return JSON.parse(localStorage.getItem("daymark-music-feedback")) || { likes: [], passes: [] };
  } catch {
    return { likes: [], passes: [] };
  }
}

function saveDiscoveryFeedback(feedback) {
  localStorage.setItem("daymark-music-feedback", JSON.stringify(feedback));
}

async function buildDiscoveryWire() {
  const status = document.querySelector("#discoveryStatus");
  const seedsFromSpotify = (lastSpotifyData.top || [])
    .map((item) => item?.artists?.[0]?.name)
    .filter(Boolean);
  const recentArtists = (lastSpotifyData.recent || [])
    .map((item) => item?.track?.artists?.[0]?.name)
    .filter(Boolean);
  const feedback = discoveryFeedback();
  const seeds = [...new Set([...feedback.likes.slice(-4), ...seedsFromSpotify, ...recentArtists])].slice(0, 8);
  if (!seeds.length) return [];

  const exclude = new Set(
    [...seedsFromSpotify, ...recentArtists, ...feedback.passes].map((name) => name.toLowerCase()),
  );
  const surfaced = JSON.parse(localStorage.getItem("daymark-discovery-surfaced") || "[]");
  surfaced.slice(-120).forEach((name) => exclude.add(name));

  if (status) status.textContent = "WALKING THE ARTIST GRAPH…";
  const wire = [];
  const wildcardTarget = 2;

  for (const seed of seeds.sort(() => Math.random() - 0.5)) {
    if (wire.filter((t) => !t.wildcard).length >= 8) break;
    const found = await deezer(`search/artist?q=${encodeURIComponent(seed)}&limit=1`);
    const artist = found?.data?.[0];
    if (!artist) continue;
    const related = await deezer(`artist/${artist.id}/related?limit=12`);
    for (const candidate of (related?.data || []).sort(() => Math.random() - 0.5).slice(0, 3)) {
      if (wire.filter((t) => !t.wildcard).length >= 8) break;
      const key = candidate.name.toLowerCase();
      if (exclude.has(key)) continue;
      const top = await deezer(`artist/${candidate.id}/top?limit=3`);
      const tracks = top?.data || [];
      if (!tracks.length) continue;
      const pick = tracks.length > 1 && Math.random() > 0.5 ? tracks[1] : tracks[0];
      exclude.add(key);
      wire.push({
        id: String(pick.id),
        title: pick.title,
        artist: candidate.name,
        preview: pick.preview || "",
        art: pick.album?.cover_medium || "",
        reason: `Related to ${seed}`,
        wildcard: false,
      });
    }
    // Wildcards: hop once more from the first seed's far relations.
    if (wire.filter((t) => t.wildcard).length < wildcardTarget && related?.data?.length > 5) {
      const bridge = related.data[Math.floor(Math.random() * related.data.length)];
      const hop2 = await deezer(`artist/${bridge.id}/related?limit=10`);
      for (const candidate of (hop2?.data || []).sort(() => Math.random() - 0.5)) {
        if (wire.filter((t) => t.wildcard).length >= wildcardTarget) break;
        const key = candidate.name.toLowerCase();
        if (exclude.has(key)) continue;
        const top = await deezer(`artist/${candidate.id}/top?limit=2`);
        const pick = top?.data?.[0];
        if (!pick) continue;
        exclude.add(key);
        wire.push({
          id: String(pick.id),
          title: pick.title,
          artist: candidate.name,
          preview: pick.preview || "",
          art: pick.album?.cover_medium || "",
          reason: `Wildcard via ${bridge.name}`,
          wildcard: true,
        });
      }
    }
  }

  localStorage.setItem(
    "daymark-discovery-surfaced",
    JSON.stringify([...surfaced, ...wire.map((t) => t.artist.toLowerCase())].slice(-200)),
  );
  return wire.sort(() => Math.random() - 0.5);
}

async function refreshDiscovery(force = false) {
  const section = document.querySelector("#discovery");
  if (!section || !spotifyAccessToken) return;
  const dayKey = new Date().toISOString().slice(0, 10);
  try {
    const cached = JSON.parse(localStorage.getItem(DISCOVERY_CACHE_KEY));
    if (!force && cached?.day === dayKey && cached.wire?.length) {
      renderDiscovery(cached.wire);
      return;
    }
  } catch {
    // rebuild below
  }
  const wire = await buildDiscoveryWire();
  if (wire.length) {
    localStorage.setItem(DISCOVERY_CACHE_KEY, JSON.stringify({ day: dayKey, wire }));
    renderDiscovery(wire);
  }
}

function renderDiscovery(wire) {
  const section = document.querySelector("#discovery");
  const list = document.querySelector("#discoveryList");
  const status = document.querySelector("#discoveryStatus");
  if (!section || !list) return;
  section.hidden = false;
  if (status) status.textContent = "TEN FOR TODAY · THUMBS TEACH TOMORROW";
  const feedback = discoveryFeedback();

  list.innerHTML = wire
    .map((track) => {
      const liked = feedback.likes.includes(track.artist.toLowerCase());
      const query = encodeURIComponent(`${track.artist} ${track.title}`);
      return `
        <div class="discovery-row" data-track-id="${escapeHtml(track.id)}">
          <button class="discovery-art" type="button" data-preview="${escapeHtml(track.preview)}" aria-label="Preview">
            ${track.art ? `<img src="${escapeHtml(track.art)}" alt="" width="46" height="46" />` : ""}
            <span class="discovery-playmark" aria-hidden="true">▶</span>
          </button>
          <div class="discovery-copy">
            <strong>${escapeHtml(track.title)}</strong>
            <small>${escapeHtml(track.artist)}</small>
            <em class="${track.wildcard ? "is-wildcard" : ""}">${escapeHtml(track.reason.toUpperCase())}</em>
          </div>
          <div class="discovery-actions">
            <button type="button" class="discovery-like${liked ? " is-on" : ""}" data-artist="${escapeHtml(track.artist)}" aria-label="More like this">👍</button>
            <button type="button" class="discovery-pass" data-artist="${escapeHtml(track.artist)}" aria-label="Less like this">👎</button>
            <a href="spotify:search:${query}" aria-label="Open in Spotify">SP</a>
            <a href="https://soundcloud.com/search?q=${query}" target="_blank" rel="noreferrer" aria-label="Find on SoundCloud">SC</a>
          </div>
        </div>
      `;
    })
    .join("");

  list.querySelectorAll(".discovery-art").forEach((button) => {
    button.addEventListener("click", () => {
      const url = button.dataset.preview;
      const row = button.closest(".discovery-row");
      const trackId = row?.dataset.trackId;
      if (!url) return;
      if (discoveryPlayingId === trackId) {
        discoveryAudio?.pause();
        discoveryPlayingId = null;
        row.classList.remove("is-previewing");
        return;
      }
      discoveryAudio?.pause();
      list.querySelectorAll(".is-previewing").forEach((el) => el.classList.remove("is-previewing"));
      discoveryAudio = new Audio(url);
      discoveryAudio.play();
      discoveryPlayingId = trackId;
      row.classList.add("is-previewing");
      discoveryAudio.addEventListener("ended", () => {
        discoveryPlayingId = null;
        row.classList.remove("is-previewing");
      });
    });
  });
  list.querySelectorAll(".discovery-like").forEach((button) => {
    button.addEventListener("click", () => {
      const feedbackNow = discoveryFeedback();
      const key = button.dataset.artist.toLowerCase();
      if (!feedbackNow.likes.includes(key)) feedbackNow.likes.push(key);
      feedbackNow.passes = feedbackNow.passes.filter((name) => name !== key);
      saveDiscoveryFeedback(feedbackNow);
      button.classList.add("is-on");
      showToast(`Noted — more like ${button.dataset.artist}.`);
    });
  });
  list.querySelectorAll(".discovery-pass").forEach((button) => {
    button.addEventListener("click", () => {
      const feedbackNow = discoveryFeedback();
      const key = button.dataset.artist.toLowerCase();
      if (!feedbackNow.passes.includes(key)) feedbackNow.passes.push(key);
      feedbackNow.likes = feedbackNow.likes.filter((name) => name !== key);
      saveDiscoveryFeedback(feedbackNow);
      button.closest(".discovery-row")?.remove();
    });
  });
}

// =====================================================================
// SoundCloud shelf (web): official widget iframes for likes + artists.
// =====================================================================

function renderSoundCloudShelf() {
  const desk = loadDeskSettings();
  const section = document.querySelector("#soundcloudShelf");
  const host = document.querySelector("#soundcloudWidgets");
  if (!section || !host) return;
  const artists = (desk.soundcloudArtists || "")
    .split(",")
    .map((slug) => slug.trim().toLowerCase())
    .filter(Boolean);
  const resources = [];
  if (desk.soundcloudUser) {
    resources.push({ label: "YOUR LIKES", url: `https://soundcloud.com/${desk.soundcloudUser}/likes` });
  }
  artists.forEach((slug) => resources.push({ label: slug.toUpperCase(), url: `https://soundcloud.com/${slug}` }));
  if (!resources.length) {
    section.hidden = true;
    return;
  }
  section.hidden = false;
  host.innerHTML = resources
    .map(
      (resource) => `
        <p class="sc-label">${escapeHtml(resource.label)}</p>
        <iframe
          class="sc-widget"
          title="SoundCloud: ${escapeHtml(resource.label)}"
          width="100%" height="166" frameborder="no" scrolling="no" allow="autoplay"
          src="https://w.soundcloud.com/player/?url=${encodeURIComponent(resource.url)}&color=%23c8102e&auto_play=false&hide_related=true&show_comments=false&show_reposts=false&visual=false"
        ></iframe>
      `,
    )
    .join("");
}

// =====================================================================
// Desk settings card
// =====================================================================

async function startFocusSoundtrack() {
  const raw = (loadDeskSettings().focusPlaylist || "").trim();
  if (!raw || !spotifyAccessToken) return;
  let uri = raw;
  try {
    const url = new URL(raw);
    if (url.hostname.includes("spotify.com")) {
      const parts = url.pathname.split("/").filter(Boolean);
      if (parts.length >= 2) uri = `spotify:${parts[parts.length - 2]}:${parts[parts.length - 1]}`;
    }
  } catch {
    // already a spotify: URI or plain id — leave as-is
  }
  try {
    await fetchSpotify("/v1/me/player/play", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ context_uri: uri }),
    });
  } catch {
    // No active device — the timer still runs.
  }
}

function exportDaymarkData() {
  const payload = {
    exportedAt: new Date().toISOString(),
    state,
    deskSettings: { ...loadDeskSettings(), aiKey: undefined },
    musicFeedback: discoveryFeedback(),
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `daymark-backup-${formatApiDate(new Date())}.json`;
  link.click();
  URL.revokeObjectURL(link.href);
}

function importDaymarkData(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const payload = JSON.parse(reader.result);
      if (!payload?.state?.schemaVersion) throw new Error("bad");
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload.state));
      if (payload.deskSettings) saveDeskSettings(payload.deskSettings);
      if (payload.musicFeedback) saveDiscoveryFeedback(payload.musicFeedback);
      showToast("Backup restored — reloading.");
      window.setTimeout(() => window.location.reload(), 700);
    } catch {
      showToast("That file didn't read as a Daymark backup.");
    }
  };
  reader.readAsText(file);
}

function initializeDeskSettings() {
  const desk = loadDeskSettings();
  const sheet = document.querySelector("#deskLandedSheet");
  const provider = document.querySelector("#deskAIProvider");
  const key = document.querySelector("#deskAIKey");
  const scUser = document.querySelector("#deskSCUser");
  const scArtists = document.querySelector("#deskSCArtists");
  const save = document.querySelector("#deskSettingsSave");
  if (!save) return;
  if (sheet) sheet.value = desk.landedSheetId || "";
  if (provider) provider.value = desk.aiProvider || "openai";
  if (key) key.value = desk.aiKey ? "••••••••••••" : "";
  if (scUser) scUser.value = desk.soundcloudUser || "";
  if (scArtists) scArtists.value = desk.soundcloudArtists || "";
  const focusPlaylist = document.querySelector("#deskFocusPlaylist");
  if (focusPlaylist) focusPlaylist.value = desk.focusPlaylist || "";
  document.querySelector("#deskExport")?.addEventListener("click", exportDaymarkData);
  document.querySelector("#deskImportFile")?.addEventListener("change", (event) => {
    const file = event.target.files?.[0];
    if (file) importDaymarkData(file);
    event.target.value = "";
  });

  save.addEventListener("click", () => {
    const partial = {
      landedSheetId: sheet?.value.trim() || "",
      aiProvider: provider?.value || "openai",
      soundcloudUser: scUser?.value.trim().toLowerCase() || "",
      soundcloudArtists: scArtists?.value.trim() || "",
      focusPlaylist: document.querySelector("#deskFocusPlaylist")?.value.trim() || "",
    };
    const keyValue = key?.value.trim() || "";
    if (keyValue && !keyValue.startsWith("•")) partial.aiKey = keyValue;
    if (!keyValue) partial.aiKey = "";
    saveDeskSettings(partial);
    if (key) key.value = loadDeskSettings().aiKey ? "••••••••••••" : "";
    showToast("Desk settings saved to this browser.");
    refreshAIDesk();
    renderSoundCloudShelf();
    refreshLanded();
    refreshDiscovery(true);
  });
}

// =====================================================================
// The Sky Desk (web): deep weather + tonight's sky + the astrology desk.
// =====================================================================

let lastWeatherPayload = null;
let lastAirQuality = null;

async function fetchAirQuality() {
  try {
    const data = await fetchJson(
      "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=35.9940&longitude=-78.8986" +
        "&current=us_aqi,pm2_5,grass_pollen,ragweed_pollen,birch_pollen,oak_pollen&timezone=America%2FNew_York",
    );
    const c = data.current || {};
    const pollens = [
      ["Grass", c.grass_pollen],
      ["Ragweed", c.ragweed_pollen],
      ["Birch", c.birch_pollen],
      ["Oak", c.oak_pollen],
    ].filter(([, value]) => typeof value === "number");
    pollens.sort((a, b) => b[1] - a[1]);
    lastAirQuality = {
      aqi: typeof c.us_aqi === "number" ? Math.round(c.us_aqi) : null,
      pm25: typeof c.pm2_5 === "number" ? Math.round(c.pm2_5) : null,
      pollenName: pollens[0] && pollens[0][1] > 0.5 ? pollens[0][0] : null,
      pollenLevel: pollens[0] ? pollens[0][1] : 0,
    };
  } catch {
    lastAirQuality = null;
  }
}

function rainWindowSentence(payload) {
  const times = payload?.hourly?.time || [];
  const probs = payload?.hourly?.precipitation_probability || [];
  const amounts = payload?.hourly?.precipitation || [];
  const now = Date.now();
  const upcoming = [];
  for (let i = 0; i < times.length && upcoming.length < 12; i += 1) {
    const t = new Date(times[i]).getTime();
    if (t >= now) upcoming.push({ t, rainy: (probs[i] || 0) >= 40 || (amounts[i] || 0) >= 0.5 });
  }
  if (!upcoming.length) return "";
  const hourText = (ms) =>
    new Date(ms).toLocaleTimeString("en-US", { hour: "numeric" }).toLowerCase().replace(" ", "");
  const first = upcoming.findIndex((h) => h.rainy);
  if (first === -1) return "Dry for the next 12 hours.";
  if (first === 0) {
    const clears = upcoming.findIndex((h, i) => i > 0 && !h.rainy);
    return clears === -1
      ? "Rain continuing through the next 12 hours."
      : `Rain now — clearing by ${hourText(upcoming[clears].t)}.`;
  }
  const ends = upcoming.findIndex((h, i) => i > first && !h.rainy);
  return ends === -1
    ? `Rain starts ~${hourText(upcoming[first].t)}.`
    : `Dry until ~${hourText(upcoming[first].t)} — clears by ${hourText(upcoming[ends].t)}.`;
}

function openSkyDesk() {
  const overlay = document.querySelector("#skyOverlay");
  const body = document.querySelector("#skyBody");
  if (!overlay || !body) return;
  overlay.hidden = false;
  document.body.style.overflow = "hidden";
  renderSkyDesk(body);
}

function closeSkyDesk() {
  const overlay = document.querySelector("#skyOverlay");
  if (overlay) overlay.hidden = true;
  document.body.style.overflow = "";
}

function renderSkyDesk(body) {
  const payload = lastWeatherPayload;
  const astro = window.DaymarkAstro
    ? window.DaymarkAstro.snapshot(35.994, -78.8986)
    : null;
  const timeText = (date) =>
    date ? date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }) : "—";

  let html = "";

  if (payload) {
    const current = payload.current || {};
    const daily = payload.daily || {};
    html += `
      <div class="sky-stats">
        <div><small>NOW</small><strong>${Math.round(current.temperature_2m ?? 0)}°</strong></div>
        <div><small>WIND</small><strong>${Math.round(current.wind_speed_10m ?? 0)} mph</strong></div>
        <div><small>HUMIDITY</small><strong>${current.relative_humidity_2m ?? "—"}%</strong></div>
        <div><small>UV MAX</small><strong>${daily.uv_index_max?.[0] != null ? Math.round(daily.uv_index_max[0]) : "—"}</strong></div>
      </div>
      <p class="sky-rainline">${escapeHtml(rainWindowSentence(payload))}</p>
    `;

    // 7-day outlook
    const week = [];
    for (let i = 1; i < Math.min(8, (daily.time || []).length); i += 1) {
      week.push(`
        <div class="sky-day">
          <span>${new Date(`${daily.time[i]}T12:00`).toLocaleDateString("en-US", { weekday: "short" })}</span>
          <i class="wx">${weatherIcon(daily.weather_code?.[i] ?? 0)}</i>
          <em>${(daily.precipitation_probability_max?.[i] ?? 0) > 20 ? `${daily.precipitation_probability_max[i]}%` : ""}</em>
          <b>${Math.round(daily.temperature_2m_min?.[i] ?? 0)}°–${Math.round(daily.temperature_2m_max?.[i] ?? 0)}°</b>
        </div>
      `);
    }
    html += `<h3 class="sky-section">THE WEEK AHEAD</h3><div class="sky-week">${week.join("")}</div>`;
  }

  html += `
    <h3 class="sky-section">RADAR</h3>
    <iframe class="sky-radar" title="Durham radar (RainViewer)" src="https://www.rainviewer.com/map.html?loc=35.994,-78.8986,8&oCS=1&c=3&o=83&lm=1&layer=radar&sm=1&sn=1" loading="lazy" allow="fullscreen"></iframe>
  `;

  if (lastAirQuality) {
    html += `
      <h3 class="sky-section">THE AIR</h3>
      <div class="sky-stats">
        <div><small>AQI</small><strong>${lastAirQuality.aqi ?? "—"}</strong></div>
        <div><small>PM2.5</small><strong>${lastAirQuality.pm25 ?? "—"}</strong></div>
        <div><small>POLLEN</small><strong>${escapeHtml(lastAirQuality.pollenName || "Low")}</strong></div>
      </div>
    `;
  }

  if (astro) {
    html += `
      <h3 class="sky-section">SUN &amp; MOON</h3>
      <div class="sky-moon">
        <strong>${escapeHtml(astro.moon.phase)}</strong>
        <span>${Math.round(astro.moon.illumination * 100)}% lit · day ${Math.round(astro.moon.ageDays)} · Moon in ${escapeHtml(astro.moon.sign)}</span>
      </div>
      <div class="sky-almanac">
        <div><span>Sunrise</span><b>${timeText(astro.sun.sunrise)}</b></div>
        <div><span>Sunset</span><b>${timeText(astro.sun.sunset)}</b></div>
        <div><span>Moonrise</span><b>${timeText(astro.moon.moonrise)}</b></div>
        <div><span>Moonset</span><b>${timeText(astro.moon.moonset)}</b></div>
      </div>
      <h3 class="sky-section">TONIGHT'S SKY</h3>
      <div class="sky-planets">
        ${astro.planets
          .map(
            (planet) => `
          <div class="${planet.visible ? "is-up" : ""}">
            <i></i><span>${escapeHtml(planet.name)}</span>
            <b>${planet.visible ? (planet.rise && planet.rise > new Date() ? `Rises ${timeText(planet.rise)}` : "Up tonight") : "Not visible"}</b>
          </div>
        `,
          )
          .join("")}
      </div>
      <h3 class="sky-section">THE ASTROLOGY DESK</h3>
      <div class="sky-astrology">
        <div class="sky-astrology-head">
          <span>TAURUS · APRIL 21</span>
          ${astro.mercuryRetrograde ? '<em class="sky-rx">MERCURY RX</em>' : ""}
        </div>
        <p>Sun in ${escapeHtml(astro.sunSign)} · Moon in ${escapeHtml(astro.moon.sign)}${astro.mercuryRetrograde ? " · Mercury retrograde" : ""}</p>
        <p class="sky-horoscope" id="skyHoroscope">${
          aiConfigured()
            ? "The desk can write today's horoscope from these transits."
            : "Add an AI key in Desk settings and the desk writes today's horoscope from these transits."
        }</p>
        ${aiConfigured() ? '<button class="ai-desk-run" id="skyHoroscopeRun" type="button">WRITE TODAY\'S HOROSCOPE</button>' : ""}
      </div>
    `;
  }

  body.innerHTML = html;

  const run = body.querySelector("#skyHoroscopeRun");
  if (run && astro) {
    run.addEventListener("click", async () => {
      run.disabled = true;
      run.textContent = "WRITING…";
      try {
        const transits =
          `Sun in ${astro.sunSign}. Moon in ${astro.moon.sign}, ${astro.moon.phase} ` +
          `(${Math.round(astro.moon.illumination * 100)}% lit, day ${Math.round(astro.moon.ageDays)}). ` +
          `Mercury retrograde: ${astro.mercuryRetrograde ? "yes" : "no"}. ` +
          `Planets visible tonight: ${astro.planets.filter((p) => p.visible).map((p) => p.name).join(", ") || "none"}.`;
        const text = await aiComplete(
          AI_VOICE,
          `Ty is a Taurus (born April 21, 1986). Today's real computed sky:\n\n${transits}\n\n` +
            "Write today's horoscope for him: 3-4 sentences, editorial and a little playful, " +
            "grounded in these actual transits. No generic filler.",
          300,
        );
        const target = body.querySelector("#skyHoroscope");
        if (target) {
          target.textContent = text;
          target.classList.add("is-written");
        }
        run.textContent = "REWRITE";
      } catch {
        showToast("The AI desk didn't answer — check the key in Desk settings.");
        run.textContent = "WRITE TODAY'S HOROSCOPE";
      } finally {
        run.disabled = false;
      }
    });
  }
}

function hasSpotifyClientId() {
  const clientId = window.DAYMARK_CONFIG?.spotifyClientId?.trim() || "";
  return Boolean(clientId && !clientId.startsWith("PASTE_") && /^[a-z0-9]+$/i.test(clientId));
}

function getSpotifyRedirectUri() {
  return new URL("./", window.location.href).href;
}

function generateSpotifyRandomString(length = 64) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  const values = crypto.getRandomValues(new Uint8Array(length));
  return [...values].map((value) => alphabet[value % alphabet.length]).join("");
}

function base64UrlEncode(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replaceAll("=", "")
    .replaceAll("+", "-")
    .replaceAll("/", "_");
}

async function getSpotifyCodeChallenge(verifier) {
  const encoded = new TextEncoder().encode(verifier);
  return base64UrlEncode(await crypto.subtle.digest("SHA-256", encoded));
}

function persistSpotifySession() {
  try {
    localStorage.setItem(
      SPOTIFY_SESSION_KEY,
      JSON.stringify({
        accessToken: spotifyAccessToken,
        refreshToken: spotifyRefreshToken,
        expiresAt: spotifyTokenExpiresAt,
        scope: spotifyGrantedScopes,
      }),
    );
  } catch {
    // Spotify remains connected until this page closes if persistent storage is unavailable.
  }
}

function clearSpotifySession() {
  spotifyAccessToken = "";
  spotifyRefreshToken = "";
  spotifyTokenExpiresAt = 0;
  spotifyGrantedScopes = "";
  spotifyIsPlaying = false;
  lastSpotifyRefreshAt = 0;
  lastSpotifyLibraryRefreshAt = 0;
  lastSpotifyData = {
    playback: null,
    devices: [],
    queue: [],
    recent: [],
    top: [],
    topMedium: [],
    topLong: [],
    topArtists: [],
    profile: null,
  };
  try {
    localStorage.removeItem(SPOTIFY_SESSION_KEY);
    sessionStorage.removeItem(SPOTIFY_PKCE_KEY);
  } catch {
    // Nothing else to clear.
  }
}

function restoreSpotifySession() {
  try {
    const saved = JSON.parse(localStorage.getItem(SPOTIFY_SESSION_KEY));
    if (saved?.accessToken && (Number(saved.expiresAt) > Date.now() + 30000 || saved.refreshToken)) {
      spotifyAccessToken = saved.accessToken;
      spotifyRefreshToken = saved.refreshToken || "";
      spotifyTokenExpiresAt = Number(saved.expiresAt) || 0;
      spotifyGrantedScopes = saved.scope || "";
      return true;
    }
  } catch {
    // Invalid or unavailable local storage means reconnecting manually.
  }
  clearSpotifySession();
  return false;
}

function cleanupSpotifyCallbackUrl() {
  const cleanUrl = new URL(window.location.href);
  ["code", "state", "error"].forEach((key) => cleanUrl.searchParams.delete(key));
  window.history.replaceState({}, document.title, `${cleanUrl.pathname}${cleanUrl.search}${cleanUrl.hash}`);
}

async function requestSpotifyConnection() {
  if (!hasSpotifyClientId()) {
    showToast("Spotify setup is required first.");
    window.open(
      new URL("./SPOTIFY_SETUP.md", window.location.href).href,
      "_blank",
      "noopener,noreferrer",
    );
    return;
  }

  const button = document.querySelector("#connectSpotify");
  if (button) {
    button.disabled = true;
    button.textContent = "Opening Spotify…";
  }

  const verifier = generateSpotifyRandomString(64);
  const oauthState = generateSpotifyRandomString(32);
  const challenge = await getSpotifyCodeChallenge(verifier);
  sessionStorage.setItem(
    SPOTIFY_PKCE_KEY,
    JSON.stringify({ verifier, oauthState, createdAt: Date.now() }),
  );
  const params = new URLSearchParams({
    client_id: window.DAYMARK_CONFIG.spotifyClientId.trim(),
    response_type: "code",
    redirect_uri: getSpotifyRedirectUri(),
    scope: SPOTIFY_SCOPES,
    code_challenge_method: "S256",
    code_challenge: challenge,
    state: oauthState,
  });
  window.location.assign(`https://accounts.spotify.com/authorize?${params}`);
}

async function requestSpotifyToken(parameters) {
  const response = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    cache: "no-store",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(parameters),
  });
  if (!response.ok) throw new Error(`Spotify authorization failed: ${response.status}`);
  return await response.json();
}

function setSpotifyTokens(data) {
  spotifyAccessToken = data.access_token || spotifyAccessToken;
  spotifyRefreshToken = data.refresh_token || spotifyRefreshToken;
  spotifyGrantedScopes = data.scope || spotifyGrantedScopes;
  spotifyTokenExpiresAt = Date.now() + Number(data.expires_in || 3600) * 1000;
  persistSpotifySession();
}

async function handleSpotifyCallback() {
  const params = new URLSearchParams(window.location.search);
  const code = params.get("code");
  const error = params.get("error");
  if (!code && !error) return false;

  if (error) {
    cleanupSpotifyCallbackUrl();
    showToast("Spotify connection was not completed.");
    return false;
  }

  try {
    const saved = JSON.parse(sessionStorage.getItem(SPOTIFY_PKCE_KEY));
    if (
      !saved?.verifier ||
      !saved.oauthState ||
      saved.oauthState !== params.get("state") ||
      Date.now() - Number(saved.createdAt) > 10 * 60 * 1000
    ) {
      throw new Error("Spotify authorization state did not match.");
    }
    const tokenData = await requestSpotifyToken({
      client_id: window.DAYMARK_CONFIG.spotifyClientId.trim(),
      grant_type: "authorization_code",
      code,
      redirect_uri: getSpotifyRedirectUri(),
      code_verifier: saved.verifier,
    });
    setSpotifyTokens(tokenData);
    sessionStorage.removeItem(SPOTIFY_PKCE_KEY);
    cleanupSpotifyCallbackUrl();
    showToast("Spotify connected.");
    return true;
  } catch {
    clearSpotifySession();
    cleanupSpotifyCallbackUrl();
    showToast("Spotify could not finish connecting.");
    return false;
  }
}

async function refreshSpotifyAccessToken() {
  if (!spotifyRefreshToken || !hasSpotifyClientId()) {
    clearSpotifySession();
    throw new Error("Spotify session has expired.");
  }
  const data = await requestSpotifyToken({
    client_id: window.DAYMARK_CONFIG.spotifyClientId.trim(),
    grant_type: "refresh_token",
    refresh_token: spotifyRefreshToken,
  });
  setSpotifyTokens(data);
}

async function fetchSpotify(path, options = {}, retry = true) {
  if (!spotifyAccessToken) throw new Error("Spotify is not connected.");
  if (Date.now() >= spotifyTokenExpiresAt - 30000) {
    await refreshSpotifyAccessToken();
  }
  const response = await fetch(`https://api.spotify.com${path}`, {
    ...options,
    cache: "no-store",
    headers: {
      Authorization: `Bearer ${spotifyAccessToken}`,
      ...(options.headers || {}),
    },
  });
  if (response.status === 401 && retry && spotifyRefreshToken) {
    await refreshSpotifyAccessToken();
    return await fetchSpotify(path, options, false);
  }
  const responseText = response.status === 204 ? "" : await response.text();
  if (!response.ok) {
    let detail = "";
    try {
      const payload = responseText ? JSON.parse(responseText) : null;
      detail = payload?.error?.message || payload?.error_description || payload?.error || "";
    } catch {
      detail = "";
    }
    const requestError = new Error(`Spotify request failed: ${response.status}`);
    requestError.status = response.status;
    requestError.spotifyMessage = String(detail || "");
    throw requestError;
  }
  if (!responseText.trim()) return null;
  try {
    return JSON.parse(responseText);
  } catch {
    const parseError = new Error("Spotify returned an unreadable success response.");
    parseError.code = "SPOTIFY_RESPONSE_PARSE";
    throw parseError;
  }
}

function getSpotifyArtwork(item) {
  return item?.album?.images?.[0]?.url || item?.images?.[0]?.url || "";
}

function getSpotifyByline(item) {
  if (item?.artists?.length) return item.artists.map((artist) => artist.name).join(", ");
  return item?.show?.name || item?.type || "Spotify";
}

function getSpotifyUrl(item) {
  return item?.uri || item?.external_urls?.spotify || "https://open.spotify.com/";
}

function formatSpotifyTime(milliseconds) {
  const seconds = Math.max(0, Math.floor(Number(milliseconds || 0) / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

function formatSpotifyPlayedAt(value) {
  const playedAt = new Date(value);
  if (Number.isNaN(playedAt.getTime())) return "Recently";
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  const dayKey = formatApiDate(playedAt);
  const prefix =
    dayKey === formatApiDate(now)
      ? "Today"
      : dayKey === formatApiDate(yesterday)
        ? "Yesterday"
        : new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(playedAt);
  const time = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(playedAt);
  return `${prefix} · ${time}`;
}

function spotifyTrackRow(item, detail = getSpotifyByline(item)) {
  const artwork = getSpotifyArtwork(item);
  return `
    <a class="spotify-list-row" href="${escapeHtml(getSpotifyUrl(item))}" target="_blank" rel="noreferrer">
      ${artwork ? `<img src="${escapeHtml(artwork)}" alt="" loading="lazy" width="38" height="38" />` : '<span class="spotify-list-placeholder"></span>'}
      <span><strong>${escapeHtml(item?.name || "Untitled")}</strong><small>${escapeHtml(detail)}</small></span>
    </a>
  `;
}

function getSpotifyListeningStats() {
  const tracks = lastSpotifyData.recent.map((entry) => entry.track).filter(Boolean);
  const uniqueTrackIds = new Set(tracks.map((track) => track.id || track.uri));
  const artistCounts = new Map();
  tracks.forEach((track) => {
    (track.artists || []).forEach((artist) => {
      artistCounts.set(artist.name, (artistCounts.get(artist.name) || 0) + 1);
    });
  });
  const topArtist =
    [...artistCounts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || "Not enough data";
  const totalMinutes = Math.round(
    tracks.reduce((sum, track) => sum + Number(track.duration_ms || 0), 0) / 60000,
  );
  const repeatRate = tracks.length
    ? Math.round(((tracks.length - uniqueTrackIds.size) / tracks.length) * 100)
    : 0;
  return {
    plays: tracks.length,
    minutes: totalMinutes,
    artists: artistCounts.size,
    repeatRate,
    topArtist,
  };
}

function getSpotifyRediscoveryTracks() {
  const recentIds = new Set(
    lastSpotifyData.recent.map((entry) => entry.track?.id).filter(Boolean),
  );
  const shortIds = new Set(lastSpotifyData.top.map((track) => track.id).filter(Boolean));
  const candidates = [...lastSpotifyData.topLong, ...lastSpotifyData.topMedium];
  const unique = new Map();
  candidates.forEach((track) => {
    if (!track?.id || recentIds.has(track.id) || shortIds.has(track.id)) return;
    if (!unique.has(track.id)) unique.set(track.id, track);
  });
  if (!unique.size) {
    lastSpotifyData.topLong.forEach((track) => {
      if (track?.id && !unique.has(track.id)) unique.set(track.id, track);
    });
  }
  return [...unique.values()].slice(0, 8);
}

function renderSpotifyStats() {
  const stats = getSpotifyListeningStats();
  const periods = [
    ["4 WEEKS", lastSpotifyData.top[0]],
    ["6 MONTHS", lastSpotifyData.topMedium[0]],
    ["AROUND A YEAR", lastSpotifyData.topLong[0]],
  ];
  return `
    <div class="spotify-stat-grid">
      <span><strong>${stats.plays}</strong><small>recent plays</small></span>
      <span><strong>${stats.minutes}</strong><small>minutes sampled</small></span>
      <span><strong>${stats.artists}</strong><small>unique artists</small></span>
      <span><strong>${stats.repeatRate}%</strong><small>repeat rate</small></span>
    </div>
    <div class="spotify-stat-highlight"><small>MOST HEARD RECENTLY</small><strong>${escapeHtml(stats.topArtist)}</strong></div>
    <div class="spotify-period-list">
      ${periods
        .map(
          ([label, track]) => `
            <a href="${escapeHtml(getSpotifyUrl(track))}" target="_blank" rel="noreferrer">
              <small>${label}</small>
              <strong>${escapeHtml(track?.name || "No data yet")}</strong>
              <span>${escapeHtml(track ? getSpotifyByline(track) : "Keep listening")}</span>
            </a>
          `,
        )
        .join("")}
    </div>
    <div class="spotify-artist-cloud">
      <small>TOP ARTISTS · LAST 4 WEEKS</small>
      <div>
        ${lastSpotifyData.topArtists
          .slice(0, 8)
          .map(
            (artist) =>
              `<a href="${escapeHtml(getSpotifyUrl(artist))}" target="_blank" rel="noreferrer">${escapeHtml(artist.name || "Artist")}</a>`,
          )
          .join("")}
      </div>
    </div>
  `;
}

function renderSpotifyLibrary() {
  const list = document.querySelector("#spotifyLibraryList");
  if (!list) return;
  const recent = lastSpotifyData.recent;

  if (spotifyLibraryView === "history") {
    list.innerHTML = recent.length
      ? `
        <div class="spotify-view-note">Your latest ${recent.length} completed plays, newest first.</div>
        ${recent
          .map((entry) =>
            spotifyTrackRow(
              entry.track,
              `${getSpotifyByline(entry.track)} · ${formatSpotifyPlayedAt(entry.played_at)}`,
            ),
          )
          .join("")}
      `
      : '<div class="spotify-list-empty">No listening history is available yet.</div>';
  } else if (spotifyLibraryView === "stats") {
    list.innerHTML = renderSpotifyStats();
  } else if (spotifyLibraryView === "rediscover") {
    const rediscovery = getSpotifyRediscoveryTracks();
    list.innerHTML = rediscovery.length
      ? `
        <div class="spotify-view-note">Older favorites missing from your recent rotation—Daymark’s honest alternative to a recommendation feed.</div>
        ${rediscovery.map((track) => spotifyTrackRow(track)).join("")}
        <a class="spotify-home-link" href="https://open.spotify.com/" target="_blank" rel="noreferrer">Open Spotify’s personalized Home</a>
      `
      : '<div class="spotify-list-empty">Keep listening and Daymark will find something worth rediscovering.</div>';
  } else {
    const tracks = recent.slice(0, 8);
    list.innerHTML = tracks.length
      ? tracks
          .map((entry) =>
            spotifyTrackRow(
              entry.track,
              `${getSpotifyByline(entry.track)} · ${formatSpotifyPlayedAt(entry.played_at)}`,
            ),
          )
          .join("")
      : '<div class="spotify-list-empty">No listening history is available yet.</div>';
  }

  document.querySelectorAll("[data-spotify-view]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.spotifyView === spotifyLibraryView);
  });
}

function bindSpotifyPanelActions() {
  document.querySelector("#spotifyPrevious")?.addEventListener("click", () => controlSpotify("previous"));
  document.querySelector("#spotifyPlay")?.addEventListener("click", () => controlSpotify("toggle"));
  document.querySelector("#spotifyNext")?.addEventListener("click", () => controlSpotify("next"));
  document.querySelector("#spotifyRefreshDevices")?.addEventListener("click", () => refreshSpotify(true));
  document.querySelectorAll("[data-spotify-device]").forEach((button) => {
    button.addEventListener("click", () => transferSpotifyPlayback(button.dataset.spotifyDevice));
  });
  document.querySelectorAll("[data-spotify-view]").forEach((button) => {
    button.addEventListener("click", () => {
      spotifyLibraryView = button.dataset.spotifyView;
      renderSpotifyLibrary();
    });
  });
}

function getActiveSpotifyDevice() {
  return (
    lastSpotifyData.playback?.device ||
    lastSpotifyData.devices.find((device) => device.is_active) ||
    null
  );
}

function spotifyControlIcon(type) {
  const paths = {
    previous:
      '<path d="M7 6v12M18 7.5 10 12l8 4.5Z" />',
    next:
      '<path d="M17 6v12M6 7.5l8 4.5-8 4.5Z" />',
    play:
      '<path d="m9 7 8 5-8 5Z" />',
    pause:
      '<path d="M9 7v10M15 7v10" />',
  };
  return `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[type] || ""}</svg>`;
}

function spotifyActionIsDisallowed(action, playback = lastSpotifyData.playback) {
  const actions = playback?.actions || {};
  if (action === "previous") return Boolean(actions.skipping_prev);
  if (action === "next") return Boolean(actions.skipping_next);
  if (action === "toggle") {
    return Boolean(playback?.is_playing ? actions.pausing : actions.resuming);
  }
  return false;
}

function renderSpotifyDevicePicker(data) {
  const devices = [...(data.devices || [])];
  const playbackDevice = data.playback?.device;
  if (playbackDevice?.id && !devices.some((device) => device.id === playbackDevice.id)) {
    devices.unshift(playbackDevice);
  }
  const availableDevices = devices.filter((device) => device.id);
  const deviceButtons = availableDevices.length
    ? availableDevices
        .map((device) => {
          const active = Boolean(device.is_active || device.id === playbackDevice?.id);
          const qualifier = device.is_restricted ? " · unavailable" : active ? " · active" : "";
          return `
            <button
              class="${active ? "is-active" : ""}${device.is_restricted ? " is-restricted" : ""}"
              type="button"
              data-spotify-device="${escapeHtml(device.id)}"
              aria-pressed="${active}"
              ${device.is_restricted || active ? "disabled" : ""}
            >${escapeHtml(device.name || device.type || "Spotify device")}${qualifier}</button>
          `;
        })
        .join("")
    : '<a class="spotify-device-empty" href="spotify:" rel="noreferrer">Open Spotify on this phone to make it available.</a>';

  return `
    <div class="spotify-device-picker">
      <div class="spotify-device-head">
        <span>PLAYBACK DEVICE</span>
        <button id="spotifyRefreshDevices" type="button">REFRESH</button>
      </div>
      <div class="spotify-device-list">${deviceButtons}</div>
    </div>
  `;
}

function renderSpotifyPanel(data = lastSpotifyData) {
  lastSpotifyData = data;
  const playback = data.playback;
  const item = playback?.item || null;
  const product = data.profile?.product?.toUpperCase() || "CONNECTED";
  const heading = document.querySelector("#spotifyHeadingStatus");
  heading.textContent = `LIVE · ${product}`;
  heading.classList.add("is-live");
  document.querySelector("#disconnectSpotify").hidden = false;

  spotifyIsPlaying = Boolean(playback?.is_playing);
  spotifyProgressBaseMs = Number(playback?.progress_ms) || 0;
  spotifyProgressFetchedAt = Date.now();
  spotifyDurationMs = Number(item?.duration_ms) || 0;
  const activeDevice = getActiveSpotifyDevice();
  const hasControlScope =
    !spotifyGrantedScopes ||
    spotifyGrantedScopes.split(/\s+/).includes("user-modify-playback-state");
  document.querySelector("#repairSpotify").hidden = hasControlScope;
  const controlsUnavailable = Boolean(!activeDevice || activeDevice.is_restricted || !hasControlScope);
  const previousUnavailable =
    controlsUnavailable || spotifyActionIsDisallowed("previous", playback);
  const toggleUnavailable =
    controlsUnavailable || spotifyActionIsDisallowed("toggle", playback);
  const nextUnavailable =
    controlsUnavailable || spotifyActionIsDisallowed("next", playback);
  const hasPlaybackRestrictions =
    spotifyActionIsDisallowed("previous", playback) ||
    spotifyActionIsDisallowed("toggle", playback) ||
    spotifyActionIsDisallowed("next", playback);
  const controlNote = !hasControlScope
    ? "Reconnect once to grant playback permission."
    : activeDevice?.is_restricted
      ? `${activeDevice.name || "This device"} does not accept remote controls.`
      : hasPlaybackRestrictions
        ? "Spotify has limited one or more controls for this playback."
      : activeDevice
        ? `Controls follow the active ${activeDevice.name}.`
        : "Start Spotify on a device, then refresh.";

  const currentMarkup = item
    ? `
      <div class="spotify-now">
        <a class="spotify-cover" href="${escapeHtml(getSpotifyUrl(item))}" target="_blank" rel="noreferrer">
          ${getSpotifyArtwork(item) ? `<img src="${escapeHtml(getSpotifyArtwork(item))}" alt="" width="88" height="88" />` : ""}
        </a>
        <div class="spotify-track-copy">
          <small>${spotifyIsPlaying ? "NOW PLAYING" : "PAUSED"}${playback.device?.name ? ` · ${escapeHtml(playback.device.name)}` : ""}</small>
          <strong>${escapeHtml(item.name || "Untitled")}</strong>
          <span>${escapeHtml(getSpotifyByline(item))}</span>
          <div class="spotify-progress" aria-hidden="true"><i id="spotifyProgressFill"></i></div>
          <time class="spotify-progress-time" id="spotifyProgressTime">0:00 / ${formatSpotifyTime(spotifyDurationMs)}</time>
        </div>
      </div>
      <div class="spotify-controls">
        <button id="spotifyPrevious" type="button" aria-label="Previous track"${previousUnavailable ? " disabled" : ""}>${spotifyControlIcon("previous")}</button>
        <button class="spotify-play" id="spotifyPlay" type="button" aria-label="${spotifyIsPlaying ? "Pause" : "Play"}"${toggleUnavailable ? " disabled" : ""}>${spotifyControlIcon(spotifyIsPlaying ? "pause" : "play")}</button>
        <button id="spotifyNext" type="button" aria-label="Next track"${nextUnavailable ? " disabled" : ""}>${spotifyControlIcon("next")}</button>
        <a class="spotify-open" href="${escapeHtml(getSpotifyUrl(item))}" target="_blank" rel="noreferrer">OPEN IN SPOTIFY</a>
      </div>
      <div class="spotify-control-status${controlsUnavailable ? " has-warning" : ""}" id="spotifyControlStatus">${escapeHtml(controlNote)}</div>
      ${
        data.queue[0]
          ? `<div class="spotify-up-next"><b>UP NEXT</b><span>${escapeHtml(data.queue[0].name || "Untitled")} · ${escapeHtml(getSpotifyByline(data.queue[0]))}</span></div>`
          : ""
      }
    `
    : `
      <div class="spotify-idle">
        <strong>Nothing is playing right now.</strong>
        <p>Start something on your phone, computer or speaker; Daymark will pick it up automatically.</p>
        <a href="spotify:" rel="noreferrer">Open Spotify</a>
      </div>
      <div class="spotify-control-status has-warning" id="spotifyControlStatus">Choose an available device below, then start playback in Spotify.</div>
    `;

  document.querySelector("#spotifyContent").innerHTML = `
    ${currentMarkup}
    ${renderSpotifyDevicePicker(data)}
    <div class="spotify-library">
      <div class="spotify-library-head">
        <span>YOUR ROTATION</span>
        <div class="spotify-tabs">
          <button class="${spotifyLibraryView === "recent" ? "is-active" : ""}" type="button" data-spotify-view="recent">RECENT</button>
          <button class="${spotifyLibraryView === "history" ? "is-active" : ""}" type="button" data-spotify-view="history">HISTORY</button>
          <button class="${spotifyLibraryView === "stats" ? "is-active" : ""}" type="button" data-spotify-view="stats">STATS</button>
          <button class="${spotifyLibraryView === "rediscover" ? "is-active" : ""}" type="button" data-spotify-view="rediscover">REDISCOVER</button>
        </div>
      </div>
      <div class="spotify-list" id="spotifyLibraryList"></div>
    </div>
  `;
  renderSpotifyLibrary();
  bindSpotifyPanelActions();
  updateSpotifyProgress();
}

function bindSpotifyConnectButton() {
  const button = document.querySelector("#connectSpotify");
  if (!button || button.dataset.bound === "true") return;
  button.dataset.bound = "true";
  button.addEventListener("click", requestSpotifyConnection);
}

function renderSpotifyDisconnected(message = "Bring the current track into Daymark") {
  const heading = document.querySelector("#spotifyHeadingStatus");
  heading.textContent = "NOT CONNECTED";
  heading.classList.remove("is-live");
  document.querySelector("#disconnectSpotify").hidden = true;
  document.querySelector("#repairSpotify").hidden = true;
  document.querySelector("#spotifyContent").innerHTML = `
    <div class="spotify-connect-state">
      <span class="spotify-record" aria-hidden="true"><i></i></span>
      <strong>${escapeHtml(message)}</strong>
      <p>See what is playing, recent listening and your short-term favorites. Control the active Spotify device without leaving the brief.</p>
      <button id="connectSpotify" type="button">Connect Spotify</button>
      <a href="spotify:" rel="noreferrer">Open Spotify instead</a>
    </div>
  `;
  bindSpotifyConnectButton();
}

function renderSpotifyLoading() {
  document.querySelector("#spotifyHeadingStatus").textContent = "CONNECTING";
  document.querySelector("#spotifyContent").innerHTML =
    '<div class="spotify-loading">Tuning into your Spotify session…</div>';
}

function setSpotifyControlStatus(message, warning = false) {
  const status = document.querySelector("#spotifyControlStatus");
  if (!status) return;
  status.textContent = message;
  status.classList.toggle("has-warning", warning);
}

async function transferSpotifyPlayback(deviceId) {
  const device = lastSpotifyData.devices.find((item) => item.id === deviceId);
  if (!deviceId || device?.is_restricted) {
    setSpotifyControlStatus("That Spotify device cannot accept remote controls.", true);
    return;
  }

  const buttons = document.querySelectorAll("[data-spotify-device]");
  buttons.forEach((button) => {
    button.disabled = true;
  });
  setSpotifyControlStatus(`Connecting Daymark controls to ${device?.name || "that device"}…`);

  try {
    await fetchSpotify("/v1/me/player", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        device_ids: [deviceId],
        play: Boolean(lastSpotifyData.playback?.is_playing),
      }),
    });
    const successMessage = `${device?.name || "Spotify device"} is now selected.`;
    setSpotifyControlStatus(successMessage);
    showToast(successMessage);
    window.setTimeout(() => refreshSpotify(true), 750);
  } catch (error) {
    buttons.forEach((button) => {
      button.disabled = false;
    });
    const fallback =
      error.status === 404
        ? "Spotify lost that device. Open Spotify there, then refresh devices."
        : error.status === 403
          ? "Spotify is not allowing playback to move to that device."
          : "Spotify could not switch playback devices.";
    setSpotifyControlStatus(error.spotifyMessage || fallback, true);
  }
}

async function getFreshSpotifyControlState() {
  const [playback, devicePayload] = await Promise.all([
    fetchSpotify("/v1/me/player"),
    fetchSpotify("/v1/me/player/devices"),
  ]);
  lastSpotifyData.playback = playback;
  lastSpotifyData.devices = devicePayload?.devices || [];
  spotifyIsPlaying = Boolean(playback?.is_playing);
  spotifyProgressBaseMs = Number(playback?.progress_ms) || 0;
  spotifyProgressFetchedAt = Date.now();
  return {
    playback,
    device:
      playback?.device ||
      lastSpotifyData.devices.find((item) => item.is_active) ||
      null,
  };
}

function spotifyCommandWasApplied(action, before, after) {
  if (!after) return false;
  if (action === "toggle") {
    return Boolean(after.is_playing) !== Boolean(before?.is_playing);
  }
  const beforeTrack = before?.item?.id || before?.item?.uri || "";
  const afterTrack = after?.item?.id || after?.item?.uri || "";
  if (action === "next") return Boolean(afterTrack && afterTrack !== beforeTrack);
  if (action === "previous") {
    return Boolean(
      (afterTrack && afterTrack !== beforeTrack) ||
      Number(after.progress_ms) + 1000 < Number(before?.progress_ms),
    );
  }
  return false;
}

async function confirmSpotifyCommand(action, before) {
  await new Promise((resolve) => window.setTimeout(resolve, 700));
  try {
    const after = await fetchSpotify("/v1/me/player");
    if (!spotifyCommandWasApplied(action, before, after)) return false;
    lastSpotifyData.playback = after;
    spotifyIsPlaying = Boolean(after?.is_playing);
    spotifyProgressBaseMs = Number(after?.progress_ms) || 0;
    spotifyProgressFetchedAt = Date.now();
    return true;
  } catch {
    return false;
  }
}

async function controlSpotify(action) {
  if (
    spotifyGrantedScopes &&
    !spotifyGrantedScopes.split(/\s+/).includes("user-modify-playback-state")
  ) {
    setSpotifyControlStatus("Playback permission is missing. Tap Reconnect access above.", true);
    return;
  }

  const buttons = document.querySelectorAll(".spotify-controls button");
  buttons.forEach((button) => {
    button.disabled = true;
  });
  setSpotifyControlStatus("Checking the active Spotify player…");

  try {
    const { playback, device } = await getFreshSpotifyControlState();
    if (!device) {
      const missingDevice = new Error("No active Spotify device.");
      missingDevice.code = "NO_DEVICE";
      throw missingDevice;
    }
    if (device.is_restricted) {
      const restrictedDevice = new Error("Spotify marked this device as restricted.");
      restrictedDevice.code = "RESTRICTED_DEVICE";
      throw restrictedDevice;
    }
    if (spotifyActionIsDisallowed(action, playback)) {
      const restrictedAction = new Error("Spotify marked this action as unavailable.");
      restrictedAction.code = "RESTRICTED_ACTION";
      throw restrictedAction;
    }

    const freshIsPlaying = Boolean(playback?.is_playing);
    const commands = {
      previous: { path: "/v1/me/player/previous", method: "POST" },
      next: { path: "/v1/me/player/next", method: "POST" },
      toggle: {
        path: `/v1/me/player/${freshIsPlaying ? "pause" : "play"}`,
        method: "PUT",
      },
    };
    const command = commands[action];
    if (!command) return;

    let commandError = null;
    try {
      await fetchSpotify(command.path, { method: command.method });
    } catch (error) {
      if (error.status === 404 && device.id) {
        const separator = command.path.includes("?") ? "&" : "?";
        try {
          await fetchSpotify(
            `${command.path}${separator}device_id=${encodeURIComponent(device.id)}`,
            { method: command.method },
          );
        } catch (fallbackError) {
          commandError = fallbackError;
        }
      } else {
        commandError = error;
      }
    }
    if (commandError && !(await confirmSpotifyCommand(action, playback))) {
      throw commandError;
    }

    if (action === "toggle") spotifyIsPlaying = !freshIsPlaying;
    const successMessage =
      action === "next"
        ? `Skipped on ${device?.name || "Spotify"}.`
        : action === "previous"
          ? `Went back on ${device?.name || "Spotify"}.`
          : `${spotifyIsPlaying ? "Playing" : "Paused"} on ${device?.name || "Spotify"}.`;
    setSpotifyControlStatus(successMessage);
    showToast(successMessage);
    window.setTimeout(() => refreshSpotify(true), 750);
  } catch (error) {
    renderSpotifyPanel(lastSpotifyData);
    const spotifyMessage = String(error.spotifyMessage || "").toLowerCase();
    const isRestriction =
      error.status === 403 ||
      error.code === "RESTRICTED_DEVICE" ||
      error.code === "RESTRICTED_ACTION" ||
      spotifyMessage.includes("restriction");
    const message =
      error.code === "NO_DEVICE" || error.status === 404
        ? "Spotify cannot see an active player. Open Spotify, start the track there, then return."
        : isRestriction
          ? "Spotify is limiting remote control for this playback. Use Open in Spotify; Daymark will keep the listening data current."
          : "Daymark sent the command but could not confirm Spotify’s response. The player may still have updated.";
    setSpotifyControlStatus(message, true);
  }
}

function updateSpotifyProgress() {
  const fill = document.querySelector("#spotifyProgressFill");
  const time = document.querySelector("#spotifyProgressTime");
  if (!fill || !time || !spotifyDurationMs) return;
  const elapsed = spotifyIsPlaying ? Date.now() - spotifyProgressFetchedAt : 0;
  const progress = Math.min(spotifyDurationMs, spotifyProgressBaseMs + elapsed);
  fill.style.width = `${Math.max(0, (progress / spotifyDurationMs) * 100)}%`;
  time.textContent = `${formatSpotifyTime(progress)} / ${formatSpotifyTime(spotifyDurationMs)}`;
}

async function refreshSpotify(force = false) {
  if (!spotifyAccessToken || spotifyRefreshInFlight) return;
  if (!force && Date.now() - lastSpotifyRefreshAt < SPOTIFY_REFRESH_INTERVAL_MS) return;
  spotifyRefreshInFlight = true;
  document.querySelector("#spotifyHeadingStatus").textContent = "UPDATING";

  try {
    const refreshLibrary =
      force ||
      !lastSpotifyData.profile ||
      Date.now() - lastSpotifyLibraryRefreshAt >= SPOTIFY_LIBRARY_REFRESH_INTERVAL_MS;
    const requests = [
      fetchSpotify("/v1/me/player"),
      fetchSpotify("/v1/me/player/devices"),
      fetchSpotify("/v1/me/player/queue"),
      refreshLibrary ? fetchSpotify("/v1/me/player/recently-played?limit=50") : Promise.resolve(null),
      refreshLibrary
        ? fetchSpotify("/v1/me/top/tracks?time_range=short_term&limit=10")
        : Promise.resolve(null),
      refreshLibrary
        ? fetchSpotify("/v1/me/top/tracks?time_range=medium_term&limit=10")
        : Promise.resolve(null),
      refreshLibrary
        ? fetchSpotify("/v1/me/top/tracks?time_range=long_term&limit=10")
        : Promise.resolve(null),
      refreshLibrary
        ? fetchSpotify("/v1/me/top/artists?time_range=short_term&limit=8")
        : Promise.resolve(null),
      refreshLibrary ? fetchSpotify("/v1/me") : Promise.resolve(null),
    ];
    const [
      playbackResult,
      devicesResult,
      queueResult,
      recentResult,
      topResult,
      topMediumResult,
      topLongResult,
      topArtistsResult,
      profileResult,
    ] = await Promise.allSettled(requests);

    if (playbackResult.status === "rejected" && !lastSpotifyData.profile) {
      throw playbackResult.reason;
    }
    if (playbackResult.status === "fulfilled") {
      lastSpotifyData.playback = playbackResult.value;
    }
    if (devicesResult.status === "fulfilled") {
      lastSpotifyData.devices = devicesResult.value?.devices || [];
    }
    if (queueResult.status === "fulfilled") {
      lastSpotifyData.queue = queueResult.value?.queue || [];
    }
    if (recentResult.status === "fulfilled" && recentResult.value) {
      lastSpotifyData.recent = recentResult.value.items || [];
    }
    if (topResult.status === "fulfilled" && topResult.value) {
      lastSpotifyData.top = topResult.value.items || [];
    }
    if (topMediumResult.status === "fulfilled" && topMediumResult.value) {
      lastSpotifyData.topMedium = topMediumResult.value.items || [];
    }
    if (topLongResult.status === "fulfilled" && topLongResult.value) {
      lastSpotifyData.topLong = topLongResult.value.items || [];
    }
    if (topArtistsResult.status === "fulfilled" && topArtistsResult.value) {
      lastSpotifyData.topArtists = topArtistsResult.value.items || [];
    }
    if (profileResult.status === "fulfilled" && profileResult.value) {
      lastSpotifyData.profile = profileResult.value;
    }
    if (refreshLibrary) {
      lastSpotifyLibraryRefreshAt = Date.now();
      refreshDiscovery();
    }
    renderSpotifyPanel(lastSpotifyData);
  } catch (error) {
    if (!spotifyRefreshToken && Date.now() >= spotifyTokenExpiresAt) {
      clearSpotifySession();
      renderSpotifyDisconnected("Reconnect Spotify");
    } else {
      document.querySelector("#spotifyHeadingStatus").textContent = "RETRYING";
    }
  } finally {
    lastSpotifyRefreshAt = Date.now();
    spotifyRefreshInFlight = false;
  }
}

async function initializeSpotify() {
  const callbackHandled = await handleSpotifyCallback();
  if (callbackHandled || restoreSpotifySession()) {
    renderSpotifyLoading();
    await refreshSpotify(true);
  } else {
    renderSpotifyDisconnected();
  }
}

function writeLiveCache(key, data) {
  localStorage.setItem(key, JSON.stringify({ savedAt: new Date().toISOString(), data }));
}

function readLiveCache(key) {
  try {
    return JSON.parse(localStorage.getItem(key));
  } catch {
    return null;
  }
}

function weatherDescription(code) {
  if (code === 0) return "Clear";
  if ([1, 2].includes(code)) return "Partly cloudy";
  if (code === 3) return "Overcast";
  if ([45, 48].includes(code)) return "Foggy";
  if ([51, 53, 55, 56, 57].includes(code)) return "Drizzle";
  if ([61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return "Rain";
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "Snow";
  if ([95, 96, 99].includes(code)) return "Thunderstorms";
  return "Current conditions";
}

function weatherIcon(code) {
  if (code === 0) return "CLR";
  if ([1, 2].includes(code)) return "PCL";
  if ([3, 45, 48].includes(code)) return "OVC";
  if ([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82].includes(code)) return "RAN";
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "SNW";
  if ([95, 96, 99].includes(code)) return "STM";
  return "WX";
}

function formatFreshness(updatedAt) {
  const timestamp = new Date(updatedAt).getTime();
  if (!Number.isFinite(timestamp)) return "unknown age";
  const ageMinutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60000));
  if (ageMinutes < 1) return "now";
  if (ageMinutes < 60) return `${ageMinutes}m ago`;
  const ageHours = Math.floor(ageMinutes / 60);
  if (ageHours < 24) return `${ageHours}h ago`;
  return `${Math.floor(ageHours / 24)}d ago`;
}

function renderWeather(data, source = "live", updatedAt = new Date()) {
  const current = Math.round(data.current.temperature_2m);
  const feelsLike = Math.round(data.current.apparent_temperature);
  const high = Math.round(data.daily.temperature_2m_max[0]);
  const rain = Math.round(data.daily.precipitation_probability_max[0]);
  const code = data.current.weather_code;
  const timeFormat = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  });
  const sunsetDate = new Date(data.daily.sunset[0]);
  const sunset = timeFormat.format(sunsetDate);
  const sunriseDate =
    data.daily.sunrise && data.daily.sunrise[0] ? new Date(data.daily.sunrise[0]) : null;
  document.body.dataset.sunset = stripMeridiem(sunset);
  if (sunriseDate) {
    const sunrise = timeFormat.format(sunriseDate);
    const minutes = Math.max(0, Math.round((sunsetDate - sunriseDate) / 60000));
    document.body.dataset.daylight = `${Math.floor(minutes / 60)}h`;
    document.body.dataset.sunwindow = `${stripMeridiem(sunrise)}–${stripMeridiem(sunset)}`;
  }
  const description = weatherDescription(code);
  const feelsText = Math.abs(feelsLike - current) >= 3 ? ` · feels ${feelsLike}°` : "";

  document.querySelector("#heroWeather").innerHTML =
    `<i class="weather-glyph" aria-hidden="true">${weatherIcon(code)}</i> ${current}° · Durham`;
  const freshness = formatFreshness(updatedAt);
  document.querySelector("#weatherSource").textContent =
    source === "live" ? `UPDATED ${freshness.toUpperCase()}` : `CACHED · ${freshness.toUpperCase()}`;
  document.querySelector("#weatherCurrent").textContent = `${current}°`;
  document.querySelector("#weatherSummary").textContent = `${description}${feelsText}`;
  document.querySelector("#weatherHigh").textContent = `${high}°`;
  document.querySelector("#weatherRain").textContent = `${rain}%`;
  document.querySelector("#weatherSunset").textContent = sunset;
  document.querySelector("#widgetWeather").textContent = `${current}° · ${description}`;
  document.querySelector("#widgetWeatherNote").textContent = `High ${high}° · Rain ${rain}%`;
  const ageMinutes = Math.max(0, (Date.now() - new Date(updatedAt).getTime()) / 60000);
  document.querySelector(".weather-card").classList.toggle("is-stale", ageMinutes > 15);
  syncGlances();
}

function renderWeatherError() {
  document.querySelector("#heroWeather").innerHTML =
    '<i class="weather-glyph" aria-hidden="true">!</i> Weather unavailable';
  document.querySelector("#weatherSource").textContent = "UNAVAILABLE";
  document.querySelector("#weatherSummary").textContent = "Could not reach the weather source.";
  document.querySelector("#widgetWeather").textContent = "Unavailable";
  document.querySelector("#widgetWeatherNote").textContent = "Will retry quietly";
  document.querySelector(".weather-card").classList.add("is-stale");
}

function getTeamDisplay(team) {
  const names = {
    LAD: "Los Angeles",
    AZ: "Arizona",
    SD: "San Diego",
    SF: "San Francisco",
    COL: "Colorado",
  };
  return names[team.abbreviation] || team.shortName || team.name;
}

function getTeamPage(teamId) {
  const slugs = {
    109: "dbacks",
    112: "cubs",
    113: "reds",
    115: "rockies",
    119: "dodgers",
    120: "nationals",
    121: "mets",
    134: "pirates",
    135: "padres",
    137: "giants",
    138: "cardinals",
    143: "phillies",
    144: "braves",
    146: "marlins",
    158: "brewers",
  };
  return `https://www.mlb.com/${slugs[teamId] || ""}`;
}

function getTeamLogo(teamId) {
  return `https://www.mlbstatic.com/team-logos/${teamId}.svg`;
}

function formatGamesBack(value) {
  return !value || value === "-" ? "—" : value;
}

function getLastTen(record) {
  const split = record?.records?.splitRecords?.find(
    (item) => item.type === "lastTen" || item.type === "lastTenGames",
  );
  return split ? `${split.wins}–${split.losses}` : "—";
}

function extractWildCardRecords(data) {
  const unique = new Map();
  (data?.records || []).forEach((group) => {
    (group.teamRecords || []).forEach((record) => {
      const existing = unique.get(record.team.id);
      if (!existing || (!existing.wildCardRank && record.wildCardRank)) {
        unique.set(record.team.id, record);
      }
    });
  });
  return [...unique.values()]
    .filter((record) => Number(record.divisionRank) !== 1)
    .filter((record) => Number(record.wildCardRank) > 0)
    .sort((a, b) => Number(a.wildCardRank) - Number(b.wildCardRank));
}

function getVisibleWildCardRecords(records) {
  return records.slice(0, 8);
}

function renderStandingsView(view = currentStandingsView) {
  currentStandingsView = view;
  const isWildCard = view === "wildcard";
  const records = isWildCard
    ? getVisibleWildCardRecords(wildCardStandingsRecords)
    : divisionStandingsRecords;
  const rows = document.querySelector("#standingsRows");

  document.querySelectorAll("[data-standings-view]").forEach((button) => {
    const selected = button.dataset.standingsView === view;
    button.classList.toggle("is-active", selected);
    button.setAttribute("aria-selected", String(selected));
  });

  if (!records.length) {
    rows.innerHTML =
      '<div class="standing-row standings-loading"><span>Standings unavailable.</span><span>—</span><span>—</span><span>—</span></div>';
    return;
  }

  rows.innerHTML = records
    .map((record) => {
      const rank = Number(isWildCard ? record.wildCardRank : record.divisionRank);
      const favoriteClass = record.team.id === 109 ? " is-favorite" : "";
      const cutlineClass = isWildCard && rank === 4 ? " is-cutline" : "";
      const gamesBack = formatGamesBack(
        isWildCard ? record.wildCardGamesBack : record.divisionGamesBack,
      );
      const percentage = record.winningPercentage || "—";
      return `
        <a class="standing-row${favoriteClass}${cutlineClass}" href="${getTeamPage(record.team.id)}" target="_blank" rel="noreferrer">
          <span class="standing-team">
            <b>${rank || "—"}</b>
            <span class="standing-logo" data-abbr="${escapeHtml(record.team.abbreviation || "")}"><img src="${getTeamLogo(record.team.id)}" alt="" loading="lazy" width="28" height="28" /></span>
            <span><strong>${escapeHtml(getTeamDisplay(record.team))}</strong><small>${escapeHtml(record.team.abbreviation || "")}</small></span>
          </span>
          <span>${record.wins}–${record.losses}</span>
          <span>${escapeHtml(percentage)}</span>
          <span>${escapeHtml(gamesBack)}</span>
        </a>
      `;
    })
    .join("");
}

function renderDbacksStanding(divisionRecord, wildCardRecord) {
  if (!divisionRecord) return;
  const divisionRank = Number(divisionRecord.divisionRank);
  const wildCardRank = Number(wildCardRecord?.wildCardRank || divisionRecord.wildCardRank);
  const wildCardGamesBack =
    wildCardRecord?.wildCardGamesBack ?? divisionRecord.wildCardGamesBack;
  const divisionLeader = divisionRank === 1;
  const inWildCard = wildCardRank > 0 && wildCardRank <= 3;
  const status = divisionLeader
    ? "DIV LEAD"
    : wildCardRank
      ? `WC #${wildCardRank}`
      : "WC —";
  const detail = divisionLeader
    ? "division position"
    : inWildCard
      ? "inside playoff line"
      : wildCardRank
        ? `${formatGamesBack(wildCardGamesBack)} GB from WC lead`
        : "wild-card position";

  document.querySelector("#dbacksRank").textContent = `NL WEST · #${divisionRank || "—"}`;
  document.querySelector("#dbacksRecord").textContent =
    `${divisionRecord.wins}–${divisionRecord.losses}`;
  document.querySelector("#dbacksWildCard").textContent = status;
  document.querySelector("#dbacksWildCardDetail").textContent = detail;
  document.querySelector("#dbacksLastTen").textContent = getLastTen(divisionRecord);
  document.querySelector("#dbacksStreak").textContent =
    divisionRecord.streak?.streakCode || "—";
  document.querySelector("#dbacksWinPct").textContent =
    divisionRecord.winningPercentage || "—";
  document.querySelector("#wildCardStatus").textContent =
    divisionLeader ? "DIVISION LEADER" : status;
  document
    .querySelector(".dbacks-position")
    .classList.toggle("is-in", divisionLeader || inWildCard);
}

function renderBaseball(
  standingsData,
  wildCardData,
  scheduleData,
  source = "live",
  updatedAt = new Date(),
) {
  const division = standingsData.records.find((record) => record.division?.id === 203);
  if (!division) throw new Error("NL West standings were missing.");

  divisionStandingsRecords = [...division.teamRecords].sort(
    (a, b) => Number(a.divisionRank) - Number(b.divisionRank),
  );
  wildCardStandingsRecords = extractWildCardRecords(wildCardData || standingsData);
  if (!wildCardStandingsRecords.length) {
    wildCardStandingsRecords = extractWildCardRecords(standingsData);
  }
  const arizonaDivision = divisionStandingsRecords.find((record) => record.team.id === 109);
  const arizonaWildCard = wildCardStandingsRecords.find((record) => record.team.id === 109);
  renderDbacksStanding(arizonaDivision, arizonaWildCard);
  renderStandingsView(currentStandingsView);

  const games = scheduleData.dates.flatMap((date) => date.games || []);
  const today = formatApiDate(new Date());
  const game =
    games.find((item) => item.officialDate === today) ||
    games.find((item) => new Date(item.gameDate) >= new Date());

  if (game) renderDiamondbacksGame(game);
  else renderNoDiamondbacksGame();

  document.querySelector("#sportsSource").textContent =
    source === "live" ? "OFFICIAL MLB" : "CACHED MLB";
  const freshness = formatFreshness(updatedAt);
  document.querySelector("#sportsUpdatedAt").textContent =
    source === "live" ? `updated ${freshness}` : `cached ${freshness}`;
  const ageMinutes = Math.max(0, (Date.now() - new Date(updatedAt).getTime()) / 60000);
  document.querySelector(".sports-freshness").classList.toggle("is-stale", ageMinutes > 5);
}

function renderDiamondbacksGame(game) {
  const dbacksHome = game.teams.home.team.id === 109;
  const dbacksSide = dbacksHome ? game.teams.home : game.teams.away;
  const opponentSide = dbacksHome ? game.teams.away : game.teams.home;
  const opponent = opponentSide.team.shortName || opponentSide.team.name;
  const gameDate = new Date(game.gameDate);
  const today = formatApiDate(new Date()) === game.officialDate;
  const dateLabel = today
    ? "TODAY"
    : new Intl.DateTimeFormat("en-US", { weekday: "short" }).format(gameDate).toUpperCase();
  const timeLabel = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(gameDate);
  const gameState = game.status.abstractGameState;
  baseballGameIsLive = gameState === "Live";
  const gameCard = document.querySelector("#diamondbacksGame");

  document.querySelector("#gameTime").textContent = `DIAMONDBACKS · ${dateLabel} ${timeLabel}`;
  document.querySelector("#gameOpponent").textContent = `${dbacksHome ? "vs." : "at"} ${opponent}`;
  document.querySelector("#gameStatus").textContent = game.status.detailedState.toUpperCase();
  document.querySelector("#widgetGame").textContent = `${dbacksHome ? "vs." : "at"} ${opponent}`;
  document.querySelector("#widgetGameNote").textContent =
    `${dateLabel} ${timeLabel} · ${game.status.detailedState}`;
  gameCard.href = `https://www.mlb.com/gameday/${game.gamePk}`;

  if (gameState === "Final") {
    document.querySelector("#gameDetail").textContent =
      `Arizona ${dbacksSide.score ?? "—"} · ${opponent} ${opponentSide.score ?? "—"} · Final`;
  } else if (gameState === "Live") {
    document.querySelector("#gameDetail").textContent =
      `Arizona ${dbacksSide.score ?? 0}–${opponentSide.score ?? 0} · ${game.status.detailedState}`;
  } else {
    const arizonaPitcher = dbacksSide.probablePitcher?.fullName || "TBD";
    const opponentPitcher = opponentSide.probablePitcher?.fullName || "TBD";
    document.querySelector("#gameDetail").textContent =
      `${arizonaPitcher} vs. ${opponentPitcher} · ${game.venue?.name || "venue TBD"}`;
  }
}

function renderNoDiamondbacksGame() {
  baseballGameIsLive = false;
  document.querySelector("#gameTime").textContent = "DIAMONDBACKS";
  document.querySelector("#gameOpponent").textContent = "No upcoming game found";
  document.querySelector("#gameDetail").textContent = "Open the official schedule for more.";
  document.querySelector("#gameStatus").textContent = "MLB";
  document.querySelector("#widgetGame").textContent = "No game found";
  document.querySelector("#widgetGameNote").textContent = "Open official schedule";
}

function renderBaseballError() {
  baseballGameIsLive = false;
  document.querySelector("#sportsSource").textContent = "MLB UNAVAILABLE";
  document.querySelector("#sportsUpdatedAt").textContent = "will retry quietly";
  document.querySelector(".sports-freshness").classList.add("is-stale");
  document.querySelector("#wildCardStatus").textContent = "WC: UNAVAILABLE";
  document.querySelector("#dbacksRank").textContent = "NL WEST · UNAVAILABLE";
  document.querySelector("#dbacksWildCard").textContent = "—";
  document.querySelector("#dbacksWildCardDetail").textContent = "wild-card position";
  document.querySelector("#dbacksLastTen").textContent = "—";
  document.querySelector("#dbacksStreak").textContent = "—";
  document.querySelector("#dbacksWinPct").textContent = "—";
  document.querySelector("#widgetGame").textContent = "MLB unavailable";
  document.querySelector("#widgetGameNote").textContent = "Will retry quietly";
  document.querySelector("#standingsRows").innerHTML =
    '<div class="standing-row standings-loading"><span>Could not reach MLB.</span><span>—</span><span>—</span><span>—</span></div>';
  document.querySelector("#gameOpponent").textContent = "MLB data unavailable";
  document.querySelector("#gameDetail").textContent = "Tap to open the official schedule.";
}

function updateSyncState() {
  const sync = document.querySelector("#syncState");
  const syncLabel = sync.querySelector(".sync-label");
  const refreshing =
    weatherRefreshInFlight ||
    baseballRefreshInFlight ||
    durhamSportsRefreshInFlight ||
    spotifyRefreshInFlight;
  sync.classList.toggle("is-refreshing", refreshing);
  if (refreshing) {
    syncLabel.textContent = "updating";
    return;
  }
  if (window.navigator?.onLine === false) {
    syncLabel.textContent = "offline";
    return;
  }
  const liveCount = Object.values(publicFeedStatus).filter((status) => status === "live").length;
  const cachedCount = Object.values(publicFeedStatus).filter((status) => status === "cached").length;
  const feedCount = Object.keys(publicFeedStatus).length;
  if (liveCount === feedCount) syncLabel.textContent = "live";
  else if (liveCount) syncLabel.textContent = `${liveCount}/${feedCount} live`;
  else if (cachedCount) syncLabel.textContent = "cached";
  else syncLabel.textContent = "waiting";
}

function getWeatherUrl() {
  return (
    "https://api.open-meteo.com/v1/forecast?latitude=35.9940&longitude=-78.8986" +
    "&current=temperature_2m,apparent_temperature,weather_code,relative_humidity_2m,wind_speed_10m" +
    "&hourly=precipitation_probability,precipitation" +
    "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunset,sunrise,weather_code,uv_index_max" +
    "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America%2FNew_York&forecast_days=8"
  );
}

function getBaseballUrls() {
  const now = new Date();
  const end = new Date(now);
  end.setDate(now.getDate() + 10);
  const season = now.getFullYear();
  const standingsUrl =
    `https://statsapi.mlb.com/api/v1/standings?leagueId=104&season=${season}` +
    "&standingsTypes=regularSeason&hydrate=team,division";
  const wildCardUrl =
    `https://statsapi.mlb.com/api/v1/standings?leagueId=104&season=${season}` +
    "&standingsTypes=wildCard&hydrate=team,division";
  const scheduleUrl =
    `https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=109` +
    `&startDate=${formatApiDate(now)}&endDate=${formatApiDate(end)}` +
    "&hydrate=probablePitcher,team";
  return { standingsUrl, wildCardUrl, scheduleUrl };
}

function getDurhamBullsScheduleUrl() {
  const now = new Date();
  const end = new Date(now);
  end.setDate(now.getDate() + 10);
  return (
    "https://statsapi.mlb.com/api/v1/schedule?sportId=11&teamId=234" +
    `&startDate=${formatApiDate(now)}&endDate=${formatApiDate(end)}&hydrate=team,linescore`
  );
}

function renderDurhamBulls(data, source = "live", updatedAt = new Date()) {
  const games = (data?.dates || []).flatMap((date) => date.games || []);
  const now = new Date();
  const today = formatApiDate(now);
  const game =
    games.find((item) => item.officialDate === today) ||
    games.find((item) => new Date(item.gameDate) >= now);
  const sourceLabel = source === "live" ? "OFFICIAL MiLB" : "CACHED MiLB";
  document.querySelector("#durhamSportsSource").textContent =
    `${sourceLabel} · ${formatFreshness(updatedAt)}`.toUpperCase();
  const gameCard = document.querySelector("#durhamBullsGame");

  if (!game) {
    durhamBullsGameIsLive = false;
    gameCard.classList.remove("is-live");
    document.querySelector("#bullsGameTime").textContent = "DURHAM BULLS";
    document.querySelector("#bullsGameOpponent").textContent = "No upcoming game found";
    document.querySelector("#bullsGameDetail").textContent = "Open the official schedule for more.";
    document.querySelector("#bullsGameStatus").textContent = "MiLB";
    return;
  }

  const bullsHome = game.teams.home.team.id === 234;
  const bullsSide = bullsHome ? game.teams.home : game.teams.away;
  const opponentSide = bullsHome ? game.teams.away : game.teams.home;
  const opponent =
    opponentSide.team.shortName || opponentSide.team.teamName || opponentSide.team.name;
  const gameDate = new Date(game.gameDate);
  const dateLabel =
    game.officialDate === today
      ? "TODAY"
      : new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric" })
          .format(gameDate)
          .toUpperCase();
  const timeLabel = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(gameDate);
  const gameState = game.status.abstractGameState;
  const linescore = game.linescore || {};
  const bullsLine = bullsHome ? linescore.teams?.home : linescore.teams?.away;
  const opponentLine = bullsHome ? linescore.teams?.away : linescore.teams?.home;
  const bullsScore = bullsLine?.runs ?? bullsSide.score ?? "—";
  const opponentScore = opponentLine?.runs ?? opponentSide.score ?? "—";
  durhamBullsGameIsLive = gameState === "Live";
  gameCard.classList.toggle("is-live", durhamBullsGameIsLive);

  if (gameState === "Final") {
    const result =
      Number(bullsScore) > Number(opponentScore)
        ? "BULLS WIN"
        : Number(bullsScore) < Number(opponentScore)
          ? "BULLS LOSS"
          : "FINAL";
    document.querySelector("#bullsGameTime").textContent = `FINAL · ${dateLabel}`;
    document.querySelector("#bullsGameOpponent").textContent =
      `Durham ${bullsScore} · ${opponent} ${opponentScore}`;
    document.querySelector("#bullsGameDetail").textContent =
      `${result} · Official MiLB result`;
    document.querySelector("#bullsGameStatus").textContent = "FINAL";
  } else if (gameState === "Live") {
    const inning = [linescore.inningState, linescore.currentInningOrdinal]
      .filter(Boolean)
      .join(" ");
    const occupiedBases = ["first", "second", "third"].filter(
      (base) => linescore.offense?.[base],
    ).length;
    const outs = Number(linescore.outs);
    const baseState = occupiedBases ? `${occupiedBases} on base` : "bases empty";
    document.querySelector("#bullsGameTime").textContent =
      `LIVE · ${inning || game.status.detailedState || "IN PROGRESS"}`.toUpperCase();
    document.querySelector("#bullsGameOpponent").textContent =
      `Durham ${bullsScore} · ${opponent} ${opponentScore}`;
    document.querySelector("#bullsGameDetail").textContent =
      `${Number.isFinite(outs) ? `${outs} ${outs === 1 ? "out" : "outs"}` : "Live"} · ${baseState}`;
    document.querySelector("#bullsGameStatus").textContent = "LIVE";
  } else {
    document.querySelector("#bullsGameTime").textContent =
      `DURHAM BULLS · ${dateLabel} ${timeLabel}`;
    document.querySelector("#bullsGameOpponent").textContent =
      `${bullsHome ? "vs." : "at"} ${opponent}`;
    document.querySelector("#bullsGameDetail").textContent =
      `${bullsHome ? "Durham Bulls Athletic Park" : game.venue?.name || "Away"} · Official schedule`;
    document.querySelector("#bullsGameStatus").textContent =
      game.status.detailedState || "SCHEDULED";
  }
}

function renderDurhamBullsError() {
  durhamBullsGameIsLive = false;
  document.querySelector("#durhamBullsGame").classList.remove("is-live");
  document.querySelector("#durhamSportsSource").textContent = "MiLB UNAVAILABLE";
  document.querySelector("#bullsGameTime").textContent = "DURHAM BULLS";
  document.querySelector("#bullsGameOpponent").textContent = "Schedule unavailable";
  document.querySelector("#bullsGameDetail").textContent = "Tap to open the official Bulls schedule.";
  document.querySelector("#bullsGameStatus").textContent = "RETRYING";
}

async function refreshWeather(force = false) {
  if (weatherRefreshInFlight) return;
  if (!force && Date.now() - lastWeatherRefreshAt < WEATHER_REFRESH_INTERVAL_MS) return;
  weatherRefreshInFlight = true;
  updateSyncState();

  try {
    const data = await fetchJson(getWeatherUrl());
    const updatedAt = new Date();
    lastWeatherPayload = data;
    renderWeather(data, "live", updatedAt);
    writeLiveCache(WEATHER_CACHE_KEY, data);
    publicFeedStatus.weather = "live";
    fetchAirQuality();
  } catch {
    const cached = readLiveCache(WEATHER_CACHE_KEY);
    if (cached?.data) {
      lastWeatherPayload = cached.data;
      renderWeather(cached.data, "cached", cached.savedAt);
      publicFeedStatus.weather = "cached";
    } else {
      renderWeatherError();
      publicFeedStatus.weather = "unavailable";
    }
  } finally {
    lastWeatherRefreshAt = Date.now();
    weatherRefreshInFlight = false;
    updateSyncState();
  }
}

async function refreshDurhamSports(force = false) {
  if (durhamSportsRefreshInFlight) return;
  const interval = durhamBullsGameIsLive
    ? DURHAM_SPORTS_LIVE_REFRESH_INTERVAL_MS
    : DURHAM_SPORTS_REFRESH_INTERVAL_MS;
  if (
    !force &&
    Date.now() - lastDurhamSportsRefreshAt < interval
  ) return;
  durhamSportsRefreshInFlight = true;
  updateSyncState();

  try {
    const data = await fetchJson(getDurhamBullsScheduleUrl());
    const updatedAt = new Date();
    renderDurhamBulls(data, "live", updatedAt);
    writeLiveCache(DURHAM_SPORTS_CACHE_KEY, data);
    publicFeedStatus.durhamSports = "live";
  } catch {
    const cached = readLiveCache(DURHAM_SPORTS_CACHE_KEY);
    if (cached?.data) {
      renderDurhamBulls(cached.data, "cached", cached.savedAt);
      publicFeedStatus.durhamSports = "cached";
    } else {
      renderDurhamBullsError();
      publicFeedStatus.durhamSports = "unavailable";
    }
  } finally {
    lastDurhamSportsRefreshAt = Date.now();
    durhamSportsRefreshInFlight = false;
    updateSyncState();
  }
}

async function refreshBaseball(force = false) {
  if (baseballRefreshInFlight) return;
  const interval = baseballGameIsLive
    ? BASEBALL_LIVE_REFRESH_INTERVAL_MS
    : BASEBALL_REFRESH_INTERVAL_MS;
  if (!force && Date.now() - lastBaseballRefreshAt < interval) return;
  baseballRefreshInFlight = true;
  updateSyncState();
  const { standingsUrl, wildCardUrl, scheduleUrl } = getBaseballUrls();

  try {
    const [standingsResult, wildCardResult, scheduleResult] = await Promise.allSettled([
      fetchJson(standingsUrl),
      fetchJson(wildCardUrl),
      fetchJson(scheduleUrl),
    ]);
    if (standingsResult.status !== "fulfilled" || scheduleResult.status !== "fulfilled") {
      throw new Error("Official MLB data was incomplete.");
    }
    const wildCardData =
      wildCardResult.status === "fulfilled" ? wildCardResult.value : standingsResult.value;
    const updatedAt = new Date();
    renderBaseball(standingsResult.value, wildCardData, scheduleResult.value, "live", updatedAt);
    writeLiveCache(BASEBALL_CACHE_KEY, {
      divisionStandings: standingsResult.value,
      wildCardStandings: wildCardData,
      schedule: scheduleResult.value,
    });
    publicFeedStatus.baseball = "live";
  } catch {
    const cached = readLiveCache(BASEBALL_CACHE_KEY);
    const cachedDivision = cached?.data?.divisionStandings || cached?.data?.standings;
    const cachedWildCard = cached?.data?.wildCardStandings || cachedDivision;
    if (cachedDivision && cached?.data?.schedule) {
      renderBaseball(
        cachedDivision,
        cachedWildCard,
        cached.data.schedule,
        "cached",
        cached.savedAt,
      );
      publicFeedStatus.baseball = "cached";
    } else {
      renderBaseballError();
      publicFeedStatus.baseball = "unavailable";
    }
  } finally {
    lastBaseballRefreshAt = Date.now();
    baseballRefreshInFlight = false;
    updateSyncState();
  }
}

async function refreshGoogleIfNeeded(force = false) {
  if (!force && Date.now() - lastGoogleRefreshAt < GOOGLE_REFRESH_INTERVAL_MS) return;
  if (!(await ensureGoogleAccessToken())) return;
  try {
    await loadGoogleData();
  } catch {
    // Individual Google panels render their own reconnect states.
  }
}

async function refreshAllData(force = false) {
  await Promise.all([
    refreshWeather(force),
    refreshBaseball(force),
    refreshDurhamSports(force),
    refreshGoogleIfNeeded(force),
    refreshSpotify(force),
  ]);
}

function runRefreshScheduler() {
  if (document.visibilityState !== "visible") return;
  refreshWeather(false);
  refreshBaseball(false);
  refreshDurhamSports(false);
  refreshGoogleIfNeeded(false);
  refreshSpotify(false);
}

function hydrateTasks() {
  taskInputs.forEach((input) => {
    const taskId = input.closest("[data-task]")?.dataset.task;
    if (!taskId) return;
    input.checked = Boolean(state.tasks[taskId]);
    input.addEventListener("change", () => {
      state.tasks[taskId] = input.checked;
      saveState();
      updateBriefProgress();
      updateSprintProgress();
      renderFocusRail();
      showToast(input.checked ? "Done. One less open loop." : "Moved back to active.");
    });
  });
}

function getVisiblePriorityInputs() {
  const closingPhase = ["evening", "night"].includes(body.dataset.phase);
  const selector = closingPhase ? "#eveningActions .task-check" : "#morningActions .task-check";
  return [...document.querySelectorAll(selector)];
}

function updateBriefProgress() {
  const inputs = getVisiblePriorityInputs();
  const done = inputs.filter((input) => input.checked).length;
  const total = inputs.length || 1;
  const percentage = Math.round((done / total) * 100);
  const capturedOpen = state.captures.filter((item) => !item.done && !item.archived).length;
  document.querySelector("#briefPercent").textContent = `${percentage}%`;
  document.querySelector("#priorityCount").textContent = `${done}/${total}`;
  document.querySelector("#openCount").textContent = String(total - done + capturedOpen + 2);
}

function updateSprintProgress() {
  const sprintInputs = [...document.querySelectorAll(".sprint-tasks .task-check")];
  const done = sprintInputs.filter((input) => input.checked).length;
  const percentage = Math.round((done / sprintInputs.length) * 100);
  document.querySelector("#sprintPercent").textContent = `${percentage}%`;
  document.querySelector("#sprintTrack").style.width = `${percentage}%`;
}

function renderWeeklyScorecard() {
  const units = {
    jobs: "actions",
    veraya: "milestones",
    writing: "sessions",
    fitness: "sessions",
    household: "tasks",
  };

  document.querySelectorAll("[data-score-key]").forEach((row) => {
    const key = row.dataset.scoreKey;
    const dots = row.querySelector(".score-dots");
    const target = Number(dots.dataset.target);
    const current = Math.max(0, Math.min(target, Number(state.weeklyScores[key]) || 0));
    const label = row.querySelector("strong").textContent;
    row.querySelector("small").textContent = `${current} of ${target} ${units[key]}`;
    dots.setAttribute("aria-label", `${current} of ${target}`);
    dots.replaceChildren();

    for (let value = 1; value <= target; value += 1) {
      const button = document.createElement("button");
      button.type = "button";
      button.classList.toggle("is-filled", value <= current);
      button.setAttribute("aria-label", `Set ${label} to ${value} of ${target}`);
      button.addEventListener("click", () => {
        state.weeklyScores[key] = current === value ? value - 1 : value;
        saveState();
        renderWeeklyScorecard();
      });
      dots.append(button);
    }
  });

  renderScoreTrends();
}

const SCORE_TARGETS = { jobs: 5, veraya: 4, writing: 3, fitness: 4, household: 5 };

function renderScoreTrends() {
  const host = document.querySelector("#scoreTrends");
  const history = state.scoreHistory || {};
  const weeks = Object.keys(history).sort().slice(-7);
  if (!host) return;
  if (!weeks.length) {
    host.hidden = true;
    return;
  }
  host.hidden = false;
  host.innerHTML =
    '<p class="trend-title">EIGHT-WEEK TREND</p>' +
    Object.keys(SCORE_TARGETS)
      .map((key) => {
        const values = weeks.map((week) => history[week]?.[key] || 0);
        values.push(Number(state.weeklyScores[key]) || 0);
        const target = SCORE_TARGETS[key];
        const bars = values
          .map((value, index) => {
            const ratio = Math.min(1, value / target);
            const isCurrent = index === values.length - 1;
            return `<i class="${isCurrent ? "is-current" : ratio >= 1 ? "is-hit" : ""}" style="height:${Math.max(3, Math.round(22 * ratio))}px"></i>`;
          })
          .join("");
        return `<div class="trend-row"><span>${key}</span><div class="trend-bars">${bars}</div></div>`;
      })
      .join("");
}

function hydrateDecisions() {
  document.querySelectorAll(".decision-card").forEach((card) => {
    const id = card.dataset.decision;
    const selected = state.decisions[id];
    card.querySelectorAll("[data-choice]").forEach((button) => {
      button.classList.toggle("is-selected", button.dataset.choice === selected);
      button.addEventListener("click", () => {
        state.decisions[id] = button.dataset.choice;
        saveState();
        card.querySelectorAll("[data-choice]").forEach((item) => {
          item.classList.toggle("is-selected", item === button);
        });
        card.classList.add("is-decided");
        if (button.dataset.choice === "Open" && id === "duke-event") {
          window.open("https://careers.duke.edu/", "_blank", "noopener,noreferrer");
        }
        if (button.dataset.choice === "Open" && id === "housing-tour") {
          window.open(
            "https://www.redfin.com/city/4909/NC/Durham/filter/max-price=450k",
            "_blank",
            "noopener,noreferrer",
          );
        }
        showToast(`${button.dataset.choice} saved. Decision off your mind.`);
      });
    });
    card.classList.toggle("is-decided", Boolean(selected));
  });
}

function renderApplications() {
  const list = document.querySelector("#applicationList");
  const visibleApplications = state.applications.filter((app) => !app.archived);
  list.replaceChildren();

  if (visibleApplications.length === 0) {
    const empty = document.createElement("div");
    empty.className = "tracker-empty";
    empty.innerHTML = "<strong>No applications yet</strong><small>Add the first real role you want to track.</small>";
    list.append(empty);
  }

  visibleApplications.forEach((app) => {
    const row = document.createElement("div");
    row.className = "application-row";
    const titleMarkup = app.url
      ? `<a class="application-title" href="${escapeHtml(app.url)}" target="_blank" rel="noreferrer">${escapeHtml(app.role)}</a>`
      : `<strong>${escapeHtml(app.role)}</strong>`;
    row.innerHTML = `
      <div>
        ${titleMarkup}
        <small>${escapeHtml(app.organization)} · <span class="application-next">${escapeHtml(app.nextStep || "Choose next step")}</span></small>
      </div>
      <div class="application-actions">
        <button class="status-button" type="button" data-status="${escapeHtml(app.status)}" aria-label="Change status for ${escapeHtml(app.role)}">${escapeHtml(app.status)}</button>
        <button class="item-edit" type="button" aria-label="Edit ${escapeHtml(app.role)}">Edit</button>
        <button class="item-archive" type="button" aria-label="Archive ${escapeHtml(app.role)}">Remove</button>
      </div>
    `;
    row.querySelector(".status-button").addEventListener("click", () => cycleApplicationStatus(app.id));
    row.querySelector(".item-edit").addEventListener("click", () => openApplicationEditor(app));
    row.querySelector(".item-archive").addEventListener("click", () => {
      app.archived = true;
      saveState();
      renderApplications();
      showToast("Application archived.");
    });
    list.append(row);
  });

  const active = visibleApplications.length;
  const followups = visibleApplications.filter((app) => app.status === "Follow-up").length;
  const interviews = visibleApplications.filter((app) => app.status === "Interview").length;
  document.querySelector("#activeApps").textContent = String(active);
  document.querySelector("#followupApps").textContent = String(followups);
  document.querySelector("#interviewApps").textContent = String(interviews);
  const stageWeight = { Interested: 20, Applied: 45, "Follow-up": 65, Interview: 90, Offer: 100 };
  const averageProgress = active
    ? Math.round(
        visibleApplications.reduce((sum, app) => sum + (stageWeight[app.status] || 0), 0) / active,
      )
    : 0;
  document.querySelector(".tracker-progress-fill").style.width = `${averageProgress}%`;
}

function openApplicationEditor(app = null) {
  applicationForm.reset();
  applicationDialog.dataset.editId = app?.id || "";
  document.querySelector("#applicationDialogTitle").textContent =
    app ? "Edit application" : "Add an application";
  document.querySelector("#applicationSubmit").textContent =
    app ? "Save changes" : "Add to tracker";
  if (app) {
    applicationForm.elements.organization.value = app.organization || "";
    applicationForm.elements.role.value = app.role || "";
    applicationForm.elements.url.value = app.url || "";
    applicationForm.elements.status.value = app.status || "Interested";
    applicationForm.elements.nextStep.value = app.nextStep || "";
  }
  applicationDialog.showModal();
  window.setTimeout(() => applicationForm.elements.organization.focus(), 80);
}

function closeApplicationEditor() {
  applicationDialog.close();
  applicationDialog.dataset.editId = "";
  applicationForm.reset();
}

function cycleApplicationStatus(id) {
  const order = ["Interested", "Applied", "Follow-up", "Interview", "Offer"];
  const app = state.applications.find((item) => item.id === id);
  if (!app) return;
  const index = order.indexOf(app.status);
  app.status = order[(index + 1) % order.length];
  saveState();
  renderApplications();
  showToast(`Moved to ${app.status}.`);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function showToast(message) {
  const toast = document.querySelector("#toast");
  toast.textContent = message;
  toast.classList.add("is-visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("is-visible"), 2200);
}

function scrollToViewTarget(target = "", smooth = true) {
  window.requestAnimationFrame(() => {
    if (target) {
      document.querySelector(`#${target}`)?.scrollIntoView({
        behavior: smooth ? "smooth" : "auto",
        block: "start",
      });
      return;
    }
    window.scrollTo({ top: 0, behavior: smooth ? "smooth" : "auto" });
  });
}

function setAppView(view, options = {}) {
  const nextView = VIEW_CONFIG[view] ? view : "today";
  const config = VIEW_CONFIG[nextView];
  body.dataset.view = nextView;
  renderMasthead(nextView);

  const shortcuts = document.querySelector("#viewShortcuts");
  shortcuts.innerHTML = config.shortcuts
    .map(
      ([label, target]) =>
        `<button type="button" data-view-shortcut="${escapeHtml(target)}">${escapeHtml(label)}</button>`,
    )
    .join("");
  shortcuts.querySelectorAll("[data-view-shortcut]").forEach((button) => {
    button.addEventListener("click", () => scrollToViewTarget(button.dataset.viewShortcut));
  });

  navButtons.forEach((button) => {
    const active = button.dataset.appView === nextView;
    button.classList.toggle("is-active", active);
    if (active) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });

  if (options.scroll !== false) {
    scrollToViewTarget(options.target || "", options.smooth !== false);
  }
}

document.querySelectorAll("[data-app-view]").forEach((button) => {
  button.addEventListener("click", (event) => {
    if (button instanceof HTMLAnchorElement) event.preventDefault();
    setAppView(button.dataset.appView, { target: button.dataset.viewTarget || "" });
  });
});

document.querySelector("#refreshBrief").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  button.classList.add("is-spinning");
  try {
    await refreshAllData(true);
  } finally {
    button.classList.remove("is-spinning");
  }
});

document.querySelector("#refreshMail").addEventListener("click", refreshPriorityMail);

document.querySelector("#mapSearchForm").addEventListener("submit", (event) => {
  event.preventDefault();
  openMapSearch(new FormData(event.currentTarget).get("query"));
});

document.querySelectorAll("[data-map-query]").forEach((button) => {
  button.addEventListener("click", () => openMapSearch(button.dataset.mapQuery));
});

document.querySelector("#youtubeSearchForm").addEventListener("submit", (event) => {
  event.preventDefault();
  openYouTubeSearch(new FormData(event.currentTarget).get("query"));
});

document.querySelectorAll("[data-youtube-query]").forEach((button) => {
  button.addEventListener("click", () => openYouTubeSearch(button.dataset.youtubeQuery));
});

document.querySelector("#disconnectGoogle").addEventListener("click", () => {
  clearGoogleSession();
  renderGoogleDisconnected();
  showToast("Google session ended on this device.");
});

document.querySelector("#disconnectSpotify").addEventListener("click", () => {
  clearSpotifySession();
  renderSpotifyDisconnected();
  showToast("Spotify session ended on this device.");
});

document.querySelector("#repairSpotify").addEventListener("click", () => {
  clearSpotifySession();
  requestSpotifyConnection();
});

document.querySelectorAll("[data-standings-view]").forEach((button) => {
  button.addEventListener("click", () => renderStandingsView(button.dataset.standingsView));
});

document.querySelector("#openApplicationDialog").addEventListener("click", () => {
  openApplicationEditor();
});

document.querySelector("#closeApplicationDialog").addEventListener("click", () => {
  closeApplicationEditor();
});

applicationDialog.addEventListener("click", (event) => {
  if (event.target === applicationDialog) closeApplicationEditor();
});

applicationForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const formData = new FormData(applicationForm);
  const rawUrl = String(formData.get("url") || "").trim();
  const url = normalizeUrl(rawUrl);
  if (rawUrl && !url) {
    showToast("That listing link does not look valid yet.");
    return;
  }
  const editId = applicationDialog.dataset.editId;
  const existing = state.applications.find((app) => app.id === editId);
  const values = {
    organization: formData.get("organization").trim(),
    role: formData.get("role").trim(),
    status: formData.get("status"),
    nextStep: formData.get("nextStep").trim() || "Choose next step",
    url,
  };
  if (existing) {
    Object.assign(existing, values, { updatedAt: new Date().toISOString() });
  } else {
    state.applications.unshift({
      id: `app-${Date.now()}`,
      createdAt: new Date().toISOString(),
      ...values,
      archived: false,
    });
  }
  saveState();
  renderApplications();
  closeApplicationEditor();
  showToast(existing ? "Application updated." : "Application added to your tracker.");
});

document.querySelectorAll("[data-open-capture]").forEach((button) => {
  button.addEventListener("click", () => openCaptureDialog("task"));
});

document.querySelectorAll("[data-open-reminder]").forEach((button) => {
  button.addEventListener("click", () => openCaptureDialog("reminder"));
});

document.querySelectorAll("[data-open-job-capture]").forEach((button) => {
  button.addEventListener("click", () => openCaptureDialog("job"));
});

document.querySelector("#openReadingCapture").addEventListener("click", () => {
  openCaptureDialog("reading");
});

document.querySelector("#closeCaptureDialog").addEventListener("click", () => {
  captureDialog.close();
});

captureDialog.addEventListener("click", (event) => {
  if (event.target === captureDialog) captureDialog.close();
});

captureForm.querySelectorAll('input[name="captureType"]').forEach((input) => {
  input.addEventListener("change", () => setCaptureType(input.value));
});

captureForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const formData = new FormData(captureForm);
  const type = String(formData.get("captureType") || "task");
  const title = String(formData.get("title") || "").trim();
  const note = String(formData.get("note") || "").trim();
  const rawUrl = String(formData.get("url") || "").trim();
  const url = normalizeUrl(rawUrl);

  if (!title) return;
  if (rawUrl && !url) {
    showToast("That link does not look valid yet.");
    return;
  }
  if (type === "reading" && !url) {
    showToast("Add the article link so it stays clickable.");
    return;
  }

  if (type === "job") {
    state.applications.unshift({
      id: `app-${Date.now()}`,
      createdAt: new Date().toISOString(),
      organization: note || "Captured lead",
      role: title,
      status: "Interested",
      nextStep: url ? "Open saved listing" : "Review opportunity",
      url,
      archived: false,
    });
    renderApplications();
    showToast("Job lead added to Applications.");
  } else if (type === "reading") {
    state.readingQueue.unshift({
      id: `read-${Date.now()}`,
      createdAt: new Date().toISOString(),
      title,
      url,
      note,
      read: false,
      archived: false,
    });
    renderReadingQueue();
    showToast("Saved to your reading queue.");
  } else {
    state.captures.unshift({
      id: `capture-${Date.now()}`,
      createdAt: new Date().toISOString(),
      type,
      title,
      note,
      url,
      done: false,
      archived: false,
    });
    renderCaptureInbox();
    renderFocusRail();
    updateBriefProgress();
    showToast(type === "reminder" ? "Reminder captured." : "Task captured.");
  }

  saveState();
  captureForm.reset();
  captureDialog.close();
});

document.querySelectorAll("[data-command-jump]").forEach((button) => {
  button.addEventListener("click", () => {
    const destination = button.dataset.commandJump;
    const destinationView = {
      jobs: "work",
      decisions: "work",
      reading: "more",
      durham: "life",
    }[destination] || "today";
    captureDialog.close();
    window.setTimeout(() => {
      setAppView(destinationView, { target: destination });
    }, 100);
  });
});

document.querySelector("#focusTimerButton").addEventListener("click", toggleFocusTimer);
document.querySelector("#focusDoneButton").addEventListener("click", completeFocusedItem);
document.querySelector("#focusNextButton").addEventListener("click", showNextFocusItem);

document.addEventListener("keydown", (event) => {
  const target = event.target;
  const isTyping = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement;
  if (!isTyping && (event.key === "q" || (event.metaKey && event.key.toLowerCase() === "k"))) {
    event.preventDefault();
    if (!captureDialog.open) openCaptureDialog("task");
  }
});

setAppView("today", { scroll: false });
formatDate();
saveState();
bindGoogleConnectButtons();
hydrateTasks();
hydrateDecisions();
renderApplications();
renderCaptureInbox();
renderReadingQueue();
renderWeeklyScorecard();
updateLiveDay();
updateSprintProgress();
renderFocusRail();
updateFocusTimer();
restoreGoogleSession();
initializeSpotify();
initializeDeskSettings();
document.querySelector("#openSkyDesk")?.addEventListener("click", openSkyDesk);
document.querySelector("#skyClose")?.addEventListener("click", closeSkyDesk);
document.querySelector("#skyOverlay")?.addEventListener("click", (event) => {
  if (event.target === event.currentTarget) closeSkyDesk();
});
refreshAIDesk();
renderSoundCloudShelf();
refreshAllData(true);
window.setInterval(() => {
  updateClock();
  updateFocusTimer();
  updateSpotifyProgress();
}, 1000);
window.setInterval(() => updateLiveDay(), 30000);
window.setInterval(runRefreshScheduler, REFRESH_SCHEDULER_INTERVAL_MS);

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible") return;
  updateLiveDay();
  refreshAllData(true);
});

window.addEventListener("online", () => refreshAllData(true));
window.addEventListener("offline", updateSyncState);

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js?v=19").catch(() => {});
  });
}
