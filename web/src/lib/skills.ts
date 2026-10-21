import type { SkillGroup } from '../generated/content';

/**
 * Keeps the skills that contain the query, ignoring case. A group whose name matches is kept
 * whole, so searching "observability" shows everything in it. Groups with no match are dropped.
 */
export function filterSkills(groups: readonly SkillGroup[], query: string): SkillGroup[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return [...groups];
  return groups.flatMap((group) => {
    if (group.category.toLowerCase().includes(needle)) return [group];
    const items = group.items.filter((item) => item.toLowerCase().includes(needle));
    return items.length > 0 ? [{ ...group, items }] : [];
  });
}

export function countSkills(groups: readonly SkillGroup[]): number {
  return groups.reduce((total, group) => total + group.items.length, 0);
}
