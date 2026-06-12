import type { ScheduleTask, SystemConfig } from '../types';
import { getThemeColorHex } from '../theme';

interface SettingsViewProps {
  config: SystemConfig;
  onChange: (updater: (config: SystemConfig) => SystemConfig) => void;
  scheduleTasks: ScheduleTask[];
}

const THEME_COLORS: SystemConfig['themeColor'][] = ['cyan', 'magenta', 'emerald', 'amber'];
const FONT_SIZES: SystemConfig['fontSize'][] = ['sm', 'md', 'lg'];
const REPOSITORY_KEYS: (keyof SystemConfig['repositories'])[] = ['apt', 'pacman', 'npm', 'pip', 'cargo'];

function Toggle({
  label,
  description,
  checked,
  onChange,
  accent,
}: {
  label: string;
  description: string;
  checked: boolean;
  onChange: () => void;
  accent: string;
}) {
  return (
    <div className="flex items-center justify-between gap-4 rounded border border-hud-border bg-hud-panel/40 px-3 py-2.5">
      <div>
        <div className="font-mono text-sm text-slate-200">{label}</div>
        <div className="font-mono text-[11px] text-slate-500">{description}</div>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={onChange}
        className="relative h-5 w-9 shrink-0 rounded-full border transition-colors"
        style={{
          borderColor: checked ? accent : '#1c2a30',
          backgroundColor: checked ? `${accent}33` : 'transparent',
        }}
      >
        <span
          className="absolute top-0.5 h-3.5 w-3.5 rounded-full transition-all"
          style={{ left: checked ? '1.25rem' : '0.125rem', backgroundColor: checked ? accent : '#5c7480' }}
        />
      </button>
    </div>
  );
}

export default function SettingsView({ config, onChange, scheduleTasks }: SettingsViewProps) {
  const accent = getThemeColorHex(config.themeColor);
  const autoUpdateEnabled = scheduleTasks.some((task) => task.enabled);

  return (
    <div className="hud-scroll h-full min-h-0 flex-1 overflow-y-auto p-4">
      <div className="mx-auto flex max-w-2xl flex-col gap-6">
        <section>
          <h2 className="mb-2 font-mono text-xs font-bold uppercase tracking-widest text-slate-400">
            Theme Color
          </h2>
          <div className="flex gap-2">
            {THEME_COLORS.map((color) => (
              <button
                key={color}
                type="button"
                onClick={() => onChange((prev) => ({ ...prev, themeColor: color }))}
                className="flex-1 rounded border px-3 py-2 font-mono text-[11px] font-bold uppercase tracking-widest"
                style={{
                  borderColor: getThemeColorHex(color),
                  color: getThemeColorHex(color),
                  backgroundColor: config.themeColor === color ? `${getThemeColorHex(color)}22` : 'transparent',
                }}
              >
                {color}
              </button>
            ))}
          </div>
        </section>

        <section>
          <h2 className="mb-2 font-mono text-xs font-bold uppercase tracking-widest text-slate-400">Font Size</h2>
          <div className="flex gap-2">
            {FONT_SIZES.map((size) => (
              <button
                key={size}
                type="button"
                onClick={() => onChange((prev) => ({ ...prev, fontSize: size }))}
                className="flex-1 rounded border px-3 py-2 font-mono text-[11px] font-bold uppercase tracking-widest"
                style={
                  config.fontSize === size
                    ? { borderColor: accent, color: accent, backgroundColor: `${accent}22` }
                    : { borderColor: '#1c2a30', color: '#7d97a3' }
                }
              >
                {size}
              </button>
            ))}
          </div>
        </section>

        <section className="flex flex-col gap-2">
          <h2 className="mb-1 font-mono text-xs font-bold uppercase tracking-widest text-slate-400">
            Daemon &amp; Notifications
          </h2>

          <div className="flex items-center justify-between gap-4 rounded border border-hud-border bg-hud-panel/20 px-3 py-2.5">
            <div>
              <div className="font-mono text-sm text-slate-200">Auto Update</div>
              <div className="font-mono text-[11px] text-slate-500">
                Derived from Schedule — {autoUpdateEnabled ? 'at least one task is enabled' : 'no tasks enabled'}.
                Manage tasks in the Schedule view.
              </div>
            </div>
            <span
              className="rounded px-2 py-1 font-mono text-[11px] font-bold uppercase tracking-widest"
              style={{ color: autoUpdateEnabled ? '#39ff14' : '#5c7480' }}
            >
              {autoUpdateEnabled ? 'On' : 'Off'}
            </span>
          </div>

          <Toggle
            label="Notify on Success"
            description="Send a desktop notification when a scheduled run completes successfully."
            checked={config.notifyOnSuccess}
            onChange={() => onChange((prev) => ({ ...prev, notifyOnSuccess: !prev.notifyOnSuccess }))}
            accent={accent}
          />
          <Toggle
            label="Notify on Failure"
            description="Send a desktop notification when a scheduled run fails."
            checked={config.notifyOnFailure}
            onChange={() => onChange((prev) => ({ ...prev, notifyOnFailure: !prev.notifyOnFailure }))}
            accent={accent}
          />
          <Toggle
            label="Silent Mode"
            description="Run sysupdate with -q (non-interactive, quiet output)."
            checked={config.silentMode}
            onChange={() => onChange((prev) => ({ ...prev, silentMode: !prev.silentMode }))}
            accent={accent}
          />
          <Toggle
            label="Glow Effects"
            description="Enable neon glow shadows around HUD panels and buttons."
            checked={config.glowEffects}
            onChange={() => onChange((prev) => ({ ...prev, glowEffects: !prev.glowEffects }))}
            accent={accent}
          />
        </section>

        <section>
          <h2 className="mb-2 font-mono text-xs font-bold uppercase tracking-widest text-slate-400">
            Registration Mirrors
          </h2>
          <div className="flex flex-col gap-2">
            {REPOSITORY_KEYS.map((key) => (
              <label key={key} className="flex items-center gap-3 font-mono text-xs">
                <span className="w-16 shrink-0 uppercase text-slate-500">{key}</span>
                <input
                  type="text"
                  value={config.repositories[key]}
                  onChange={(event) =>
                    onChange((prev) => ({
                      ...prev,
                      repositories: { ...prev.repositories, [key]: event.target.value },
                    }))
                  }
                  className="flex-1 rounded border border-hud-border bg-black/40 px-2 py-1.5 text-slate-200 outline-none focus:border-slate-500"
                />
              </label>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
