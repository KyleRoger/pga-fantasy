<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { errorMessage } from '@/lib/supabase'

type Mode = 'signin' | 'signup' | 'magic'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const mode = ref<Mode>('signin')
const email = ref('')
const password = ref('')
const displayName = ref('')
const busy = ref(false)
const error = ref('')
const notice = ref('')

const redirect = computed(() => {
  const r = route.query.redirect
  return typeof r === 'string' && r.startsWith('/') ? r : '/'
})

function setMode(next: Mode) {
  mode.value = next
  error.value = ''
  notice.value = ''
}

async function submit() {
  error.value = ''
  notice.value = ''
  busy.value = true
  try {
    if (mode.value === 'signin') {
      await auth.signInWithPassword(email.value.trim(), password.value)
      await router.replace(redirect.value)
    } else if (mode.value === 'signup') {
      const { needsConfirmation } = await auth.signUp(email.value.trim(), password.value, displayName.value.trim())
      if (needsConfirmation) {
        notice.value = `Check ${email.value.trim()} for a link to confirm your account.`
      } else {
        await router.replace(redirect.value)
      }
    } else {
      await auth.sendMagicLink(email.value.trim(), redirect.value)
      notice.value = `We sent a sign-in link to ${email.value.trim()}.`
    }
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <main class="login">
    <section class="login__hero">
      <img src="/icons/icon.svg" alt="" width="64" height="64" />
      <h1>PGA Fantasy</h1>
      <p>Draft golfers every week, chase daily points, and settle the side bets.</p>
    </section>

    <section class="page page--bare login__form">
      <div class="segmented" role="group" aria-label="Sign-in method">
        <button type="button" :aria-pressed="mode === 'signin'" @click="setMode('signin')">Sign in</button>
        <button type="button" :aria-pressed="mode === 'signup'" @click="setMode('signup')">Create account</button>
      </div>

      <form class="card stack" @submit.prevent="submit">
        <div v-if="mode === 'signup'" class="field">
          <label for="name">Display name</label>
          <input id="name" v-model="displayName" class="input" autocomplete="nickname" maxlength="40" required />
          <span class="hint">What your league sees on the leaderboard.</span>
        </div>

        <div class="field">
          <label for="email">Email</label>
          <input id="email" v-model="email" class="input" type="email" autocomplete="email" inputmode="email" required />
        </div>

        <div v-if="mode !== 'magic'" class="field">
          <label for="password">Password</label>
          <input
            id="password"
            v-model="password"
            class="input"
            type="password"
            :autocomplete="mode === 'signup' ? 'new-password' : 'current-password'"
            minlength="8"
            required
          />
          <span v-if="mode === 'signup'" class="hint">At least 8 characters.</span>
        </div>

        <p v-if="error" class="alert" role="alert">{{ error }}</p>
        <p v-if="notice" class="alert alert--ok" role="status">{{ notice }}</p>

        <button class="btn btn--primary btn--block" :disabled="busy">
          {{ busy ? 'One moment…' : mode === 'signin' ? 'Sign in' : mode === 'signup' ? 'Create account' : 'Email me a link' }}
        </button>
      </form>

      <p class="center small">
        <button v-if="mode !== 'magic'" type="button" class="link-btn" @click="setMode('magic')">
          Email me a sign-in link instead
        </button>
        <button v-else type="button" class="link-btn" @click="setMode('signin')">Use a password instead</button>
      </p>
    </section>
  </main>
</template>

<style scoped>
.login__hero {
  padding: calc(48px + var(--safe-top)) 24px 56px;
  text-align: center;
  color: var(--cream);
  background:
    radial-gradient(120% 80% at 50% 0%, var(--green-700) 0%, transparent 70%),
    var(--green-900);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
}
.login__hero img {
  border-radius: 16px;
  box-shadow: 0 6px 20px rgb(0 0 0 / 30%);
}
.login__hero h1 {
  font-size: 2.1rem;
}
.login__hero p {
  max-width: 300px;
  color: rgb(246 243 234 / 78%);
}
.login__form {
  margin-top: -32px;
}
</style>
