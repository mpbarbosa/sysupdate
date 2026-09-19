// Pure mapping from an UpdateItem onto what its card is allowed to offer:
// which action button, whether a `current → latest` transition means anything,
// and what to show in its place. No React, no side effects — unit-tested in
// updateCard.test.ts.
import type { ActionTone, UpdateItem } from './types';

/** Shown for a blocked item whose event carried no `remediation` field. */
export const DEFAULT_BLOCKED_REMEDIATION =
  'Needs a fix on the host before sysupdate can update this.';

export interface CardAffordances {
  actionLabel: string;
  /** False when pressing the button could not accomplish anything. */
  actionEnabled: boolean;
  actionTone: ActionTone;
  /** False when `current → latest` would be noise — no real transition is known. */
  showVersions: boolean;
  /** Line to render instead of the versions, or null. */
  remediation: string | null;
}

/** What the card for `item` may offer the user. */
export function toCardAffordances(
  item: Pick<UpdateItem, 'status' | 'snippetId' | 'remediation'>,
): CardAffordances {
  // A blocked install is deterministic: the snippet re-runs, meets the same
  // broken state, and reports it again. A "Retry" button here invites the user
  // to click at a problem only they can clear from a shell — so name the fix
  // instead, and drop the meaningless "unknown → unknown".
  if (item.status === 'blocked') {
    const remediation = item.remediation?.trim();
    return {
      actionLabel: 'Action Needed',
      actionEnabled: false,
      actionTone: 'warning',
      showVersions: false,
      remediation: remediation ? remediation : DEFAULT_BLOCKED_REMEDIATION,
    };
  }

  if (item.status === 'up_to_date') {
    return base('Up to Date', 'muted', { showVersions: false });
  }

  // Self-managed tools update through their own updater and expose no
  // trackable "latest".
  if (item.status === 'self_managed') {
    return base('Self-Update', 'muted', { showVersions: false });
  }

  if (item.status === 'updating') {
    return base('Updating...', 'accent');
  }

  // 'ready' / 'failed' are only actionable when a snippet exists to run.
  if (!item.snippetId) {
    return base('Unavailable', 'muted');
  }

  return item.status === 'failed'
    ? { ...base('Retry', 'danger'), actionEnabled: true }
    : { ...base('Upgrade', 'accent'), actionEnabled: true };
}

function base(
  actionLabel: string,
  actionTone: ActionTone,
  overrides: Partial<CardAffordances> = {},
): CardAffordances {
  return {
    actionLabel,
    actionEnabled: false,
    actionTone,
    showVersions: true,
    remediation: null,
    ...overrides,
  };
}
