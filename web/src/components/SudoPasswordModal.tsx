import { useState, type FormEvent } from 'react';
import type { BackendSudoPrompt, SystemConfig } from '../types';
import { getActionToneColor, getThemeColorHex, getThemeGlowClass } from '../theme';

interface SudoPasswordModalProps {
  prompt: BackendSudoPrompt;
  themeColor: SystemConfig['themeColor'];
  glowEffects: boolean;
  /** True while the answer is in flight to the bridge. */
  submitting: boolean;
  /** Bridge-side failure to deliver the answer (not a wrong password). */
  error: string | null;
  onSubmit: (password: string) => void;
  onCancel: () => void;
}

// Shown while the CLI the bridge spawned is blocked inside sudo waiting for a
// password. The child has no terminal, so sudo's askpass helper asks the bridge,
// which asks this tab. The password goes to the local bridge only and is kept
// in memory for the rest of the run so later sudo calls do not ask again.
export default function SudoPasswordModal({
  prompt,
  themeColor,
  glowEffects,
  submitting,
  error,
  onSubmit,
  onCancel,
}: SudoPasswordModalProps) {
  const accent = getThemeColorHex(themeColor);
  const danger = getActionToneColor('danger', themeColor);
  // App.tsx keys this component on prompt.requestId, so a new request (e.g.
  // after a rejection) remounts it with an empty, freshly focused field.
  const [password, setPassword] = useState('');

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!password || submitting) return;
    onSubmit(password);
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 px-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-labelledby="sudo-password-title"
    >
      <form
        onSubmit={handleSubmit}
        className={`w-full max-w-[440px] rounded border bg-hud-panel p-5 font-mono ${glowEffects ? getThemeGlowClass(themeColor) : ''}`}
        style={{ borderColor: accent }}
      >
        <h2 id="sudo-password-title" className="text-xs font-bold uppercase tracking-widest" style={{ color: accent }}>
          Sudo authentication
        </h2>
        <p className="mt-2 text-xs text-slate-400">
          The update needs root privileges. Enter your sudo password to continue the run.
        </p>
        <p className="mt-3 text-xs text-slate-300">{prompt.prompt}</p>

        {prompt.rejected && (
          <p className="mt-2 text-xs" style={{ color: danger }}>
            Sorry, try again. The previous password was rejected.
          </p>
        )}

        <input
          type="password"
          name="sudo-password"
          autoComplete="current-password"
          autoFocus
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          disabled={submitting}
          className="mt-3 w-full rounded border border-hud-border bg-hud-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-slate-400 disabled:opacity-50"
          aria-label="sudo password"
        />

        {error && (
          <p className="mt-2 text-xs" style={{ color: danger }}>
            {error}
          </p>
        )}

        <p className="mt-3 text-[11px] text-slate-600">
          Sent only to the local bridge on this machine, never stored, and forgotten when the run ends.
        </p>

        <div className="mt-4 flex justify-end gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={submitting}
            className="rounded border border-hud-border px-3 py-1.5 text-[11px] font-bold uppercase tracking-widest text-slate-300 hover:border-slate-500 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={submitting || password.length === 0}
            className="rounded border px-3 py-1.5 text-[11px] font-bold uppercase tracking-widest disabled:opacity-50"
            style={{ borderColor: accent, color: accent }}
          >
            {submitting ? 'Sending…' : 'Authenticate'}
          </button>
        </div>
      </form>
    </div>
  );
}
