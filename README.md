# 🌐 NGO Connect — AI-Powered Volunteer Matching Platform

> Built for **Google Developer Groups Solution Challenge**  
> Team **QuadAgents**

NGO Connect bridges the gap between NGOs and volunteers using AI-powered matching, real-time task management, and location-aware coordination — all in one platform.

---

## 🚀 Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter Web |
| Backend | FastAPI (Python) |
| Database | Firebase Firestore |
| Auth | Firebase Authentication |
| AI | Groq API (LLaMA 3.3 70B) |
| Maps | OpenStreetMap via flutter_map |
| Geocoding | Photon API (routed through backend) |
| Storage | Firebase Storage |
| Hosting | Firebase Hosting + Render |

---

## 🏗️ Architecture Overview

```
Flutter Web (Frontend)
    │
    ├── Firebase Auth       → Login / Register
    ├── Cloud Firestore     → All data (needs, assignments, notifications)
    ├── Firebase Storage    → Document uploads
    │
    └── FastAPI Backend (localhost:8000 / Render)
            ├── /match/parse-text     → AI need extraction (Groq)
            ├── /match/volunteer      → AI volunteer matching (Groq)
            ├── /match/prioritize-needs → AI urgency ranking (Groq)
            └── /geo/geocode          → Address → lat/lng (Photon OSM)
```

---

## 👥 Two Portals, One Platform

### 🏢 NGO Dashboard
### 🙋 Volunteer Dashboard

Both portals share the same Firestore backend — actions on one side are instantly reflected on the other in real time.

---

## 🏢 NGO Portal — Features

### 1. 📊 Overview Dashboard
- Live metrics: total needs posted, open needs, fulfilled needs, active volunteers
- Quick-access navigation to all sections

### 2. 📄 Document Hub
- Upload PDF/CSV survey reports (max 10 MB)
- **AI Survey Parser** — paste field survey text, Groq AI extracts structured volunteer needs automatically
- Extracted needs can be published directly to the platform with one click
- Uploaded documents listed with filename, size, and upload date

### 3. ➕ Create Need
- Full form: title, description, category, urgency (Low → Immediate), skills required, deadline, location
- **AI Pre-fill** — paste any report text and AI auto-populates all fields
- Location geocoded to lat/lng via Photon OSM (through backend to avoid CORS)
- On publish: AI matching runs automatically against all registered volunteers, top 5 matched volunteers receive notifications

### 4. 📋 Manage Needs
- Live stream of all posted needs from Firestore
- Filter by status: All / Open / In-Progress / Closed
- Sorted by urgency (descending) then deadline (ascending)
- Edit title, description, urgency inline
- Close any open need

### 5. 🗂️ Task Board (Kanban)
- Real-time Kanban board of all volunteer assignments
- Columns: **Invited → Accepted → In Progress → Reported → Verified → Closed**
- Each card shows volunteer name, need title, and invite date
- NGO can advance any assignment to the next stage
- When a task is **Reported**: NGO sees "Mark Verified" button
- When **Verified**: NGO receives a rating prompt notification
- When **Closed**: volunteer is automatically notified

### 6. 📈 Analytics Dashboard
- Fulfillment trends chart (open vs fulfilled needs by month)
- Need status donut chart (open / in-progress / fulfilled breakdown)
- Top 5 needs by applicant count
- Date range filter
- CSV export of all needs data

### 7. 🔔 Notifications
- Receive alerts when volunteers accept or decline tasks
- Status change notifications for every assignment transition
- Rating prompts when tasks are verified

---

## 🙋 Volunteer Portal — Features

### 1. 🔍 Explore Needs
- Live feed of all open needs from Firestore
- **List View** — responsive grid (1/2/3 columns based on screen width)
- **Map View** — real OpenStreetMap with urgency-colored pins (green = low, orange = medium, red = high)
- Search by title, description, or skill keyword
- Filter by category (Technology, Education, Medical, Environment, Legal, Community)
- Tap any map pin → popup summary card with "View Details" button

