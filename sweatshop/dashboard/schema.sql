-- One row per lane: the driver's latest snapshot, stamped by the server.
-- receivedAt is the server's clock (ms since epoch), never a PC's: two PCs, two clocks.
CREATE TABLE IF NOT EXISTS lanes (
  key TEXT PRIMARY KEY,        -- '<project>/<lane>'
  json TEXT NOT NULL,
  receivedAt INTEGER NOT NULL
);
