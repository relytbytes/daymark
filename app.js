const STORAGE_KEY = "daymark-state-v1";
const WEATHER_CACHE_KEY = "daymark-weather-cache-v1";
const BASEBALL_CACHE_KEY = "daymark-baseball-cache-v1";
const REFRESH_INTERVAL_MS = 15 * 60 * 1000;
const DEMO_APPLICATION_IDS = new Set(["duke-policy", "public-affairs", "foundation", "dataworks"]);
const initialApplications = [];

const defaultState = {
  tasks: {
    "veraya-interviews": true,
    "veraya-draft": true,
  },
  decisions: {},
  applications: initialApplications,
};

let state = loadState();
let toastTimer;
let lastRefreshAt = new Date();
let liveRefreshInFlight = false;
let liveFeedCount = 0;

const body = document.body;
const taskInputs = [...document.querySelectorAll(".task-check")];
const navButtons = [...document.querySelectorAll(".nav-button")];
const applicationDialog = document.querySelector("#applicationDialog");
const applicationForm = document.querySelector("#applicationForm");

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
    return {
      ...defaultState,
      ...saved,
      tasks: { ...defaultState.tasks, ...(saved?.tasks || {}) },
      decisions: { ...defaultState.decisions, ...(saved?.decisions || {}) },
      applications: Array.isArray(saved?.applications)
        ? saved.applications.filter((application) => !DEMO_APPLICATION_IDS.has(application.id))
        : initialApplications,
    };
  } catch {
    return { ...defaultState };
  }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function formatDate() {
  const date = new Date();
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
  document.querySelector("#tomorrowTitle").textContent = `${tomorrowName} begins clean.`;

  const startOfYear = new Date(date.getFullYear(), 0, 1);
  const week = Math.ceil(((date - startOfYear) / 86400000 + startOfYear.getDay() + 1) / 7);
  document.querySelector("#weekLabel").textContent = `WEEK ${week}`;
}

function updateLiveDay(date = new Date()) {
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
  document.querySelector("#currentTime").textContent = new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
  }).format(date);

  const dayStart = new Date(date);
  dayStart.setHours(5, 0, 0, 0);
  const dayEnd = new Date(date);
  dayEnd.setHours(23, 0, 0, 0);
  const progress = Math.max(0, Math.min(100, ((date - dayStart) / (dayEnd - dayStart)) * 100));
  document.querySelector("#dayProgress").style.width = `${progress}%`;

  updateRefreshCountdown(date);
  updateBriefProgress();
}

