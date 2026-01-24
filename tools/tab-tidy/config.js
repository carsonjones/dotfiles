// Edit here, then hit reload on chrome://extensions

export const DEFAULT_SETTINGS = {
  dedupeEnabled: true,
  disabledRules: [], // rule.match values toggled off in popup
};

// Tabs created within this window are "new": eligible for dedupe
export const NEW_TAB_MS = 15_000;

// close-stale: tabs not viewed within this window get closed (pinned/active/audible kept)
export const STALE_TAB_MS = 60 * 60_000;

// Per-host sort overrides; default is site, then title. Each fn gets a URL
// group: key sorted before title; name: replaces title; then: tiebreak after title
const seg = (u, i) => u.pathname.split("/")[i] ?? "";
export const SORT_RULES = {
  // /document /presentation /spreadsheets each cluster, then title
  "docs.google.com": { group: (u) => seg(u, 1) },
  // /global/{hex|app}/<Name-ID>/...: same project's editing + public side by side
};

// Only dedupe freshly opened tabs; false = also close a tab that navigates to an already-open URL
export const DEDUPE_ONLY_NEW_TABS = true;

// match: hostname, also matches subdomains
// ignoreHash / ignoreQuery: drop those URL parts before comparing
// key(url): optional custom identity, overrides the flags
// navigateExisting: load the new tab's URL in the surviving tab (e.g. a linked thread/event)
const googleAccount = (app) => (u) =>
  `/${app}/u/${u.pathname.match(/\/u\/(\d+)/)?.[1] ?? "0"}`;

export const DEDUPE_RULES = [
  // one tab per account (u/0, u/1 kept separate)
  {
    match: "mail.google.com",
    key: googleAccount("mail"),
    navigateExisting: true,
  },
  {
    match: "calendar.google.com",
    key: googleAccount("calendar"),
    navigateExisting: true,
  },
  {
    match: "docs.google.com",
    // /document/d/<id>/edit?tab=...#heading=... -> same doc regardless of tab/heading/slide/gid
    key: (u) => u.pathname.match(/^\/\w+\/d\/[^/]+/)?.[0] ?? u.pathname,
  },
  {
    match: "linear.app",
    key: (u) =>
      u.pathname.match(/^\/[^/]+\/(issue|project|review)\/[^/]+/)?.[0] ??
      u.pathname,
  },
  { match: "github.com", ignoreHash: true },
];
