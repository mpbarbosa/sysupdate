import { describe, it, expect } from 'vitest';
import { toUpdateStatus, toSeverity } from './summaryStatus';

describe('toUpdateStatus', () => {
  it('maps update_available to ready', () => {
    expect(toUpdateStatus('update_available')).toBe('ready');
  });

  it('maps failure-ish statuses to failed', () => {
    for (const s of ['not_installed', 'invalid_installation', 'unknown', 'insufficient_efi_space']) {
      expect(toUpdateStatus(s)).toBe('failed');
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
  });

  it('self_managed is info, never major', () => {
    expect(toSeverity('self_managed')).toBe('info');
  });

  it('up_to_date is info', () => {
    expect(toSeverity('up_to_date')).toBe('info');
  });
});
