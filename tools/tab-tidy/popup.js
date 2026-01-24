import { DEFAULT_SETTINGS, DEDUPE_RULES } from "./config.js";

const settings = await chrome.storage.sync.get(DEFAULT_SETTINGS);
const save = () => chrome.storage.sync.set(settings);
const rulesEl = document.getElementById("rules");

const dedupeEl = document.getElementById("dedupeEnabled");
dedupeEl.checked = settings.dedupeEnabled;
dedupeEl.onchange = () => {
  settings.dedupeEnabled = dedupeEl.checked;
  rulesEl.classList.toggle("off", !settings.dedupeEnabled);
  save();
};
rulesEl.classList.toggle("off", !settings.dedupeEnabled);

for (const { match } of DEDUPE_RULES) {
  const label = document.createElement("label");
  const box = document.createElement("input");
  box.type = "checkbox";
  box.checked = !settings.disabledRules.includes(match);
  box.onchange = () => {
    settings.disabledRules = box.checked
      ? settings.disabledRules.filter((m) => m !== match)
      : [...settings.disabledRules, match];
    save();
  };
  label.append(match, box);
  rulesEl.append(label);
}

const win = await chrome.windows.getCurrent();
const counts = await chrome.runtime.sendMessage({ type: "preview", windowId: win.id });
for (const btn of document.querySelectorAll("button[data-action]")) {
  const n = counts[btn.dataset.action];
  if (n !== undefined) {
    btn.textContent = btn.dataset.label.replace("{n}", n);
    btn.disabled = n === 0;
  }
  btn.onclick = async () => {
    await chrome.runtime.sendMessage({ type: btn.dataset.action, windowId: win.id });
    window.close();
  };
}

const shortcutsEl = document.getElementById("shortcuts");
for (const cmd of await chrome.commands.getAll()) {
  if (!cmd.description) continue; // _execute_action
  const row = document.createElement("div");
  const key = document.createElement("b");
  key.textContent = cmd.shortcut || "not set";
  row.append(cmd.description, key);
  shortcutsEl.append(row);
}
document.getElementById("editShortcut").onclick = () =>
  chrome.tabs.create({ url: "chrome://extensions/shortcuts" });
