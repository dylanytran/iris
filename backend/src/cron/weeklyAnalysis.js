/**
 * Weekly Analysis Cron Job
 * 
 * This script is designed to be run as a Render Cron Job.
 * It analyzes all transcripts from the past week and generates
 * cognitive health reports for each user.
 * 
 * Schedule: Weekly (e.g., every Sunday at midnight)
 * Command: node src/cron/weeklyAnalysis.js
 */

require('dotenv').config();
const { Pool } = require('pg');
const OpenAI = require('openai');

// Database connection
const db = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

// OpenAI client
const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
});

/**
 * Main entry point for cron job
 */
async function runWeeklyAnalysis() {
    console.log('🗓️  Starting weekly transcript analysis...');
    console.log(`📅 Date: ${new Date().toISOString()}`);

    try {
        // Get all users with transcripts from the past week
        const usersResult = await db.query(`
            SELECT DISTINCT u.id, u.device_id, u.name
            FROM users u
            JOIN transcripts t ON t.user_id = u.id
            WHERE t.created_at >= NOW() - INTERVAL '7 days'
        `);

        console.log(`👥 Found ${usersResult.rows.length} users with recent transcripts`);

        for (const user of usersResult.rows) {
            await analyzeUserWeek(user);
        }

        console.log('✅ Weekly analysis complete!');

    } catch (error) {
        console.error('❌ Weekly analysis failed:', error);
        process.exit(1);
    } finally {
        await db.end();
    }
}

/**
 * Analyze a single user's transcripts from the past week
 */
async function analyzeUserWeek(user) {
    console.log(`\n📊 Analyzing user: ${user.name || user.device_id}`);

    // Get all transcripts from the past week
    const transcriptsResult = await db.query(`
        SELECT id, session_name, transcript, duration_seconds, participants, created_at
        FROM transcripts
        WHERE user_id = $1 AND created_at >= NOW() - INTERVAL '7 days'
        ORDER BY created_at ASC
    `, [user.id]);

    const transcripts = transcriptsResult.rows;
    console.log(`   📝 Found ${transcripts.length} transcripts this week`);

    if (transcripts.length === 0) {
        return;
    }

    // Calculate basic stats
    const stats = {
        totalTranscripts: transcripts.length,
        totalDuration: transcripts.reduce((sum, t) => sum + (t.duration_seconds || 0), 0),
        averageDuration: Math.round(transcripts.reduce((sum, t) => sum + (t.duration_seconds || 0), 0) / transcripts.length),
        totalWords: transcripts.reduce((sum, t) => sum + t.transcript.split(/\s+/).length, 0)
    };

    console.log(`   ⏱️  Total call time: ${Math.round(stats.totalDuration / 60)} minutes`);

    // Generate weekly cognitive analysis
    const weeklyAnalysis = await generateWeeklyReport(user, transcripts, stats);

    // Store the weekly report
    await db.query(`
        INSERT INTO transcript_analysis (transcript_id, analysis_type, result)
        VALUES ($1, 'weekly_report', $2)
    `, [transcripts[transcripts.length - 1].id, JSON.stringify(weeklyAnalysis)]);

    console.log(`   ✅ Weekly report generated and saved`);

    // Check for alerts
    if (weeklyAnalysis.alertLevel === 'significant' || weeklyAnalysis.alertLevel === 'moderate') {
        console.log(`   ⚠️  ALERT: ${weeklyAnalysis.alertLevel} concerns detected`);
        // TODO: Send notification to caregiver
        // await sendAlert(user, weeklyAnalysis);
    }
}

/**
 * Generate a comprehensive weekly cognitive health report
 */
async function generateWeeklyReport(user, transcripts, stats) {
    // Prepare transcript excerpts for analysis
    const excerpts = transcripts.map((t, i) => {
        const date = new Date(t.created_at).toLocaleDateString();
        const excerpt = t.transcript.substring(0, 800);
        return `--- ${t.session_name} (${date}, ${Math.round((t.duration_seconds || 0) / 60)} min) ---\n${excerpt}...`;
    }).join('\n\n');

    const response = await openai.chat.completions.create({
        model: 'gpt-4o-mini',
        messages: [
            {
                role: 'system',
                content: `You are an expert in cognitive health monitoring. Analyze the following week's worth of conversations and provide a comprehensive weekly report.

The user's name is: ${user.name || 'Unknown'}

Provide your analysis as a JSON object with these fields:
{
  "weekSummary": "2-3 paragraph summary of the week's conversations and any notable patterns",
  "cognitiveScores": {
    "clarity": 1-10 average score,
    "coherence": 1-10 average score,
    "wordFinding": 1-10 average score (10=no issues),
    "memoryRecall": 1-10 score for ability to recall past events,
    "futureOrientation": 1-10 score for discussing/planning future events,
    "engagement": 1-10 average engagement level
  },
  "weeklyTrend": "improving" | "stable" | "declining" | "variable",
  "moodPattern": "Description of emotional patterns observed this week",
  "socialActivity": {
    "callFrequency": "How often they're engaging in calls",
    "relationshipTypes": ["family", "medical", "social", etc.],
    "socialEngagement": "Assessment of social interaction quality"
  },
  "keyTopicsThisWeek": ["List of main topics discussed"],
  "memorableEvents": ["Notable events or conversations from the week"],
  "tasksAndFollowUps": ["Any pending tasks or follow-ups needed"],
  "strengths": ["Cognitive/communication strengths observed"],
  "areasOfConcern": ["Any concerning patterns or behaviors"],
  "recommendations": ["Suggestions for the coming week"],
  "alertLevel": "normal" | "mild" | "moderate" | "significant",
  "caregiverNotes": "Brief note for caregiver/family about this week"
}`
            },
            {
                role: 'user',
                content: `Weekly Statistics:
- Total conversations: ${stats.totalTranscripts}
- Total call time: ${Math.round(stats.totalDuration / 60)} minutes
- Average call length: ${Math.round(stats.averageDuration / 60)} minutes
- Words spoken: ${stats.totalWords}

Conversation excerpts from this week:

${excerpts}`
            }
        ],
        response_format: { type: 'json_object' },
        temperature: 0.3,
        max_tokens: 2000
    });

    const analysis = JSON.parse(response.choices[0].message.content);

    // Add metadata
    analysis.generatedAt = new Date().toISOString();
    analysis.userId = user.id;
    analysis.periodStart = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    analysis.periodEnd = new Date().toISOString();
    analysis.stats = stats;

    return analysis;
}

// Run the analysis
runWeeklyAnalysis();
