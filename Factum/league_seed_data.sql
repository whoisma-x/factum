-- Fantasy League Seed Data — "who asked" league
-- Run this in the Supabase SQL Editor to populate a working 8-team league.
-- 
-- This creates:
--   • 7 fake user profiles (the 8th is the real user: 61BB6A49-8A34-4DA1-91DE-FA1617C409CF)
--   • 1 league: "who asked" with 8 members
--   • 8 teams with win/loss records through 5 weeks
--   • 48 roster slots (6 per team), drafted
--   • 20 completed matchups (weeks 1-5) + 4 current week matchups
--   • 2 pending trades
--   • Manager ratings for all 8 managers

-- ============================================================
-- FAKE USER PROFILES
-- ============================================================

INSERT INTO users (uid, display_name, username, bio, join_date, total_study_minutes, streak_days, friend_uids, pending_friend_request_uids, subjects, is_private)
VALUES
  ('A1B2C3D4-1111-4000-A000-000000000001'::uuid, 'Jordan Kim', 'jordank', 'grind never stops', now() - interval '90 days', 4820, 12, '{}', '{}', '[{"name":"AP Physics","color":"#5B9BD5"},{"name":"Calc BC","color":"#FF6B6B"},{"name":"AP English","color":"#4ECDC4"},{"name":"AP Psych","color":"#DFE6E9"},{"name":"AP World","color":"#636E72"},{"name":"Precalc","color":"#B2BEC3"}]', false),
  ('A1B2C3D4-2222-4000-A000-000000000002'::uuid, 'Priya Sharma', 'priya_s', 'med school or bust', now() - interval '120 days', 6340, 8, '{}', '{}', '[{"name":"AP Biology","color":"#95E1D3"},{"name":"AP Chemistry","color":"#F38181"},{"name":"Organic Chem","color":"#AA96DA"},{"name":"Anatomy","color":"#E8D5B7"},{"name":"Bioethics","color":"#C4E538"},{"name":"MCAT Prep","color":"#7ED6DF"}]', false),
  ('A1B2C3D4-3333-4000-A000-000000000003'::uuid, 'Marcus Johnson', 'marcusj', 'cs major loading...', now() - interval '60 days', 3210, 5, '{}', '{}', '[{"name":"Data Structures","color":"#6C5CE7"},{"name":"Linear Algebra","color":"#00B894"},{"name":"AP CS","color":"#FDCB6E"},{"name":"Discrete Math","color":"#E056A0"},{"name":"Algorithms","color":"#10AC84"},{"name":"OS","color":"#EE5A24"}]', false),
  ('A1B2C3D4-4444-4000-A000-000000000004'::uuid, 'Sophie Chen', 'soph.chen', 'studying is my sport', now() - interval '150 days', 8920, 21, '{}', '{}', '[{"name":"SAT Math","color":"#E17055"},{"name":"SAT English","color":"#74B9FF"},{"name":"AP History","color":"#A29BFE"},{"name":"AP Art History","color":"#FDA7DF"},{"name":"AP Euro","color":"#55E6C1"},{"name":"AP Seminar","color":"#D980FA"}]', false),
  ('A1B2C3D4-5555-4000-A000-000000000005'::uuid, 'Tyler Brooks', 'tylerb', 'barely surviving', now() - interval '45 days', 1890, 3, '{}', '{}', '[{"name":"AP Gov","color":"#55E6C1"},{"name":"AP Econ","color":"#F8C291"},{"name":"Statistics","color":"#82CCDD"},{"name":"Sociology","color":"#EAB543"},{"name":"AP Human Geo","color":"#58B19F"},{"name":"Rhetoric","color":"#B53471"}]', false),
  ('A1B2C3D4-6666-4000-A000-000000000006'::uuid, 'Emily Patel', 'emilyp', 'future engineer', now() - interval '200 days', 7450, 15, '{}', '{}', '[{"name":"Physics C","color":"#E77F67"},{"name":"Multivariable","color":"#778BEB"},{"name":"AP CS A","color":"#F3A683"},{"name":"Diff Eq","color":"#0652DD"},{"name":"Circuits","color":"#9980FA"},{"name":"Thermo","color":"#FD7272"}]', false),
  ('A1B2C3D4-7777-4000-A000-000000000007'::uuid, 'Ethan Reyes', 'ethanr', 'locked in', now() - interval '75 days', 5100, 9, '{}', '{}', '[{"name":"AP Spanish","color":"#CF6A87"},{"name":"AP Literature","color":"#574B90"},{"name":"World History","color":"#E15F41"},{"name":"Creative Writing","color":"#6AB04C"},{"name":"Latin","color":"#F9CA24"},{"name":"Philosophy","color":"#30336B"}]', false)
