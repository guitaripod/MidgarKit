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
const LOOKUP_URL = "https://itunes.apple.com/lookup";
const LOOKUP_USER_AGENT = "midgar-catalog/1.0";
const LOOKUP_KINDS = new Set(["software", "mac-software"]);
const TAGLINE_LIMIT = 60;
const SCREENSHOT_LIMIT = 5;
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

async function handleDiscovered(env) {
  const discovered = await readDiscovered(env);
  return json(discovered || { updatedAt: null, apps: [] }, 200, { "cache-control": "no-store" });
}

/**
 * Looks up the developer's live apps on the iTunes lookup API and stores them in the
 * `discovered` KV key. A failed fetch or an empty result keeps the previous value.
 * Returns the stored object, or null when nothing was written.
 */
async function refreshDiscovered(env) {
  if (!env || !env.MIDGAR) return null;
  try {
    const curated = await loadCuratedCatalog(env);
    const artistId = String(curated.developer && curated.developer.artistId);
    const response = await fetch(
      `${LOOKUP_URL}?id=${encodeURIComponent(artistId)}&entity=software&country=us&limit=200`,
      { headers: { "user-agent": LOOKUP_USER_AGENT } }
    );
    if (!response.ok) return null;
    const payload = await response.json();
    const apps = (Array.isArray(payload.results) ? payload.results : [])
      .filter((result) => isDeveloperSoftware(result, artistId))
      .map((result, index) => discoveredEntry(result, index));
    if (apps.length === 0) return null;
    const stored = { updatedAt: new Date().toISOString(), apps };
    await env.MIDGAR.put(DISCOVERED_KEY, JSON.stringify(stored), { expirationTtl: DISCOVERED_TTL_SECONDS });
    return stored;
  } catch (error) {
    console.error("discovery_failed", error);
    return null;
  }
}

/**
 * True for a lookup result that is a software product of the given developer with the
 * fields a catalog entry needs.
 */
function isDeveloperSoftware(result, artistId) {
  if (!result || typeof result !== "object") return false;
  const software = result.wrapperType === "software" || LOOKUP_KINDS.has(result.kind);
  return (
    software &&
    String(result.artistId) === artistId &&
    Boolean(result.trackId) &&
    Boolean(result.bundleId) &&
    Boolean(result.trackName)
  );
}

/**
 * Builds a catalog entry with sensible defaults from one iTunes lookup software result.
 */
function discoveredEntry(result, index) {
  const appId = String(result.trackId);
  const genre = result.primaryGenreName || "";
  return {
    appId,
    bundleId: result.bundleId,
    name: result.trackName,
    tagline: taglineFrom(result.description, genre),
    genre,
    accent: accentFor(appId),
    featured: false,
    order: DISCOVERED_ORDER_BASE + index,
    icon: null,
    screenshots: Array.isArray(result.screenshotUrls) ? result.screenshotUrls.slice(0, SCREENSHOT_LIMIT) : [],
    platforms: result.kind === "mac-software" ? ["mac"] : ["ios"],
    topics: genre ? [genre.toLowerCase()] : [],
    related: [],
    value: DISCOVERED_VALUE,
    status: "live",
    auto: true,
  };
}

/**
 * First sentence of a description, cut to TAGLINE_LIMIT characters on a word boundary.
 * Falls back to the genre when the description has no usable text.
 */
function taglineFrom(description, fallback) {
  const text = String(description || "").trim();
  const sentence = (text.match(/^[^\n]*?(?:[.!?](?=\s|$)|(?=\n|$))/) || [""])[0].trim();
  if (!sentence) return fallback;
  if (sentence.length <= TAGLINE_LIMIT) return sentence;
  const cut = sentence.slice(0, TAGLINE_LIMIT + 1);
  const boundary = cut.lastIndexOf(" ");
  const trimmed = (boundary > 0 ? cut.slice(0, boundary) : cut.slice(0, TAGLINE_LIMIT)).replace(/[\s,;:.\-]+$/, "");
  return trimmed || fallback;
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
