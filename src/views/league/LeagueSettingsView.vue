<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import PageHeader from '@/components/PageHeader.vue'
import { useAuthStore } from '@/stores/auth'
import { useLeaguesStore } from '@/stores/leagues'
import { errorMessage } from '@/lib/supabase'
import { DEFAULT_SCORING_RULES, RULE_GROUPS, withDefaults } from '@/lib/scoring'
import { formatCents, parseDollars } from '@/lib/format'
import type { ScoringRules } from '@/types/models'

const auth = useAuthStore()
const leagues = useLeaguesStore()
const router = useRouter()
const league = computed(() => leagues.current!)
const me = computed(() => leagues.members.find((m) => m.user_id === auth.user?.id))

// ---- General ---------------------------------------------------------------
const general = reactive({
  name: '',
  roster_size: 5,
  rookie_slots: 1,
  pick_seconds: 90,
  side_bets_enabled: true,
  side_bet_min: '',
  side_bet_max: '',
})

function resetGeneral() {
  const l = league.value
  Object.assign(general, {
    name: l.name,
    roster_size: l.roster_size,
    rookie_slots: l.rookie_slots,
    pick_seconds: l.pick_seconds,
    side_bets_enabled: l.side_bets_enabled,
    side_bet_min: (l.side_bet_min_cents / 100).toFixed(2),
    side_bet_max: (l.side_bet_max_cents / 100).toFixed(2),
  })
}

// ---- Scoring ---------------------------------------------------------------
// Work on a deep copy so editing never touches the stored league until saved.
const copyRules = (source: Partial<ScoringRules> | null | undefined): ScoringRules =>
  JSON.parse(JSON.stringify(withDefaults(source))) as ScoringRules

const rules = ref<ScoringRules>(copyRules(leagues.current?.scoring_rules))
const rulesDirty = computed(
  () => JSON.stringify(rules.value) !== JSON.stringify(withDefaults(leagues.current?.scoring_rules)),
)

watch(
  () => leagues.current,
  (value) => {
    if (!value) return
    resetGeneral()
    rules.value = copyRules(value.scoring_rules)
  },
  { immediate: true },
)

const status = reactive({ general: '', scoring: '', error: '' })
const busy = ref<'general' | 'scoring' | 'optin' | null>(null)

async function saveGeneral() {
  status.error = ''
  status.general = ''
  const min = parseDollars(general.side_bet_min)
  const max = parseDollars(general.side_bet_max)
  if (min === null || max === null || min <= 0 || max < min) {
    status.error = 'Side-bet limits need a minimum above $0 and a maximum at least as high.'
    return
  }
  if (general.rookie_slots > general.roster_size) {
    status.error = 'Rookie slots can’t be more than the roster size.'
    return
  }
  busy.value = 'general'
  try {
    await leagues.updateSettings({
      name: general.name.trim(),
      roster_size: general.roster_size,
      rookie_slots: general.rookie_slots,
      pick_seconds: general.pick_seconds,
      side_bets_enabled: general.side_bets_enabled,
      side_bet_min_cents: min,
      side_bet_max_cents: max,
    })
    status.general = 'League settings saved.'
  } catch (e) {
    status.error = errorMessage(e)
  } finally {
    busy.value = null
  }
}

async function saveScoring() {
  status.error = ''
  status.scoring = ''
  busy.value = 'scoring'
  try {
    await leagues.updateScoringRules(rules.value)
    status.scoring = 'Scoring saved. It applies from the next event whose draft hasn’t started.'
  } catch (e) {
    status.error = errorMessage(e)
  } finally {
    busy.value = null
  }
}

function resetScoringToDefaults() {
  rules.value = copyRules(DEFAULT_SCORING_RULES)
}

async function toggleOptIn(event: Event) {
  busy.value = 'optin'
  try {
    await leagues.setSideBetOptIn((event.target as HTMLInputElement).checked)
  } catch (e) {
    status.error = errorMessage(e)
  } finally {
    busy.value = null
  }
}

async function leave() {
  if (!confirm(`Leave ${league.value.name}? You’ll need a new invite to come back.`)) return
  try {
    await leagues.leaveLeague()
    await router.replace({ name: 'leagues' })
  } catch (e) {
    status.error = errorMessage(e)
  }
}
</script>

