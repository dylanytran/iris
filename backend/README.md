# Iris Backend API

Backend service for the Iris app - stores meeting transcripts and provides cognitive analysis.

## Features

- **Transcript Storage**: PostgreSQL database for all meeting transcripts
- **Multi-device Sync**: Access transcripts from any device via device_id
- **Full-text Search**: Search across all your past conversations
- **Cognitive Analysis**: AI-powered analysis of conversation patterns
- **Task Extraction**: Automatically extract tasks and reminders from calls
- **Trend Analysis**: Track cognitive health patterns over time

## API Endpoints

### Transcripts

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/transcripts` | Save a new transcript |
| GET | `/api/transcripts` | List all transcripts |
| GET | `/api/transcripts/:id` | Get a single transcript |
| GET | `/api/transcripts/search?q=...` | Search transcripts |
| DELETE | `/api/transcripts/:id` | Delete a transcript |

### Analysis

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/analysis/:id/conversation` | Analyze cognitive patterns |
| POST | `/api/analysis/:id/tasks` | Extract tasks from transcript |
| POST | `/api/analysis/:id/summary` | Generate summary |
| GET | `/api/analysis/trends` | Trend analysis over time |
| GET | `/api/analysis/stats` | Overall statistics |

## Analysis Features

### Cognitive Analysis
Returns insights about:
- **Clarity** (1-10): How clearly thoughts are expressed
- **Coherence** (1-10): Logical flow of conversation
- **Word Finding** (1-10): Difficulty finding words (lower = more difficulty)
- **Repetition** (1-10): Degree of repetition
- **Engagement** (1-10): How engaged/participatory
- Memory references and orientation
- Mood indicators
- Recommendations and alerts

### Task Extraction
Automatically identifies:
- Action items and tasks
- Appointments
- Medication reminders

### Trend Analysis
Analyzes multiple conversations to identify:
- Overall cognitive trends (improving/stable/declining)
- Mood patterns over time
- Areas of strength and concern
- Recommendations for support

## Deploy to Render

### Option 1: One-click Deploy
1. Fork this repo
2. Go to [Render Dashboard](https://dashboard.render.com/)
3. Click "New" → "Blueprint"
4. Connect your repo
5. Render will create the database and service automatically
6. Set `OPENAI_API_KEY` in environment variables

### Option 2: Manual Deploy
1. Create a PostgreSQL database on Render
2. Create a Web Service pointing to `/backend`
3. Set environment variables:
   - `DATABASE_URL`: Your Postgres connection string
   - `OPENAI_API_KEY`: Your OpenAI API key
4. Deploy!

## Local Development

```bash
# Install dependencies
npm install

# Copy environment variables
cp .env.example .env
# Edit .env with your values

# Run migrations
npm run migrate

# Start dev server
npm run dev
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `OPENAI_API_KEY` | OpenAI API key for analysis |
| `PORT` | Server port (default: 3000) |
| `NODE_ENV` | `development` or `production` |

## Example Usage

### Save a transcript
```bash
curl -X POST https://your-api.onrender.com/api/transcripts \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "your-device-uuid",
    "session_name": "Call with Dr. Smith",
    "transcript": "The full transcript text...",
    "duration_seconds": 1800,
    "participants": ["Me", "Dr. Smith"]
  }'
```

### Analyze a transcript
```bash
curl -X POST https://your-api.onrender.com/api/analysis/TRANSCRIPT_ID/conversation \
  -H "Content-Type: application/json" \
  -d '{"device_id": "your-device-uuid"}'
```

### Search transcripts
```bash
curl "https://your-api.onrender.com/api/transcripts/search?device_id=xxx&q=medication"
```
