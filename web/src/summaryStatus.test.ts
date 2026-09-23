import { describe, it, expect } from 'vitest';
import { toUpdateStatus, toSeverity } from './summaryStatus';

describe('toUpdateStatus', () => {
  it('maps update_available to ready', () => {
    expect(toUpdateStatus('update_available')).toBe('ready');
  });

  it('maps retryable failures to failed', () => {
    for (const s of ['not_installed', 'unknown']) {
      expect(toUpdateStatus(s)).toBe('failed');
    }
  });

  it('maps host-side breakage to blocked, not failed', () => {
    // Re-running the snippet cannot clear either of these, so the card must
    // not offer a retry.
    for (const s of ['invalid_installation', 'insufficient_efi_space', 'externally_managed']) {
      expect(toUpdateStatus(s)).toBe('blocked');
    }
  });

  it('maps self_managed to self_managed (not failed)', () => {
    expect(toUpdateStatus('self_managed')).toBe('self_managed');
  });

  it('maps up_to_date / unrecognized to up_to_date', () => {
    expect(toUpdateStatus('up_to_date')).toBe('up_to_date');
    expect(toUpdateStatus('something_new')).toBe('up_to_date');
  });
});

describe('toSeverity', () => {
  it('update_available is minor, or major at >= 10 updates', () => {
    expect(toSeverity('update_available')).toBe('minor');
    expect(toSeverity('update_available', 3)).toBe('minor');
    expect(toSeverity('update_available', 10)).toBe('major');
  });

  it('failure-ish statuses are major', () => {
    expect(toSeverity('unknown')).toBe('major');
    expect(toSeverity('not_installed')).toBe('major');
    expect(toSeverity('externally_managed')).toBe('major');
  });

  it('externally_managed stays major even with a pending update count', () => {
    // pip reports the count it found alongside the block; that count must not
    // downgrade the badge to the ordinary "minor / N updates" look.
    expect(toSeverity('externally_managed', 8)).toBe('major');
  });

  it('self_managed is info, never major', () => {
    expect(toSeverity('self_managed')).toBe('info');
  });

  it('up_to_date is info', () => {
    expect(toSeverity('up_to_date')).toBe('info');
  });
});
