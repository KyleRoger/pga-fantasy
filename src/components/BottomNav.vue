<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'

const route = useRoute()

// Inside a league the bar switches to that league's sections.
const leagueId = computed(() =>
  typeof route.params.leagueId === 'string' ? route.params.leagueId : null,
)

const items = computed(() =>
  leagueId.value
    ? [
        { to: { name: 'league-home', params: { leagueId: leagueId.value } }, label: 'League', icon: 'flag' },
        { to: { name: 'league-events', params: { leagueId: leagueId.value } }, label: 'Events', icon: 'calendar' },
        { to: { name: 'league-money', params: { leagueId: leagueId.value } }, label: 'Money', icon: 'wallet' },
        { to: { name: 'league-settings', params: { leagueId: leagueId.value } }, label: 'Settings', icon: 'sliders' },
      ]
    : [
        { to: { name: 'leagues' }, label: 'Leagues', icon: 'flag' },
        { to: { name: 'profile' }, label: 'Profile', icon: 'user' },
      ],
)

const paths: Record<string, string> = {
  flag: 'M6 21V4m0 0h10l-2 4 2 4H6',
  calendar: 'M4 7h16v13H4zM4 11h16M9 3v4m6-4v4',
  wallet: 'M3 7h15a3 3 0 0 1 3 3v8H3zM3 7l12-3v3m2 7h.01',
  sliders: 'M5 4v16M12 4v16M19 4v16M3 9h4M10 15h4M17 7h4',
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm-7 9a7 7 0 0 1 14 0',
}
</script>

<template>
  <nav class="bottom-nav" aria-label="Main">
    <RouterLink
      v-for="item in items"
      :key="item.label"
      :to="item.to"
      class="bottom-nav__item"
      exact-active-class="is-active"
    >
      <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
        <path
          :d="paths[item.icon]"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
      <span>{{ item.label }}</span>
    </RouterLink>
  </nav>
</template>

<style scoped>
.bottom-nav {
  position: fixed;
  inset: auto 0 0 0;
  z-index: 20;
  display: flex;
  justify-content: space-around;
  height: calc(var(--nav-height) + var(--safe-bottom));
  padding-bottom: var(--safe-bottom);
  background: rgb(255 253 247 / 94%);
  backdrop-filter: blur(12px);
  border-top: 1px solid var(--line);
}
.bottom-nav__item {
  flex: 1;
  max-width: 120px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 3px;
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--ink-soft);
  text-decoration: none;
}
.bottom-nav__item.is-active {
  color: var(--green-800);
}
.bottom-nav__item.is-active svg {
  color: var(--gold);
}
</style>
