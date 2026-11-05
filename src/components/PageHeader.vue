<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'

defineProps<{
  title: string
  eyebrow?: string
  back?: RouteLocationRaw
}>()
</script>

<template>
  <header class="page-header">
    <RouterLink v-if="back" :to="back" class="page-header__back" aria-label="Back">
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
        <path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    </RouterLink>
    <div class="grow">
      <p v-if="eyebrow" class="eyebrow">{{ eyebrow }}</p>
      <h1 class="truncate">{{ title }}</h1>
    </div>
    <slot name="action" />
  </header>
</template>

<style scoped>
.page-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding-top: var(--safe-top);
}
.page-header__back {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  margin-left: -8px;
  border-radius: 50%;
  color: var(--green-800);
}
.page-header__back:active {
  background: var(--green-100);
}
</style>
