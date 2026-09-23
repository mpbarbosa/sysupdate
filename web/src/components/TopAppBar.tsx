import { useState } from 'react';
import type { SystemConfig, ViewName } from '../types';
import { getActionToneColor, getThemeColorHex } from '../theme';

const VIEWS: { id: ViewName; label: string }[] = [
  { id: 'dashboard', label: 'Dashboard' },
  { id: 'logs', label: 'Logs' },
  { id: 'schedule', label: 'Schedule' },
  { id: 'settings', label: 'Settings' },
];

interface TopAppBarProps {
  activeView: ViewName;
  onViewChange: (view: ViewName) => void;
  onRefresh: () => void;
  onRunAll: () => void;
  /** Stop the backend bridge and try to close this tab. Already confirmed by the user. */
  onShutdown: () => void;
  isProcessing: boolean;
  progress: number;
  pendingTotal: number;
  themeColor: SystemConfig['themeColor'];
  glowEffects: boolean;
}

export default function TopAppBar({
  activeView,
  onViewChange,
  onRefresh,
  onRunAll,
  onShutdown,
  isProcessing,
  progress,
  pendingTotal,
  themeColor,
  glowEffects,
}: TopAppBarProps) {
  const accent = getThemeColorHex(themeColor);
  const dangerColor = getActionToneColor('danger', themeColor);
  const mutedColor = getActionToneColor('muted', themeColor);
  // Shutdown is not undoable from the page, so it needs a second click. The
  // browser's confirm() would do, but an inline prompt keeps the HUD look.
  const [confirmingShutdown, setConfirmingShutdown] = useState(false);

  return (
    <header className="border-b border-hud-border bg-hud-panel/60">
      <div className="flex items-center justify-between px-5 py-3">
        <div className="flex items-center gap-8">
          <h1 className="text-glow-cyan text-lg font-bold tracking-[0.3em]" style={{ color: accent }}>
            SYSUPDATE
          </h1>

          <nav className="flex gap-1 font-mono text-xs">
            {VIEWS.map((view) => {
              const isActive = view.id === activeView;
              return (
                <button
                  key={view.id}
                  type="button"
                  onClick={() => onViewChange(view.id)}
                  className="rounded px-3 py-1.5 uppercase tracking-widest transition-colors"
                  style={
                    isActive
                      ? { color: accent, backgroundColor: 'rgba(255,255,255,0.06)' }
                      : { color: '#7d97a3' }
                  }
                >
                  {view.label}
                </button>
              );
            })}
          </nav>
        </div>

        <div className="flex items-center gap-3">
          <button
            type="button"
            aria-label="Notifications"
            className="relative rounded border border-hud-border px-2.5 py-1.5 text-sm text-slate-300 hover:border-slate-500"
          >
            🔔
            {pendingTotal > 0 && (
              <span
                className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full text-[10px] font-bold text-black"
                style={{ backgroundColor: accent }}
              >
                {pendingTotal > 9 ? '9+' : pendingTotal}
              </span>
            )}
          </button>

          <button
            type="button"
            onClick={onRefresh}
            disabled={isProcessing}
            className="rounded border border-hud-border px-2.5 py-1.5 text-sm text-slate-300 hover:border-slate-500 disabled:opacity-50"
            aria-label="Refresh"
          >
            ⟳
          </button>

          <button
            type="button"
            onClick={onRunAll}
            disabled={isProcessing || pendingTotal === 0}
            className={`rounded border px-3 py-1.5 font-mono text-xs font-bold uppercase tracking-widest disabled:opacity-50 ${glowEffects ? 'glow-emerald' : ''}`}
            style={{ borderColor: '#39ff14', color: '#39ff14' }}
          >
            Run All
          </button>

          <div className="relative">
            <button
              type="button"
              onClick={() => setConfirmingShutdown((previous) => !previous)}
              aria-expanded={confirmingShutdown}
              className="rounded border border-hud-border px-2.5 py-1.5 text-sm text-slate-300 hover:border-slate-500"
              style={confirmingShutdown ? { borderColor: dangerColor, color: dangerColor } : undefined}
              aria-label="Shut down backend and close tab"
              title="Shut down backend and close tab"
            >
              ⏻
            </button>

            {confirmingShutdown && (
              <div
                role="alertdialog"
                aria-label="Confirm shutdown"
                className="absolute right-0 top-full z-20 mt-2 w-64 rounded border bg-hud-panel p-3 font-mono text-[11px] shadow-lg"
                style={{ borderColor: dangerColor }}
              >
                <p className="uppercase tracking-wider text-slate-300">
                  {isProcessing
                    ? 'Stop the running update and the backend, then close this tab?'
                    : 'Stop the backend and close this tab?'}
                </p>
                <div className="mt-3 flex justify-end gap-2">
                  <button
                    type="button"
                    onClick={() => setConfirmingShutdown(false)}
                    className="rounded border px-2 py-0.5 uppercase tracking-widest"
                    style={{ borderColor: mutedColor, color: mutedColor }}
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setConfirmingShutdown(false);
                      onShutdown();
                    }}
                    className="rounded border px-2 py-0.5 font-bold uppercase tracking-widest"
                    style={{ borderColor: dangerColor, color: dangerColor }}
                  >
                    Shut down
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="px-5 pb-3">
        <div className="flex items-center justify-between font-mono text-[10px] uppercase tracking-widest text-slate-500">
          <span>Installation Integrity</span>
          <span>{progress}% Completed</span>
        </div>
        <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-black/40">
          <div
            className="h-full rounded-full transition-all duration-500"
            style={{ width: `${progress}%`, backgroundColor: accent, boxShadow: `0 0 6px ${accent}` }}
          />
        </div>
      </div>
    </header>
  );
}
