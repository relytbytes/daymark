const STORAGE_KEY = "daymark-state-v1";
const WEATHER_CACHE_KEY = "daymark-weather-cache-v1";
const BASEBALL_CACHE_KEY = "daymark-baseball-cache-v1";
const GOOGLE_SESSION_KEY = "daymark-google-session-v1";
const STATE_SCHEMA_VERSION = 9;
const WEATHER_REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const BASEBALL_REFRESH_INTERVAL_MS = 60 * 1000;
const BASEBALL_LIVE_REFRESH_INTERVAL_MS = 30 * 1000;
const GOOGLE_REFRESH_INTERVAL_MS = 2 * 60 * 1000;
const REFRESH_SCHEDULER_INTERVAL_MS = 15 * 1000;
const GOOGLE_SCOPES = [
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/gmail.readonly",
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
let lastGoogleRefreshAt = 0;
let weatherRefreshInFlight = false;
let baseballRefreshInFlight = false;
let publicFeedStatus = { weather: "checking", baseball: "checking" };
let googleAccessToken = "";
let googleTokenExpiresAt = 0;
let focusCompletionAnnounced = false;
let baseballGameIsLive = false;
let currentStandingsView = "division";
let divisionStandingsRecords = [];
let wildCardStandingsRecords = [];
let navScrollLockUntil = 0;
let navScrollFrame = 0;

const body = document.body;
const taskInputs = [...document.querySelectorAll(".task-check")];
const navButtons = [...document.querySelectorAll(".nav-button")];
const applicationDialog = document.querySelector("#applicationDialog");
const applicationForm = document.querySelector("#applicationForm");
const captureDialog = document.querySelector("#captureDialog");
const captureForm = document.querySelector("#captureForm");

document.addEventListener(
  "error",
  (event) => {
    if (!(event.target instanceof HTMLImageElement)) return;
    if (!event.target.src.includes("mlbstatic.com/team-logos")) return;
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
      <button class="item-archive" type="button" aria-label="Archive ${escapeHtml(item.title)}">×</button>
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
    reminder?.note || "Tap to capture the thing that cannot slip. ↗";
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
        <span aria-hidden="true">↗</span>
      </a>
      <div class="reading-row-actions">
        <button class="reading-toggle" type="button">${item.read ? "Unread" : "Read"}</button>
        <button class="item-archive" type="button" aria-label="Archive ${escapeHtml(item.title)}">×</button>
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
  document.querySelector("#stripDay").textContent =
    new Intl.DateTimeFormat("en-US", { weekday: "long" }).format(date).toUpperCase();
  document.querySelector("#stripDate").textContent =
    new Intl.DateTimeFormat("en-US", { month: "long", day: "numeric" })
      .format(date)
      .toUpperCase();

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
  document.querySelector("#stripDay").textContent =
    new Intl.DateTimeFormat("en-US", { weekday: "long" }).format(date).toUpperCase();
  document.querySelector("#stripDate").textContent =
    new Intl.DateTimeFormat("en-US", { month: "long", day: "numeric" })
      .format(date)
      .toUpperCase();
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
  const phaseContent = {
    morning: {
      label: "Morning runway",
      title: "Good morning, Ty.",
      note: "A clear day to move the important things. The rest can wait.",
      priorityKicker: "START HERE",
      priorityTitle: "Today’s essential three",
      signalKicker: "WHAT’S IN MOTION",
      signalTitle: "Calendar + priority mail",
      readingKicker: "LATER TONIGHT · 28 MIN",
    },
    afternoon: {
      label: "Afternoon check-in",
      title: "Good afternoon, Ty.",
      note: "The day is in motion. Protect the next useful block and let the noise pass.",
      priorityKicker: "MIDDAY CHECK",
      priorityTitle: "What matters this afternoon",
      signalKicker: "THE NEXT FEW HOURS",
      signalTitle: "Calendar + priority mail",
      readingKicker: "FOR LATER · 28 MIN",
    },
    evening: {
      label: "Evening landing",
      title: "Good evening, Ty.",
      note: "The ambitious part of the day is over. Close what matters and release the rest.",
      priorityKicker: "CLOSE THE LOOPS",
      priorityTitle: "Finish the day clean",
      signalKicker: "WHAT MOVED",
      signalTitle: "Day in review",
      readingKicker: "WIND DOWN · 28 MIN",
    },
    night: {
      label: "Night reset",
      title: "The day can end, Ty.",
      note: "Capture the loose ends, choose tomorrow’s first move, and get out of the dashboard.",
      priorityKicker: "RESET",
      priorityTitle: "Leave tomorrow lighter",
      signalKicker: "TOMORROW",
      signalTitle: "A clean start is ready",
      readingKicker: "BEDTIME READING · 28 MIN",
    },
  }[phase];

  body.dataset.phase = phase;
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
      <span aria-hidden="true">＋</span>
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
    sessionStorage.setItem(
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
    sessionStorage.removeItem(GOOGLE_SESSION_KEY);
  } catch {
    // Nothing else to clear.
  }
  const disconnectButton = document.querySelector("#disconnectGoogle");
  if (disconnectButton) disconnectButton.hidden = true;
}

function restoreGoogleSession() {
  try {
    const saved = JSON.parse(sessionStorage.getItem(GOOGLE_SESSION_KEY));
    if (saved?.accessToken && Number(saved.expiresAt) > Date.now() + 30000) {
      googleAccessToken = saved.accessToken;
      googleTokenExpiresAt = Number(saved.expiresAt);
      return true;
    }
  } catch {
    // Invalid or unavailable session storage means reconnecting manually.
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
      persistGoogleSession();
      await loadGoogleData();
    },
    error_callback: () => {
      setGoogleButtonsDisabled(false);
      showToast("Google sign-in was closed or blocked.");
    },
  });

  const wasConnected = localStorage.getItem("daymark-google-was-connected") === "1";
  tokenClient.requestAccessToken({ prompt: wasConnected ? "" : "consent" });
}

