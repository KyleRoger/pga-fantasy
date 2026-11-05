// Row shapes the app reads. They mirror supabase/migrations; once you have a
// Supabase project you can replace these with generated types:
//   npx supabase gen types typescript --local > src/types/database.ts

export type LeagueRole = 'commissioner' | 'member'
export type LeagueEventStatus = 'scheduled' | 'drafting' | 'in_progress' | 'final'

export interface ScoringRule {
  enabled: boolean
  points: number
}

export type ScoringRuleKey =
  | 'daily_leader'
  | 'daily_top5'
  | 'daily_top10'
  | 'finish_win'
  | 'finish_second'
  | 'finish_third_plus'
  | 'hole_in_one'
  | 'eagle'
  | 'birdie'
  | 'bogey_or_worse'
  | 'rookie_win'
  | 'rookie_top5'

export type ScoringRules = Record<ScoringRuleKey, ScoringRule>

export interface Profile {
  id: string
  display_name: string
  avatar_url: string | null
}

export interface League {
  id: string
  name: string
  season: number
  commissioner_id: string
  roster_size: number
  rookie_slots: number
  pick_seconds: number
  scoring_rules: ScoringRules
  side_bets_enabled: boolean
  side_bet_min_cents: number
  side_bet_max_cents: number
  created_at: string
}

export interface LeagueMember {
  league_id: string
  user_id: string
  role: LeagueRole
  side_bets_opt_in: boolean
  joined_at: string
  profile: Pick<Profile, 'display_name' | 'avatar_url'> | null
}

export interface LeagueInvite {
  id: string
  token: string
  email: string | null
  expires_at: string
  max_uses: number | null
  use_count: number
  revoked_at: string | null
  created_at: string
}

export interface InvitePreview {
  league_id: string
  league_name: string
  season: number
  commissioner_name: string
  member_count: number
  is_valid: boolean
  reason: 'revoked' | 'expired' | 'used_up' | null
  already_member: boolean
}

export interface Tournament {
  id: string
  name: string
  season: number
  start_date: string
  end_date: string
  course: string | null
  is_major: boolean
  has_cut: boolean
  status: 'scheduled' | 'in_progress' | 'final' | 'cancelled'
}

export interface LeagueEvent {
  id: string
  league_id: string
  tournament_id: string
  draft_at: string | null
  status: LeagueEventStatus
}

export interface MoneySummaryRow {
  user_id: string
  display_name: string
  buy_in_cents: number
  main_balance_cents: number
  side_balance_cents: number
}