function updateRefreshCountdown(date = new Date()) {
  const elapsed = date - lastRefreshAt;
  if (elapsed >= REFRESH_INTERVAL_MS && !liveRefreshInFlight) fetchLiveData();
  const nextMinutes = Math.max(1, Math.ceil((REFRESH_INTERVAL_MS - elapsed) / 60000));
  document.querySelector("#nextRefresh").textContent = `refreshes in ${nextMinutes} min`;
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

function renderWeather(data, source = "live") {
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
  document.querySelector("#weatherSource").textContent = source === "live" ? "LIVE NOW" : "CACHED";
  document.querySelector("#weatherCurrent").textContent = `${current}°`;
  document.querySelector("#weatherSummary").textContent = `${description}${feelsText}`;
  document.querySelector("#weatherHigh").textContent = `${high}°`;
  document.querySelector("#weatherRain").textContent = `${rain}%`;
  document.querySelector("#weatherSunset").textContent = sunset;
}

function renderWeatherError() {
  document.querySelector("#heroWeather").innerHTML =
    '<i class="weather-glyph" aria-hidden="true">!</i> Weather unavailable';
  document.querySelector("#weatherSource").textContent = "UNAVAILABLE";
  document.querySelector("#weatherSummary").textContent = "Could not reach the weather source.";
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

function getTeamDotClass(abbreviation) {
  return {
    LAD: "team-dot--la",
    AZ: "team-dot--az",
    SD: "team-dot--sd",
    SF: "team-dot--sf",
    COL: "team-dot--col",
  }[abbreviation] || "";
}

function renderBaseball(standingsData, scheduleData, source = "live") {
  const division = standingsData.records.find((record) => record.division?.id === 203);
  if (!division) throw new Error("NL West standings were missing.");

  const teams = [...division.teamRecords].sort(
    (a, b) => Number(a.divisionRank) - Number(b.divisionRank),
  );
  const standingsRows = document.querySelector("#standingsRows");
  standingsRows.innerHTML = teams
    .map((record) => {
      const abbreviation = record.team.abbreviation;
      const favoriteClass = record.team.id === 109 ? " is-favorite" : "";
      const gamesBack = record.divisionGamesBack === "-" ? "—" : record.divisionGamesBack;
      return `
        <div class="standing-row${favoriteClass}">
          <span><i class="team-dot ${getTeamDotClass(abbreviation)}"></i>${escapeHtml(getTeamDisplay(record.team))}</span>
          <span>${record.wins}–${record.losses}</span>
          <span>${escapeHtml(gamesBack)}</span>
        </div>
      `;
    })
    .join("");

  const arizona = teams.find((record) => record.team.id === 109);
  if (arizona) {
    const wildcard = arizona.wildCardRank
      ? `WC #${arizona.wildCardRank} · ${arizona.wildCardGamesBack === "-" ? "IN" : `${arizona.wildCardGamesBack} GB`}`
      : "WILD CARD: —";
    document.querySelector("#wildCardStatus").textContent = wildcard;
  }

  const games = scheduleData.dates.flatMap((date) => date.games || []);
  const today = formatApiDate(new Date());
  const game =
    games.find((item) => item.officialDate === today) ||
    games.find((item) => new Date(item.gameDate) >= new Date());

  if (game) renderDiamondbacksGame(game);
  else renderNoDiamondbacksGame();

  document.querySelector("#sportsSource").textContent =
    source === "live" ? "LIVE · OFFICIAL MLB" : "CACHED · MLB";
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
  document.querySelector("#gameTime").textContent = "DIAMONDBACKS";
  document.querySelector("#gameOpponent").textContent = "No upcoming game found";
  document.querySelector("#gameDetail").textContent = "Open the official schedule for more.";
  document.querySelector("#gameStatus").textContent = "MLB";
}

function renderBaseballError() {
  document.querySelector("#sportsSource").textContent = "MLB DATA UNAVAILABLE";
  document.querySelector("#wildCardStatus").textContent = "WILD CARD: UNAVAILABLE";
  document.querySelector("#standingsRows").innerHTML =
    '<div class="standing-row standings-loading"><span>Could not reach MLB.</span><span>—</span><span>—</span></div>';
  document.querySelector("#gameOpponent").textContent = "MLB data unavailable";
  document.querySelector("#gameDetail").textContent = "Tap to open the official schedule.";
}

async function fetchLiveData(announce = false) {
  if (liveRefreshInFlight) return;
  liveRefreshInFlight = true;
  const sync = document.querySelector("#syncState");
  const syncLabel = sync.querySelector(".sync-label");
  sync.classList.add("is-refreshing");
  syncLabel.textContent = "updating";

  const now = new Date();
  const end = new Date(now);
  end.setDate(now.getDate() + 10);
  const season = now.getFullYear();
  const weatherUrl =
    "https://api.open-meteo.com/v1/forecast?latitude=35.9940&longitude=-78.8986" +
    "&current=temperature_2m,apparent_temperature,weather_code" +
    "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunset" +
    "&temperature_unit=fahrenheit&timezone=America%2FNew_York&forecast_days=2";
  const standingsUrl =
    `https://statsapi.mlb.com/api/v1/standings?leagueId=104&season=${season}` +
    "&standingsTypes=regularSeason&hydrate=team,division";
  const scheduleUrl =
    `https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=109` +
    `&startDate=${formatApiDate(now)}&endDate=${formatApiDate(end)}` +
    "&hydrate=probablePitcher,team";

  const [weatherResult, standingsResult, scheduleResult] = await Promise.allSettled([
    fetchJson(weatherUrl),
    fetchJson(standingsUrl),
    fetchJson(scheduleUrl),
  ]);

  liveFeedCount = 0;
  if (weatherResult.status === "fulfilled") {
    renderWeather(weatherResult.value);
    writeLiveCache(WEATHER_CACHE_KEY, weatherResult.value);
    liveFeedCount += 1;
  } else {
    const cached = readLiveCache(WEATHER_CACHE_KEY);
    if (cached?.data) renderWeather(cached.data, "cached");
    else renderWeatherError();
  }

  if (standingsResult.status === "fulfilled" && scheduleResult.status === "fulfilled") {
    renderBaseball(standingsResult.value, scheduleResult.value);
    writeLiveCache(BASEBALL_CACHE_KEY, {
      standings: standingsResult.value,
      schedule: scheduleResult.value,
    });
    liveFeedCount += 1;
  } else {
    const cached = readLiveCache(BASEBALL_CACHE_KEY);
    if (cached?.data) renderBaseball(cached.data.standings, cached.data.schedule, "cached");
    else renderBaseballError();
  }

  lastRefreshAt = new Date();
  liveRefreshInFlight = false;
  sync.classList.remove("is-refreshing");
  syncLabel.textContent = `${liveFeedCount}/2 live`;
  updateRefreshCountdown(lastRefreshAt);
  if (announce) {
    showToast(
      liveFeedCount === 2
        ? "Weather and MLB data are current."
        : `${liveFeedCount} of 2 live feeds updated.`,
    );
  }
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
  document.querySelector("#briefPercent").textContent = `${percentage}%`;
  document.querySelector("#priorityCount").textContent = `${done}/${total}`;
  document.querySelector("#openCount").textContent = String(total - done + 2);
}

function updateSprintProgress() {
  const sprintInputs = [...document.querySelectorAll(".sprint-tasks .task-check")];
  const done = sprintInputs.filter((input) => input.checked).length;
  const percentage = Math.round((done / sprintInputs.length) * 100);
  document.querySelector("#sprintPercent").textContent = `${percentage}%`;
  document.querySelector("#sprintTrack").style.width = `${percentage}%`;
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
        showToast(`${button.dataset.choice} saved. Decision off your mind.`);
      });
    });
    card.classList.toggle("is-decided", Boolean(selected));
  });
}

