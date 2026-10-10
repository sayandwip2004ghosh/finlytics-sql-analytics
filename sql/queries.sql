-- Each query is tagged `-- name:` and loaded by app.py / run_analysis.py.
-- Skills shown: multi-table JOINs, CTEs, window functions (LAG, AVG OVER, MAX OVER, NTILE, RANK),
-- conditional aggregation, HAVING, subqueries, views.

-- name: q01_sector_performance
-- 12-month return and annualised volatility by sector (equal-weighted across constituents)
WITH r AS (
    SELECT i.sector, v.price_date, AVG(v.daily_ret) AS sec_ret
    FROM v_returns v JOIN instruments i USING (instrument_id)
    WHERE v.daily_ret IS NOT NULL AND i.asset_class='Equity'
      AND v.price_date > (SELECT date(MAX(price_date),'-12 months') FROM prices)
    GROUP BY i.sector, v.price_date
)
SELECT sector,
       ROUND((EXP(SUM(LN(1+sec_ret)))-1)*100,2)                              AS return_12m_pct,
       ROUND(SQRT(AVG(sec_ret*sec_ret)-AVG(sec_ret)*AVG(sec_ret))*SQRT(252)*100,2) AS ann_vol_pct,
       ROUND((EXP(SUM(LN(1+sec_ret)))-1) / (SQRT(AVG(sec_ret*sec_ret)-AVG(sec_ret)*AVG(sec_ret))*SQRT(252)),2) AS return_per_unit_risk
FROM r GROUP BY sector ORDER BY return_12m_pct DESC;

