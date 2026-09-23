import { describe, it, expect } from 'vitest';
import { countHiddenUpToDate, filterUpdateItems, isUpToDate } from './updateFilter';
import type { UpdateItem } from './types';

type Row = Pick<UpdateItem, 'id' | 'category' | 'status'>;

const rows: Row[] = [
  { id: 'apt', category: 'system', status: 'ready' },
  { id: 'firefox', category: 'apps', status: 'up_to_date' },
  { id: 'zed', category: 'apps', status: 'up_to_date' },
  { id: 'vscode', category: 'apps', status: 'failed' },
  { id: 'rustup', category: 'rust', status: 'self_managed' },
  { id: 'pip', category: 'python', status: 'blocked' },
];

const ids = (items: Row[]) => items.map((item) => item.id);

describe('isUpToDate', () => {
  it('matches only the up_to_date status', () => {
    expect(isUpToDate({ status: 'up_to_date' })).toBe(true);
    for (const status of ['ready', 'failed', 'updating', 'self_managed', 'blocked'] as const) {
      expect(isUpToDate({ status })).toBe(false);
    }
  });
});

describe('filterUpdateItems', () => {
  it('shows everything when the toggle is off and category is all', () => {
    expect(filterUpdateItems(rows, { category: 'all', hideUpToDate: false })).toEqual(rows);
  });

  it('drops up-to-date items when the toggle is on, keeping order', () => {
    expect(ids(filterUpdateItems(rows, { category: 'all', hideUpToDate: true }))).toEqual([
      'apt',
      'vscode',
      'rustup',
      'pip',
    ]);
  });

  it('combines the category filter with the toggle', () => {
    expect(ids(filterUpdateItems(rows, { category: 'apps', hideUpToDate: false }))).toEqual([
      'firefox',
      'zed',
      'vscode',
    ]);
    expect(ids(filterUpdateItems(rows, { category: 'apps', hideUpToDate: true }))).toEqual(['vscode']);
  });

  it('keeps self-managed and blocked items — they still need attention', () => {
    const shown = ids(filterUpdateItems(rows, { category: 'all', hideUpToDate: true }));
    expect(shown).toContain('rustup');
    expect(shown).toContain('pip');
  });
});

describe('countHiddenUpToDate', () => {
  it('is zero when the toggle is off', () => {
    expect(countHiddenUpToDate(rows, { category: 'all', hideUpToDate: false })).toBe(0);
  });

  it('counts only up-to-date items inside the active category', () => {
    expect(countHiddenUpToDate(rows, { category: 'all', hideUpToDate: true })).toBe(2);
    expect(countHiddenUpToDate(rows, { category: 'apps', hideUpToDate: true })).toBe(2);
    expect(countHiddenUpToDate(rows, { category: 'system', hideUpToDate: true })).toBe(0);
  });
});
