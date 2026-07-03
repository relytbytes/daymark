const STORAGE_KEY = "daymark-state-v1";

const initialApplications = [
  {
    id: "duke-policy",
    organization: "Duke University",
    role: "Policy Program Manager",
    status: "Interview",
    nextStep: "Prep stories · Fri",
  },
  {
    id: "public-affairs",
    organization: "City of Durham",
    role: "Public Affairs Specialist",
    status: "Applied",
    nextStep: "Follow up · Jul 8",
  },
  {
    id: "foundation",
    organization: "Triangle Community Foundation",
    role: "Strategy Associate",
    status: "Follow-up",
    nextStep: "Email Jamal · today",
  },
  {
    id: "dataworks",
    organization: "DataWorks NC",
    role: "Partnerships Lead",
    status: "Interested",
    nextStep: "Tailor résumé",
  },
];

const defaultState = {
  mode: getSuggestedMode(),
  tasks: {
    "veraya-interviews": true,
    "veraya-draft": true,
  },
  decisions: {},
  applications: initialApplications,
};

let state = loadState();
let toastTimer;

const body = document.body;
const modeButtons = [...document.querySelectorAll("[data-set-mode]")];
const taskInputs = [...document.querySelectorAll(".task-check")];
const navButtons = [...document.querySelectorAll(".nav-button")];
const applicationDialog = document.querySelector("#applicationDialog");
const applicationForm = document.querySelector("#applicationForm");

function getSuggestedMode() {
  const hour = new Date().getHours();
  return hour >= 20 || hour < 6 ? "evening" : "morning";
}

function loadState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    return {
      ...defaultState,
      ...saved,
      mode: getSuggestedMode(),
      tasks: { ...defaultState.tasks, ...(saved?.tasks || {}) },
      decisions: { ...defaultState.decisions, ...(saved?.decisions || {}) },
      applications: Array.isArray(saved?.applications) ? saved.applications : initialApplications,
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

function setMode(mode, announce = false) {
  state.mode = mode;
  body.dataset.mode = mode;
  modeButtons.forEach((button) => {
    const active = button.dataset.setMode === mode;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });

  const title = document.querySelector("#heroTitle");
  title.textContent = mode === "morning" ? "Good morning, Ty." : "Good evening, Ty.";
  saveState();
  updateBriefProgress();

  if (announce) {
    showToast(mode === "morning" ? "Morning plan is up." : "Evening reset is up.");
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
  const selector = state.mode === "morning" ? "#morningActions .task-check" : "#eveningActions .task-check";
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

modeButtons.forEach((button) => {
  button.addEventListener("click", () => setMode(button.dataset.setMode, true));
});

document.querySelectorAll("[data-scroll]").forEach((button) => {
  button.addEventListener("click", () => {
    const id = button.dataset.scroll;
    document.querySelector(`#${id}`)?.scrollIntoView({ behavior: "smooth", block: "start" });
    if (button.classList.contains("nav-button")) {
      navButtons.forEach((item) => item.classList.toggle("is-active", item === button));
    }
  });
});

document.querySelector("#refreshBrief").addEventListener("click", (event) => {
  const button = event.currentTarget;
  const sync = document.querySelector("#syncState");
  const label = sync.querySelector(".sync-label");
  button.classList.add("is-spinning");
  sync.classList.add("is-refreshing");
  label.textContent = "checking";
  window.setTimeout(() => {
    button.classList.remove("is-spinning");
    sync.classList.remove("is-refreshing");
    label.textContent = "just updated";
    showToast("Brief checked. Nothing urgent changed.");
  }, 850);
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
setMode(state.mode);
updateSprintProgress();

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  });
}
