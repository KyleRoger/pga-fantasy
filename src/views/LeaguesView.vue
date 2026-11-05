<script setup lang="ts">
import { onMounted, ref } from 'vue'
import PageHeader from '@/components/PageHeader.vue'
import { useAuthStore } from '@/stores/auth'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'

const auth = useAuthStore()
const leagues = useLeaguesStore()
const loading = ref(!leagues.listLoaded)
const error = ref('')

onMounted(async () => {
  try {
    await leagues.fetchMyLeagues()
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <main class="page">
    <PageHeader :eyebrow="auth.profile ? `Hi, ${auth.profile.display_name}` : undefined" title="My leagues">
      <template #action>
        <RouterLink :to="{ name: 'league-new' }" class="btn btn--primary btn--sm">New league</RouterLink>
      </template>
    </PageHeader>

    <p v-if="error" class="alert" role="alert">{{ error }}</p>
    <div v-if="loading" class="spinner" aria-label="Loading" />

    <div v-else-if="leagues.list.length === 0" class="card empty">
      <h2>No leagues yet</h2>
      <p class="muted">Start one and invite your group, or open an invite link a commissioner sent you.</p>
      <RouterLink :to="{ name: 'league-new' }" class="btn btn--primary">Start a league</RouterLink>
    </div>

    <ul v-else class="card card--flush list">
      <li v-for="league in leagues.list" :key="league.id" style="padding: 0">
        <RouterLink :to="{ name: 'league-home', params: { leagueId: league.id } }" class="list-link">
          <div class="avatar" aria-hidden="true">⛳</div>
          <div class="grow">
            <div class="row" style="gap: 8px">
              <strong class="truncate">{{ league.name }}</strong>
              <span v-if="league.my_role === 'commissioner'" class="badge badge--gold">Commish</span>
            </div>
            <p class="small muted">
              {{ league.season }} season · {{ league.member_count }} {{ league.member_count === 1 ? 'member' : 'members' }}
            </p>
          </div>
          <span class="muted" aria-hidden="true">›</span>
        </RouterLink>
      </li>
    </ul>
  </main>
</template>
