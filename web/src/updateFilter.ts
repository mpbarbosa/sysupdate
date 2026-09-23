// Pure list-level filtering for the Available Updates panel: which items the
// user sees given the sidebar category and the "hide up to date" toggle.
// No React, no side effects — unit-tested in updateFilter.test.ts.
import type { SidebarCategory, UpdateItem } from './types';

export interface UpdateFilter {
  category: SidebarCategory;
  /** When true, items the CLI reported as already current are not listed. */
  hideUpToDate: boolean;
}

/** True for an item that needs nothing from the user and offers no action. */
export const isUpToDate = (item: Pick<UpdateItem, 'status'>): boolean => item.status === 'up_to_date';

/** Items visible in the Available Updates list under `filter`, in original order. */
export function filterUpdateItems<T extends Pick<UpdateItem, 'category' | 'status'>>(
  items: T[],
  filter: UpdateFilter,
): T[] {
  return items.filter(
    (item) =>
      (filter.category === 'all' || item.category === filter.category) &&
      !(filter.hideUpToDate && isUpToDate(item)),
  );
}

/** How many items in the active category the toggle is currently hiding. */
export function countHiddenUpToDate<T extends Pick<UpdateItem, 'category' | 'status'>>(
  items: T[],
  filter: UpdateFilter,
): number {
  if (!filter.hideUpToDate) {
    return 0;
  }
  const shown = filterUpdateItems(items, filter).length;
  const inCategory = filterUpdateItems(items, { ...filter, hideUpToDate: false }).length;
  return inCategory - shown;
}
