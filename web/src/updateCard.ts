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
  /** False when ticking "update automatically" could never cause an upgrade to run. */
  autoUpdateSupported: boolean;
  /** Why auto-update is unavailable, to render in the checkbox's place, or null. */
  autoUpdateNote: string | null;
}

/** Shown where a self-managed item's auto-update checkbox would be. */
export const SELF_MANAGED_AUTO_UPDATE_NOTE =
  'Updates itself — sysupdate cannot schedule this.';

/** Shown where an item with no runnable snippet would have its checkbox. */
export const NO_SNIPPET_AUTO_UPDATE_NOTE = 'No snippet to run — nothing to schedule.';

/** What the card for `item` may offer the user. */
export function toCardAffordances(
  item: Pick<UpdateItem, 'status' | 'snippetId' | 'remediation'> &
    Partial<Pick<UpdateItem, 'currentVersion' | 'latestVersion'>>,
): CardAffordances {
  // Whether an unattended upgrade could ever run for this item — independent of
  // whether its button is pressable right now. Merged into every branch below.
  const auto = autoUpdate(item);

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
      // Blocked is not permanent: once the host-side fix lands, the snippet
      // reports `ready` and a ticked item upgrades on its own. Keep the choice.
      ...auto,
    };
  }

  if (item.status === 'up_to_date') {
    return base('Up to Date', 'muted', { showVersions: false, ...auto });
  }

  // Self-managed tools update through their own updater, so the button stays
  // inert — but the snippet may still have resolved a real newer build (Android
  // Studio reads Google's updates.xml). Show the transition when there is one:
  // hiding it left a card that was a full release behind reading as an
  // all-clear. Fall back to hiding it when no usable `latest` came through.
  if (item.status === 'self_managed') {
    return base('Self-Update', 'muted', { showVersions: hasRealLatest(item), ...auto });
  }

  if (item.status === 'updating') {
    return base('Updating...', 'accent', auto);
  }

  // 'ready' / 'failed' are only actionable when a snippet exists to run.
  if (!item.snippetId) {
    return base('Unavailable', 'muted', auto);
  }

  return item.status === 'failed'
    ? { ...base('Retry', 'danger', auto), actionEnabled: true }
    : { ...base('Upgrade', 'accent', auto), actionEnabled: true };
}

/** True when `latestVersion` names a build actually worth showing beside the current one. */
function hasRealLatest(
  item: Partial<Pick<UpdateItem, 'currentVersion' | 'latestVersion'>>,
): boolean {
  const latest = item.latestVersion?.trim();
  return Boolean(latest) && latest !== 'unknown' && latest !== item.currentVersion?.trim();
}

/**
 * Whether scheduling an unattended upgrade for `item` could ever do anything.
 *
 * Deliberately NOT `actionEnabled`: an up-to-date item has an inert button but
 * is the main reason to tick the box — the choice persists, and the next scan
 * that turns it `ready` upgrades it. What rules an item out is structural:
 * a self-managed tool applies its own updates and sysupdate will never install
 * one, and an item with no snippet has nothing to run in the first place.
 */
function autoUpdate(
  item: Pick<UpdateItem, 'status' | 'snippetId'>,
): Pick<CardAffordances, 'autoUpdateSupported' | 'autoUpdateNote'> {
  if (item.status === 'self_managed') {
    return { autoUpdateSupported: false, autoUpdateNote: SELF_MANAGED_AUTO_UPDATE_NOTE };
  }

  if (!item.snippetId) {
    return { autoUpdateSupported: false, autoUpdateNote: NO_SNIPPET_AUTO_UPDATE_NOTE };
  }

  return { autoUpdateSupported: true, autoUpdateNote: null };
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
    autoUpdateSupported: true,
    autoUpdateNote: null,
    ...overrides,
  };
}
