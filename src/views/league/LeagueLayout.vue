<script setup lang="ts">
import { ref, watch } from 'vue'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'

const props = defineProps<{ leagueId: string }>()
const leagues = useLeaguesStore()
const loading = ref(true)
const error = ref('')

watch(
  () => props.leagueId,
  async (id) => {
    loading.value = !leagues.current || leagues.current.id !== id
    error.value = ''
    try {
      await leagues.loadLeague(id)
    } catch (e) {
      error.value = errorMessage(e)
    } finally {
      loading.value = false
    }
  },
  { immediate: true },
)
</script>

<template>
  <div v-if="loading" class="page"><div class="spinner" aria-label="Loading" /></div>

  <main v-else-if="error || !leagues.current" class="page">
    <div class="card empty">
      <h2>League not found</h2>
      <p class="muted">{{ error || 'It may have been deleted, or you’re not a member.' }}</p>
      <RouterLink :to="{ name: 'leagues' }" class="btn btn--ghost">Back to my leagues</RouterLink>
    </div>
  </main>

  <RouterView v-else />
</template>
