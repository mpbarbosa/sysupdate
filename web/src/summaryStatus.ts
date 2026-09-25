// Pure mappings from the CLI's `summary.updates` status onto the dashboard's
// UpdateItem status + severity + version labels. No React, no side effects —
// unit-tested in summaryStatus.test.ts.
import type { UpdateItem } from './types';

// Map a raw CLI summary status to the card's lifecycle status.
export function toUpdateStatus(status: unknown): UpdateItem['status'] {
  switch (status) {
    case 'update_available':
      return 'ready';
    // Deterministic host-side problems: re-running the snippet reproduces the
    // identical failure, because only a change on the host (dpkg --configure,
    // reinstalling a mangled checkout, freeing ESP space, moving packages into
    // a venv) clears them. They are blocked, not retryable — see
    // toCardAffordances in updateCard.ts.
    case 'invalid_installation':
    case 'insufficient_efi_space':
    case 'externally_managed':
      return 'blocked';
    // These can succeed on a second try: a not-installed tool may be offered
    // an install, and 'unknown' is usually a transient network/rate-limit miss.
    case 'not_installed':
    case 'unknown':
      return 'failed';
    // Self-managed tools (e.g. Android Studio) apply their own updates, so
    // sysupdate cannot act even when it knows a newer build exists — the
    // snippet may still send a real `latest_version` alongside this status.
    // Informational, not a failure: never a red/RETRY card.
    case 'self_managed':
      return 'self_managed';
    default:
      return 'up_to_date';
  }
}

// Map a raw CLI summary status to the card's severity badge.
export function toSeverity(status: unknown, totalUpdates?: number): UpdateItem['severity'] {
  if (status === 'update_available') {
    return (totalUpdates ?? 0) >= 10 ? 'major' : 'minor';
  }

  if (
    status === 'not_installed' ||
    status === 'invalid_installation' ||
    status === 'unknown' ||
    status === 'insufficient_efi_space' ||
    status === 'externally_managed'
  ) {
    return 'major';
  }

  // Everything else — up_to_date, self_managed, unrecognized — is informational.
  return 'info';
}

/**
 * A package-manager summary reports an inventory (`total_updates`), not a
 * version pair, so the card's `current → latest` line is synthesized here.
 *
 * Only statuses that actually produced an inventory may claim one. `unknown`
 * means the check itself failed — a network miss, a rate limit, a manager that
 * would not answer — and it is the one status whose labels the card really
 * renders (`up_to_date` and blocked cards hide the latest half), so claiming
 * "up to date" there put a green all-clear next to a red Retry button.
 */
export function toManagerVersionLabels(
  status: unknown,
  totalUpdates = 0,
): Pick<UpdateItem, 'currentVersion' | 'latestVersion'> {
  if (status === 'update_available') {
    return {
      currentVersion: 'pending updates',
      latestVersion: `${totalUpdates} update${totalUpdates === 1 ? '' : 's'}`,
    };
  }

  if (status === 'up_to_date') {
    return { currentVersion: 'checked', latestVersion: 'up to date' };
  }

  // The check ran and reported a host state we cannot act on (pip's
  // externally-managed environment, a full ESP). The card shows the
  // remediation instead of these, but they must still not read as an all-clear.
  if (toUpdateStatus(status) === 'blocked') {
    return { currentVersion: 'checked', latestVersion: 'blocked' };
  }

  return { currentVersion: 'unknown', latestVersion: 'check failed' };
}
