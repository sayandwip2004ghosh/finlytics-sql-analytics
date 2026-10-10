-- Relational schema: market data + client/portfolio data
PRAGMA foreign_keys = ON;

CREATE TABLE instruments (
    instrument_id INTEGER PRIMARY KEY,
    symbol        TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL,
    asset_class   TEXT NOT NULL CHECK (asset_class IN ('Equity','Bond','Commodity')),
    sector        TEXT NOT NULL
);

CREATE TABLE prices (
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id),
    price_date    TEXT    NOT NULL,           -- ISO date
    open REAL, high REAL, low REAL,
    close         REAL    NOT NULL,
    volume        INTEGER,
    PRIMARY KEY (instrument_id, price_date)
);

CREATE TABLE clients (
    client_id    INTEGER PRIMARY KEY,
    name         TEXT NOT NULL,
    region       TEXT NOT NULL,
    segment      TEXT NOT NULL CHECK (segment IN ('Retail','Affluent','HNI')),
    risk_profile TEXT NOT NULL CHECK (risk_profile IN ('Conservative','Moderate','Aggressive')),
    joined_on    TEXT NOT NULL
);

CREATE TABLE accounts (
    account_id INTEGER PRIMARY KEY,
    client_id  INTEGER NOT NULL REFERENCES clients(client_id),
    opened_on  TEXT NOT NULL
);

CREATE TABLE trades (
    trade_id      INTEGER PRIMARY KEY,
    account_id    INTEGER NOT NULL REFERENCES accounts(account_id),
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id),
    trade_date    TEXT NOT NULL,
    side          TEXT NOT NULL CHECK (side IN ('BUY','SELL')),
    quantity      INTEGER NOT NULL CHECK (quantity > 0),
    price         REAL NOT NULL
);

CREATE INDEX idx_prices_date  ON prices(price_date);
CREATE INDEX idx_trades_acct  ON trades(account_id, instrument_id);
CREATE INDEX idx_trades_date  ON trades(trade_date);
