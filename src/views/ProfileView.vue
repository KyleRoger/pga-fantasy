<script setup lang="ts">
import { ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import PageHeader from '@/components/PageHeader.vue'
import { useAuthStore } from '@/stores/auth'
import { errorMessage } from '@/lib/supabase'

const auth = useAuthStore()
const router = useRouter()

const name = ref(auth.profile?.display_name ?? '')
watch(
  () => auth.profile?.display_name,
  (value) => {
    if (value) name.value = value
  },
)

const busy = ref(false)
const message = ref('')
const error = ref('')

async function save() {
  busy.value = true
  message.value = ''
  error.value = ''
  try {
    await auth.updateDisplayName(name.value)
    message.value = 'Saved.'
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    busy.value = false
  }
}

async function signOut() {
  await auth.signOut()
  await router.replace({ name: 'login' })
}
</script>

<template>
  <main class="page">
    <PageHeader title="Profile" />

    <form class="card stack" @submit.prevent="save">
      <div class="field">
        <label for="display-name">Display name</label>
        <input id="display-name" v-model="name" class="input" maxlength="40" required />
      </div>
      <p class="small muted">Signed in as {{ auth.user?.email }}</p>
      <p v-if="error" class="alert" role="alert">{{ error }}</p>
      <p v-if="message" class="alert alert--ok" role="status">{{ message }}</p>
      <button class="btn btn--primary btn--block" :disabled="busy || !name.trim()">Save</button>
    </form>

    <button class="btn btn--danger btn--block" @click="signOut">Sign out</button>
  </main>
</template>
