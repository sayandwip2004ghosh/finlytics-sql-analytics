"""Builds data/finlytics.db with SYNTHETIC but market-like data (seeded, reproducible).
Swap in real prices with load_real_prices.py -- schema is identical."""
import sqlite3, os
import numpy as np, pandas as pd

SEED = 42
rng = np.random.default_rng(SEED)
DB = "data/finlytics.db"

# (symbol, name, asset_class, sector, annual_drift, annual_vol, sector_beta)
INSTR = []
sectors = {
    "Banking":  [("NBNK","Northbridge Bank"),("CAPF","Capital First Finance"),("UNTD","United Trust Bank"),("MRCH","Merchant Credit")],
    "IT":       [("TECX","TechNova Systems"),("DATW","DataWave Software"),("CLDV","CloudVista"),("INFR","InfraSoft")],
    "Energy":   [("PWRG","PowerGrid Energy"),("OILX","Meridian Oil & Gas"),("SOLR","SolarArc Renewables"),("COAL","Terra Resources")],
    "Pharma":   [("MEDI","MediCore Pharma"),("BIOL","BioLife Sciences"),("HLTH","HealthFirst Labs"),("GENX","GenX Therapeutics")],
    "FMCG":     [("HOMC","HomeCare Brands"),("FOOD","FreshFoods Ltd"),("BEVR","Beverage Co"),("PERS","PersonalCare Corp")],
    "Auto":     [("MOTR","MotorWorks"),("EVCO","VoltDrive EV"),("TYRE","GripTyre Industries"),("AUTP","AutoParts United")],
}
prof = {"Banking":(0.11,0.24,1.1),"IT":(0.14,0.28,1.2),"Energy":(0.09,0.30,0.9),
        "Pharma":(0.10,0.22,0.6),"FMCG":(0.08,0.16,0.5),"Auto":(0.12,0.30,1.3)}
for sec, names in sectors.items():
    d,v,b = prof[sec]
    for s,n in names:
        INSTR.append((s,n,"Equity",sec, d+rng.normal(0,0.02), v*rng.uniform(0.85,1.15), b))
INSTR += [("GBND","Govt Bond ETF","Bond","Government",0.045,0.05,-0.15),
          ("CBND","Corporate Bond ETF","Bond","Corporate",0.060,0.07,0.10),
          ("GOLD","Gold ETF","Commodity","Gold",0.07,0.14,-0.05)]

dates = pd.bdate_range("2023-01-02","2026-09-30")
n = len(dates)

# Market factor with a stress regime (mid-2025) to create realistic drawdowns
mkt_vol = np.full(n, 0.14/np.sqrt(252)); mkt_mu = np.full(n, 0.10/252)
stress = (dates >= "2025-03-03") & (dates <= "2025-05-30")
mkt_vol[stress] *= 2.4; mkt_mu[stress] = -0.9/252
mkt = rng.normal(mkt_mu, mkt_vol)
sec_f = {s: rng.normal(0, 0.007, n) for s in sectors}

rows_i, rows_p = [], []
for iid,(sym,name,ac,sec,drift,vol,beta) in enumerate(INSTR, start=1):
    rows_i.append((iid,sym,name,ac,sec))
    d = vol/np.sqrt(252)
    idio = rng.normal(0, d*0.55, n)
    sf = sec_f.get(sec, np.zeros(n)) if ac=="Equity" else np.zeros(n)
    r = drift/252 + beta*(mkt-mkt_mu) + sf + idio
    close = 100*rng.uniform(0.5,4)*np.exp(np.cumsum(r))
    op = np.r_[close[0], close[:-1]]*(1+rng.normal(0,0.002,n))
    hi = np.maximum(op,close)*(1+np.abs(rng.normal(0,0.004,n)))
    lo = np.minimum(op,close)*(1-np.abs(rng.normal(0,0.004,n)))
    vol_ = (rng.lognormal(13.5,0.4,n)*(1+np.abs(r)*40)).astype(int)
    for k in range(n):
        rows_p.append((iid,dates[k].strftime("%Y-%m-%d"),round(op[k],2),round(hi[k],2),round(lo[k],2),round(close[k],2),int(vol_[k])))

