"""Runs every query in sql/queries.sql and prints the head of each result. Exports CSVs to outputs/."""
import re, sqlite3, os, pandas as pd

def load_queries(path="sql/queries.sql"):
    txt = open(path).read()
    parts = re.split(r"^-- name: (\w+)\s*$", txt, flags=re.M)
    return {parts[i]: parts[i+1].strip() for i in range(1, len(parts), 2)}

def connect(db="data/finlytics.db"):
    con = sqlite3.connect(db)
    # SQLite lacks EXP/LN/POWER/SQRT unless math functions are compiled in; register fallbacks.
    import math
    for name, fn, n in [("EXP",math.exp,1),("LN",math.log,1),("SQRT",math.sqrt,1),("POWER",math.pow,2)]:
        con.create_function(name, n, fn)
    return con

if __name__ == "__main__":
    os.makedirs("outputs", exist_ok=True)
    con = connect()
    for name, sql in load_queries().items():
        df = pd.read_sql_query(sql, con)
        df.to_csv(f"outputs/{name}.csv", index=False)
        print(f"\n=== {name} ({len(df)} rows) ===")
        print(df.head(8).to_string(index=False))
