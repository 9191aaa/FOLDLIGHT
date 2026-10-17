-- Existing matches keep their original rules; new clients explicitly request v4.
ALTER TABLE race_rooms ADD COLUMN rules_version TEXT NOT NULL DEFAULT 'endless_race_v3';
