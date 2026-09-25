import { describe, it, expect } from 'vitest';
import { toCardAffordances, DEFAULT_BLOCKED_REMEDIATION,
  SELF_MANAGED_AUTO_UPDATE_NOTE,
  NO_SNIPPET_AUTO_UPDATE_NOTE,
} from './updateCard';

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

  it('hides the version transition for up-to-date items', () => {
    expect(toCardAffordances({ status: 'up_to_date', snippetId: 'firefox' })).toMatchObject({
      actionLabel: 'Up to Date',
      actionEnabled: false,
      showVersions: false,
    });
  });

  it('shows the transition for a self-managed item that resolved a newer build', () => {
    expect(
      toCardAffordances({
        status: 'self_managed',
        snippetId: 'android-studio',
        currentVersion: 'AI-251.25410.109.2511.13752376',
        latestVersion: 'AI-261.26222.65.2614.16379836',
      }),
    ).toMatchObject({
      actionLabel: 'Self-Update',
      actionEnabled: false,
      showVersions: true,
    });
  });

  it('hides the transition for a self-managed item with no usable latest', () => {
    for (const latestVersion of [undefined, '', 'unknown', 'AI-251.25410.109.2511.13752376']) {
      expect(
        toCardAffordances({
          status: 'self_managed',
          snippetId: 'android-studio',
          currentVersion: 'AI-251.25410.109.2511.13752376',
          latestVersion,
        }),
      ).toMatchObject({
        actionLabel: 'Self-Update',
        actionEnabled: false,
        showVersions: false,
      });
    }
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

  describe('auto-update availability', () => {
    it('offers auto-update on an up-to-date item — the tick fires on a later scan', () => {
      expect(toCardAffordances({ status: 'up_to_date', snippetId: 'firefox' })).toMatchObject({
        actionEnabled: false,
        autoUpdateSupported: true,
        autoUpdateNote: null,
      });
    });

    it('offers auto-update on a blocked item — the host fix makes it runnable', () => {
      expect(toCardAffordances({ status: 'blocked', snippetId: 'pip' })).toMatchObject({
        actionEnabled: false,
        autoUpdateSupported: true,
      });
    });

    it('offers auto-update on ready, failed and updating items with a snippet', () => {
      for (const status of ['ready', 'failed', 'updating'] as const) {
        expect(toCardAffordances({ status, snippetId: 'firefox' })).toMatchObject({
          autoUpdateSupported: true,
          autoUpdateNote: null,
        });
      }
    });

    it('withholds auto-update from a self-managed item, even with a snippet', () => {
      expect(
        toCardAffordances({ status: 'self_managed', snippetId: 'android-studio' }),
      ).toMatchObject({
        autoUpdateSupported: false,
        autoUpdateNote: SELF_MANAGED_AUTO_UPDATE_NOTE,
      });
    });

    it('withholds auto-update when there is no snippet to run', () => {
      for (const status of ['ready', 'failed', 'up_to_date', 'updating'] as const) {
        expect(toCardAffordances({ status })).toMatchObject({
          autoUpdateSupported: false,
          autoUpdateNote: NO_SNIPPET_AUTO_UPDATE_NOTE,
        });
      }
    });
  });
});
