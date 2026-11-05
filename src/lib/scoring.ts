import type { ScoringRuleKey, ScoringRules } from '@/types/models'

// Keep in sync with public.default_scoring_rules() in the first migration.
export const DEFAULT_SCORING_RULES: ScoringRules = {
  daily_leader: { enabled: true, points: 20 },
  daily_top5: { enabled: true, points: 10 },
  daily_top10: { enabled: true, points: 5 },
  finish_win: { enabled: true, points: 50 },
  finish_second: { enabled: true, points: 25 },
  finish_third_plus: { enabled: true, points: 24 },
  hole_in_one: { enabled: true, points: 25 },
  eagle: { enabled: true, points: 10 },
  birdie: { enabled: true, points: 1 },
  bogey_or_worse: { enabled: true, points: -1 },
  rookie_win: { enabled: true, points: 25 },
  rookie_top5: { enabled: true, points: 10 },
}

export interface RuleMeta {
  key: ScoringRuleKey
  label: string
  hint: string
}

export interface RuleGroup {
  title: string
  rules: RuleMeta[]
}

export const RULE_GROUPS: RuleGroup[] = [
  {
    title: 'Daily leaderboard',
    rules: [
      { key: 'daily_leader', label: 'Leading at end of day', hint: 'Only the highest tier counts each day' },
      { key: 'daily_top5', label: 'Top 5 at end of day', hint: 'Ties count (T4 is top 5)' },
      { key: 'daily_top10', label: 'Top 10 at end of day', hint: '' },
    ],
  },
  {
    title: 'Final finish',
    rules: [
      { key: 'finish_win', label: 'Tournament winner', hint: '' },
      { key: 'finish_second', label: '2nd place', hint: '' },
      { key: 'finish_third_plus', label: '3rd place', hint: 'One point less per place after that, down to 0' },
    ],
  },
  {
    title: 'Holes',
    rules: [
      { key: 'hole_in_one', label: 'Hole-in-one', hint: 'Replaces the eagle points, not added to them' },
      { key: 'eagle', label: 'Eagle or better', hint: '' },
      { key: 'birdie', label: 'Birdie', hint: '' },
      { key: 'bogey_or_worse', label: 'Bogey or worse', hint: '' },
    ],
  },
  {
    title: 'Rookie bonus',
    rules: [
      { key: 'rookie_win', label: 'Rookie wins', hint: 'On top of finish points; only the higher rookie bonus applies' },
      { key: 'rookie_top5', label: 'Rookie finishes top 5', hint: '' },
    ],
  },
]

/** Fills in any keys missing from a league's stored rules. */
export function withDefaults(rules: Partial<ScoringRules> | null | undefined): ScoringRules {
  return { ...DEFAULT_SCORING_RULES, ...(rules ?? {}) }
}

/**
 * Final-finish points for a numeric place. Ties average the tied places,
 * e.g. two golfers T3 each get (24 + 23) / 2.
 */
export function finishPoints(place: number, tiedCount: number, rules: ScoringRules): number {
  const pointsFor = (p: number): number => {
    if (p === 1) return rules.finish_win.enabled ? rules.finish_win.points : 0
    if (p === 2) return rules.finish_second.enabled ? rules.finish_second.points : 0
    if (!rules.finish_third_plus.enabled) return 0
    return Math.max(0, rules.finish_third_plus.points - (p - 3))
  }
  let total = 0
  for (let p = place; p < place + tiedCount; p++) total += pointsFor(p)
  return Math.round((total / tiedCount) * 100) / 100
}