-- name: q02_instrument_risk_return
-- Since-inception CAGR, volatility, Sharpe-like ratio (rf=5%), max drawdown per instrument
WITH base AS (
    SELECT instrument_id, price_date, close, daily_ret,
           MAX(close) OVER (PARTITION BY instrument_id ORDER BY price_date
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS run_max
    FROM v_returns
),
agg AS (
    SELECT instrument_id,
           MIN(price_date) AS d0, MAX(price_date) AS d1,
           MIN(close/run_max-1) AS max_dd,
           SQRT(AVG(daily_ret*daily_ret)-AVG(daily_ret)*AVG(daily_ret))*SQRT(252) AS ann_vol
    FROM base GROUP BY instrument_id
),
ends AS (
    SELECT a.instrument_id,
           (SELECT close FROM prices WHERE instrument_id=a.instrument_id AND price_date=a.d0) AS p0,
           (SELECT close FROM prices WHERE instrument_id=a.instrument_id AND price_date=a.d1) AS p1,
           (julianday(a.d1)-julianday(a.d0))/365.25 AS yrs
    FROM agg a
)
SELECT i.symbol, i.asset_class, i.sector,
       ROUND((POWER(e.p1/e.p0, 1/e.yrs)-1)*100,2)                         AS cagr_pct,
       ROUND(a.ann_vol*100,2)                                             AS ann_vol_pct,
       ROUND(((POWER(e.p1/e.p0,1/e.yrs)-1)-0.05)/a.ann_vol,2)             AS sharpe,
       ROUND(a.max_dd*100,2)                                              AS max_drawdown_pct,
       RANK() OVER (ORDER BY ((POWER(e.p1/e.p0,1/e.yrs)-1)-0.05)/a.ann_vol DESC) AS sharpe_rank
FROM agg a JOIN ends e USING (instrument_id) JOIN instruments i USING (instrument_id)
ORDER BY sharpe_rank;

-- name: q03_monthly_returns
-- Month-end close and month-on-month return per instrument (LAG over month-end series)
WITH me AS (
    SELECT instrument_id, strftime('%Y-%m', price_date) AS ym, price_date, close,
           ROW_NUMBER() OVER (PARTITION BY instrument_id, strftime('%Y-%m', price_date)
                              ORDER BY price_date DESC) AS rn
    FROM prices
)
SELECT i.symbol, ym, close AS month_end_close,
       ROUND((close / LAG(close) OVER (PARTITION BY instrument_id ORDER BY ym) - 1)*100,2) AS mom_ret_pct
FROM me JOIN instruments i USING (instrument_id)
WHERE rn = 1
ORDER BY i.symbol, ym;

-- name: q04_ma_crossover_signals
-- 50-day vs 200-day moving average; flags latest trend state per instrument
WITH ma AS (
    SELECT instrument_id, price_date, close,
           AVG(close) OVER (PARTITION BY instrument_id ORDER BY price_date ROWS BETWEEN 49  PRECEDING AND CURRENT ROW) AS ma50,
           AVG(close) OVER (PARTITION BY instrument_id ORDER BY price_date ROWS BETWEEN 199 PRECEDING AND CURRENT ROW) AS ma200,
           COUNT(*)   OVER (PARTITION BY instrument_id ORDER BY price_date ROWS BETWEEN 199 PRECEDING AND CURRENT ROW) AS n
    FROM prices
)
SELECT i.symbol, i.sector, ROUND(close,2) AS close, ROUND(ma50,2) AS ma50, ROUND(ma200,2) AS ma200,
       CASE WHEN ma50 > ma200 THEN 'Bullish' ELSE 'Bearish' END AS trend,
       ROUND((ma50/ma200-1)*100,2) AS ma_spread_pct
FROM ma JOIN instruments i USING (instrument_id)
WHERE n = 200 AND price_date = (SELECT MAX(price_date) FROM prices)
ORDER BY ma_spread_pct DESC;

-- name: q05_correlation_matrix
-- Pairwise return correlation computed in pure SQL (self-join on date) for the last 2 years
WITH r AS (
    SELECT instrument_id, price_date, daily_ret FROM v_returns
    WHERE daily_ret IS NOT NULL AND price_date > (SELECT date(MAX(price_date),'-2 years') FROM prices)
),
pairs AS (
    SELECT a.instrument_id AS ia, b.instrument_id AS ib,
           COUNT(*) n, AVG(a.daily_ret) ma, AVG(b.daily_ret) mb,
           AVG(a.daily_ret*b.daily_ret) mab, AVG(a.daily_ret*a.daily_ret) maa, AVG(b.daily_ret*b.daily_ret) mbb
    FROM r a JOIN r b ON a.price_date=b.price_date AND a.instrument_id<=b.instrument_id
    GROUP BY a.instrument_id, b.instrument_id
)
SELECT x.symbol AS sym_a, y.symbol AS sym_b,
       ROUND((mab-ma*mb)/SQRT((maa-ma*ma)*(mbb-mb*mb)),3) AS corr
FROM pairs p JOIN instruments x ON x.instrument_id=p.ia JOIN instruments y ON y.instrument_id=p.ib;

-- name: q06_market_stress_analysis
-- Equal-weighted equity index; worst days and cumulative drawdown trough
WITH idx AS (
    SELECT v.price_date, AVG(v.daily_ret) AS idx_ret
    FROM v_returns v JOIN instruments i USING (instrument_id)
    WHERE i.asset_class='Equity' AND v.daily_ret IS NOT NULL GROUP BY v.price_date
),
lvl AS (
    SELECT price_date, idx_ret, EXP(SUM(LN(1+idx_ret)) OVER (ORDER BY price_date)) AS level FROM idx
),
dd AS (
    SELECT price_date, idx_ret, level,
           level / MAX(level) OVER (ORDER BY price_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) - 1 AS drawdown
    FROM lvl
)
SELECT price_date, ROUND(idx_ret*100,2) AS idx_ret_pct, ROUND(level,4) AS index_level, ROUND(drawdown*100,2) AS drawdown_pct
FROM dd ORDER BY price_date;

-- name: q07_defensive_assets_in_stress
-- How did each asset class behave on the 20 worst equity-index days? (diversification check)
WITH idx AS (
    SELECT v.price_date, AVG(v.daily_ret) AS idx_ret
    FROM v_returns v JOIN instruments i USING (instrument_id)
    WHERE i.asset_class='Equity' AND v.daily_ret IS NOT NULL GROUP BY v.price_date
),
worst AS (SELECT price_date FROM idx ORDER BY idx_ret LIMIT 20)
SELECT i.asset_class, ROUND(AVG(v.daily_ret)*100,3) AS avg_ret_on_worst_days_pct,
       ROUND(100.0*SUM(v.daily_ret>0)/COUNT(*),1) AS pct_positive
FROM v_returns v JOIN instruments i USING (instrument_id)
WHERE v.price_date IN (SELECT price_date FROM worst)
GROUP BY i.asset_class;

-- name: q08_client_portfolio_summary
-- Per-client market value, cost, unrealised P&L and return (4-table join through views)
SELECT c.client_id, c.name, c.segment, c.risk_profile, c.region,
       ROUND(SUM(h.market_value),0) AS aum,
       ROUND(SUM(h.cost_basis),0)   AS cost_basis,
       ROUND(SUM(h.unrealized_pnl),0) AS unrealized_pnl,
       ROUND(100.0*SUM(h.unrealized_pnl)/SUM(h.cost_basis),2) AS return_pct,
       COUNT(DISTINCT h.instrument_id) AS n_holdings
FROM clients c JOIN v_holdings h USING (client_id)
GROUP BY c.client_id
ORDER BY aum DESC;

-- name: q09_aum_by_segment_and_asset_class
SELECT c.segment, h.asset_class,
       ROUND(SUM(h.market_value),0) AS aum,
       ROUND(100.0*SUM(h.market_value)/SUM(SUM(h.market_value)) OVER (PARTITION BY c.segment),1) AS pct_of_segment
FROM clients c JOIN v_holdings h USING (client_id)
GROUP BY c.segment, h.asset_class
ORDER BY c.segment, aum DESC;

-- name: q10_suitability_flags
-- Business insight: clients whose equity share is far above their stated risk profile
WITH alloc AS (
    SELECT client_id,
           SUM(market_value) AS aum,
           SUM(CASE WHEN asset_class='Equity' THEN market_value ELSE 0 END)/SUM(market_value) AS equity_pct
    FROM v_holdings GROUP BY client_id
)
SELECT c.client_id, c.name, c.segment, c.risk_profile, ROUND(a.aum,0) AS aum,
       ROUND(a.equity_pct*100,1) AS equity_pct,
       CASE c.risk_profile WHEN 'Conservative' THEN 40 WHEN 'Moderate' THEN 70 ELSE 100 END AS max_equity_pct_policy
FROM alloc a JOIN clients c USING (client_id)
WHERE a.equity_pct*100 > CASE c.risk_profile WHEN 'Conservative' THEN 40 WHEN 'Moderate' THEN 70 ELSE 100 END
ORDER BY a.aum DESC;

-- name: q11_concentration_risk
-- Clients with a single EQUITY holding above 25% of their total portfolio (ETFs excluded: already diversified)
WITH w AS (
    SELECT client_id, symbol, sector, asset_class, market_value,
           market_value*1.0 / SUM(market_value) OVER (PARTITION BY client_id) AS weight
    FROM (SELECT client_id, instrument_id, symbol, sector, asset_class, SUM(market_value) AS market_value
          FROM v_holdings GROUP BY client_id, instrument_id)
)
SELECT c.client_id, c.name, c.segment, w.symbol, w.sector, ROUND(w.market_value,0) AS position_value, ROUND(w.weight*100,1) AS weight_pct
FROM w JOIN clients c USING (client_id)
WHERE w.weight > 0.25 AND w.asset_class = 'Equity'
ORDER BY w.market_value DESC;

-- name: q12_client_value_tiers
-- NTILE quartiles of AUM with average activity (trade count) per tier
WITH aum AS (SELECT client_id, SUM(market_value) AS aum FROM v_holdings GROUP BY client_id),
act AS (SELECT a.client_id, COUNT(t.trade_id) AS trades, SUM(t.quantity*t.price) AS turnover
        FROM accounts a LEFT JOIN trades t USING (account_id) GROUP BY a.client_id),
tiers AS (SELECT client_id, aum, NTILE(4) OVER (ORDER BY aum DESC) AS tier FROM aum)
SELECT 'Q'||tier AS aum_tier, COUNT(*) AS clients, ROUND(SUM(aum),0) AS total_aum,
       ROUND(100.0*SUM(aum)/SUM(SUM(aum)) OVER (),1) AS share_of_total_aum_pct,
       ROUND(AVG(trades),1) AS avg_trades, ROUND(AVG(turnover),0) AS avg_turnover
FROM tiers JOIN act USING (client_id)
GROUP BY tier ORDER BY tier;

-- name: q13_trading_activity_monthly
SELECT strftime('%Y-%m', trade_date) AS ym,
       COUNT(*) AS trades,
       SUM(side='BUY')  AS buys, SUM(side='SELL') AS sells,
       ROUND(SUM(quantity*price),0) AS turnover,
       COUNT(DISTINCT account_id) AS active_accounts
FROM trades GROUP BY ym ORDER BY ym;

-- name: q14_top_sector_exposure_by_segment
SELECT c.segment, h.sector, ROUND(SUM(h.market_value),0) AS exposure,
       RANK() OVER (PARTITION BY c.segment ORDER BY SUM(h.market_value) DESC) AS rnk
FROM clients c JOIN v_holdings h USING (client_id)
WHERE h.asset_class='Equity'
GROUP BY c.segment, h.sector
ORDER BY c.segment, rnk;

-- name: q15_data_quality_checks
-- Integrity checks (shows data-validation habit)
SELECT 'prices with non-positive close' AS check_name, COUNT(*) AS violations FROM prices WHERE close<=0
UNION ALL SELECT 'high < low', COUNT(*) FROM prices WHERE high<low
UNION ALL SELECT 'trades on non-trading dates', COUNT(*) FROM trades t
          WHERE NOT EXISTS (SELECT 1 FROM prices p WHERE p.instrument_id=t.instrument_id AND p.price_date=t.trade_date)
UNION ALL SELECT 'negative positions', COUNT(*) FROM v_positions WHERE qty<0
UNION ALL SELECT 'accounts without client', COUNT(*) FROM accounts a LEFT JOIN clients c USING(client_id) WHERE c.client_id IS NULL;
