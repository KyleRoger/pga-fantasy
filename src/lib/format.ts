const money = new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD' })

export function formatCents(cents: number): string {
  return money.format(cents / 100)
}

/** Parses "75", "75.50" or "$75" into cents. Returns null if it isn't a number. */
export function parseDollars(input: string): number | null {
  const cleaned = input.replace(/[$,\s]/g, '')
  if (!/^-?\d+(\.\d{1,2})?$/.test(cleaned)) return null
  return Math.round(Number(cleaned) * 100)
}

export function formatDateRange(start: string, end: string): string {
  const s = new Date(`${start}T12:00:00`)
  const e = new Date(`${end}T12:00:00`)
  const month = (d: Date) => d.toLocaleDateString('en-CA', { month: 'short' })
  if (s.getMonth() === e.getMonth()) return `${month(s)} ${s.getDate()}–${e.getDate()}`
  return `${month(s)} ${s.getDate()} – ${month(e)} ${e.getDate()}`
}

export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('')
}
