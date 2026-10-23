from fastapi import FastAPI
from pydantic import BaseModel

# Create FastAPI application
app = FastAPI(title="MallPilot AI Backend")

# Test API
@app.get("/")
def home():
    return {
        "message": "MallPilot AI Backend Running!"
    }

# Define route request format
class RouteRequest(BaseModel):
    start: str
    destinations: list[str]
    time_limit_minutes: int

# Route optimisation API (temporary test)
@app.post("/optimize")
def optimize_route(request: RouteRequest):

    return {
        "status": "success",
        "start": request.start,
        "visit_order": request.destinations,
        "time_limit_minutes": request.time_limit_minutes,
        "message": "API working. Optimisation not implemented yet."
    }