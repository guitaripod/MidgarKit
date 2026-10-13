import defaultCatalog from "../catalog.json";

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,POST,OPTIONS",
  "access-control-allow-headers": "content-type,authorization",
};

const CATALOG_CACHE = "public, max-age=60, s-maxage=60, stale-while-revalidate=600";
const VALID_EVENTS = new Set(["impression", "tap", "loaded", "launch", "portal_open"]);
const MAX_APP_ID_LENGTH = 12;
const DISCOVERED_KEY = "discovered";
const DISCOVERED_TTL_SECONDS = 14 * 24 * 60 * 60;
const DEVELOPER_PAGE_URL = "https://apps.apple.com/us/developer/midgar-oy/id";
const PAGE_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
const SERVER_DATA_PATTERN = /<script[^>]*id="serialized-server-data"[^>]*>([\s\S]*?)<\/script>/;
const ICON_SIZE = 512;
const TAGLINE_LIMIT = 60;
const DISCOVERED_ORDER_BASE = 100;
const DISCOVERED_VALUE = 0.4;
const ACCENT_SATURATION = 0.62;
const ACCENT_LIGHTNESS = 0.58;
const UNKNOWN_SOURCE = "unknown";
const EMPTY_STOREFRONT = "";
const DEFAULT_PLACEMENT = "settings";
const SOURCE_PATTERN = /^[A-Za-z0-9._-]{1,100}$/;
const STOREFRONT_PATTERN = /^[A-Za-z]{2}$/;
const PLACEMENT_PATTERN = /^[a-z0-9_-]{1,24}$/;
const DAY_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const STATS_COLUMNS = new Map([
  ["app", "app_id"],
  ["source", "source"],
  ["storefront", "storefront"],
  ["placement", "placement"],
  ["day", "day"],
]);
const INSERT_COUNTER_SQL =
  "INSERT INTO counters (day, event, app_id, source, storefront, placement, n) VALUES (?,?,?,?,?,?,1) " +
  "ON CONFLICT(day,event,app_id,source,storefront,placement) DO UPDATE SET n = n + 1";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: JSON_HEADERS });
    }
    if (url.pathname === "/v1/catalog" && request.method === "GET") {
      return handleCatalog(request, url, env, ctx);
    }
    if (url.pathname === "/v1/discovered/refresh" && request.method === "POST") {
      return handleDiscoveredRefresh(request, url, env);
    }
    if (url.pathname === "/v1/discovered" && request.method === "GET") {
      return handleDiscovered(env);
    }
    if (url.pathname === "/v1/event" && request.method === "POST") {
      return handleEvent(request, env, ctx);
    }
    if (url.pathname === "/v1/stats" && request.method === "GET") {
      return handleStats(request, url, env);
    }
    if (url.pathname === "/" || url.pathname === "/health") {
      return json({
        service: "midgar-catalog",
        endpoints: ["/v1/catalog", "/v1/discovered", "/v1/event", "/v1/stats"],
        apps: defaultCatalog.apps.length,
      });
    }
    return json({ error: "not_found" }, 404);
  },

  async scheduled(event, env, ctx) {
    await refreshDiscovered(env);
  },
};

let bootstrapStarted = false;

/**
 * Returns the curated catalog: the `catalog` KV override when it has an apps array,
 * otherwise the bundled catalog.json.
 */
async function loadCuratedCatalog(env) {
  if (env && env.MIDGAR) {
    const override = await env.MIDGAR.get("catalog", "json").catch(() => null);
    if (override && Array.isArray(override.apps)) return override;
  }
  return defaultCatalog;
}

/**
 * Returns the stored `{updatedAt, apps}` discovery object, or null when KV has none yet.
 */
async function readDiscovered(env) {
  if (!env || !env.MIDGAR) return null;
  const stored = await env.MIDGAR.get(DISCOVERED_KEY, "json").catch(() => null);
  return stored && Array.isArray(stored.apps) ? stored : null;
}

/**
 * Merges the curated catalog with the discovered apps. Curated entries always win; a
 * discovered entry is added only when neither its appId nor its bundleId is curated and
 * its bundleId is not listed in the curated catalog's optional `hide` array. The merged
 * catalog carries `discoveredAt` so callers can fold it into cache validators.
 */
async function loadCatalog(env, discovered) {
  const curated = await loadCuratedCatalog(env);
  const found = discovered === undefined ? await readDiscovered(env) : discovered;
  const appIds = new Set(curated.apps.map((app) => String(app.appId)));
  const bundleIds = new Set(curated.apps.map((app) => String(app.bundleId).toLowerCase()));
  const hidden = new Set((Array.isArray(curated.hide) ? curated.hide : []).map((id) => String(id).toLowerCase()));
  const extra = ((found && found.apps) || []).filter((app) => {
    const bundleId = String(app.bundleId).toLowerCase();
    return !appIds.has(String(app.appId)) && !bundleIds.has(bundleId) && !hidden.has(bundleId);
  });
  return { ...curated, apps: [...curated.apps, ...extra], discoveredAt: (found && found.updatedAt) || "" };
}

