<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import PageHeader from '@/components/PageHeader.vue'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'

const leagues = useLeaguesStore()
const router = useRouter()

// PGA Tour seasons run on the calendar year; from late in the year, default to next season.
const now = new Date()
const defaultSeason = now.getMonth() >= 9 ? now.getFullYear() + 1 : now.getFullYear()

const name = ref('')
const season = ref(defaultSeason)
const busy = ref(false)
const error = ref('')

async function submit() {
  busy.value = true
  error.value = ''
  try {
    const id = await leagues.createLeague(name.value.trim(), season.value)
    await router.replace({ name: 'league-home', params: { leagueId: id }, query: { created: '1' } })
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="page">
    <PageHeader title="Start a league" :back="{ name: 'leagues' }" />

    <form class="card stack" @submit.prevent="submit">
      <div class="field">
        <label for="league-name">League name</label>
        <input id="league-name" v-model="name" class="input" maxlength="60" minlength="2" required placeholder="Sunday Hackers" />
      </div>

      <div class="field">
        <label for="season">Season</label>
        <select id="season" v-model.number="season" class="select">
          <option :value="defaultSeason - 1">{{ defaultSeason - 1 }}</option>
          <option :value="defaultSeason">{{ defaultSeason }}</option>
          <option :value="defaultSeason + 1">{{ defaultSeason + 1 }}</option>
        </select>
      </div>

      <div class="card" style="background: var(--green-100); border: none; box-shadow: none">
        <p class="small">
          You'll be the commissioner. The league starts with <strong>5-golfer rosters, 1 rookie slot</strong> and the
          standard scoring. You can change all of it in Settings before the first draft.
        </p>
      </div>

      <p v-if="error" class="alert" role="alert">{{ error }}</p>
      <button class="btn btn--primary btn--block" :disabled="busy || name.trim().length < 2">
        {{ busy ? 'Creating…' : 'Create league' }}
      </button>
    </form>
  </main>
</template>
