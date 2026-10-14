import { describe, it, expect } from 'vitest';
import { getRunControlState, isRunActiveStatus } from './runControls';
import type { BackendRunStatus } from './types';

const ALL_STATUSES: BackendRunStatus[] = [
  'starting',
  'running',
  'paused',
  'stopped',
  'completed',
  'failed',
];

describe('isRunActiveStatus', () => {
  it('counts a paused run as active — the bridge still owns the child', () => {
    expect(isRunActiveStatus('paused')).toBe(true);
    expect(isRunActiveStatus('starting')).toBe(true);
    expect(isRunActiveStatus('running')).toBe(true);
  });

  it('treats settled statuses and no run as inactive', () => {
    for (const status of ['stopped', 'completed', 'failed'] as const) {
      expect(isRunActiveStatus(status)).toBe(false);
    }
    expect(isRunActiveStatus(null)).toBe(false);
    expect(isRunActiveStatus(undefined)).toBe(false);
  });
});

describe('getRunControlState', () => {
  it('offers pause and stop while a run is running', () => {
    const state = getRunControlState('running');
    expect(state).toMatchObject({
      isActive: true,
      isPaused: false,
      canToggle: true,
      canStop: true,
      toggleAction: 'pause',
    });
  });

  it('offers resume while a run is paused', () => {
    const state = getRunControlState('paused');
    expect(state).toMatchObject({ isPaused: true, canToggle: true, canStop: true, toggleAction: 'resume' });
    expect(state.toggleLabel).toBe('Resume run');
  });

  it('allows stop but not pause while the run is still starting', () => {
    expect(getRunControlState('starting')).toMatchObject({ canStop: true, canToggle: false });
  });

  it('disables both controls once the run has settled', () => {
    for (const status of ['stopped', 'completed', 'failed'] as const) {
      expect(getRunControlState(status)).toMatchObject({ isActive: false, canStop: false, canToggle: false });
    }
  });

  it('is inert with no run at all', () => {
    expect(getRunControlState(null)).toMatchObject({ isActive: false, canStop: false, canToggle: false });
  });

  it('never reports a settled status as pausable', () => {
    for (const status of ALL_STATUSES) {
      const state = getRunControlState(status);
      expect(state.canToggle).toBe(isRunActiveStatus(status) && status !== 'starting');
    }
  });
});
