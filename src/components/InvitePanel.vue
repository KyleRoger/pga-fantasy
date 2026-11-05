<script setup lang="ts">
import { computed, ref } from 'vue'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'

const leagues = useLeaguesStore()

const email = ref('')
const busy = ref(false)
const error = ref('')
const copiedId = ref<string | null>(null)

const active = computed(() =>
  leagues.invites.filter(
    (i) =>
      !i.revoked_at &&
      new Date(i.expires_at) > new Date() &&
      (i.max_uses === null || i.use_count < i.max_uses),
  ),
)

function linkFor(token: string) {
  return `${window.location.origin}/join/${token}`
}

async function create() {
  busy.value = true
  error.value = ''
  try {
    const target = email.value.trim()
    const token = await leagues.createInvite(target ? { email: target, maxUses: 1 } : {})
    email.value = ''
    await share(token)
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    busy.value = false
  }
}

async function share(token: string, inviteId?: string) {
  const url = linkFor(token)
  const text = `Join ${leagues.current?.name} on PGA Fantasy`
  if ('share' in navigator) {
    try {
      await navigator.share({ title: text, text, url })
      return
    } catch {
      /* cancelled: fall back to copying */
    }
  }
  try {
    await navigator.clipboard.writeText(url)
    copiedId.value = inviteId ?? leagues.invites.find((i) => i.token === token)?.id ?? null
    setTimeout(() => (copiedId.value = null), 2000)
  } catch {
    prompt('Copy this invite link', url)
  }
}

async function revoke(id: string) {
  try {
    await leagues.revokeInvite(id)
  } catch (e) {
    error.value = errorMessage(e)
  }
}

function expiresIn(iso: string) {
  const days = Math.ceil((new Date(iso).getTime() - Date.now()) / 86_400_000)
  return days <= 1 ? 'expires today' : `expires in ${days} days`
}
</script>

<template>
  <section class="card stack">
    <div>
      <h2>Invite your group</h2>
      <p class="small muted">Share a link anyone can use for 14 days, or lock one to a single email address.</p>
    </div>

    <form class="row" @submit.prevent="create">
      <input
        v-model="email"
        class="input grow"
        type="email"
        inputmode="email"
        placeholder="Email (optional)"
        aria-label="Restrict invite to this email (optional)"
      />
      <button class="btn btn--primary" :disabled="busy">{{ busy ? '…' : 'Share link' }}</button>
    </form>

    <p v-if="error" class="alert" role="alert">{{ error }}</p>

    <ul v-if="active.length" class="list" style="margin: 0 -16px -16px; border-top: 1px solid var(--line)">
      <li v-for="invite in active" :key="invite.id" class="row">
        <div class="grow">
          <p class="small truncate">
            <strong>{{ invite.email ?? 'Open link' }}</strong>
          </p>
          <p class="tiny muted">
            {{ expiresIn(invite.expires_at) }}
            <template v-if="!invite.email"> · used {{ invite.use_count }}×</template>
          </p>
        </div>
        <button class="btn btn--ghost btn--sm" @click="share(invite.token, invite.id)">
          {{ copiedId === invite.id ? 'Copied' : 'Copy' }}
        </button>
        <button class="btn btn--danger btn--sm" @click="revoke(invite.id)">Cancel</button>
      </li>
    </ul>
  </section>
</template>
