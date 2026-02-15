const express = require('express');
const router = express.Router();
const db = require('../db');
const { v4: uuidv4 } = require('uuid');

// Middleware to get or create user from device_id
async function getOrCreateUser(deviceId) {
  // Try to find existing user
  let result = await db.query(
    'SELECT id FROM users WHERE device_id = $1',
    [deviceId]
  );
  
  if (result.rows.length > 0) {
    // Update last_seen
    await db.query(
      'UPDATE users SET last_seen = CURRENT_TIMESTAMP WHERE id = $1',
      [result.rows[0].id]
    );
    return result.rows[0].id;
  }
  
  // Create new user
  result = await db.query(
    'INSERT INTO users (device_id) VALUES ($1) RETURNING id',
    [deviceId]
  );
  return result.rows[0].id;
}

// POST /api/transcripts - Save a new transcript
router.post('/', async (req, res) => {
  try {
    const { device_id, session_name, transcript, duration_seconds, participants } = req.body;
    
    if (!device_id || !transcript) {
      return res.status(400).json({ error: 'device_id and transcript are required' });
    }
    
    const userId = await getOrCreateUser(device_id);
    
    const result = await db.query(
      `INSERT INTO transcripts (user_id, session_name, transcript, duration_seconds, participants)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [userId, session_name || 'Untitled', transcript, duration_seconds || 0, participants || []]
    );
    
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error saving transcript:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/transcripts - List all transcripts for a user
router.get('/', async (req, res) => {
  try {
    const { device_id, limit = 50, offset = 0 } = req.query;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getOrCreateUser(device_id);
    
    const result = await db.query(
      `SELECT id, session_name, 
              LEFT(transcript, 200) as preview,
              duration_seconds, participants, created_at
       FROM transcripts 
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset]
    );
    
    res.json(result.rows);
  } catch (err) {
    console.error('Error listing transcripts:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/transcripts/:id - Get a single transcript
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { device_id } = req.query;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getOrCreateUser(device_id);
    
    const result = await db.query(
      `SELECT t.*, 
              (SELECT json_agg(ta.*) FROM transcript_analysis ta WHERE ta.transcript_id = t.id) as analyses
       FROM transcripts t
       WHERE t.id = $1 AND t.user_id = $2`,
      [id, userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Transcript not found' });
    }
    
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Error fetching transcript:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/transcripts/search - Search transcripts
router.get('/search', async (req, res) => {
  try {
    const { device_id, q, limit = 20 } = req.query;
    
    if (!device_id || !q) {
      return res.status(400).json({ error: 'device_id and q (query) are required' });
    }
    
    const userId = await getOrCreateUser(device_id);
    
    const result = await db.query(
      `SELECT id, session_name, 
              ts_headline('english', transcript, plainto_tsquery('english', $2), 
                'MaxWords=50, MinWords=20, StartSel=**, StopSel=**') as highlight,
              duration_seconds, participants, created_at,
              ts_rank(to_tsvector('english', transcript), plainto_tsquery('english', $2)) as rank
       FROM transcripts 
       WHERE user_id = $1 
         AND to_tsvector('english', transcript) @@ plainto_tsquery('english', $2)
       ORDER BY rank DESC, created_at DESC
       LIMIT $3`,
      [userId, q, limit]
    );
    
    res.json(result.rows);
  } catch (err) {
    console.error('Error searching transcripts:', err);
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/transcripts/:id - Delete a transcript
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { device_id } = req.query;
    
    if (!device_id) {
      return res.status(400).json({ error: 'device_id is required' });
    }
    
    const userId = await getOrCreateUser(device_id);
    
    const result = await db.query(
      'DELETE FROM transcripts WHERE id = $1 AND user_id = $2 RETURNING id',
      [id, userId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Transcript not found' });
    }
    
    res.json({ deleted: true, id });
  } catch (err) {
    console.error('Error deleting transcript:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
