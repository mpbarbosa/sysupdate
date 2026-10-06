// Pure affordance rules for the top bar's run controls (stop and play/pause).
// Which of the two buttons are offered, and what the toggle currently means,
// follows from the bridge's run status alone — there is no React test renderer
// in this project, so the decision lives here and is unit-tested in
// runControls.test.ts rather than as ternaries in TopAppBar.tsx.
import type { BackendRunStatus } from './types';

export interface RunControlState {
  /** A run exists and has not finished — the controls are worth showing. */
  isActive: boolean;
  /** The run is suspended, so the toggle offers resume rather than pause. */
  isPaused: boolean;
  /** The toggle may be clicked (false while the run is still spawning). */
  canToggle: boolean;
  /** Stop may be clicked. */
  canStop: boolean;
  /** Which endpoint the toggle should call next. */
  toggleAction: 'pause' | 'resume';
  toggleLabel: string;
}

/** Statuses for which the bridge still owns a live child process. */
export const isRunActiveStatus = (status: BackendRunStatus | null | undefined): boolean =>
  status === 'starting' || status === 'running' || status === 'paused';

/**
 * The controls a run in `status` offers. A null status (no run yet, or a
 * finished one) yields an inert state so the caller can render the buttons
 * disabled instead of unmounting them and shifting the top bar's layout.
 */
export function getRunControlState(status: BackendRunStatus | null | undefined): RunControlState {
  const isPaused = status === 'paused';
  const isActive = isRunActiveStatus(status);
  // 'starting' means the child is spawned but has not emitted run.started yet;
  // signalling that window races the process group's own creation.
  const canToggle = status === 'running' || isPaused;

  return {
    isActive,
    isPaused,
    canToggle,
    canStop: isActive,
    toggleAction: isPaused ? 'resume' : 'pause',
    toggleLabel: isPaused ? 'Resume run' : 'Pause run',
  };
}
