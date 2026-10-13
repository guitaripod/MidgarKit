CREATE TABLE counters (
  day TEXT NOT NULL,
  event TEXT NOT NULL,
  app_id TEXT NOT NULL,
  source TEXT NOT NULL,
  storefront TEXT NOT NULL,
  placement TEXT NOT NULL,
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, app_id, source, storefront, placement)
) WITHOUT ROWID;

CREATE INDEX counters_app_day ON counters (app_id, day);
