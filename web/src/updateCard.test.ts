import { describe, it, expect } from 'vitest';
import { toCardAffordances, DEFAULT_BLOCKED_REMEDIATION } from './updateCard';

describe('toCardAffordances', () => {
  it('offers Upgrade for a ready item with a snippet', () => {
    const a = toCardAffordances({ status: 'ready', snippetId: 'firefox' });
    expect(a).toMatchObject({ actionLabel: 'Upgrade', actionEnabled: true, actionTone: 'accent' });
    expect(a.showVersions).toBe(true);
  });

  it('offers Retry for a failed item — those can succeed on a second try', () => {
    const a = toCardAffordances({ status: 'failed', snippetId: 'firefox' });
    expect(a).toMatchObject({ actionLabel: 'Retry', actionEnabled: true, actionTone: 'danger' });
  });

  it('never offers a retry for a blocked item', () => {
    const a = toCardAffordances({
      status: 'blocked',
      snippetId: 'vscode-insiders',
      remediation: "Run 'sudo dpkg --configure -a' to finish the installation",
    });
    expect(a.actionEnabled).toBe(false);
    expect(a.actionLabel).not.toMatch(/retry/i);
    expect(a.actionTone).toBe('warning');
  });

  it('shows the CLI remediation instead of an unknown version transition', () => {
    const a = toCardAffordances({
      status: 'blocked',
      snippetId: 'vscode-insiders',
      remediation: "Run 'sudo dpkg --configure -a' to finish the installation",
    });
    expect(a.showVersions).toBe(false);
    expect(a.remediation).toBe("Run 'sudo dpkg --configure -a' to finish the installation");
  });

  it('falls back to a generic remediation when the event carries none', () => {
    expect(toCardAffordances({ status: 'blocked' }).remediation).toBe(DEFAULT_BLOCKED_REMEDIATION);
    expect(toCardAffordances({ status: 'blocked', remediation: '   ' }).remediation).toBe(
      DEFAULT_BLOCKED_REMEDIATION,
    );
  });

  it('hides the version transition for up-to-date and self-managed items', () => {
    expect(toCardAffordances({ status: 'up_to_date', snippetId: 'firefox' })).toMatchObject({
      actionLabel: 'Up to Date',
      actionEnabled: false,
      showVersions: false,
    });
    expect(toCardAffordances({ status: 'self_managed', snippetId: 'android-studio' })).toMatchObject({
      actionLabel: 'Self-Update',
      actionEnabled: false,
      showVersions: false,
    });
  });

  it('disables the button while an upgrade is running', () => {
    expect(toCardAffordances({ status: 'updating', snippetId: 'firefox' })).toMatchObject({
      actionLabel: 'Updating...',
      actionEnabled: false,
    });
  });

  it('reports Unavailable when no snippet can be run', () => {
    expect(toCardAffordances({ status: 'ready' })).toMatchObject({
      actionLabel: 'Unavailable',
      actionEnabled: false,
      actionTone: 'muted',
    });
  });

  it('never leaves a remediation line on a non-blocked card', () => {
    for (const status of ['ready', 'failed', 'up_to_date', 'updating', 'self_managed'] as const) {
      expect(toCardAffordances({ status, snippetId: 'firefox', remediation: 'ignored' }).remediation).toBeNull();
    }
  });
});
