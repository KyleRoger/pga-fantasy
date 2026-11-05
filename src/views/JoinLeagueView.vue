<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { errorMessage, supabase } from '@/lib/supabase'
import { useLeaguesStore } from '@/stores/leagues'
import type { InvitePreview } from '@/types/models'

const props = defineProps<{ token: string }>()
const router = useRouter()
const leagues = useLeaguesStore()

const preview = ref<InvitePreview | null>(null)
const loading = ref(true)
const busy = ref(false)
const error = ref('')

const problem = computed(() => {
  if (!preview.value) return 'This invite link isn’t valid. Ask your commissioner for a new one.'
  switch (preview.value.reason) {
    case 'revoked':
      return 'This invite was cancelled by the commissioner.'
    case 'expired':
      return 'This invite has expired. Ask your commissioner for a new link.'
    case 'used_up':
      return 'This invite has already been used.'
    default:
      return ''
  }
})

onMounted(async () => {
  const { data, error: err } = await supabase.rpc('get_invite_preview', { p_token: props.token })
  if (err) error.value = errorMessage(err)
  preview.value = ((data ?? []) as InvitePreview[])[0] ?? null
  loading.value = false
  if (preview.value?.already_member) {
    await router.replace({ name: 'league-home', params: { leagueId: preview.value.league_id } })
  }
})

async function join() {
  busy.value = true
  error.value = ''
  try {
    const { data, error: err } = await supabase.rpc('accept_invite', { p_token: props.token })
    if (err) throw err
    leagues.listLoaded = false
    await router.replace({ name: 'league-home', params: { leagueId: data as string } })
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="page">
    <div v-if="loading" class="spinner" aria-label="Loading" />

    <div v-else-if="problem" class="card empty">
      <h2>Can’t join with this link</h2>
      <p class="muted">{{ problem }}</p>
      <RouterLink :to="{ name: 'leagues' }" class="btn btn--ghost">Go to my leagues</RouterLink>
    </div>

    <template v-else-if="preview">
      <div class="card card--hero stack">
        <p class="eyebrow muted">You’re invited to</p>
        <h1>{{ preview.league_name }}</h1>
        <p class="muted">
          {{ preview.season }} season · run by {{ preview.commissioner_name }} ·
          {{ preview.member_count }} {{ preview.member_count === 1 ? 'member' : 'members' }}
        </p>
      </div>
      <p v-if="error" class="alert" role="alert">{{ error }}</p>
      <button class="btn btn--primary btn--block" :disabled="busy" @click="join">
        {{ busy ? 'Joining…' : 'Join league' }}
      </button>
    </template>
  </main>
</template>
