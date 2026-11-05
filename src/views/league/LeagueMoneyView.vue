<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import PageHeader from '@/components/PageHeader.vue'
import { useAuthStore } from '@/stores/auth'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'
import { formatCents, parseDollars } from '@/lib/format'
import type { MoneySummaryRow } from '@/types/models'

const auth = useAuthStore()
const leagues = useLeaguesStore()
const league = computed(() => leagues.current!)

const rows = ref<MoneySummaryRow[]>([])
const loading = ref(true)
const error = ref('')

const pot = computed(() => rows.value.reduce((sum, r) => sum + r.buy_in_cents, 0))
const sideBetsActive = computed(() => rows.value.some((r) => r.side_balance_cents !== 0))

// Commissioner form
const memberId = ref('')
const amount = ref('')
const note = ref('')
const saving = ref(false)
const saved = ref('')

async function load() {
  try {
    rows.value = await leagues.fetchMoneySummary()
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    loading.value = false
  }
}
onMounted(load)

async function record() {
  error.value = ''
  saved.value = ''
  const cents = parseDollars(amount.value)
  if (cents === null || cents === 0) {
    error.value = 'Enter an amount like 50 or 72.50. Use a minus sign to record a refund.'
    return
  }
  saving.value = true
  try {
    await leagues.recordBuyIn(memberId.value, cents, note.value)
    const who = rows.value.find((r) => r.user_id === memberId.value)?.display_name ?? 'member'
    saved.value = `${cents > 0 ? 'Buy-in' : 'Refund'} of ${formatCents(Math.abs(cents))} recorded for ${who}.`
    amount.value = ''
    note.value = ''
    await load()
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <main class="page">
    <PageHeader :eyebrow="league.name" title="Money" />

    <section class="card card--hero stack-sm">
      <p class="eyebrow muted">Season pot</p>
      <p class="pot">{{ formatCents(pot) }}</p>
      <p class="small muted">The member with the most points at the end of the {{ league.season }} season takes it all.</p>
    </section>

    <p v-if="error" class="alert" role="alert">{{ error }}</p>
    <div v-if="loading" class="spinner" aria-label="Loading" />

    <template v-else>
      <section class="stack">
        <h2>Buy-ins</h2>
        <ul class="card card--flush list">
          <li v-for="r in rows" :key="r.user_id" class="row">
            <span class="grow truncate">
              {{ r.display_name }}
              <span v-if="r.user_id === auth.user?.id" class="badge badge--muted">You</span>
            </span>
            <span class="money">{{ formatCents(r.buy_in_cents) }}</span>
          </li>
        </ul>
      </section>

      <section v-if="leagues.isCommissioner" class="card stack">
        <div>
          <h2>Record a buy-in</h2>
          <p class="small muted">Amounts can differ by member. Money is settled outside the app; this keeps the record.</p>
        </div>
        <form class="stack" @submit.prevent="record">
          <div class="field">
            <label for="member">Member</label>
            <select id="member" v-model="memberId" class="select" required>
              <option value="" disabled>Choose a member</option>
              <option v-for="r in rows" :key="r.user_id" :value="r.user_id">{{ r.display_name }}</option>
            </select>
          </div>
          <div class="row">
            <div class="field" style="width: 132px">
              <label for="amount">Amount ($)</label>
              <input id="amount" v-model="amount" class="input" inputmode="decimal" placeholder="50.00" required />
            </div>
            <div class="field grow">
              <label for="note">Note</label>
              <input id="note" v-model="note" class="input" maxlength="120" placeholder="Paid by e-transfer" />
            </div>
          </div>
          <p v-if="saved" class="alert alert--ok" role="status">{{ saved }}</p>
          <button class="btn btn--primary btn--block" :disabled="saving || !memberId">
            {{ saving ? 'Saving…' : 'Record buy-in' }}
          </button>
        </form>
      </section>

      <section class="card stack-sm">
        <h2>Side bets</h2>
        <p v-if="!sideBetsActive" class="small muted">
          Side bets are a separate pot. When two members’ golfers are in the same PGA Tour tee-time group, both get an
          alert and can put money on that match. Coming in phase 5.
        </p>
        <ul v-else class="list" style="margin: 0 -16px -16px">
          <li v-for="r in rows" :key="r.user_id" class="row">
            <span class="grow">{{ r.display_name }}</span>
            <span
              class="money"
              :class="{ 'money--pos': r.side_balance_cents > 0, 'money--neg': r.side_balance_cents < 0 }"
            >
              {{ formatCents(r.side_balance_cents) }}
            </span>
          </li>
        </ul>
      </section>
    </template>
  </main>
</template>

<style scoped>
.pot {
  font-family: var(--font-display);
  font-size: 2.5rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: var(--gold);
}
</style>
