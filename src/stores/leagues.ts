import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import type {
  League,
  LeagueEvent,
  LeagueInvite,
  LeagueMember,
  LeagueRole,
  MoneySummaryRow,
  ScoringRules,
  Tournament,
} from '@/types/models'

export interface LeagueListItem extends League {
  my_role: LeagueRole
  member_count: number
}

export const useLeaguesStore = defineStore('leagues', () => {
  const auth = useAuthStore()

  const list = ref<LeagueListItem[]>([])
  const listLoaded = ref(false)

  const current = ref<League | null>(null)
  const members = ref<LeagueMember[]>([])
  const invites = ref<LeagueInvite[]>([])

  const isCommissioner = computed(
    () => !!current.value && current.value.commissioner_id === auth.user?.id,
  )

  async function fetchMyLeagues() {
    const { data, error } = await supabase
      .from('league_members')
      .select('role, league:leagues(*, league_members(count))')
      .eq('user_id', auth.user!.id)
    if (error) throw error

    type Row = { role: LeagueRole; league: League & { league_members: { count: number }[] } }
    list.value = ((data ?? []) as unknown as Row[])
      .filter((row) => row.league)
      .map((row) => ({
        ...row.league,
        my_role: row.role,
        member_count: row.league.league_members?.[0]?.count ?? 1,
      }))
      .sort((a, b) => b.season - a.season || a.name.localeCompare(b.name))
    listLoaded.value = true
  }

  async function createLeague(name: string, season: number): Promise<string> {
    const { data, error } = await supabase.rpc('create_league', { p_name: name, p_season: season })
    if (error) throw error
    listLoaded.value = false
    return data as string
  }

  async function loadLeague(leagueId: string) {
    if (current.value?.id !== leagueId) {
      current.value = null
      members.value = []
      invites.value = []
    }
    const [leagueRes, membersRes] = await Promise.all([
      supabase.from('leagues').select('*').eq('id', leagueId).maybeSingle(),
      supabase
        .from('league_members')
        .select('*, profile:profiles(display_name, avatar_url)')
        .eq('league_id', leagueId)
        .order('joined_at'),
    ])
    if (leagueRes.error) throw leagueRes.error
    if (membersRes.error) throw membersRes.error
    current.value = leagueRes.data as League | null
    members.value = (membersRes.data ?? []) as LeagueMember[]
  }

  async function updateSettings(
    patch: Partial<
      Pick<
        League,
        | 'name'
        | 'roster_size'
        | 'rookie_slots'
        | 'pick_seconds'
        | 'side_bets_enabled'
        | 'side_bet_min_cents'
        | 'side_bet_max_cents'
      >
    >,
  ) {
    if (!current.value) return
    const { error } = await supabase.from('leagues').update(patch).eq('id', current.value.id)
    if (error) throw error
    await loadLeague(current.value.id)
  }

  async function updateScoringRules(rules: ScoringRules) {
    if (!current.value) return
    const { data, error } = await supabase.rpc('update_scoring_rules', {
      p_league_id: current.value.id,
      p_rules: rules,
    })
    if (error) throw error
    current.value = { ...current.value, scoring_rules: data as ScoringRules }
  }

  async function setSideBetOptIn(optIn: boolean) {
    if (!current.value || !auth.user) return
    const { error } = await supabase
      .from('league_members')
      .update({ side_bets_opt_in: optIn })
      .eq('league_id', current.value.id)
      .eq('user_id', auth.user.id)
    if (error) throw error
    await loadLeague(current.value.id)
  }

  async function removeMember(userId: string) {
    if (!current.value) return
    const { error } = await supabase
      .from('league_members')
      .delete()
      .eq('league_id', current.value.id)
      .eq('user_id', userId)
    if (error) throw error
    await loadLeague(current.value.id)
  }

  async function leaveLeague() {
    if (!current.value || !auth.user) return
    const { error } = await supabase
      .from('league_members')
      .delete()
      .eq('league_id', current.value.id)
      .eq('user_id', auth.user.id)
    if (error) throw error
    // Leaving removes read access, so don't reload this league. The caller
    // navigates away; the league list refetches on its next visit.
    listLoaded.value = false
  }

  // ---- Invites (commissioner) ----------------------------------------------
  async function fetchInvites() {
    if (!current.value) return
    const { data, error } = await supabase
      .from('league_invites')
      .select('id, token, email, expires_at, max_uses, use_count, revoked_at, created_at')
      .eq('league_id', current.value.id)
      .order('created_at', { ascending: false })
    if (error) throw error
    invites.value = data ?? []
  }

  async function createInvite(options: { email?: string; daysValid?: number; maxUses?: number | null } = {}) {
    if (!current.value) throw new Error('No league loaded')
    const { data, error } = await supabase.rpc('create_invite', {
      p_league_id: current.value.id,
      p_email: options.email || null,
      p_days_valid: options.daysValid ?? 14,
      p_max_uses: options.maxUses ?? null,
    })
    if (error) throw error
    await fetchInvites()
    return data as string
  }

  async function revokeInvite(inviteId: string) {
    const { error } = await supabase.rpc('revoke_invite', { p_invite_id: inviteId })
    if (error) throw error
    await fetchInvites()
  }

  // ---- Events --------------------------------------------------------------
  async function fetchSeasonEvents(season: number) {
    if (!current.value) return { tournaments: [] as Tournament[], selected: [] as LeagueEvent[] }
    const [tRes, eRes] = await Promise.all([
      supabase
        .from('tournaments')
        .select('id, name, season, start_date, end_date, course, is_major, has_cut, status')
        .eq('season', season)
        .order('start_date'),
      supabase
        .from('league_events')
        .select('id, league_id, tournament_id, draft_at, status')
        .eq('league_id', current.value.id),
    ])
    if (tRes.error) throw tRes.error
    if (eRes.error) throw eRes.error
    return { tournaments: (tRes.data ?? []) as Tournament[], selected: (eRes.data ?? []) as LeagueEvent[] }
  }

  async function addEvent(tournamentId: string, draftAt: string | null = null) {
    const { error } = await supabase.rpc('add_league_event', {
      p_league_id: current.value!.id,
      p_tournament_id: tournamentId,
      p_draft_at: draftAt,
    })
    if (error) throw error
  }

  async function removeEvent(leagueEventId: string) {
    const { error } = await supabase.rpc('remove_league_event', { p_league_event_id: leagueEventId })
    if (error) throw error
  }

  // ---- Money ---------------------------------------------------------------
  async function fetchMoneySummary(): Promise<MoneySummaryRow[]> {
    if (!current.value) return []
    const { data, error } = await supabase.rpc('league_money_summary', { p_league_id: current.value.id })
    if (error) throw error
    return (data ?? []) as MoneySummaryRow[]
  }

  async function recordBuyIn(userId: string, amountCents: number, note: string) {
    const { error } = await supabase.rpc('record_buy_in', {
      p_league_id: current.value!.id,
      p_user_id: userId,
      p_amount_cents: amountCents,
      p_note: note || null,
    })
    if (error) throw error
  }

  return {
    list,
    listLoaded,
    current,
    members,
    invites,
    isCommissioner,
    fetchMyLeagues,
    createLeague,
    loadLeague,
    updateSettings,
    updateScoringRules,
    setSideBetOptIn,
    removeMember,
    leaveLeague,
    fetchInvites,
    createInvite,
    revokeInvite,
    fetchSeasonEvents,
    addEvent,
    removeEvent,
    fetchMoneySummary,
    recordBuyIn,
  }
})
