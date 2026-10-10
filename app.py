import streamlit as st, pandas as pd, plotly.express as px
from run_analysis import load_queries, connect

st.set_page_config(page_title="Finlytics", layout="wide")
con, Q = connect(), load_queries()

@st.cache_data
def run(name): return pd.read_sql_query(Q[name], con)

st.title("Finlytics: Market & Client Portfolio Analytics")
st.caption("SQL-first analytics on synthetic market + client data (SQLite). Every chart is driven by a query in sql/queries.sql.")

t1, t2, t3, t4 = st.tabs(["Market", "Risk", "Clients", "SQL explorer"])

with t1:
    sec = run("q01_sector_performance")
    c1, c2 = st.columns(2)
    c1.plotly_chart(px.bar(sec, x="sector", y="return_12m_pct", title="12M sector return (%)", color="return_12m_pct",
                           color_continuous_scale="RdYlGn"), width="stretch")
    c2.plotly_chart(px.scatter(sec, x="ann_vol_pct", y="return_12m_pct", text="sector", title="Risk vs return by sector"),
                    width="stretch")
    idx = run("q06_market_stress_analysis")
    st.plotly_chart(px.line(idx, x="price_date", y="drawdown_pct", title="Equal-weighted equity index drawdown (%)"),
                    width="stretch")
    ma = run("q04_ma_crossover_signals")
    st.subheader("Trend signals (50D vs 200D MA)")
    st.dataframe(ma, width="stretch", hide_index=True)

with t2:
    r = run("q02_instrument_risk_return")
    st.plotly_chart(px.scatter(r, x="ann_vol_pct", y="cagr_pct", color="asset_class", hover_name="symbol", size="ann_vol_pct",
                               title="CAGR vs volatility"), width="stretch")
    st.dataframe(r, width="stretch", hide_index=True)
    c = run("q05_correlation_matrix")
    m = c.pivot(index="sym_a", columns="sym_b", values="corr")
    m = m.combine_first(m.T)
    st.plotly_chart(px.imshow(m, color_continuous_scale="RdBu_r", zmin=-1, zmax=1, title="Return correlation (2Y)"),
                    width="stretch")
    st.subheader("Diversification in stress: worst 20 equity days")
    st.dataframe(run("q07_defensive_assets_in_stress"), hide_index=True)

with t3:
    tiers = run("q12_client_value_tiers")
    c1, c2 = st.columns(2)
    c1.plotly_chart(px.bar(tiers, x="aum_tier", y="share_of_total_aum_pct", title="Share of AUM by client quartile (%)"),
                    width="stretch")
    c2.plotly_chart(px.bar(run("q09_aum_by_segment_and_asset_class"), x="segment", y="pct_of_segment", color="asset_class",
                           title="Asset mix by segment (%)"), width="stretch")
    st.subheader("Suitability flags: equity share above risk-profile policy")
    sf = run("q10_suitability_flags"); st.metric("Flagged clients", len(sf)); st.dataframe(sf, hide_index=True)
    st.subheader("Concentration risk: single equity > 25% of portfolio")
    st.dataframe(run("q11_concentration_risk"), hide_index=True)
    st.plotly_chart(px.bar(run("q13_trading_activity_monthly"), x="ym", y="turnover", title="Monthly trading turnover"),
                    width="stretch")

with t4:
    name = st.selectbox("Query", list(Q))
    st.code(Q[name], language="sql")
    st.dataframe(run(name), width="stretch", hide_index=True)
