-- Reusable views. Positions use weighted-average cost (simplification, documented in README).

CREATE VIEW v_returns AS
SELECT instrument_id, price_date, close,
       close / LAG(close) OVER (PARTITION BY instrument_id ORDER BY price_date) - 1 AS daily_ret
FROM prices;

CREATE VIEW v_latest_price AS
SELECT p.instrument_id, p.close AS last_close, p.price_date AS last_date
FROM prices p
WHERE p.price_date = (SELECT MAX(price_date) FROM prices);

CREATE VIEW v_positions AS
SELECT t.account_id, t.instrument_id,
       SUM(CASE WHEN side='BUY' THEN quantity ELSE -quantity END) AS qty,
       SUM(CASE WHEN side='BUY' THEN quantity*price END) * 1.0
         / NULLIF(SUM(CASE WHEN side='BUY' THEN quantity END),0)  AS avg_cost,
       SUM(CASE WHEN side='SELL' THEN quantity*price END)         AS sell_proceeds,
       SUM(CASE WHEN side='SELL' THEN quantity END)               AS sold_qty
FROM trades t
GROUP BY t.account_id, t.instrument_id;

CREATE VIEW v_holdings AS
SELECT a.client_id, pos.account_id, pos.instrument_id, i.symbol, i.asset_class, i.sector,
       pos.qty, pos.avg_cost, lp.last_close,
       pos.qty * lp.last_close                              AS market_value,
       pos.qty * pos.avg_cost                               AS cost_basis,
       pos.qty * (lp.last_close - pos.avg_cost)             AS unrealized_pnl,
       COALESCE(pos.sell_proceeds,0) - COALESCE(pos.sold_qty,0)*pos.avg_cost AS realized_pnl
FROM v_positions pos
JOIN accounts a       ON a.account_id = pos.account_id
JOIN instruments i    ON i.instrument_id = pos.instrument_id
JOIN v_latest_price lp ON lp.instrument_id = pos.instrument_id
WHERE pos.qty > 0;
