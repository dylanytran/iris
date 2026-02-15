const OpenAI = require('openai');

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

/**
 * Analyze a transcript for cognitive patterns and conversation quality
 */
async function analyzeConversation(transcript, participantName = 'User') {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `You are an expert in conversation analysis, cognitive assessment, and memory health. 
Analyze the following transcript and provide insights about the speaker's cognitive patterns.

Return a JSON object with these fields:
{
  "summary": "2-3 sentence summary of the conversation",
  "topics": ["array", "of", "main", "topics"],
  "mood": "overall emotional tone (positive/neutral/negative/mixed)",
  "mood_indicators": ["specific words/phrases that indicate mood"],
  "cognitive_observations": {
    "clarity": 1-10 score for how clearly thoughts are expressed,
    "coherence": 1-10 score for logical flow of conversation,
    "word_finding": 1-10 score (10=no issues, lower=difficulty finding words),
    "repetition": 1-10 score (10=no repetition, lower=more repetition),
    "engagement": 1-10 score for how engaged/participatory,
    "notes": "any notable cognitive observations"
  },
  "memory_references": {
    "past_events_mentioned": ["events the person recalled"],
    "future_plans_mentioned": ["upcoming events/tasks discussed"],
    "orientation": "assessment of awareness of time/place/context"
  },
  "communication_style": {
    "verbosity": "brief/moderate/verbose",
    "question_ratio": "how often they ask vs answer questions",
    "initiative": "proactive/reactive in conversation"
  },
  "recommendations": ["suggestions for the caregiver or family"],
  "alerts": ["any concerning patterns that should be flagged"]
}`
      },
      {
        role: 'user',
        content: `Analyze this conversation transcript for ${participantName}:\n\n${transcript}`
      }
    ],
    response_format: { type: 'json_object' },
    temperature: 0.3
  });

  return JSON.parse(response.choices[0].message.content);
}

/**
 * Extract tasks and reminders from transcript
 */
async function extractTasks(transcript) {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `Extract tasks, reminders, and action items from this conversation transcript.

Return a JSON object:
{
  "tasks": [
    {
      "title": "Short task title",
      "description": "More detail if available",
      "priority": "high/medium/low",
      "due_date_hint": "any mentioned timing (e.g., 'tomorrow', 'next week', null if none)",
      "source_quote": "exact quote from transcript mentioning this"
    }
  ],
  "appointments": [
    {
      "title": "Appointment name",
      "datetime_hint": "mentioned time/date",
      "location": "if mentioned",
      "source_quote": "exact quote"
    }
  ],
  "medications": [
    {
      "name": "medication name if mentioned",
      "instruction": "any dosage/timing mentioned",
      "source_quote": "exact quote"
    }
  ]
}`
      },
      {
        role: 'user',
        content: transcript
      }
    ],
    response_format: { type: 'json_object' },
    temperature: 0.2
  });

  return JSON.parse(response.choices[0].message.content);
}

/**
 * Generate a simple summary for quick reference
 */
async function generateSummary(transcript) {
  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `Summarize this conversation in 2-3 sentences. Focus on the main topic and any important decisions or information shared.`
      },
      {
        role: 'user',
        content: transcript
      }
    ],
    temperature: 0.3,
    max_tokens: 200
  });

  return { summary: response.choices[0].message.content };
}

/**
 * Trend analysis across multiple transcripts
 */
async function analyzeTrends(transcripts) {
  // Combine recent transcripts for trend analysis
  const combined = transcripts.map((t, i) => 
    `--- Conversation ${i + 1} (${t.created_at}) ---\n${t.transcript.substring(0, 500)}...`
  ).join('\n\n');

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `You are analyzing multiple conversations over time to identify trends in cognitive health and communication patterns.

Return a JSON object:
{
  "overall_assessment": "Brief overall assessment",
  "trends": {
    "cognitive": "improving/stable/declining/insufficient_data",
    "mood": "improving/stable/declining/variable",
    "engagement": "improving/stable/declining"
  },
  "notable_changes": ["any significant changes observed"],
  "consistent_patterns": ["patterns that appear across conversations"],
  "areas_of_strength": ["cognitive/communication strengths"],
  "areas_of_concern": ["any concerning patterns"],
  "recommendations": ["suggestions for support"]
}`
      },
      {
        role: 'user',
        content: `Analyze these ${transcripts.length} recent conversations for trends:\n\n${combined}`
      }
    ],
    response_format: { type: 'json_object' },
    temperature: 0.3
  });

  return JSON.parse(response.choices[0].message.content);
}

module.exports = {
  analyzeConversation,
  extractTasks,
  generateSummary,
  analyzeTrends
};
