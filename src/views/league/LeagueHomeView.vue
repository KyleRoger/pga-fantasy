<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import PageHeader from '@/components/PageHeader.vue'
import InvitePanel from '@/components/InvitePanel.vue'
import { useAuthStore } from '@/stores/auth'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'
import { initials } from '@/lib/format'

const route = useRoute()
const auth = useAuthStore()
const leagues = useLeaguesStore()

const league = computed(() => leagues.current!)
const justCreated = ref(route.query.created === '1')
const error = ref('')

onMounted(async () => {
  if (leagues.isCommissioner) {
    try {
      await leagues.fetchInvites()
    } catch (e) {
      error.value = errorMessage(e)
    }
  }
})

async function remove(userId: string, name: string) {
  if (!confirm(`Remove ${name} from ${league.value.name}?`)) return
  try {
    await leagues.removeMember(userId)
  } catch (e) {
    error.value = errorMessage(e)
  }
}
</script>

<template>
  <main class="page">
    <PageHeader :eyebrow="`${league.season} season`" :title="league.name" :back="{ name: 'leagues' }" />

    <div v-if="justCreated" class="alert alert--ok row row--between" role="status">
      <span>League created. Next: invite your group below, then pick events.</span>
      <button class="link-btn" aria-label="Dismiss" @click="justCreated = false">×</button>
    </div>

    <section class="card card--hero stack-sm">
      <p class="eyebrow muted">Format</p>
      <p>
        <strong>{{ league.roster_size }} golfers per event</strong>, including
        {{ league.rookie_slots }} rookie {{ league.rookie_slots === 1 ? 'pick' : 'picks' }}. A fresh snake draft every
        event, {{ league.pick_seconds }}s per pick.
      </p>
      <p class="small muted">Most points at season’s end takes the whole pot.</p>
    </section>

    <p v-if="error" class="alert" role="alert">{{ error }}</p>

    <InvitePanel v-if="leagues.isCommissioner" />

    <section class="stack">
      <div class="row row--between">
        <h2>Members</h2>
        <span class="muted small">{{ leagues.members.length }}</span>
      </div>
      <ul class="card card--flush list">
        <li v-for="m in leagues.members" :key="m.user_id" class="row">
          <div class="avatar" aria-hidden="true">{{ initials(m.profile?.display_name ?? '?') }}</div>
          <div class="grow">
            <div class="row" style="gap: 8px">
              <strong class="truncate">{{ m.profile?.display_name ?? 'Member' }}</strong>
              <span v-if="m.user_id === auth.user?.id" class="badge badge--muted">You</span>
              <span v-if="m.role === 'commissioner'" class="badge badge--gold">Commish</span>
            </div>
            <p class="tiny muted">{{ m.side_bets_opt_in ? 'In for side bets' : 'Not in side bets' }}</p>
          </div>
          <button
            v-if="leagues.isCommissioner && m.role !== 'commissioner'"
            class="btn btn--ghost btn--sm"
            @click="remove(m.user_id, m.profile?.display_name ?? 'this member')"
          >
            Remove
          </button>
        </li>
      </ul>
      <p v-if="!leagues.isCommissioner" class="small muted">Only the commissioner can invite new members.</p>
    </section>
  </main>
</template>
