<script setup lang="ts">
// Nudges people to add the app to their home screen. On iPhone this is also
// what makes push notifications possible later (phase 5).
import { onMounted, ref } from 'vue'

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

const DISMISS_KEY = 'pga-fantasy:install-dismissed'
const visible = ref(false)
const isIos = ref(false)
let deferred: BeforeInstallPromptEvent | null = null

function dismissedRecently(): boolean {
  try {
    const at = Number(localStorage.getItem(DISMISS_KEY) ?? 0)
    return Date.now() - at < 1000 * 60 * 60 * 24 * 14
  } catch {
    return false
  }
}

onMounted(() => {
  const standalone =
    window.matchMedia('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  if (standalone || dismissedRecently()) return

  isIos.value = /iphone|ipad|ipod/i.test(navigator.userAgent)
  if (isIos.value) {
    visible.value = true
    return
  }
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault()
    deferred = event as BeforeInstallPromptEvent
    visible.value = true
  })
})

async function install() {
  if (!deferred) return
  await deferred.prompt()
  await deferred.userChoice
  deferred = null
  visible.value = false
}

function dismiss() {
  visible.value = false
  try {
    localStorage.setItem(DISMISS_KEY, String(Date.now()))
  } catch {
    /* private mode: just hide it */
  }
}
</script>

<template>
  <div v-if="visible" class="install" role="dialog" aria-label="Install the app">
    <div class="grow">
      <strong>Add to your home screen</strong>
      <p v-if="isIos" class="small">Tap the Share button, then <b>Add to Home Screen</b>, to get draft and side-bet alerts.</p>
      <p v-else class="small">Install the app for one-tap access and alerts.</p>
    </div>
    <button v-if="!isIos" class="btn btn--gold btn--sm" @click="install">Install</button>
    <button class="install__close" aria-label="Dismiss" @click="dismiss">×</button>
  </div>
</template>

<style scoped>
.install {
  position: fixed;
  left: 12px;
  right: 12px;
  bottom: calc(var(--nav-height) + var(--safe-bottom) + 12px);
  z-index: 19;
  display: flex;
  align-items: center;
  gap: 12px;
  max-width: 616px;
  margin: 0 auto;
  padding: 12px 14px;
  border-radius: var(--radius);
  background: var(--green-800);
  color: var(--cream);
  box-shadow: 0 8px 24px rgb(10 42 32 / 25%);
}
.install p {
  color: rgb(246 243 234 / 80%);
  margin-top: 2px;
}
.install__close {
  background: none;
  border: none;
  color: var(--cream);
  font-size: 1.5rem;
  line-height: 1;
  padding: 4px;
  cursor: pointer;
}
</style>
