import { DEFAULT_SETTINGS, DEDUPE_ONLY_NEW_TABS, DEDUPE_RULES, NEW_TAB_MS, SORT_RULES, STALE_TAB_MS } from "./config.js";

const createdAt = new Map(); // tabId -> ms

const getSettings = () => chrome.storage.sync.get(DEFAULT_SETTINGS);
const isNew = (tabId) => Date.now() - (createdAt.get(tabId) ?? 0) < NEW_TAB_MS;

function host(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

// [site, host, group, name, then]: google subdomains cluster, SORT_RULES reshape the rest
function sortKey(tab) {
  const url = tab.url || tab.pendingUrl || "";
  const h = host(url);
  const rule = SORT_RULES[h];
  let u;
  try {
    u = new URL(url);
  } catch {}
  const apply = (fn, fallback = "") => (rule?.[fn] && u ? rule[fn](u) : fallback);
  return [h.split(".").slice(-2).join("."), h, apply("group"), apply("name", tab.title ?? ""), apply("then")];
}

function compareTabs(a, b) {
  const ka = sortKey(a);
  const kb = sortKey(b);
  return ka.reduce((cmp, k, i) => cmp || k.localeCompare(kb[i], undefined, { sensitivity: "base" }), 0);
}

// Sorts within each contiguous block (tab group or ungrouped run); pinned untouched
export async function sortWindow(windowId) {
  const tabs = (await chrome.tabs.query({ windowId })).filter((t) => !t.pinned);
  if (!tabs.length) return;
  const base = tabs[0].index;

  const blocks = [];
  for (const t of tabs) {
    const last = blocks.at(-1);
    if (last && last[0].groupId === t.groupId) last.push(t);
    else blocks.push([t]);
  }

  const desired = blocks.flatMap((block) => block.sort(compareTabs));

  const order = tabs.map((t) => t.id);
  for (const [i, t] of desired.entries()) {
    const cur = order.indexOf(t.id);
    if (cur === i) continue;
    await chrome.tabs.move(t.id, { index: base + i });
    order.splice(cur, 1);
    order.splice(i, 0, t.id);
  }
}

function findRule(url) {
  const h = host(url);
  return DEDUPE_RULES.find((r) => h === r.match || h.endsWith("." + r.match));
}

function dedupeKey(url, rule) {
  const u = new URL(url);
  if (rule.key) return u.hostname + rule.key(u);
  if (rule.ignoreHash) u.hash = "";
  if (rule.ignoreQuery) u.search = "";
  return u.hostname + u.pathname.replace(/\/$/, "") + u.search + u.hash;
}

// On-demand: keyed by DEDUPE_RULES where one matches, else exact URL. Keeps active > pinned > leftmost
async function duplicateIds(windowId) {
  const tabs = await chrome.tabs.query({ windowId });
  const rank = (t) => (t.active ? 0 : t.pinned ? 1 : 2);
  const keep = new Map(); // key -> tab
  for (const t of [...tabs].sort((a, b) => rank(a) - rank(b) || a.index - b.index)) {
    const url = t.url || t.pendingUrl;
    if (!url) continue;
    const rule = findRule(url);
    let key;
    try {
      key = rule ? dedupeKey(url, rule) : dedupeKey(url, {});
    } catch {
      key = url; // chrome://, about:blank, etc.
    }
    if (!keep.has(key)) keep.set(key, t);
  }
  const survivors = new Set([...keep.values()].map((t) => t.id));
  return tabs.filter((t) => !survivors.has(t.id) && (t.url || t.pendingUrl)).map((t) => t.id);
}

async function staleIds(windowId) {
  const cutoff = Date.now() - STALE_TAB_MS;
  const tabs = await chrome.tabs.query({ windowId });
  return tabs
    .filter((t) => !t.pinned && !t.active && !t.audible && (t.lastAccessed ?? Infinity) < cutoff)
    .map((t) => t.id);
}

// Flash "-N" on the toolbar icon so shortcut runs aren't silent
let badgeTimer;
async function closeTabs(ids) {
  if (ids.length) await chrome.tabs.remove(ids);
  clearTimeout(badgeTimer);
  await chrome.action.setBadgeText({ text: `-${ids.length}` });
  badgeTimer = setTimeout(() => chrome.action.setBadgeText({ text: "" }), 3000);
}

const ACTIONS = {
  "sort-tabs": sortWindow,
  "close-duplicates": async (w) => closeTabs(await duplicateIds(w)),
  "close-stale": async (w) => closeTabs(await staleIds(w)),
  preview: async (w) => ({ "close-duplicates": (await duplicateIds(w)).length, "close-stale": (await staleIds(w)).length }),
};

chrome.tabs.onCreated.addListener((tab) => createdAt.set(tab.id, Date.now()));

chrome.tabs.onRemoved.addListener((tabId) => createdAt.delete(tabId));

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo) => {
  if (!changeInfo.url) return;
  const rule = findRule(changeInfo.url);
  if (!rule) return;
  if (DEDUPE_ONLY_NEW_TABS && !isNew(tabId)) return;
  const settings = await getSettings();
  if (!settings.dedupeEnabled || settings.disabledRules.includes(rule.match)) return;

  const key = dedupeKey(changeInfo.url, rule);
  const existing = (await chrome.tabs.query({})).find((t) => {
    const url = t.url || t.pendingUrl;
    return t.id !== tabId && url && findRule(url) === rule && dedupeKey(url, rule) === key;
  });
  if (!existing) return;

  const existingUrl = existing.url || existing.pendingUrl;
  const navigate = rule.navigateExisting && existingUrl !== changeInfo.url;
  await chrome.tabs.update(existing.id, { active: true, ...(navigate && { url: changeInfo.url }) });
  await chrome.windows.update(existing.windowId, { focused: true });
  await chrome.tabs.remove(tabId);
});

chrome.commands.onCommand.addListener(async (command) => {
  if (!ACTIONS[command]) return;
  const win = await chrome.windows.getLastFocused();
  await ACTIONS[command](win.id);
});

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (!ACTIONS[msg.type]) return;
  ACTIONS[msg.type](msg.windowId).then((res) => reply(res ?? true));
  return true;
});
