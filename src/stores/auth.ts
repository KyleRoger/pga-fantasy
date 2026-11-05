import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import type { Profile } from '@/types/models'

export const useAuthStore = defineStore('auth', () => {
  const session = ref<Session | null>(null)
  const profile = ref<Profile | null>(null)
  const ready = ref(false)

  const user = computed(() => session.value?.user ?? null)
  const isSignedIn = computed(() => !!session.value)

  let readyPromise: Promise<void> | null = null

  /** Resolves once the stored session (if any) has been restored. Safe to call many times. */
  function init(): Promise<void> {
    if (readyPromise) return readyPromise
    readyPromise = (async () => {
      const { data } = await supabase.auth.getSession()
      session.value = data.session
      if (data.session) await loadProfile()
      ready.value = true

      supabase.auth.onAuthStateChange((_event, next) => {
        session.value = next
        if (next) void loadProfile()
        else profile.value = null
      })
    })()
    return readyPromise
  }

  async function loadProfile() {
    if (!session.value) return
    const { data } = await supabase
      .from('profiles')
      .select('id, display_name, avatar_url')
      .eq('id', session.value.user.id)
      .maybeSingle()
    profile.value = data
  }

  async function signInWithPassword(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
  }

  async function signUp(email: string, password: string, displayName: string) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { display_name: displayName },
        emailRedirectTo: `${window.location.origin}/`,
      },
    })
    if (error) throw error
    // With email confirmation on, there is no session until they click the link.
    return { needsConfirmation: !data.session }
  }

  async function sendMagicLink(email: string, redirectPath = '/') {
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}${redirectPath}` },
    })
    if (error) throw error
  }

  async function updateDisplayName(displayName: string) {
    if (!session.value) return
    const { error } = await supabase
      .from('profiles')
      .update({ display_name: displayName.trim() })
      .eq('id', session.value.user.id)
    if (error) throw error
    await loadProfile()
  }

  async function signOut() {
    await supabase.auth.signOut()
    session.value = null
    profile.value = null
  }

  return {
    session,
    profile,
    ready,
    user,
    isSignedIn,
    init,
    loadProfile,
    signInWithPassword,
    signUp,
    sendMagicLink,
    updateDisplayName,
    signOut,
  }
})
