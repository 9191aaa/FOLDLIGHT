CREATE TABLE `race_players` (
	`id` text PRIMARY KEY NOT NULL,
	`room` text NOT NULL,
	`name` text NOT NULL,
	`token_hash` text NOT NULL,
	`slot` integer NOT NULL,
	`instance_id` text,
	`ready` integer DEFAULT 0 NOT NULL,
	`status` text DEFAULT 'waiting' NOT NULL,
	`elapsed` real DEFAULT 0 NOT NULL,
	`kills` integer DEFAULT 0 NOT NULL,
	`health` real DEFAULT 1 NOT NULL,
	`seq` integer DEFAULT -1 NOT NULL,
	`joined_at` integer NOT NULL,
	`seen_at` integer NOT NULL,
	`reported_at` integer,
	FOREIGN KEY (`room`) REFERENCES `race_rooms`(`code`) ON UPDATE no action ON DELETE cascade
);

CREATE UNIQUE INDEX `player_room_slot` ON `race_players` (`room`,`slot`);
CREATE INDEX `player_room` ON `race_players` (`room`);
CREATE TABLE `race_rooms` (
	`code` text PRIMARY KEY NOT NULL,
	`seed` integer NOT NULL,
	`phase` text DEFAULT 'waiting' NOT NULL,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	`start_at` integer,
	`creator_hash` text NOT NULL
);

CREATE INDEX `room_creator_time` ON `race_rooms` (`creator_hash`,`created_at`);
CREATE INDEX `room_expiration` ON `race_rooms` (`expires_at`);
