-- Fantasy Study League — Supabase Migration
-- Run this in the Supabase SQL Editor to create all required tables and RPCs.

-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS fantasy_leagues (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                     TEXT NOT NULL,
    commissioner_uid         TEXT NOT NULL,
    member_uids              TEXT[] NOT NULL DEFAULT '{}',
    season_start_date        TIMESTAMPTZ NOT NULL,
    season_end_date          TIMESTAMPTZ NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    max_roster_size          INT NOT NULL DEFAULT 8,
    bench_size               INT NOT NULL DEFAULT 3,
    draft_status             TEXT NOT NULL DEFAULT 'pending',
    draft_order              TEXT[] NOT NULL DEFAULT '{}',
    current_draft_pick_index INT NOT NULL DEFAULT 0,
    playoff_team_count       INT NOT NULL DEFAULT 4,
    weekly_matchups_json     TEXT,
    scoring_config_json      TEXT,
    slot_config_json         TEXT,
    icon_name                TEXT NOT NULL DEFAULT 'trophy.fill',
    description              TEXT NOT NULL DEFAULT '',
    draft_seconds_per_pick   INT NOT NULL DEFAULT 90
);

CREATE TABLE IF NOT EXISTS fantasy_teams (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id             UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    owner_uid             TEXT NOT NULL,
    team_name             TEXT NOT NULL,
    wins                  INT NOT NULL DEFAULT 0,
    losses                INT NOT NULL DEFAULT 0,
    ties                  INT NOT NULL DEFAULT 0,
    total_points_for      DOUBLE PRECISION NOT NULL DEFAULT 0,
    total_points_against  DOUBLE PRECISION NOT NULL DEFAULT 0,
    playoff_seed          INT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fantasy_teams_league ON fantasy_teams(league_id);

CREATE TABLE IF NOT EXISTS fantasy_roster_slots (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id               UUID NOT NULL REFERENCES fantasy_teams(id) ON DELETE CASCADE,
    league_id             UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    player_uid            TEXT NOT NULL,
    subject_name          TEXT NOT NULL,
    is_active             BOOLEAN NOT NULL DEFAULT true,
    acquired_date         TIMESTAMPTZ NOT NULL DEFAULT now(),
    acquired_via          TEXT NOT NULL DEFAULT 'draft',
    multiplier            INT NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_fantasy_roster_league ON fantasy_roster_slots(league_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_fantasy_roster_unique ON fantasy_roster_slots(league_id, player_uid, subject_name);

CREATE TABLE IF NOT EXISTS fantasy_matchups (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id             UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    week_number           INT NOT NULL,
    team1_id              UUID NOT NULL REFERENCES fantasy_teams(id),
    team2_id              UUID NOT NULL REFERENCES fantasy_teams(id),
    team1_score           DOUBLE PRECISION NOT NULL DEFAULT 0,
    team2_score           DOUBLE PRECISION NOT NULL DEFAULT 0,
    winner_team_id        UUID,
    week_start_date       TIMESTAMPTZ NOT NULL,
    week_end_date         TIMESTAMPTZ NOT NULL,
    is_playoff            BOOLEAN NOT NULL DEFAULT false,
    is_bye                BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_fantasy_matchups_league_week ON fantasy_matchups(league_id, week_number);

CREATE TABLE IF NOT EXISTS fantasy_trades (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id             UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    proposer_team_id      UUID NOT NULL REFERENCES fantasy_teams(id),
    receiver_team_id      UUID NOT NULL REFERENCES fantasy_teams(id),
    offered_slot_ids      TEXT[] NOT NULL,
    requested_slot_ids    TEXT[] NOT NULL,
    status                TEXT NOT NULL DEFAULT 'pending',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at           TIMESTAMPTZ,
    message               TEXT
);

CREATE TABLE IF NOT EXISTS fantasy_draft_picks (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id             UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    team_id               UUID NOT NULL REFERENCES fantasy_teams(id),
    round_number          INT NOT NULL,
    pick_number           INT NOT NULL,
    player_uid            TEXT NOT NULL,
    subject_name          TEXT NOT NULL,
    picked_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fantasy_picks_league ON fantasy_draft_picks(league_id);

CREATE TABLE IF NOT EXISTS fantasy_punishments (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id                UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    week_number              INT NOT NULL,
    target_uid               TEXT NOT NULL,
    reason                   TEXT NOT NULL,
    punishment_description   TEXT NOT NULL DEFAULT '',
    video_url                TEXT,
    approval_votes           TEXT[] NOT NULL DEFAULT '{}',
    status                   TEXT NOT NULL DEFAULT 'proposed',
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fantasy_league_invites (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id             UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    inviter_uid           TEXT NOT NULL,
    invitee_uid           TEXT NOT NULL,
    status                TEXT NOT NULL DEFAULT 'pending',
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fantasy_manager_ratings (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    league_id                  UUID NOT NULL REFERENCES fantasy_leagues(id) ON DELETE CASCADE,
    manager_uid                TEXT NOT NULL,
    overall_rating             DOUBLE PRECISION NOT NULL DEFAULT 50,
    draft_grade                DOUBLE PRECISION NOT NULL DEFAULT 50,
    trade_grade                DOUBLE PRECISION NOT NULL DEFAULT 50,
    roster_management_grade    DOUBLE PRECISION NOT NULL DEFAULT 50,
    consistency_grade          DOUBLE PRECISION NOT NULL DEFAULT 50,
    weekly_ratings_json        TEXT,
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(league_id, manager_uid)
);

-- ============================================================
-- RPC FUNCTIONS
-- ============================================================

-- 1. Join a fantasy league (atomic: add to member_uids + create team)
CREATE OR REPLACE FUNCTION join_fantasy_league(
    p_league_id UUID,
    p_user_uid TEXT,
    p_team_name TEXT
) RETURNS void AS $$
BEGIN
    -- Add user to member_uids if not already present
    UPDATE fantasy_leagues
    SET member_uids = array_append(member_uids, p_user_uid)
    WHERE id = p_league_id
      AND NOT (p_user_uid = ANY(member_uids));

    -- Create team for this user
    INSERT INTO fantasy_teams (league_id, owner_uid, team_name)
    VALUES (p_league_id, p_user_uid, p_team_name)
    ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Make a draft pick (atomic: insert pick + create roster slot + advance index)
CREATE OR REPLACE FUNCTION make_draft_pick(
    p_league_id UUID,
    p_team_id UUID,
    p_player_uid TEXT,
    p_subject_name TEXT,
    p_round INT,
    p_pick INT,
    p_multiplier INT DEFAULT 1
) RETURNS void AS $$
BEGIN
    -- Insert the draft pick record
    INSERT INTO fantasy_draft_picks (league_id, team_id, round_number, pick_number, player_uid, subject_name)
    VALUES (p_league_id, p_team_id, p_round, p_pick, p_player_uid, p_subject_name);

    -- Create the roster slot with multiplier
    INSERT INTO fantasy_roster_slots (team_id, league_id, player_uid, subject_name, acquired_via, multiplier)
    VALUES (p_team_id, p_league_id, p_player_uid, p_subject_name, 'draft', p_multiplier);

    -- Advance draft pick index
    UPDATE fantasy_leagues
    SET current_draft_pick_index = current_draft_pick_index + 1
    WHERE id = p_league_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Execute a trade (atomic: swap roster slot ownership)
CREATE OR REPLACE FUNCTION execute_trade(p_trade_id UUID) RETURNS void AS $$
DECLARE
    v_trade fantasy_trades%ROWTYPE;
    v_slot_id UUID;
BEGIN
    SELECT * INTO v_trade FROM fantasy_trades WHERE id = p_trade_id AND status = 'pending';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trade not found or not pending';
    END IF;

    -- Move offered slots to receiver team
    FOREACH v_slot_id IN ARRAY (
        SELECT array_agg(x::UUID) FROM unnest(v_trade.offered_slot_ids) x
    )
    LOOP
        UPDATE fantasy_roster_slots
        SET team_id = v_trade.receiver_team_id, acquired_via = 'trade', acquired_date = now()
        WHERE id = v_slot_id;
    END LOOP;

    -- Move requested slots to proposer team
    FOREACH v_slot_id IN ARRAY (
        SELECT array_agg(x::UUID) FROM unnest(v_trade.requested_slot_ids) x
    )
    LOOP
        UPDATE fantasy_roster_slots
        SET team_id = v_trade.proposer_team_id, acquired_via = 'trade', acquired_date = now()
        WHERE id = v_slot_id;
    END LOOP;

    -- Mark trade as accepted
    UPDATE fantasy_trades
    SET status = 'accepted', resolved_at = now()
    WHERE id = p_trade_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Pick up a free agent (atomic: drop old slot + add new one)
CREATE OR REPLACE FUNCTION pickup_free_agent(
    p_league_id UUID,
    p_team_id UUID,
    p_drop_slot_id UUID,
    p_player_uid TEXT,
    p_subject_name TEXT
) RETURNS void AS $$
BEGIN
    -- Remove the dropped slot
    DELETE FROM fantasy_roster_slots WHERE id = p_drop_slot_id;

    -- Add the new free agent
    INSERT INTO fantasy_roster_slots (team_id, league_id, player_uid, subject_name, acquired_via)
    VALUES (p_team_id, p_league_id, p_player_uid, p_subject_name, 'free_agent');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Finalize a week (placeholder — scoring computed client-side, this updates records)
CREATE OR REPLACE FUNCTION finalize_week(
    p_league_id UUID,
    p_week_number INT
) RETURNS void AS $$
DECLARE
    v_matchup fantasy_matchups%ROWTYPE;
BEGIN
    -- For each matchup in this week, determine winner and update team records
    FOR v_matchup IN
        SELECT * FROM fantasy_matchups
        WHERE league_id = p_league_id AND week_number = p_week_number AND is_bye = false
    LOOP
        IF v_matchup.team1_score > v_matchup.team2_score THEN
            UPDATE fantasy_matchups SET winner_team_id = v_matchup.team1_id WHERE id = v_matchup.id;
            UPDATE fantasy_teams SET wins = wins + 1, total_points_for = total_points_for + v_matchup.team1_score, total_points_against = total_points_against + v_matchup.team2_score WHERE id = v_matchup.team1_id;
            UPDATE fantasy_teams SET losses = losses + 1, total_points_for = total_points_for + v_matchup.team2_score, total_points_against = total_points_against + v_matchup.team1_score WHERE id = v_matchup.team2_id;
        ELSIF v_matchup.team2_score > v_matchup.team1_score THEN
            UPDATE fantasy_matchups SET winner_team_id = v_matchup.team2_id WHERE id = v_matchup.id;
            UPDATE fantasy_teams SET wins = wins + 1, total_points_for = total_points_for + v_matchup.team2_score, total_points_against = total_points_against + v_matchup.team1_score WHERE id = v_matchup.team2_id;
            UPDATE fantasy_teams SET losses = losses + 1, total_points_for = total_points_for + v_matchup.team1_score, total_points_against = total_points_against + v_matchup.team2_score WHERE id = v_matchup.team1_id;
        ELSE
            UPDATE fantasy_teams SET ties = ties + 1, total_points_for = total_points_for + v_matchup.team1_score, total_points_against = total_points_against + v_matchup.team2_score WHERE id = v_matchup.team1_id;
            UPDATE fantasy_teams SET ties = ties + 1, total_points_for = total_points_for + v_matchup.team2_score, total_points_against = total_points_against + v_matchup.team1_score WHERE id = v_matchup.team2_id;
        END IF;
    END LOOP;

    -- Bye teams get auto-wins
    FOR v_matchup IN
        SELECT * FROM fantasy_matchups
        WHERE league_id = p_league_id AND week_number = p_week_number AND is_bye = true
    LOOP
        UPDATE fantasy_matchups SET winner_team_id = v_matchup.team1_id WHERE id = v_matchup.id;
        UPDATE fantasy_teams SET wins = wins + 1 WHERE id = v_matchup.team1_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
