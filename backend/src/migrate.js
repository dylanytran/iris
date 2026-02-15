require('dotenv').config();
const db = require('./db');

const migrations = [
  // Users table (for multi-device sync)
  `CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )`,

  // Transcripts table
  `CREATE TABLE IF NOT EXISTS transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    session_name VARCHAR(255) NOT NULL,
    transcript TEXT NOT NULL,
    duration_seconds INTEGER,
    participants TEXT[], -- Array of participant names
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )`,

  // Analysis results table
  `CREATE TABLE IF NOT EXISTS transcript_analysis (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transcript_id UUID REFERENCES transcripts(id) ON DELETE CASCADE,
    analysis_type VARCHAR(50) NOT NULL, -- 'cognitive', 'mood', 'summary', 'tasks'
    result JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )`,

  // Tasks extracted from transcripts
  `CREATE TABLE IF NOT EXISTS tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    transcript_id UUID REFERENCES transcripts(id) ON DELETE SET NULL,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    due_date TIMESTAMP,
    is_completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
  )`,

  // Indexes for search performance
  `CREATE INDEX IF NOT EXISTS idx_transcripts_user_id ON transcripts(user_id)`,
  `CREATE INDEX IF NOT EXISTS idx_transcripts_created_at ON transcripts(created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_transcripts_search ON transcripts USING gin(to_tsvector('english', transcript))`,
  `CREATE INDEX IF NOT EXISTS idx_tasks_user_id ON tasks(user_id)`,
  `CREATE INDEX IF NOT EXISTS idx_analysis_transcript_id ON transcript_analysis(transcript_id)`
];

async function migrate() {
  console.log('🔄 Running migrations...');
  
  for (const sql of migrations) {
    try {
      await db.query(sql);
      console.log('✅ Executed:', sql.substring(0, 60) + '...');
    } catch (err) {
      console.error('❌ Migration failed:', err.message);
      console.error('SQL:', sql);
    }
  }
  
  console.log('✅ Migrations complete');
  process.exit(0);
}

migrate();
