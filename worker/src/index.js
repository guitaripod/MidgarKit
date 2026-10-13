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
      return handleCatalog(request, url, env);
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
        endpoints: ["/v1/catalog", "/v1/event", "/v1/stats"],
        apps: defaultCatalog.apps.length,
      });
    }
    return json({ error: "not_found" }, 404);
  },
};

async function loadCatalog(env) {
  if (env && env.MIDGAR) {
    const override = await env.MIDGAR.get("catalog", "json").catch(() => null);
    if (override && Array.isArray(override.apps)) return override;
  }
  return defaultCatalog;
}

async function handleCatalog(request, url, env) {
  const catalog = await loadCatalog(env);
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

  const etag = `"${catalog.version}-${catalog.updatedAt || ""}-${[...exclude].sort().join(",")}"`;
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
