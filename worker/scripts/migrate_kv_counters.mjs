const LEGACY_DAY = "1970-01-01";
const LEGACY_SOURCE = "legacy";
const LEGACY_PLACEMENT = "legacy";

/**
 * Reads the totals from the legacy KV-backed /v1/stats response. Only performs a GET.
 */
async function fetchLegacyTotals(statsUrl, statsKey) {
  const response = await fetch(statsUrl, { headers: { authorization: `Bearer ${statsKey}` } });
  if (!response.ok) throw new Error(`stats request failed: HTTP ${response.status}`);
  const body = await response.json();
  if (!body || typeof body.totals !== "object" || body.totals === null) {
    throw new Error("stats response has no totals object");
  }
  return body.totals;
}

/**
 * Quotes a value as a SQL string literal, doubling embedded single quotes.
 */
function sqlString(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

/**
 * Turns legacy { appId: { event: count } } totals into plain INSERT statements. A plain
 * INSERT (not an upsert) is deliberate: re-running the import fails on the primary key
 * instead of counting the legacy totals twice.
 */
function legacyInsertStatements(totals) {
  const statements = [];
  for (const [appId, events] of Object.entries(totals)) {
    for (const [event, count] of Object.entries(events || {})) {
      if (!Number.isSafeInteger(count) || count <= 0) continue;
      statements.push(
        `INSERT INTO counters (day, event, app_id, source, storefront, placement, n) VALUES ` +
          `(${sqlString(LEGACY_DAY)}, ${sqlString(event)}, ${sqlString(appId)}, ` +
          `${sqlString(LEGACY_SOURCE)}, '', ${sqlString(LEGACY_PLACEMENT)}, ${count});`
      );
    }
  }
  return statements;
}

/**
 * Prints the migration SQL to stdout for piping into `wrangler d1 execute`.
 */
async function main() {
  const statsUrl = process.env.MIDGAR_STATS_URL;
  const statsKey = process.env.MIDGAR_STATS_KEY;
  if (!statsUrl || !statsKey) {
    throw new Error("set MIDGAR_STATS_URL and MIDGAR_STATS_KEY");
  }
  const statements = legacyInsertStatements(await fetchLegacyTotals(statsUrl, statsKey));
  if (statements.length > 0) process.stdout.write(`${statements.join("\n")}\n`);
}

main().catch((error) => {
  process.stderr.write(`migrate_kv_counters: ${error.message}\n`);
  process.exitCode = 1;
});
