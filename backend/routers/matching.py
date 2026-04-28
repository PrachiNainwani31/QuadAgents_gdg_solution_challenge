from fastapi import APIRouter
from pydantic import BaseModel
from services.gemini_service import match_volunteer_to_needs, extract_needs_from_text, prioritize_needs
import json

router = APIRouter()

from routers.needs import needs_db
from routers.volunteers import volunteers_db

class MatchRequest(BaseModel):
    volunteer_id: str

class ParseTextRequest(BaseModel):
    text: str

@router.post("/volunteer")
async def match_volunteer(request: MatchRequest):
    volunteer = next((v for v in volunteers_db if v["id"] == request.volunteer_id), None)
    if not volunteer:
        return {"error": "Volunteer not found"}
    if not needs_db:
        return {"error": "No needs available"}
    matches = await match_volunteer_to_needs(volunteer, needs_db)
    return {"volunteer": volunteer["name"], "matches": matches}

@router.get("/prioritize-needs")
async def prioritize_needs_route():
    if not needs_db:
        return {"error": "No needs available"}
    ranked = await prioritize_needs(needs_db)
    return {"ranked_needs": ranked}

@router.post("/parse-text")
async def parse_text(request: ParseTextRequest):
    needs = await extract_needs_from_text(request.text)
    return {"needs": needs}
