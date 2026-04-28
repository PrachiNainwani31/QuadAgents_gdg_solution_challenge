from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import needs, volunteers, matching, analytics, auth, geocoding

app = FastAPI(title="NGO Connect API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"]
)

@app.get("/")
def root():
    return {"message": "NGO Connect API running!"}

@app.get("/health")
def health():
    return {"status": "ok"}

app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(needs.router, prefix="/needs", tags=["Needs"])
app.include_router(volunteers.router, prefix="/volunteers", tags=["Volunteers"])
app.include_router(matching.router, prefix="/match", tags=["AI Matching"])
app.include_router(analytics.router, prefix="/analytics", tags=["Analytics"])
app.include_router(geocoding.router, prefix="/geo", tags=["Geocoding"])