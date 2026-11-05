<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import PageHeader from '@/components/PageHeader.vue'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'
import { formatDateRange } from '@/lib/format'
import type { LeagueEvent, Tournament } from '@/types/models'

const leagues = useLeaguesStore()
const league = computed(() => leagues.current!)

const tournaments = ref<Tournament[]>([])
const selected = ref<LeagueEvent[]>([])
const loading = ref(true)
const pending = ref<string | null>(null)
const error = ref('')
const filter = ref<'all' | 'selected'>(leagues.isCommissioner ? 'all' : 'selected')

const selectedByTournament = computed(() => new Map(selected.value.map((e) => [e.tournament_id, e])))
const visible = computed(() =>
  filter.value === 'all'
    ? tournaments.value
    : tournaments.value.filter((t) => selectedByTournament.value.has(t.id)),
)

async function load() {
  try {
    const res = await leagues.fetchSeasonEvents(league.value.season)
    tournaments.value = res.tournaments
    selected.value = res.selected
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function toggle(t: Tournament) {
  if (!leagues.isCommissioner) return
  pending.value = t.id
  error.value = ''
  try {
    const existing = selectedByTournament.value.get(t.id)
    if (existing) await leagues.removeEvent(existing.id)
    else await leagues.addEvent(t.id)
    const res = await leagues.fetchSeasonEvents(league.value.season)
    selected.value = res.selected
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    pending.value = null
  }
}

async function selectMajors() {
  for (const t of tournaments.value) {
    if (t.is_major && !selectedByTournament.value.has(t.id)) await toggle(t)
  }
}
</script>

<template>
  <main class="page">
    <PageHeader :eyebrow="league.name" title="Events" />

    <p class="muted small">
      {{ selected.length }} {{ selected.length === 1 ? 'event counts' : 'events count' }} toward the {{ league.season }}
      season. Each one gets its own draft.
    </p>

    <div class="segmented" role="group" aria-label="Show">
      <button type="button" :aria-pressed="filter === 'all'" @click="filter = 'all'">Full schedule</button>
      <button type="button" :aria-pressed="filter === 'selected'" @click="filter = 'selected'">Our events</button>
    </div>

    <p v-if="error" class="alert" role="alert">{{ error }}</p>
    <div v-if="loading" class="spinner" aria-label="Loading" />

    <div v-else-if="tournaments.length === 0" class="card empty">
      <h2>No schedule yet</h2>
      <p class="muted">
        The {{ league.season }} PGA Tour schedule appears here once the golf data sync is connected (phase 3). For
        local testing, run <code>supabase db reset</code> to load sample events.
      </p>
    </div>

    <div v-else-if="visible.length === 0" class="card empty">
      <p class="muted">No events picked yet.</p>
      <button v-if="leagues.isCommissioner" class="btn btn--ghost" @click="filter = 'all'">Pick from the schedule</button>
    </div>

    <template v-else>
      <button
        v-if="leagues.isCommissioner && filter === 'all' && tournaments.some((t) => t.is_major)"
        class="btn btn--ghost btn--sm"
        style="align-self: flex-start"
        @click="selectMajors"
      >
        Add all majors
      </button>

      <ul class="card card--flush list">
        <li v-for="t in visible" :key="t.id" class="row">
          <div class="grow">
            <div class="row" style="gap: 8px">
              <strong class="truncate">{{ t.name }}</strong>
              <span v-if="t.is_major" class="badge badge--gold">Major</span>
              <span v-if="!t.has_cut" class="badge badge--muted">No cut</span>
            </div>
            <p class="tiny muted truncate">
              {{ formatDateRange(t.start_date, t.end_date) }}<template v-if="t.course"> · {{ t.course }}</template>
            </p>
          </div>
          <input
            v-if="leagues.isCommissioner"
            type="checkbox"
            class="switch"
            :checked="selectedByTournament.has(t.id)"
            :disabled="pending === t.id || (selectedByTournament.get(t.id)?.status ?? 'scheduled') !== 'scheduled'"
            :aria-label="`Include ${t.name}`"
            @change="toggle(t)"
          />
          <span v-else-if="selectedByTournament.has(t.id)" class="badge">In</span>
        </li>
      </ul>
    </template>
  </main>
</template>
