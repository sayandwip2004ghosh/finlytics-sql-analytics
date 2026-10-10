# Finlytics: Market & Client Portfolio Analytics (SQL + Python)

**Problem:** A wealth/data team needs to answer three questions from raw prices and trades:
1. Which sectors and assets gave the best risk-adjusted returns, and how did diversifiers behave in a sell-off?
2. How are client portfolios performing, and who holds too much risk for their stated profile (suitability)?
3. Where is concentration risk, and which client tiers drive AUM?

**Users:** relationship managers, risk/compliance analysts, product owners.

## Stack
SQLite, SQL (CTEs, window functions), Python (pandas), Streamlit + Plotly.

## Data (synthetic, reproducible)
`generate_data.py` (seed 42) builds 27 instruments (24 equities across 6 sectors, 2 bond ETFs, 1 gold ETF),
~26k daily price rows (Jan 2023 to Sep 2026, with a stress regime in 2025), 300 clients, 364 accounts, ~4.6k trades.
Prices follow a factor model (market + sector + idiosyncratic). Instrument names are fictional.
**Findings below describe the synthetic data, not real markets.** `load_real_prices.py` shows how to load real NSE prices.

## Schema
`instruments` 1-N `prices`; `clients` 1-N `accounts` 1-N `trades` N-1 `instruments`.
Views: `v_returns`, `v_latest_price`, `v_positions` (weighted-average cost), `v_holdings` (market value, unrealised P&L).

## Analyses (sql/queries.sql, 15 queries)
| Area | Queries | SQL techniques |
|---|---|---|
| Market | sector return/vol, CAGR/Sharpe/max drawdown, monthly returns, 50/200D MA signals | LAG, running MAX/AVG frames, ROW_NUMBER, RANK |
| Risk | correlation matrix in pure SQL, index drawdown, asset-class behaviour on 20 worst days | self-join, aggregates, subqueries |
| Clients | portfolio P&L, AUM mix, suitability flags, concentration, AUM quartiles, trading activity | multi-table joins, NTILE, conditional aggregation, window share-of-total |
| Quality | integrity checks (orphans, non-trading-day trades, negative positions) | UNION ALL, anti-joins |

## Key findings (on the synthetic data)
- Top 25% of clients hold **78% of AUM** but are 25% of clients: prioritise coverage on Q1 tier.
- On the 20 worst equity days, equities fell **-2.9%** on average, gold rose **+0.43%** (85% of days positive), bonds +0.09%: diversifiers worked.
- **29 clients (INR 22.6M)** hold more equity than their risk profile allows: suitability review list.
- **68 clients** hold a single equity above 25% of portfolio: concentration alerts.
- Equal-weighted equity index peak-to-trough drawdown: **-24.8%**.
- FMCG delivered the best 12M risk-adjusted return; Banking the worst.

## Run
```
pip install -r requirements.txt
python generate_data.py     # builds data/finlytics.db
python run_analysis.py      # runs all queries, writes CSVs to outputs/
streamlit run app.py        # dashboard
```

## Assumptions / limitations
- Weighted-average cost basis, no fees/taxes/dividends; trades execute at the day's close.
- Volatility uses population std; risk-free rate fixed at 5%.
- Suitability thresholds (40/70/100% equity by risk profile) are illustrative policy limits.