async function handleCatalog(request, url, env, ctx) {
  const discovered = await readDiscovered(env);
  if (!discovered && ctx && !bootstrapStarted) {
    bootstrapStarted = true;
    ctx.waitUntil(refreshDiscovered(env).then((stored) => { bootstrapStarted = stored !== null; }));
  }
  const catalog = await loadCatalog(env, discovered);
  const exclude = new Set(
    (url.searchParams.get("exclude") || "")
      .split(",")
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean)
  );
  const seen = new Set();
  const apps = catalog.apps
    .filter((app) => !exclude.has(String(app.bundleId).toLowerCase()))
    .filter((app) => {
      const id = String(app.appId);
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    })
    .sort((a, b) => (a.order ?? 999) - (b.order ?? 999));

  const etag = `"${catalog.version}-${catalog.updatedAt || ""}-${catalog.discoveredAt}-${[...exclude].sort().join(",")}"`;
  if (request.headers.get("if-none-match") === etag) {
    return new Response(null, {
      status: 304,
      headers: { ...JSON_HEADERS, etag, "cache-control": CATALOG_CACHE },
    });
  }

  return json(
    { version: catalog.version, updatedAt: catalog.updatedAt, developer: catalog.developer, apps },
    200,
    { "cache-control": CATALOG_CACHE, etag }
  );
}

/**
 * Forces a discovery run and reports what the App Store answered, for the stats key holder.
 */
async function handleDiscoveredRefresh(request, url, env) {
  if (!env || !env.STATS_KEY) return json({ error: "stats_unconfigured" }, 503);
  if (!authorized(request, url, env)) return json({ error: "unauthorized" }, 401);
  const report = {};
  const stored = await refreshDiscovered(env, report);
  return json({ stored: Boolean(stored), report }, 200, { "cache-control": "no-store" });
}

async function handleDiscovered(env) {
  const discovered = await readDiscovered(env);
  return json(discovered || { updatedAt: null, apps: [] }, 200, { "cache-control": "no-store" });
}

/**
 * Reads the developer's public App Store page, which lists every live app with its bundle id,
 * subtitle and icon, and stores one catalog entry per app. The lookup API answers 403 to
 * Workers, the page does not. A failed or empty read keeps the previous value.
 */
async function refreshDiscovered(env, report = {}) {
  if (!env || !env.MIDGAR) return null;
  try {
    const curated = await loadCuratedCatalog(env);
    const artistId = String(curated.developer && curated.developer.artistId);
    const developerName = String((curated.developer && curated.developer.name) || "Midgar");
    const response = await fetch(`${DEVELOPER_PAGE_URL}${encodeURIComponent(artistId)}`, {
      headers: { "user-agent": PAGE_USER_AGENT, "accept-language": "en-US" },
    });
    report.status = response.status;
    if (!response.ok) return null;
    const lockups = developerLockups(await response.text(), developerName);
    report.lockups = lockups.length;
    const apps = lockups.map((lockup, index) => discoveredEntry(lockup, index));
    if (apps.length === 0) return null;
    const stored = { updatedAt: new Date().toISOString(), apps };
    await env.MIDGAR.put(DISCOVERED_KEY, JSON.stringify(stored), { expirationTtl: DISCOVERED_TTL_SECONDS });
    return stored;
  } catch (error) {
    report.error = String(error);
    console.error("discovery_failed", error);
    return null;
  }
}

/**
 * Pulls the app lockups out of the page's serialized server data: objects of kind Lockup that
 * carry an adamId, a bundle id and a title and belong to the developer. Deduplicated by adamId.
 */
function developerLockups(html, developerName) {
  const match = SERVER_DATA_PATTERN.exec(html);
  if (!match) return [];
  const found = new Map();
  const visit = (node) => {
    if (Array.isArray(node)) {
      node.forEach(visit);
    } else if (node && typeof node === "object") {
      if (isDeveloperLockup(node, developerName) && !found.has(String(node.adamId))) {
        found.set(String(node.adamId), node);
      }
      Object.values(node).forEach(visit);
    }
  };
  visit(JSON.parse(match[1]));
  return [...found.values()];
}

function isDeveloperLockup(node, developerName) {
  return (
    node.$kind === "Lockup" &&
    Boolean(node.adamId) &&
    Boolean(node.bundleId) &&
    Boolean(node.title) &&
    typeof node.developerName === "string" &&
    node.developerName.startsWith(developerName)
  );
}

function discoveredEntry(lockup, index) {
  const appId = String(lockup.adamId);
  const fields = (lockup.impressionMetrics && lockup.impressionMetrics.fields) || {};
  const subtitle = typeof lockup.subtitle === "string" ? lockup.subtitle.trim() : "";
  return {
    appId,
    bundleId: lockup.bundleId,
    name: lockup.title,
    tagline: subtitle || null,
    genre: null,
    accent: accentFor(appId),
    featured: false,
    order: DISCOVERED_ORDER_BASE + index,
    icon: artworkURL(lockup.icon),
    screenshots: [],
    platforms: String(fields.kind).toLowerCase() === "macsoftware" ? ["mac"] : ["ios"],
    topics: [],
    related: [],
    value: DISCOVERED_VALUE,
    status: "live",
    auto: true,
  };
}

