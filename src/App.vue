<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import BottomNav from '@/components/BottomNav.vue'
import InstallPrompt from '@/components/InstallPrompt.vue'
import { useAuthStore } from '@/stores/auth'

const route = useRoute()
const auth = useAuthStore()
const showNav = computed(() => auth.isSignedIn && !route.meta.public)
</script>

<template>
  <RouterView />
  <InstallPrompt v-if="showNav" />
  <BottomNav v-if="showNav" />
</template>
