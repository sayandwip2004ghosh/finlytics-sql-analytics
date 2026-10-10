"""OPTIONAL: replace synthetic prices with real data (needs internet + `pip install yfinance`).
Keeps clients/trades; re-prices by re-running generate_data logic is NOT done here -- simplest path:
    1) edit TICKERS below (use real symbols)  2) run this script to build data/real_prices.db
    3) point run_analysis.connect() / app.py at that DB for the market-only queries (q01-q07)."""
import sqlite3, yfinance as yf, pandas as pd
TICKERS = {"HDFCBANK.NS":("HDFC Bank","Equity","Banking"), "TCS.NS":("TCS","Equity","IT"),
           "RELIANCE.NS":("Reliance","Equity","Energy"), "SUNPHARMA.NS":("Sun Pharma","Equity","Pharma"),
           "ITC.NS":("ITC","Equity","FMCG"), "MARUTI.NS":("Maruti Suzuki","Equity","Auto"),
           "GOLDBEES.NS":("Gold ETF","Commodity","Gold")}
con = sqlite3.connect("data/real_prices.db")
con.executescript(open("sql/schema.sql").read())
for i,(sym,(name,ac,sec)) in enumerate(TICKERS.items(), 1):
    con.execute("INSERT INTO instruments VALUES (?,?,?,?,?)",(i,sym,name,ac,sec))
    df = yf.download(sym, start="2023-01-01", progress=False, auto_adjust=True)
    df.columns = [c[0] if isinstance(c, tuple) else c for c in df.columns]
    for d,r in df.iterrows():
        con.execute("INSERT INTO prices VALUES (?,?,?,?,?,?,?)",(i,d.strftime("%Y-%m-%d"),r.Open,r.High,r.Low,r.Close,int(r.Volume)))
con.executescript(open("sql/views.sql").read()); con.commit()