### 2. 📌 Task Detail & Apply
- Full need details: title, description, required skills, category, deadline, urgency
- NGO name and coordinator contact point
- **Embedded OSM map** showing the coordinator/need location (geocoded automatically)
- **Accept Task** — creates assignment, advances to "Accepted", notifies NGO instantly
- **Decline Task** — marks as declined, notifies NGO to offer to next ranked volunteer
- Expired deadline detection — accept button disabled automatically

### 3. 🗂️ My Tasks (Kanban)
- Personal Kanban board of all accepted assignments
- Columns: **Invited → Accepted → In Progress → Reported → Verified → Closed**
- Volunteer can advance their own tasks:
  - Mark as **In Progress** when they start
  - Mark as **Reported** when complete (triggers NGO verification)
- Declined tasks filtered out automatically
- Completed tasks show a "Completed" badge

### 4. 👤 Profile
- Select skills (used for AI matching — Jaccard similarity scoring)
- Select languages and preferred causes
- Set availability (Weekdays / Weekends / Evenings / Full-time / Flexible)
- Location field — geocoded to lat/lng for proximity-based matching
- Past experience text
- Live stats: average rating, tasks completed, skills count
- Saving profile re-runs AI matching against all open needs

### 5. 🔔 Notifications
- Match invites when a new need matches your skills (top 5 only)
- Status change alerts from NGO (verified, closed, etc.)

---

## 🔗 NGO ↔ Volunteer Interactions

| Action | Trigger | Effect on Other Side |
|---|---|---|
| NGO posts a need | Create Need form | Top 5 matched volunteers get notified |
| Volunteer accepts task | Task Detail → Accept | NGO sees card move to "Accepted" on Kanban |
| Volunteer starts task | My Tasks → In Progress | NGO Kanban updates live; need status → in-progress |
| Volunteer marks reported | My Tasks → Reported | NGO gets notification to verify |
| NGO verifies task | Task Board → Mark Verified | Volunteer notified; NGO gets rating prompt |
| NGO closes task | Task Board → Closed | Volunteer notified; completedTaskCount incremented |
| Volunteer declines | Task Detail → Decline | NGO notified to offer to next ranked volunteer |

---

## 🤖 AI Features

### Groq LLaMA 3.3 70B powers:
- **Need extraction** from raw survey/report text
- **Volunteer-to-need matching** re-ranking (on top of rule-based scoring)
- **Need prioritization** by urgency score

### Rule-based matching engine:
```
Final Score = (0.5 × Skill Score) + (0.3 × Proximity Score) + (0.2 × Availability Score)
            × (1 + Rating Bonus)

Skill Score     = Jaccard similarity of skill sets × 100
Proximity Score = max(0, 100 - haversine_distance_km)
Rating Bonus    = (averageRating / 5.0) × 0.1   [max 10% boost]
```

---

## 🛠️ Local Setup

### Backend
```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
# Add your keys to .env
uvicorn main:app --reload --port 8000
```

### Frontend
```bash
cd ngo_connect
flutter pub get
flutter run -d chrome
```

### Environment Variables (`backend/.env`)
```
GROQ_API_KEY=your_groq_api_key
GEMINI_API_KEY=your_gemini_api_key   # optional fallback
```

---

## 🚢 Deployment

| Service | Platform |
|---|---|
| Backend | Render (Docker) |
| Frontend | Firebase Hosting |

**Render config:**
- Root directory: `backend`
- Build: `pip install -r requirements.txt`
- Start: `uvicorn main:app --host 0.0.0.0 --port $PORT`
- Add `GROQ_API_KEY` in Render environment variables

**Firebase Hosting:**
```bash
flutter build web
firebase deploy
```

---

## 👥 Authors

- **Nikhil Gupta** — [@Nikhilg27425](https://github.com/Nikhilg27425)
- **Vanshika Thadani** — [@vanshika-thadani](https://github.com/vanshika-thadani)
- **Prachi Nainwani** — [@PrachiNainwani31](https://github.com/PrachiNainwani31)
- **Prachi Saxena** — [@prachis2312](https://github.com/prachis2312)

---

<p align="center">Built with ❤️ for GDG Solution Challenge 2026</p>