<template>
  <main class="page">
    <PageHeader :eyebrow="league.name" title="Settings" />

    <p v-if="status.error" class="alert" role="alert">{{ status.error }}</p>

    <!-- Everyone: personal settings -->
    <section class="card stack">
      <h2>Your settings</h2>
      <label class="row">
        <span class="grow">
          <strong>Side bets</strong>
          <span class="small muted" style="display: block">
            Get alerts and take bets when your golfer is grouped with another member’s.
          </span>
        </span>
        <input
          type="checkbox"
          class="switch"
          :checked="me?.side_bets_opt_in"
          :disabled="busy === 'optin' || !league.side_bets_enabled"
          @change="toggleOptIn"
        />
      </label>
      <p v-if="!league.side_bets_enabled" class="tiny muted">The commissioner has turned side bets off for this league.</p>
    </section>

    <!-- Commissioner: league settings -->
    <template v-if="leagues.isCommissioner">
      <form class="card stack" @submit.prevent="saveGeneral">
        <h2>League</h2>
        <div class="field">
          <label for="name">Name</label>
          <input id="name" v-model="general.name" class="input" maxlength="60" minlength="2" required />
        </div>
        <div class="row">
          <div class="field grow">
            <label for="roster">Golfers per event</label>
            <select id="roster" v-model.number="general.roster_size" class="select">
              <option v-for="n in 10" :key="n" :value="n">{{ n }}</option>
            </select>
          </div>
          <div class="field grow">
            <label for="rookies">Rookie slots</label>
            <select id="rookies" v-model.number="general.rookie_slots" class="select">
              <option v-for="n in general.roster_size + 1" :key="n - 1" :value="n - 1">{{ n - 1 }}</option>
            </select>
          </div>
        </div>
        <div class="field">
          <label for="pick-seconds">Seconds per draft pick</label>
          <select id="pick-seconds" v-model.number="general.pick_seconds" class="select">
            <option v-for="s in [30, 60, 90, 120, 180, 300]" :key="s" :value="s">{{ s }} seconds</option>
          </select>
        </div>

        <label class="row">
          <span class="grow"><strong>Allow side bets</strong></span>
          <input v-model="general.side_bets_enabled" type="checkbox" class="switch" />
        </label>
        <div v-if="general.side_bets_enabled" class="row">
          <div class="field grow">
            <label for="bet-min">Min stake ($)</label>
            <input id="bet-min" v-model="general.side_bet_min" class="input" inputmode="decimal" />
          </div>
          <div class="field grow">
            <label for="bet-max">Max stake ($)</label>
            <input id="bet-max" v-model="general.side_bet_max" class="input" inputmode="decimal" />
          </div>
        </div>
        <p v-if="general.side_bets_enabled" class="tiny muted">
          Currently {{ formatCents(league.side_bet_min_cents) }} to {{ formatCents(league.side_bet_max_cents) }} per bet,
          each side.
        </p>

        <p v-if="status.general" class="alert alert--ok" role="status">{{ status.general }}</p>
        <button class="btn btn--primary btn--block" :disabled="busy === 'general'">Save league settings</button>
      </form>

      <form class="card stack" @submit.prevent="saveScoring">
        <div class="row row--between">
          <h2>Scoring</h2>
          <button type="button" class="link-btn small" @click="resetScoringToDefaults">Reset to defaults</button>
        </div>
        <p class="small muted">Switch any rule off or change its points. An event in progress keeps the rules it started with.</p>

        <div v-for="group in RULE_GROUPS" :key="group.title" class="stack-sm">
          <p class="eyebrow" style="margin-top: 8px">{{ group.title }}</p>
          <div v-for="meta in group.rules" :key="meta.key" class="rule" :class="{ 'rule--off': !rules[meta.key].enabled }">
            <input
              v-model="rules[meta.key].enabled"
              type="checkbox"
              class="switch"
              :aria-label="`${meta.label} on or off`"
            />
            <div class="grow">
              <p class="small"><strong>{{ meta.label }}</strong></p>
              <p v-if="meta.hint" class="tiny muted">{{ meta.hint }}</p>
            </div>
            <input
              v-model.number="rules[meta.key].points"
              type="number"
              class="input input--num"
              step="1"
              min="-1000"
              max="1000"
              :disabled="!rules[meta.key].enabled"
              :aria-label="`${meta.label} points`"
            />
          </div>
        </div>

        <p v-if="status.scoring" class="alert alert--ok" role="status">{{ status.scoring }}</p>
        <button class="btn btn--primary btn--block" :disabled="busy === 'scoring' || !rulesDirty">
          {{ rulesDirty ? 'Save scoring' : 'No changes' }}
        </button>
      </form>
    </template>

    <!-- Members: read-only scoring, and leaving -->
    <template v-else>
      <section class="card stack-sm">
        <h2>Scoring</h2>
        <div v-for="group in RULE_GROUPS" :key="group.title" class="stack-sm">
          <p class="eyebrow" style="margin-top: 8px">{{ group.title }}</p>
          <div v-for="meta in group.rules" :key="meta.key" class="row row--between small">
            <span :class="{ muted: !rules[meta.key].enabled }">{{ meta.label }}</span>
            <span class="money">{{ rules[meta.key].enabled ? rules[meta.key].points : 'Off' }}</span>
          </div>
        </div>
      </section>
      <button class="btn btn--danger btn--block" @click="leave">Leave league</button>
    </template>
  </main>
</template>

<style scoped>
.rule {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 0;
  border-top: 1px solid var(--line);
}
.rule--off .grow {
  opacity: 0.55;
}
</style>
