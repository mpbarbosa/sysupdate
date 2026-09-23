import type { SystemConfig } from '../types';
import { getThemeColorHex } from '../theme';

interface ShutdownScreenProps {
  /** True when this tab asked for the shutdown and tried to close itself. */
  closeAttempted: boolean;
  themeColor: SystemConfig['themeColor'];
}

// Shown once the backend bridge has confirmed it is stopping. Browsers only let
// a page close its own tab when a script opened it (or it is the tab's sole
// history entry), so this screen is the fallback when window.close() is
// ignored — and what other open dashboard tabs see.
export default function ShutdownScreen({ closeAttempted, themeColor }: ShutdownScreenProps) {
  const accent = getThemeColorHex(themeColor);

  return (
    <main className="terminal-grid flex h-screen flex-col items-center justify-center gap-3 px-6 font-mono">
      <h1 className="text-lg font-bold tracking-[0.3em]" style={{ color: accent }}>
        SYSUPDATE
      </h1>
      <p className="text-sm uppercase tracking-widest text-slate-300">Backend bridge stopped</p>
      <p className="max-w-md text-center text-xs text-slate-500">
        {closeAttempted
          ? 'The browser kept this tab open. You can close it now.'
          : 'The bridge was shut down from another tab. You can close this one.'}
      </p>
      <p className="mt-2 text-center text-[11px] text-slate-600">
        To start again, run <span className="text-slate-400">./web/run_app.sh</span> from the repository.
      </p>
    </main>
  );
}
