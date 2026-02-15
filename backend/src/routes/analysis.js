const express = require('express');
const router = express.Router();
const db = require('../db');
const analysisService = require('../services/analysisService');

// Middleware to get user from device_id
async function getUserId(deviceId) {
  const result = await db.query(
    'SELECT id FROM users WHERE device_id = $1',
    [deviceId]
  );
  return result.rows.length > 0 ? result.rows[0].id : null;
}

// POST /api/analysis/:transcriptId/conversation - Analyze a specific transcript
router.post('/:transcriptId/conversation', async (req, res) => {
  try {
    const { transcriptId } = req.params;
    const { device_id } = req.body;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getUserId(device_id);
    if (!userId) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Get the transcript
    const transcriptResult = await db.query(
      'SELECT transcript, session_name FROM transcripts WHERE id = $1 AND user_id = $2',
      [transcriptId, userId]
    );
    
    if (transcriptResult.rows.length === 0) {
      return res.status(404).json({ error: 'Transcript not found' });
    }
    
    const { transcript, session_name } = transcriptResult.rows[0];
    
    // Run analysis
    const analysis = await analysisService.analyzeConversation(transcript);
    
    // Save analysis to database
    await db.query(
      `INSERT INTO transcript_analysis (transcript_id, analysis_type, result)
       VALUES ($1, 'cognitive', $2)
       ON CONFLICT DO NOTHING`,
      [transcriptId, JSON.stringify(analysis)]
    );
    
    res.json(analysis);
  } catch (err) {
    console.error('Error analyzing transcript:', err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/analysis/:transcriptId/tasks - Extract tasks from transcript
router.post('/:transcriptId/tasks', async (req, res) => {
  try {
    const { transcriptId } = req.params;
    const { device_id } = req.body;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getUserId(device_id);
    if (!userId) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Get the transcript
    const transcriptResult = await db.query(
      'SELECT transcript FROM transcripts WHERE id = $1 AND user_id = $2',
      [transcriptId, userId]
    );
    
    if (transcriptResult.rows.length === 0) {
      return res.status(404).json({ error: 'Transcript not found' });
    }
    
    const { transcript } = transcriptResult.rows[0];
    
    // Extract tasks
    const extracted = await analysisService.extractTasks(transcript);
    
    // Save tasks to database
    for (const task of extracted.tasks || []) {
      await db.query(
        `INSERT INTO tasks (user_id, transcript_id, title, description)
         VALUES ($1, $2, $3, $4)`,
        [userId, transcriptId, task.title, task.description || '']
      );
    }
    
    // Save analysis result
    await db.query(
      `INSERT INTO transcript_analysis (transcript_id, analysis_type, result)
       VALUES ($1, 'tasks', $2)`,
      [transcriptId, JSON.stringify(extracted)]
    );
    
    res.json(extracted);
  } catch (err) {
    console.error('Error extracting tasks:', err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/analysis/:transcriptId/summary - Generate summary
router.post('/:transcriptId/summary', async (req, res) => {
  try {
    const { transcriptId } = req.params;
    const { device_id } = req.body;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getUserId(device_id);
    if (!userId) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Get the transcript
    const transcriptResult = await db.query(
      'SELECT transcript FROM transcripts WHERE id = $1 AND user_id = $2',
      [transcriptId, userId]
    );
    
    if (transcriptResult.rows.length === 0) {
      return res.status(404).json({ error: 'Transcript not found' });
    }
    
    const { transcript } = transcriptResult.rows[0];
    
    // Generate summary
    const summary = await analysisService.generateSummary(transcript);
    
    // Save analysis
    await db.query(
      `INSERT INTO transcript_analysis (transcript_id, analysis_type, result)
       VALUES ($1, 'summary', $2)`,
      [transcriptId, JSON.stringify(summary)]
    );
    
    res.json(summary);
  } catch (err) {
    console.error('Error generating summary:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/analysis/trends - Get trend analysis across recent transcripts
router.get('/trends', async (req, res) => {
  try {
    const { device_id, days = 30 } = req.query;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getUserId(device_id);
    if (!userId) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Get recent transcripts
    const transcriptsResult = await db.query(
      `SELECT id, transcript, created_at 
       FROM transcripts 
       WHERE user_id = $1 AND created_at > NOW() - INTERVAL '${parseInt(days)} days'
       ORDER BY created_at DESC
       LIMIT 10`,
      [userId]
    );
    
    if (transcriptsResult.rows.length < 2) {
      return res.json({ 
        message: 'Need at least 2 transcripts for trend analysis',
        transcript_count: transcriptsResult.rows.length
      });
    }
    
    // Analyze trends
    const trends = await analysisService.analyzeTrends(transcriptsResult.rows);
    
    res.json({
      period_days: parseInt(days),
      transcript_count: transcriptsResult.rows.length,
      ...trends
    });
  } catch (err) {
    console.error('Error analyzing trends:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/analysis/stats - Get overall statistics
router.get('/stats', async (req, res) => {
  try {
    const { device_id } = req.query;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getUserId(device_id);
    if (!userId) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Get stats
    const stats = await db.query(
      `SELECT 
        (SELECT COUNT(*) FROM transcripts WHERE user_id = $1) as total_transcripts,
        (SELECT COALESCE(SUM(duration_seconds), 0) FROM transcripts WHERE user_id = $1) as total_duration_seconds,
        (SELECT COUNT(*) FROM tasks WHERE user_id = $1) as total_tasks,
        (SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND is_completed = true) as completed_tasks,
        (SELECT COUNT(*) FROM transcripts WHERE user_id = $1 AND created_at > NOW() - INTERVAL '7 days') as transcripts_last_week,
        (SELECT COUNT(*) FROM transcripts WHERE user_id = $1 AND created_at > NOW() - INTERVAL '30 days') as transcripts_last_month`,
      [userId]
    );
    
    const row = stats.rows[0];
    res.json({
      total_transcripts: parseInt(row.total_transcripts),
      total_duration_minutes: Math.round(parseInt(row.total_duration_seconds) / 60),
      total_tasks: parseInt(row.total_tasks),
      completed_tasks: parseInt(row.completed_tasks),
      task_completion_rate: row.total_tasks > 0 
        ? Math.round((row.completed_tasks / row.total_tasks) * 100) 
        : 0,
      transcripts_last_week: parseInt(row.transcripts_last_week),
      transcripts_last_month: parseInt(row.transcripts_last_month)
    });
  } catch (err) {
    console.error('Error getting stats:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
