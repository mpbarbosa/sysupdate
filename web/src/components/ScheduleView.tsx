import type { ScheduleTask, SystemConfig } from '../types';
import { getThemeColorHex } from '../theme';

interface ScheduleViewProps {
  tasks: ScheduleTask[];
  onToggle: (id: string) => void;
  onRunNow: (id: string) => void;
  isProcessing: boolean;
  themeColor: SystemConfig['themeColor'];
}

const CRON_FIELDS = ['minute', 'hour', 'day of month', 'month', 'day of week'];

export default function ScheduleView({ tasks, onToggle, onRunNow, isProcessing, themeColor }: ScheduleViewProps) {
  const accent = getThemeColorHex(themeColor);

  return (
    <div className="flex h-full min-h-0 flex-1 flex-col gap-3 p-4">
      <h2 className="font-mono text-xs font-bold uppercase tracking-widest text-slate-400">
        Automated Cron Daemon
      </h2>

      <div className="rounded border border-hud-border bg-hud-panel/40 px-3 py-2 font-mono text-[11px] text-slate-500">
        <span className="text-slate-400">Crontab syntax: </span>
        {CRON_FIELDS.map((field, idx) => (
          <span key={field}>
            <span style={{ color: accent }}>*</span>
            {idx < CRON_FIELDS.length - 1 ? ' ' : ' '}
            <span className="text-slate-600">({field})</span>
            {idx < CRON_FIELDS.length - 1 ? '  ' : ''}
          </span>
        ))}
      </div>

      <div className="hud-scroll flex-1 overflow-y-auto">
        <div className="flex flex-col gap-2">
          {tasks.map((task) => (
            <div
              key={task.id}
              className="flex items-center gap-4 rounded border border-hud-border bg-hud-panel/40 px-3 py-3"
            >
              <button
                type="button"
                role="switch"
                aria-checked={task.enabled}
                onClick={() => onToggle(task.id)}
                className="relative h-5 w-9 shrink-0 rounded-full border transition-colors"
                style={{
                  borderColor: task.enabled ? accent : '#1c2a30',
                  backgroundColor: task.enabled ? `${accent}33` : 'transparent',
                }}
              >
                <span
                  className="absolute top-0.5 h-3.5 w-3.5 rounded-full transition-all"
                  style={{
                    left: task.enabled ? '1.25rem' : '0.125rem',
                    backgroundColor: task.enabled ? accent : '#5c7480',
                  }}
                />
              </button>

              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-sm font-semibold text-slate-100">{task.name}</span>
                  <span className="rounded border border-hud-border px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-wider text-slate-500">
                    {task.category}
                  </span>
                </div>
                <div className="mt-1 font-mono text-[11px] text-slate-500">
                  <span style={{ color: accent }}>{task.cron}</span>
                  <span className="mx-2 text-slate-700">|</span>
                  <span className="text-slate-400">{task.command}</span>
                </div>
                <div className="mt-1 font-mono text-[10px] text-slate-600">
                  Last run: {task.lastRun} · Next run: {task.nextRun}
                </div>
              </div>

              <button
                type="button"
                onClick={() => onRunNow(task.id)}
                disabled={isProcessing || !task.enabled}
                className="shrink-0 rounded border px-3 py-1 font-mono text-[11px] font-bold uppercase tracking-widest disabled:opacity-50"
                style={{ borderColor: accent, color: accent }}
              >
                Run Now
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