ON CONFLICT (uid) DO NOTHING;

-- ============================================================
-- LEAGUE
-- ============================================================

-- Use a fixed league ID so we can reference it everywhere
-- League ID: AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01

INSERT INTO fantasy_leagues (
  id, name, commissioner_uid, member_uids,
  season_start_date, season_end_date, created_at,
  max_roster_size, bench_size, draft_status, draft_order,
  current_draft_pick_index, playoff_team_count,
  icon_name, description, draft_seconds_per_pick
) VALUES (
  'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid,
  'who asked',
  '61BB6A49-8A34-4DA1-91DE-FA1617C409CF',
  ARRAY[
    '61BB6A49-8A34-4DA1-91DE-FA1617C409CF',
    'A1B2C3D4-1111-4000-A000-000000000001',
    'A1B2C3D4-2222-4000-A000-000000000002',
    'A1B2C3D4-3333-4000-A000-000000000003',
    'A1B2C3D4-4444-4000-A000-000000000004',
    'A1B2C3D4-5555-4000-A000-000000000005',
    'A1B2C3D4-6666-4000-A000-000000000006',
    'A1B2C3D4-7777-4000-A000-000000000007'
  ],
  now() - interval '42 days',  -- season started 6 weeks ago
  now() + interval '56 days',  -- 8 more weeks
  now() - interval '42 days',
  6, 0, 'completed',
  ARRAY[
    '61BB6A49-8A34-4DA1-91DE-FA1617C409CF',
    'A1B2C3D4-4444-4000-A000-000000000004',
    'A1B2C3D4-2222-4000-A000-000000000002',
    'A1B2C3D4-6666-4000-A000-000000000006',
    'A1B2C3D4-1111-4000-A000-000000000001',
    'A1B2C3D4-7777-4000-A000-000000000007',
    'A1B2C3D4-3333-4000-A000-000000000003',
    'A1B2C3D4-5555-4000-A000-000000000005'
  ],
  48, 4,
  'emoji:🏆', 'the league where nobody asked but everyone showed up', 60
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- TEAMS (8 teams with records through 5 weeks)
-- ============================================================

-- Team IDs: use deterministic UUIDs for referencing
-- T1 = real user (max c), T2-T8 = fake users

INSERT INTO fantasy_teams (id, league_id, owner_uid, team_name, wins, losses, ties, total_points_for, total_points_against, created_at) VALUES
  ('11111111-0001-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 'max''s pigeons', 4, 1, 0, 487.3, 392.1, now() - interval '42 days'),
  ('11111111-0002-4000-A000-000000000002'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 'jordan''s grinders', 3, 2, 0, 445.8, 421.0, now() - interval '42 days'),
  ('11111111-0003-4000-A000-000000000003'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 'priya''s prodigies', 4, 1, 0, 512.6, 378.4, now() - interval '42 days'),
  ('11111111-0004-4000-A000-000000000004'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 'team marcus', 2, 3, 0, 367.2, 440.9, now() - interval '42 days'),
  ('11111111-0005-4000-A000-000000000005'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 'sophie''s scholars', 5, 0, 0, 548.9, 345.2, now() - interval '42 days'),
  ('11111111-0006-4000-A000-000000000006'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 'barely passing', 1, 4, 0, 298.4, 478.6, now() - interval '42 days'),
  ('11111111-0007-4000-A000-000000000007'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 'aisha''s aces', 3, 2, 0, 468.1, 410.3, now() - interval '42 days'),
  ('11111111-0008-4000-A000-000000000008'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 'ethan''s empire', 2, 3, 0, 389.7, 451.5, now() - interval '42 days')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- ROSTER SLOTS (6 per team = 48 total, all active starters)
-- Each player drafts from OTHER members' subjects
-- ============================================================

INSERT INTO fantasy_roster_slots (id, team_id, league_id, player_uid, subject_name, is_active, acquired_via, multiplier) VALUES
  -- max's pigeons (T1): drafted from other members
  ('22222222-0101-4000-A000-000000000001'::uuid, '11111111-0001-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 'SAT Math', true, 'draft', 3),
  ('22222222-0102-4000-A000-000000000002'::uuid, '11111111-0001-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 'AP Biology', true, 'draft', 3),
  ('22222222-0103-4000-A000-000000000003'::uuid, '11111111-0001-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 'Physics C', true, 'draft', 3),
  ('22222222-0104-4000-A000-000000000004'::uuid, '11111111-0001-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 'AP Physics', true, 'draft', 2),
  ('22222222-0105-4000-A000-000000000005'::uuid, '11111111-0001-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 'AP Literature', true, 'draft', 2),
  ('22222222-0106-4000-A000-000000000006'::uuid, '11111111-0001-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 'Data Structures', true, 'draft', 1),

  -- jordan's grinders (T2)
  ('22222222-0201-4000-A000-000000000001'::uuid, '11111111-0002-4000-A000-000000000002'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 'SAT English', true, 'draft', 3),
  ('22222222-0202-4000-A000-000000000002'::uuid, '11111111-0002-4000-A000-000000000002'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 'Multivariable', true, 'draft', 3),
  ('22222222-0203-4000-A000-000000000003'::uuid, '11111111-0002-4000-A000-000000000002'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 'SAT English', true, 'draft', 3),
  ('22222222-0204-4000-A000-000000000004'::uuid, '11111111-0002-4000-A000-000000000002'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 'Linear Algebra', true, 'draft', 2),
  ('22222222-0205-4000-A000-000000000005'::uuid, '11111111-0002-4000-A000-000000000002'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 'Statistics', true, 'draft', 2),
  ('22222222-0206-4000-A000-000000000006'::uuid, '11111111-0002-4000-A000-000000000002'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 'World History', true, 'draft', 1),

  -- priya's prodigies (T3)
  ('22222222-0301-4000-A000-000000000001'::uuid, '11111111-0003-4000-A000-000000000003'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 'AP CS A', true, 'draft', 3),
  ('22222222-0302-4000-A000-000000000002'::uuid, '11111111-0003-4000-A000-000000000003'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 'AP History', true, 'draft', 3),
  ('22222222-0303-4000-A000-000000000003'::uuid, '11111111-0003-4000-A000-000000000003'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 'Calc BC', true, 'draft', 3),
  ('22222222-0304-4000-A000-000000000004'::uuid, '11111111-0003-4000-A000-000000000003'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 'SAT Math', true, 'draft', 2),
  ('22222222-0305-4000-A000-000000000005'::uuid, '11111111-0003-4000-A000-000000000003'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 'AP Spanish', true, 'draft', 2),
  ('22222222-0306-4000-A000-000000000006'::uuid, '11111111-0003-4000-A000-000000000003'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 'AP Gov', true, 'draft', 1),

  -- team marcus (T4)
  ('22222222-0401-4000-A000-000000000001'::uuid, '11111111-0004-4000-A000-000000000004'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 'AP Chemistry', true, 'draft', 3),
  ('22222222-0402-4000-A000-000000000002'::uuid, '11111111-0004-4000-A000-000000000004'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 'AP English', true, 'draft', 3),
  ('22222222-0403-4000-A000-000000000003'::uuid, '11111111-0004-4000-A000-000000000004'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 'AP Econ', true, 'draft', 3),
  ('22222222-0404-4000-A000-000000000004'::uuid, '11111111-0004-4000-A000-000000000004'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 'Diff Eq', true, 'draft', 2),
  ('22222222-0405-4000-A000-000000000005'::uuid, '11111111-0004-4000-A000-000000000004'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 'Creative Writing', true, 'draft', 2),
  ('22222222-0406-4000-A000-000000000006'::uuid, '11111111-0004-4000-A000-000000000004'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 'English', true, 'draft', 1),

  -- sophie's scholars (T5) — undefeated
  ('22222222-0501-4000-A000-000000000001'::uuid, '11111111-0005-4000-A000-000000000005'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 'Organic Chem', true, 'draft', 3),
  ('22222222-0502-4000-A000-000000000002'::uuid, '11111111-0005-4000-A000-000000000005'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 'Circuits', true, 'draft', 3),
  ('22222222-0503-4000-A000-000000000003'::uuid, '11111111-0005-4000-A000-000000000005'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 'AP Psych', true, 'draft', 3),
  ('22222222-0504-4000-A000-000000000004'::uuid, '11111111-0005-4000-A000-000000000005'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 'AP CS', true, 'draft', 2),
  ('22222222-0505-4000-A000-000000000005'::uuid, '11111111-0005-4000-A000-000000000005'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 'Science', true, 'draft', 2),
  ('22222222-0506-4000-A000-000000000006'::uuid, '11111111-0005-4000-A000-000000000005'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 'Latin', true, 'draft', 1),

  -- barely passing (T6)
  ('22222222-0601-4000-A000-000000000001'::uuid, '11111111-0006-4000-A000-000000000006'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 'Discrete Math', true, 'draft', 3),
  ('22222222-0602-4000-A000-000000000002'::uuid, '11111111-0006-4000-A000-000000000006'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 'Philosophy', true, 'draft', 3),
  ('22222222-0603-4000-A000-000000000003'::uuid, '11111111-0006-4000-A000-000000000006'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 'History', true, 'draft', 3),
  ('22222222-0604-4000-A000-000000000004'::uuid, '11111111-0006-4000-A000-000000000006'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 'Anatomy', true, 'draft', 2),
  ('22222222-0605-4000-A000-000000000005'::uuid, '11111111-0006-4000-A000-000000000006'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 'AP Art History', true, 'draft', 2),
  ('22222222-0606-4000-A000-000000000006'::uuid, '11111111-0006-4000-A000-000000000006'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 'AP World', true, 'draft', 1),

  -- emily's aces (T7)
  ('22222222-0701-4000-A000-000000000001'::uuid, '11111111-0007-4000-A000-000000000007'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 'AP Euro', true, 'draft', 3),
  ('22222222-0702-4000-A000-000000000002'::uuid, '11111111-0007-4000-A000-000000000007'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 'Bioethics', true, 'draft', 3),
  ('22222222-0703-4000-A000-000000000003'::uuid, '11111111-0007-4000-A000-000000000007'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 'Algorithms', true, 'draft', 3),
  ('22222222-0704-4000-A000-000000000004'::uuid, '11111111-0007-4000-A000-000000000007'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 'Sociology', true, 'draft', 2),
  ('22222222-0705-4000-A000-000000000005'::uuid, '11111111-0007-4000-A000-000000000007'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 'Math', true, 'draft', 2),
  ('22222222-0706-4000-A000-000000000006'::uuid, '11111111-0007-4000-A000-000000000007'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 'Precalc', true, 'draft', 1),

  -- ethan's empire (T8)
  ('22222222-0801-4000-A000-000000000001'::uuid, '11111111-0008-4000-A000-000000000008'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 'Thermo', true, 'draft', 3),
  ('22222222-0802-4000-A000-000000000002'::uuid, '11111111-0008-4000-A000-000000000008'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 'AP Seminar', true, 'draft', 3),
  ('22222222-0803-4000-A000-000000000003'::uuid, '11111111-0008-4000-A000-000000000008'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 'MCAT Prep', true, 'draft', 3),
  ('22222222-0804-4000-A000-000000000004'::uuid, '11111111-0008-4000-A000-000000000008'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 'Rhetoric', false, 'draft', 2),
  ('22222222-0805-4000-A000-000000000005'::uuid, '11111111-0008-4000-A000-000000000008'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 'AP Human Geo', true, 'draft', 2),
  ('22222222-0806-4000-A000-000000000006'::uuid, '11111111-0008-4000-A000-000000000008'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 'OS', true, 'draft', 1)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- MATCHUPS — Weeks 1-5 (completed) + Week 6 (current, in progress)
-- Round-robin: 4 matchups per week with 8 teams
-- ============================================================

-- Matchup week start/end are based on season_start_date (42 days ago)
-- Week 1: days 0-6, Week 2: days 7-13, ... Week 6: days 35-41

INSERT INTO fantasy_matchups (id, league_id, week_number, team1_id, team2_id, team1_score, team2_score, winner_team_id, week_start_date, week_end_date, is_playoff, is_bye) VALUES
  -- WEEK 1
  ('33333333-0101-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 1,
   '11111111-0001-4000-A000-000000000001'::uuid, '11111111-0008-4000-A000-000000000008'::uuid,
   102.4, 78.3, '11111111-0001-4000-A000-000000000001'::uuid,
   now() - interval '42 days', now() - interval '36 days', false, false),

  ('33333333-0102-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 1,
   '11111111-0002-4000-A000-000000000002'::uuid, '11111111-0007-4000-A000-000000000007'::uuid,
   89.5, 95.2, '11111111-0007-4000-A000-000000000007'::uuid,
   now() - interval '42 days', now() - interval '36 days', false, false),

  ('33333333-0103-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 1,
   '11111111-0003-4000-A000-000000000003'::uuid, '11111111-0006-4000-A000-000000000006'::uuid,
   110.8, 62.1, '11111111-0003-4000-A000-000000000003'::uuid,
   now() - interval '42 days', now() - interval '36 days', false, false),

  ('33333333-0104-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 1,
   '11111111-0005-4000-A000-000000000005'::uuid, '11111111-0004-4000-A000-000000000004'::uuid,
   115.3, 71.9, '11111111-0005-4000-A000-000000000005'::uuid,
   now() - interval '42 days', now() - interval '36 days', false, false),

  -- WEEK 2
  ('33333333-0201-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 2,
   '11111111-0001-4000-A000-000000000001'::uuid, '11111111-0003-4000-A000-000000000003'::uuid,
   88.7, 105.4, '11111111-0003-4000-A000-000000000003'::uuid,
   now() - interval '35 days', now() - interval '29 days', false, false),

  ('33333333-0202-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 2,
   '11111111-0002-4000-A000-000000000002'::uuid, '11111111-0006-4000-A000-000000000006'::uuid,
   94.1, 58.7, '11111111-0002-4000-A000-000000000002'::uuid,
   now() - interval '35 days', now() - interval '29 days', false, false),

  ('33333333-0203-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 2,
   '11111111-0005-4000-A000-000000000005'::uuid, '11111111-0007-4000-A000-000000000007'::uuid,
   108.9, 92.6, '11111111-0005-4000-A000-000000000005'::uuid,
   now() - interval '35 days', now() - interval '29 days', false, false),

  ('33333333-0204-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 2,
   '11111111-0004-4000-A000-000000000004'::uuid, '11111111-0008-4000-A000-000000000008'::uuid,
   82.3, 79.1, '11111111-0004-4000-A000-000000000004'::uuid,
   now() - interval '35 days', now() - interval '29 days', false, false),

  -- WEEK 3
  ('33333333-0301-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 3,
   '11111111-0001-4000-A000-000000000001'::uuid, '11111111-0006-4000-A000-000000000006'::uuid,
   97.2, 54.8, '11111111-0001-4000-A000-000000000001'::uuid,
   now() - interval '28 days', now() - interval '22 days', false, false),

  ('33333333-0302-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 3,
   '11111111-0002-4000-A000-000000000002'::uuid, '11111111-0005-4000-A000-000000000005'::uuid,
   76.4, 112.8, '11111111-0005-4000-A000-000000000005'::uuid,
   now() - interval '28 days', now() - interval '22 days', false, false),

  ('33333333-0303-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 3,
   '11111111-0003-4000-A000-000000000003'::uuid, '11111111-0004-4000-A000-000000000004'::uuid,
   99.1, 88.6, '11111111-0003-4000-A000-000000000003'::uuid,
   now() - interval '28 days', now() - interval '22 days', false, false),

  ('33333333-0304-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 3,
   '11111111-0007-4000-A000-000000000007'::uuid, '11111111-0008-4000-A000-000000000008'::uuid,
   85.3, 91.7, '11111111-0008-4000-A000-000000000008'::uuid,
   now() - interval '28 days', now() - interval '22 days', false, false),

  -- WEEK 4
  ('33333333-0401-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 4,
   '11111111-0001-4000-A000-000000000001'::uuid, '11111111-0004-4000-A000-000000000004'::uuid,
   103.6, 68.4, '11111111-0001-4000-A000-000000000001'::uuid,
   now() - interval '21 days', now() - interval '15 days', false, false),

  ('33333333-0402-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 4,
   '11111111-0002-4000-A000-000000000002'::uuid, '11111111-0004-4000-A000-000000000004'::uuid,
   91.7, 56.3, '11111111-0002-4000-A000-000000000002'::uuid,
   now() - interval '21 days', now() - interval '15 days', false, false),

  ('33333333-0403-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 4,
   '11111111-0005-4000-A000-000000000005'::uuid, '11111111-0008-4000-A000-000000000008'::uuid,
   99.2, 72.8, '11111111-0005-4000-A000-000000000005'::uuid,
   now() - interval '21 days', now() - interval '15 days', false, false),

  ('33333333-0404-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 4,
   '11111111-0003-4000-A000-000000000003'::uuid, '11111111-0007-4000-A000-000000000007'::uuid,
   87.5, 95.0, '11111111-0007-4000-A000-000000000007'::uuid,
   now() - interval '21 days', now() - interval '15 days', false, false),

  -- WEEK 5
  ('33333333-0501-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 5,
   '11111111-0001-4000-A000-000000000001'::uuid, '11111111-0007-4000-A000-000000000007'::uuid,
   95.4, 100.5, '11111111-0007-4000-A000-000000000007'::uuid,
   now() - interval '14 days', now() - interval '8 days', false, false),

  ('33333333-0502-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 5,
   '11111111-0002-4000-A000-000000000002'::uuid, '11111111-0003-4000-A000-000000000003'::uuid,
   94.1, 109.8, '11111111-0003-4000-A000-000000000003'::uuid,
   now() - interval '14 days', now() - interval '8 days', false, false),

  ('33333333-0503-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 5,
   '11111111-0005-4000-A000-000000000005'::uuid, '11111111-0006-4000-A000-000000000006'::uuid,
   112.7, 66.5, '11111111-0005-4000-A000-000000000005'::uuid,
   now() - interval '14 days', now() - interval '8 days', false, false),

  ('33333333-0504-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 5,
   '11111111-0004-4000-A000-000000000004'::uuid, '11111111-0008-4000-A000-000000000008'::uuid,
   56.0, 67.8, '11111111-0008-4000-A000-000000000008'::uuid,
   now() - interval '14 days', now() - interval '8 days', false, false),

  -- WEEK 6 (CURRENT — scores in progress)
  ('33333333-0601-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 6,
   '11111111-0001-4000-A000-000000000001'::uuid, '11111111-0002-4000-A000-000000000002'::uuid,
   67.2, 54.8, NULL,
   now() - interval '7 days', now(), false, false),

  ('33333333-0602-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 6,
   '11111111-0003-4000-A000-000000000003'::uuid, '11111111-0008-4000-A000-000000000008'::uuid,
   72.1, 48.3, NULL,
   now() - interval '7 days', now(), false, false),

  ('33333333-0603-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 6,
   '11111111-0005-4000-A000-000000000005'::uuid, '11111111-0004-4000-A000-000000000004'::uuid,
   81.5, 39.7, NULL,
   now() - interval '7 days', now(), false, false),

  ('33333333-0604-4000-A000-000000000001'::uuid, 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 6,
   '11111111-0007-4000-A000-000000000007'::uuid, '11111111-0006-4000-A000-000000000006'::uuid,
   58.9, 41.2, NULL,
   now() - interval '7 days', now(), false, false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- PENDING TRADES (2 trades involving the real user's team)
-- ============================================================

INSERT INTO fantasy_trades (id, league_id, proposer_team_id, receiver_team_id, offered_slot_ids, requested_slot_ids, status, created_at, message) VALUES
  -- Jordan wants to trade SAT English (from T2) for max's Physics C slot
  ('44444444-0001-4000-A000-000000000001'::uuid,
   'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid,
   '11111111-0002-4000-A000-000000000002'::uuid,
   '11111111-0001-4000-A000-000000000001'::uuid,
   ARRAY['22222222-0201-4000-A000-000000000001'],
   ARRAY['22222222-0103-4000-A000-000000000003'],
   'pending', now() - interval '1 day', 'i need that physics slot bad lol'),

  -- Max proposing a trade to Emily: offering AP Literature for her AP Euro
  ('44444444-0002-4000-A000-000000000001'::uuid,
   'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid,
   '11111111-0001-4000-A000-000000000001'::uuid,
   '11111111-0007-4000-A000-000000000007'::uuid,
   ARRAY['22222222-0105-4000-A000-000000000005'],
   ARRAY['22222222-0701-4000-A000-000000000001'],
   'pending', now() - interval '3 hours', 'fair trade?')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- MANAGER RATINGS
-- ============================================================

INSERT INTO fantasy_manager_ratings (id, league_id, manager_uid, overall_rating, draft_grade, trade_grade, roster_management_grade, consistency_grade, updated_at) VALUES
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, '61BB6A49-8A34-4DA1-91DE-FA1617C409CF', 82.5, 88.0, 75.0, 85.0, 80.0, now()),
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-1111-4000-A000-000000000001', 74.2, 70.0, 78.0, 72.0, 76.0, now()),
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-2222-4000-A000-000000000002', 88.1, 92.0, 85.0, 88.0, 87.0, now()),
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-3333-4000-A000-000000000003', 61.8, 55.0, 60.0, 65.0, 66.0, now()),
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-4444-4000-A000-000000000004', 94.3, 96.0, 90.0, 95.0, 95.0, now()),
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-5555-4000-A000-000000000005', 42.1, 38.0, 45.0, 40.0, 44.0, now()),
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-6666-4000-A000-000000000006', 79.6, 82.0, 76.0, 80.0, 80.0, now()),
  (gen_random_uuid(), 'AAAAAAAA-BBBB-4CCC-DDDD-EEEEEEEEEE01'::uuid, 'A1B2C3D4-7777-4000-A000-000000000007', 67.9, 65.0, 70.0, 68.0, 68.0, now())
ON CONFLICT DO NOTHING;