async function fetchGoogleJson(url) {
  if (!googleAccessToken || Date.now() >= googleTokenExpiresAt) {
    clearGoogleSession();
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
    document.querySelector("#calendarContent").innerHTML =
      '<div class="google-empty">No remaining events on your primary calendar.</div>';
    return;
  }

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
    "in:inbox newer_than:7d (is:important OR is:starred) -category:promotions -category:social";
  const list = await fetchGoogleJson(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=4&q=${encodeURIComponent(query)}`,
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
  document.querySelector("#emailStatus").textContent = `LIVE · ${messages.length}`;
  document.querySelector("#emailStatus").classList.remove("disconnected-status");

  if (messages.length === 0) {
    document.querySelector("#emailContent").innerHTML =
      '<div class="google-empty">No recent priority messages matched.</div>';
    return;
  }

  document.querySelector("#emailContent").innerHTML = `
    ${messages
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
          <a class="mail-item" href="https://mail.google.com/mail/u/0/#inbox/${escapeHtml(message.threadId)}" target="_blank" rel="noreferrer">
            <span class="sender-avatar${index % 2 ? " sender-avatar--blue" : ""}">${escapeHtml(getSenderInitials(sender))}</span>
            <span class="mail-copy">
              <span><strong>${escapeHtml(sender)}</strong><time>${escapeHtml(time)}</time></span>
              <b>${escapeHtml(subject)}</b>
              <small>${escapeHtml(message.snippet || "Open in Gmail")}</small>
            </span>
          </a>
        `;
      })
      .join("")}
    <div class="mail-summary">Read-only · Google Gmail</div>
  `;
}

function renderGooglePanelError(type, message) {
  const isCalendar = type === "calendar";
  const status = document.querySelector(isCalendar ? "#calendarStatus" : "#emailStatus");
  const content = document.querySelector(isCalendar ? "#calendarContent" : "#emailContent");
  status.textContent = "CONNECT AGAIN";
  status.classList.add("disconnected-status");
  content.innerHTML = googleConnectMarkup("Reconnect Google", message);
  bindGoogleConnectButtons();
}

function renderGoogleDisconnected() {
  document.querySelector("#calendarStatus").textContent = "NOT CONNECTED";
  document.querySelector("#calendarStatus").classList.add("disconnected-status");
  document.querySelector("#emailStatus").textContent = "NOT CONNECTED";
  document.querySelector("#emailStatus").classList.add("disconnected-status");
  document.querySelector("#calendarContent").innerHTML = googleConnectMarkup(
    "Connect Google securely",
    "Allow read-only access to your calendar.",
  );
  document.querySelector("#emailContent").innerHTML = googleConnectMarkup(
    "Connect Google securely",
    "Allow read-only access to priority email.",
  );
  bindGoogleConnectButtons();
  formatDate();
  document.querySelector("#tomorrowSummary").textContent =
    "Connect Google and Daymark will build this from your real schedule.";
  document.querySelector("#tomorrowFirstLabel").textContent = "FIRST EVENT";
  document.querySelector("#tomorrowFirstValue").textContent = "NOT CONNECTED";
}

async function loadGoogleData() {
  document.querySelector("#calendarStatus").textContent = "SYNCING";
  document.querySelector("#emailStatus").textContent = "SYNCING";
  const [calendarResult, emailResult] = await Promise.allSettled([
    fetchCalendarData(),
    fetchPriorityEmailData(),
  ]);

  if (calendarResult.status === "fulfilled") renderCalendar(calendarResult.value);
  else renderGooglePanelError("calendar", "Calendar access needs attention.");

  if (emailResult.status === "fulfilled") renderPriorityEmails(emailResult.value);
  else renderGooglePanelError("email", "Gmail access needs attention.");

  lastGoogleRefreshAt = Date.now();
  document.querySelector("#disconnectGoogle").hidden =
    calendarResult.status !== "fulfilled" && emailResult.status !== "fulfilled";
  setGoogleButtonsDisabled(false);
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
  if (code === 0) return "☀";
  if ([1, 2].includes(code)) return "◐";
  if ([3, 45, 48].includes(code)) return "☁";
  if ([71, 73, 75, 77, 85, 86].includes(code)) return "✳";
  if ([95, 96, 99].includes(code)) return "ϟ";
  return "●";
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
  const sunset = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(data.daily.sunset[0]));
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
  const ageMinutes = Math.max(0, (Date.now() - new Date(updatedAt).getTime()) / 60000);
  document.querySelector(".weather-card").classList.toggle("is-stale", ageMinutes > 15);
}

function renderWeatherError() {
  document.querySelector("#heroWeather").innerHTML =
    '<i class="weather-glyph" aria-hidden="true">!</i> Weather unavailable';
  document.querySelector("#weatherSource").textContent = "UNAVAILABLE";
  document.querySelector("#weatherSummary").textContent = "Could not reach the weather source.";
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
  document.querySelector("#standingsRows").innerHTML =
    '<div class="standing-row standings-loading"><span>Could not reach MLB.</span><span>—</span><span>—</span><span>—</span></div>';
  document.querySelector("#gameOpponent").textContent = "MLB data unavailable";
  document.querySelector("#gameDetail").textContent = "Tap to open the official schedule.";
}

function updateSyncState() {
  const sync = document.querySelector("#syncState");
  const syncLabel = sync.querySelector(".sync-label");
  const refreshing = weatherRefreshInFlight || baseballRefreshInFlight;
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
  if (liveCount === 2) syncLabel.textContent = "live";
  else if (liveCount) syncLabel.textContent = `${liveCount}/2 live`;
  else if (cachedCount) syncLabel.textContent = "cached";
  else syncLabel.textContent = "waiting";
}

function getWeatherUrl() {
  return (
    "https://api.open-meteo.com/v1/forecast?latitude=35.9940&longitude=-78.8986" +
    "&current=temperature_2m,apparent_temperature,weather_code" +
    "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunset" +
    "&temperature_unit=fahrenheit&timezone=America%2FNew_York&forecast_days=2"
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

async function refreshWeather(force = false) {
  if (weatherRefreshInFlight) return;
  if (!force && Date.now() - lastWeatherRefreshAt < WEATHER_REFRESH_INTERVAL_MS) return;
  weatherRefreshInFlight = true;
  updateSyncState();

  try {
    const data = await fetchJson(getWeatherUrl());
    const updatedAt = new Date();
    renderWeather(data, "live", updatedAt);
    writeLiveCache(WEATHER_CACHE_KEY, data);
    publicFeedStatus.weather = "live";
  } catch {
    const cached = readLiveCache(WEATHER_CACHE_KEY);
    if (cached?.data) {
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
  if (!googleAccessToken || Date.now() >= googleTokenExpiresAt) return;
  if (!force && Date.now() - lastGoogleRefreshAt < GOOGLE_REFRESH_INTERVAL_MS) return;
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
    refreshGoogleIfNeeded(force),
  ]);
}

function runRefreshScheduler() {
  if (document.visibilityState !== "visible") return;
  refreshWeather(false);
  refreshBaseball(false);
  refreshGoogleIfNeeded(false);
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
            "https://www.zillow.com/durham-nc/rentals/",
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
      ? `<a class="application-title" href="${escapeHtml(app.url)}" target="_blank" rel="noreferrer">${escapeHtml(app.role)} ↗</a>`
      : `<strong>${escapeHtml(app.role)}</strong>`;
    row.innerHTML = `
      <div>
        ${titleMarkup}
        <small>${escapeHtml(app.organization)} · <span class="application-next">${escapeHtml(app.nextStep || "Choose next step")}</span></small>
      </div>
      <div class="application-actions">
        <button class="status-button" type="button" data-status="${escapeHtml(app.status)}" aria-label="Change status for ${escapeHtml(app.role)}">${escapeHtml(app.status)}</button>
        <button class="item-edit" type="button" aria-label="Edit ${escapeHtml(app.role)}">✎</button>
        <button class="item-archive" type="button" aria-label="Archive ${escapeHtml(app.role)}">×</button>
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

document.querySelectorAll("[data-scroll]").forEach((button) => {
  button.addEventListener("click", () => {
    const id = button.dataset.scroll;
    document.querySelector(`#${id}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
    if (button.classList.contains("nav-button")) {
      navScrollLockUntil = Date.now() + 1200;
      navButtons.forEach((item) => item.classList.toggle("is-active", item === button));
      window.setTimeout(updateActiveNavigation, 1250);
    }
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

document.querySelector("#disconnectGoogle").addEventListener("click", () => {
  clearGoogleSession();
  renderGoogleDisconnected();
  showToast("Google session ended on this device.");
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
    captureDialog.close();
    window.setTimeout(() => {
      document.querySelector(`#${destination}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
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

function updateActiveNavigation() {
  if (Date.now() < navScrollLockUntil) return;
  const anchor = 165;
  const sections = [
    { id: "today", nav: "today" },
    { id: "jobs", nav: "jobs" },
    { id: "veraya", nav: "jobs" },
    { id: "durham", nav: "durham" },
    { id: "sports", nav: "sports" },
  ];
  let active = "today";
  sections.forEach((item) => {
    const section = document.querySelector(`#${item.id}`);
    if (section && section.getBoundingClientRect().top <= anchor) active = item.nav;
  });
  navButtons.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.scroll === active);
  });
}

window.addEventListener(
  "scroll",
  () => {
    if (navScrollFrame) return;
    navScrollFrame = window.requestAnimationFrame(() => {
      navScrollFrame = 0;
      updateActiveNavigation();
    });
  },
  { passive: true },
);

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
refreshAllData(true);
window.setInterval(() => {
  updateClock();
  updateFocusTimer();
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
    navigator.serviceWorker.register("./sw.js?v=9").catch(() => {});
  });
}
