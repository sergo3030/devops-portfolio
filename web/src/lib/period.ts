const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "2024-03" -> "Mar 2024". A fixed table, not Intl, so a server and a browser print the same text. */
function formatMonth(value: string): string {
  const match = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(value);
  if (!match) return value;
  return `${MONTHS[Number(match[2]) - 1]} ${match[1]}`;
}

/** "2024-03", "present" -> "Mar 2024 – present". Text that is not a year-month is shown as is. */
export function formatPeriod(start: string, end: string): string {
  return `${formatMonth(start)} – ${formatMonth(end)}`;
}

/** Newest first. Year-month strings sort correctly as text. Does not change the input. */
export function newestFirst<T extends { start: string }>(items: readonly T[]): T[] {
  return [...items].sort((a, b) => b.start.localeCompare(a.start));
}
