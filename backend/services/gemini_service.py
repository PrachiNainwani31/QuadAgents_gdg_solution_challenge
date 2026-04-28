from groq import Groq
from dotenv import load_dotenv
import os, json, re

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

client = Groq(api_key=os.getenv("GROQ_API_KEY"))
MODEL = "llama-3.3-70b-versatile"

def _chat(prompt: str) -> str:
    response = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3,
    )
    text = response.choices[0].message.content or ""
    return re.sub(r"```(?:json)?", "", text).replace("```", "").strip()

def _safe_json(text: str, fallback):
    try:
        return json.loads(text)
    except Exception:
        match = re.search(r'(\[.*\]|\{.*\})', text, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(1))
            except Exception:
                pass
        return fallback

async def match_volunteer_to_needs(volunteer: dict, needs: list) -> list:
    prompt = f"""
    You are a smart volunteer coordinator for NGOs.
    Volunteer profile:
    - Skills: {volunteer['skills']}
    - Availability: {volunteer['availability']}
    - Location: {volunteer['location']}

    Open needs from NGOs:
    {json.dumps(needs, indent=2)}

    Rank top 3 most suitable needs for this volunteer.
    Return ONLY valid JSON array: [{{"need_id": "...", "score": 0, "reason": "..."}}]
    """
    return _safe_json(_chat(prompt), [])

async def extract_needs_from_text(raw_text: str) -> list:
    prompt = f"""
    Extract volunteer needs from this community survey/report text.
    For each need found, extract: title, description, skills, urgency, location.

    Text: "{raw_text}"

    Return ONLY a valid JSON array (no explanation, no markdown):
    [{{"title":"...", "description":"...", "skills":[], "urgency":"Medium", "location":"..."}}]
    If no needs found, return [].
    """
    return _safe_json(_chat(prompt), [])

async def prioritize_needs(needs: list) -> list:
    prompt = f"""
    Analyze these NGO needs and assign urgency scores 1-100.
    Consider: people affected, deadline, skill scarcity, social impact.

    Needs: {json.dumps(needs, indent=2)}

    Return ONLY a valid JSON array (no explanation, no markdown):
    [{{"need_id":"...", "urgency_score":0, "priority_reason":"..."}}]
    """
    return _safe_json(_chat(prompt), [])
