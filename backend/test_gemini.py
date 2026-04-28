"""
Quick test to verify the Gemini API key is working.
Run: python3 test_gemini.py
"""
from dotenv import load_dotenv
import os

load_dotenv()

api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    print("❌ GEMINI_API_KEY not found in .env")
    exit(1)

print(f"🔑 Key found: {api_key[:10]}...")

try:
    from google import genai
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents="Say hello in one word."
    )
    print(f"✅ Gemini API working! Response: {response.text.strip()}")
except Exception as e:
    print(f"❌ Gemini API failed: {e}")
