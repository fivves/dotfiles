from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, Dict, Any
import json
from pathlib import Path

app = FastAPI(title="Wordle Sync API")

DATA_DIR = Path("/app/data")
DATA_DIR.mkdir(parents=True, exist_ok=True)

STATE_FILE = DATA_DIR / "state.json"
STATS_FILE = DATA_DIR / "stats.json"

class SyncData(BaseModel):
    state: Optional[Dict[str, Any]] = None
    stats: Optional[Dict[str, Any]] = None

@app.get("/sync", response_model=SyncData)
def get_sync():
    state = {}
    stats = {}
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, "r") as f:
                state = json.load(f)
        except Exception:
            pass
    if STATS_FILE.exists():
        try:
            with open(STATS_FILE, "r") as f:
                stats = json.load(f)
        except Exception:
            pass
    return SyncData(state=state, stats=stats)

@app.post("/sync")
def post_sync(data: SyncData):
    if data.state is not None:
        try:
            with open(STATE_FILE, "w") as f:
                json.dump(data.state, f, indent=2)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to write state: {e}")
    
    if data.stats is not None:
        try:
            with open(STATS_FILE, "w") as f:
                json.dump(data.stats, f, indent=2)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to write stats: {e}")
            
    return {"message": "Sync successful"}