# Clients / accounts
regions = ["North","South","East","West","Central"]
seg_p = {"Retail":0.62,"Affluent":0.30,"HNI":0.08}
seg_budget = {"Retail":(0.5e5,4e5),"Affluent":(4e5,2.5e6),"HNI":(2.5e6,1.5e7)}
risk_by_seg = {"Retail":[0.5,0.35,0.15],"Affluent":[0.25,0.45,0.30],"HNI":[0.10,0.40,0.50]}
risks = ["Conservative","Moderate","Aggressive"]
eq_w = {"Conservative":0.25,"Moderate":0.55,"Aggressive":0.85}
N_CLIENTS = 300
clients, accounts = [], []
aid = 1
for cid in range(1, N_CLIENTS+1):
    seg = rng.choice(list(seg_p), p=list(seg_p.values()))
    risk = rng.choice(risks, p=risk_by_seg[seg])
    joined = dates[rng.integers(0, n//3)].strftime("%Y-%m-%d")
    clients.append((cid, f"Client {cid:03d}", rng.choice(regions), seg, risk, joined))
    for _ in range(rng.choice([1,2],p=[0.75,0.25])):
        accounts.append((aid,cid,joined)); aid += 1

# Trades (simulate holdings so SELL never exceeds position)
price_df = pd.DataFrame(rows_p, columns=["iid","d","o","h","l","c","v"])
px = price_df.pivot(index="d", columns="iid", values="c")
date_strs = list(px.index)
eq_ids = [i for i,x in enumerate(INSTR,1) if x[2]=="Equity"]
bond_ids = [i for i,x in enumerate(INSTR,1) if x[2]=="Bond"]
com_ids = [i for i,x in enumerate(INSTR,1) if x[2]=="Commodity"]
cinfo = {c[0]:c for c in clients}
trades, tid = [], 1
for (acc, cid, opened) in accounts:
    _,_,_,seg,risk,joined = cinfo[cid]
    budget = rng.uniform(*seg_budget[seg])
    start = date_strs.index(joined) if joined in date_strs else 0
    held = {}
    # initial allocation, with some clients deliberately off-profile
    w_eq = float(np.clip(eq_w[risk] + rng.normal(0,0.18), 0.05, 0.98))
    alloc = {"eq": w_eq, "bond": (1-w_eq)*0.7, "com": (1-w_eq)*0.3}
    picks = list(rng.choice(eq_ids, size=int(rng.integers(3,9)), replace=False))
    if rng.random()<0.25:      # concentrated investors
        picks = picks[:2]
    targets = []
    for i in picks: targets.append((i, budget*alloc["eq"]/len(picks)))
    targets += [(int(rng.choice(bond_ids)), budget*alloc["bond"]), (com_ids[0], budget*alloc["com"])]
    for i,amt in targets:
        d0 = date_strs[min(start+int(rng.integers(0,30)), len(date_strs)-1)]
        p = float(px.loc[d0,i]); q = int(amt//p)
        if q>0:
            trades.append((tid,acc,i,d0,"BUY",q,p)); tid+=1; held[i]=held.get(i,0)+q
    # ongoing activity
    for _ in range(int(rng.poisson({"Retail":4,"Affluent":9,"HNI":16}[seg]))):
        di = int(rng.integers(start+30, len(date_strs)))
        d = date_strs[di]; i = int(rng.choice(list(held) if held and rng.random()<0.5 else picks))
        p = float(px.loc[d,i])
        if rng.random()<0.45 and held.get(i,0)>1:
            q = int(held[i]*rng.uniform(0.1,0.6)); side="SELL"; held[i]-=q
        else:
            q = max(1,int(budget*rng.uniform(0.01,0.06)//p)); side="BUY"; held[i]=held.get(i,0)+q
        if q>0: trades.append((tid,acc,i,d,side,q,p)); tid+=1

if os.path.exists(DB): os.remove(DB)
con = sqlite3.connect(DB)
con.executescript(open("sql/schema.sql").read())
con.executemany("INSERT INTO instruments VALUES (?,?,?,?,?)", rows_i)
con.executemany("INSERT INTO prices VALUES (?,?,?,?,?,?,?)", rows_p)
con.executemany("INSERT INTO clients VALUES (?,?,?,?,?,?)", [tuple(map(lambda x: x.item() if hasattr(x,'item') else x, c)) for c in clients])
con.executemany("INSERT INTO accounts VALUES (?,?,?)", accounts)
trades = [(int(a),int(b),int(c),d,e,int(f),float(g)) for a,b,c,d,e,f,g in trades]
con.executemany("INSERT INTO trades VALUES (?,?,?,?,?,?,?)", trades)
con.executescript(open("sql/views.sql").read())
con.commit()
for t in ["instruments","prices","clients","accounts","trades"]:
    print(t, con.execute(f"select count(*) from {t}").fetchone()[0])
con.close()