/**
 * Builds a 512 point icon URL from the page's artwork template, or null when it has none.
 */
function artworkURL(artwork) {
  if (!artwork || typeof artwork.template !== "string") return null;
  return artwork.template
    .replace("{w}", String(ICON_SIZE))
    .replace("{h}", String(ICON_SIZE))
    .replace("{c}", "bb")
    .replace("{f}", "png");
}

/**
 * Deterministic `#RRGGBB` accent: hue from an FNV-1a hash of the app id, fixed
 * saturation and lightness.
 */
function accentFor(appId) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < appId.length; i++) {
    hash ^= appId.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hslToHex((hash % 360) / 360, ACCENT_SATURATION, ACCENT_LIGHTNESS);
}

function hslToHex(h, s, l) {
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const channel = (t) => {
    const x = (t + 1) % 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  };
  const hex = (v) => Math.round(v * 255).toString(16).padStart(2, "0");
  return `#${hex(channel(h + 1 / 3))}${hex(channel(h))}${hex(channel(h - 1 / 3))}`.toUpperCase();
}

async function handleEvent(request, env, ctx) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const counter = parseCounter(body);
  if (!counter) return json({ error: "invalid_event" }, 400);
  if (env && env.DB) ctx.waitUntil(recordCounter(env.DB, counter));
  return new Response(null, { status: 204, headers: JSON_HEADERS });
}

/**
 * Validates a telemetry body and normalises its optional dimensions. Returns null when
 * the event name or app id is unusable; an unusable source, storefront or placement
 * falls back to its default instead of rejecting the event.
 */
function parseCounter(body) {
  const fields = body && typeof body === "object" ? body : {};
  const event = String(fields.event || "").toLowerCase();
  const appId = String(fields.appId || "").replace(/[^0-9]/g, "");
  if (!VALID_EVENTS.has(event) || !appId || appId.length > MAX_APP_ID_LENGTH) return null;
  return {
    day: utcDay(),
    event,
    appId,
    source: matchOrDefault(fields.source, SOURCE_PATTERN, UNKNOWN_SOURCE),
    storefront: normalizeStorefront(fields.storefront),
    placement: matchOrDefault(fields.placement, PLACEMENT_PATTERN, DEFAULT_PLACEMENT),
  };
}

function utcDay() {
  return new Date().toISOString().slice(0, 10);
}

function matchOrDefault(value, pattern, fallback) {
  return typeof value === "string" && pattern.test(value) ? value : fallback;
}

function normalizeStorefront(value) {
  return typeof value === "string" && STOREFRONT_PATTERN.test(value)
    ? value.toLowerCase()
    : EMPTY_STOREFRONT;
}

async function recordCounter(db, counter) {
  try {
    await db
      .prepare(INSERT_COUNTER_SQL)
      .bind(counter.day, counter.event, counter.appId, counter.source, counter.storefront, counter.placement)
      .run();
  } catch (error) {
    console.error("counter_write_failed", error);
  }
}

function authorized(request, url, env) {
  const header = request.headers.get("authorization") || "";
  const bearer = header.startsWith("Bearer ") ? header.slice(7) : "";
  const key = bearer || url.searchParams.get("key") || "";
  return key.length > 0 && key === env.STATS_KEY;
}

async function handleStats(request, url, env) {
  if (!env || !env.DB) return json({ error: "no_storage" }, 503);
  if (!env.STATS_KEY) return json({ error: "stats_unconfigured" }, 503);
  if (!authorized(request, url, env)) return json({ error: "unauthorized" }, 401);

  const query = parseStatsQuery(url);
  if (!query) return json({ error: "invalid_query" }, 400);
  const { results } = await env.DB.prepare(query.sql).bind(...query.binds).all();
  return json({ totals: totalsFromRows(results) });
}

/**
 * Builds the aggregate query for /v1/stats. The grouping column comes only from the
 * STATS_COLUMNS allowlist, and every user-supplied value is bound as a parameter.
 * Returns null when `by` or `since` is not recognised.
 */
function parseStatsQuery(url) {
  const column = STATS_COLUMNS.get(url.searchParams.get("by") || "app");
  const since = url.searchParams.get("since") || "";
  const app = url.searchParams.get("app") || "";
  if (!column) return null;
  if (since && !DAY_PATTERN.test(since)) return null;

  const clauses = [];
  const binds = [];
  if (since) {
    clauses.push("day >= ?");
    binds.push(since);
  }
  if (app) {
    clauses.push("app_id = ?");
    binds.push(app);
  }
  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  const sql = `SELECT ${column} AS dimension, event, SUM(n) AS n FROM counters ${where} GROUP BY ${column}, event`;
  return { sql, binds };
}

function totalsFromRows(rows) {
  const totals = {};
  for (const row of rows) {
    const key = String(row.dimension);
    totals[key] = totals[key] || {};
    totals[key][row.event] = (totals[key][row.event] || 0) + Number(row.n);
  }
  return totals;
}

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...JSON_HEADERS, ...extra },
  });
}
