// Pure mappings from the CLI's `summary.updates` status onto the dashboard's
// UpdateItem status + severity. No React, no side effects — unit-tested in
// summaryStatus.test.ts.
import type { UpdateItem } from './types';

// Map a raw CLI summary status to the card's lifecycle status.
export function toUpdateStatus(status: unknown): UpdateItem['status'] {
  switch (status) {
    case 'update_available':
      return 'ready';
    case 'not_installed':
    case 'invalid_installation':
    case 'unknown':
    case 'insufficient_efi_space':
      return 'failed';
    // Self-managed tools (e.g. Android Studio) update through their own updater
    // and expose no trackable "latest" — informational, not a failure, so they
    // must not render as a red/RETRY card.
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
    status === 'insufficient_efi_space'
  ) {
    return 'major';
  }

  // Everything else — up_to_date, self_managed, unrecognized — is informational.
  return 'info';
}