function renderApplications() {
  const list = document.querySelector("#applicationList");
  list.replaceChildren();

  if (state.applications.length === 0) {
    const empty = document.createElement("div");
    empty.className = "tracker-empty";
    empty.innerHTML = "<strong>No applications yet</strong><small>Add the first real role you want to track.</small>";
    list.append(empty);
  }

  state.applications.forEach((app) => {
    const row = document.createElement("div");
    row.className = "application-row";
    row.innerHTML = `
      <div>
        <strong>${escapeHtml(app.role)}</strong>
        <small>${escapeHtml(app.organization)} · <span class="application-next">${escapeHtml(app.nextStep || "Choose next step")}</span></small>
      </div>
      <button class="status-button" type="button" data-status="${escapeHtml(app.status)}" aria-label="Change status for ${escapeHtml(app.role)}">${escapeHtml(app.status)}</button>
    `;
    row.querySelector(".status-button").addEventListener("click", () => cycleApplicationStatus(app.id));
    list.append(row);
  });

  const active = state.applications.length;
  const followups = state.applications.filter((app) => app.status === "Follow-up").length;
  const interviews = state.applications.filter((app) => app.status === "Interview").length;
  document.querySelector("#activeApps").textContent = String(active);
  document.querySelector("#followupApps").textContent = String(followups);
  document.querySelector("#interviewApps").textContent = String(interviews);
  const stageWeight = { Interested: 20, Applied: 45, "Follow-up": 65, Interview: 90 };
  const averageProgress = active
    ? Math.round(
        state.applications.reduce((sum, app) => sum + (stageWeight[app.status] || 0), 0) / active,
      )
    : 0;
  document.querySelector(".tracker-progress-fill").style.width = `${averageProgress}%`;
}

function cycleApplicationStatus(id) {
  const order = ["Interested", "Applied", "Follow-up", "Interview"];
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
      navButtons.forEach((item) => item.classList.toggle("is-active", item === button));
    }
  });
});

document.querySelector("#refreshBrief").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  button.classList.add("is-spinning");
  try {
    await fetchLiveData(true);
  } finally {
    button.classList.remove("is-spinning");
  }
});

document.querySelector("#openApplicationDialog").addEventListener("click", () => {
  applicationDialog.showModal();
  window.setTimeout(() => applicationForm.elements.organization.focus(), 80);
});

document.querySelector("#closeApplicationDialog").addEventListener("click", () => {
  applicationDialog.close();
});

applicationDialog.addEventListener("click", (event) => {
  if (event.target === applicationDialog) applicationDialog.close();
});

applicationForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const formData = new FormData(applicationForm);
  state.applications.unshift({
    id: `app-${Date.now()}`,
    organization: formData.get("organization").trim(),
    role: formData.get("role").trim(),
    status: formData.get("status"),
    nextStep: formData.get("nextStep").trim() || "Choose next step",
  });
  saveState();
  renderApplications();
  applicationForm.reset();
  applicationDialog.close();
  showToast("Application added to your tracker.");
});

const sectionObserver = new IntersectionObserver(
  (entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting)
      .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
    if (!visible) return;
    const map = { today: "today", jobs: "jobs", veraya: "jobs", durham: "durham", sports: "sports" };
    const activeTarget = map[visible.target.id];
    if (!activeTarget) return;
    navButtons.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.scroll === activeTarget);
    });
  },
  { rootMargin: "-20% 0px -65% 0px", threshold: [0, 0.2, 0.5] },
);

["today", "jobs", "veraya", "durham", "sports"].forEach((id) => {
  const section = document.querySelector(`#${id}`);
  if (section) sectionObserver.observe(section);
});

formatDate();
hydrateTasks();
hydrateDecisions();
renderApplications();
updateLiveDay();
updateSprintProgress();
fetchLiveData();
window.setInterval(() => updateLiveDay(), 30000);

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js?v=4").catch(() => {});
  });
}
