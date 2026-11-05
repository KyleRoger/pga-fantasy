import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

declare module 'vue-router' {
  interface RouteMeta {
    public?: boolean
    title?: string
  }
}

const router = createRouter({
  history: createWebHistory(),
  scrollBehavior: () => ({ top: 0 }),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('@/views/LoginView.vue'),
      meta: { public: true, title: 'Sign in' },
    },
    {
      path: '/',
      name: 'leagues',
      component: () => import('@/views/LeaguesView.vue'),
      meta: { title: 'My leagues' },
    },
    {
      path: '/leagues/new',
      name: 'league-new',
      component: () => import('@/views/CreateLeagueView.vue'),
      meta: { title: 'New league' },
    },
    {
      path: '/leagues/:leagueId',
      component: () => import('@/views/league/LeagueLayout.vue'),
      props: true,
      children: [
        { path: '', name: 'league-home', component: () => import('@/views/league/LeagueHomeView.vue') },
        { path: 'events', name: 'league-events', component: () => import('@/views/league/LeagueEventsView.vue') },
        { path: 'money', name: 'league-money', component: () => import('@/views/league/LeagueMoneyView.vue') },
        { path: 'settings', name: 'league-settings', component: () => import('@/views/league/LeagueSettingsView.vue') },
      ],
    },
    {
      path: '/join/:token',
      name: 'join',
      component: () => import('@/views/JoinLeagueView.vue'),
      props: true,
      meta: { title: 'Join a league' },
    },
    {
      path: '/profile',
      name: 'profile',
      component: () => import('@/views/ProfileView.vue'),
      meta: { title: 'Profile' },
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'not-found',
      component: () => import('@/views/NotFoundView.vue'),
      meta: { public: true, title: 'Not found' },
    },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.init()

  if (!to.meta.public && !auth.isSignedIn) {
    // Send them back where they were going (e.g. an invite link) after sign-in.
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.name === 'login' && auth.isSignedIn) {
    const redirect = typeof to.query.redirect === 'string' ? to.query.redirect : '/'
    return redirect.startsWith('/') ? redirect : '/'
  }
})

router.afterEach((to) => {
  document.title = to.meta.title ? `${to.meta.title} · PGA Fantasy` : 'PGA Fantasy'
})

export default router
