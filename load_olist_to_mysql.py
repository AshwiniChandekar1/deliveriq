
import getpass
from pathlib import Path
from urllib.parse import quote_plus
 
import pandas as pd
from sqlalchemy import create_engine, text
 
# ---- Settings you may need to change ---------------------------------
DATA_FOLDER = Path("data")      # folder that holds the CSV files
DB_NAME = "deliveriq"           # the database you created
DB_USER = "root"                # your MySQL username
DB_HOST = "localhost"
DB_PORT = 3306
# -----------------------------------------------------------------------
 
 
def table_name_from_file(file: Path) -> str:
    """olist_orders_dataset.csv -> orders"""
    name = file.stem
    name = name.replace("olist_", "").replace("_dataset", "")
    return name
 
 
def main():
    password = getpass.getpass(f"MySQL password for user '{DB_USER}': ")
    url = (
        f"mysql+pymysql://{DB_USER}:{quote_plus(password)}"
        f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    )
    engine = create_engine(url)
 
    # Quick connection test
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    print("Connected to MySQL.\n")
 
    csv_files = sorted(DATA_FOLDER.glob("*.csv"))
    if not csv_files:
        print(f"No CSV files found in '{DATA_FOLDER}'. Check the folder name.")
        return
 
    for file in csv_files:
        table = table_name_from_file(file)
        df = pd.read_csv(file)
        df.to_sql(
            table,
            engine,
            if_exists="replace",   # safe to re-run
            index=False,
            chunksize=5000,
        )
        print(f"Loaded {len(df):>8,} rows  ->  table '{table}'")
 
    print("\nDone. Now run in MySQL Workbench:  SHOW TABLES;")
 
 
if __name__ == "__main__":
    main()
 