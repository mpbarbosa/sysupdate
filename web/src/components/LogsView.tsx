import { useMemo, useState } from 'react';
import type { LogEntry, SystemConfig } from '../types';
import { getThemeColorHex } from '../theme';

interface LogsViewProps {
  logs: LogEntry[];
  themeColor: SystemConfig['themeColor'];
}

type StatusFilter = 'all' | 'success' | 'failed';

export default function LogsView({ logs, themeColor }: LogsViewProps) {
  const accent = getThemeColorHex(themeColor);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase();
    return logs.filter((log) => {
      if (statusFilter !== 'all' && log.status !== statusFilter) return false;
      if (!query) return true;
      return (
        log.target.toLowerCase().includes(query) ||
        log.action.toLowerCase().includes(query) ||
        log.category.toLowerCase().includes(query) ||
        log.details.toLowerCase().includes(query)
      );
    });
  }, [logs, search, statusFilter]);

  const exportLogs = () => {
    const blob = new Blob([JSON.stringify(filtered, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'sysupdate-logs.json';
    link.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="flex h-full min-h-0 flex-1 flex-col gap-3 p-4">
      <div className="flex items-center gap-3">
        <h2 className="font-mono text-xs font-bold uppercase tracking-widest text-slate-400">
          Historical Audits Journal
        </h2>

        <input
          type="text"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search target, action, details..."
          className="ml-auto w-64 rounded border border-hud-border bg-black/40 px-2 py-1 font-mono text-xs text-slate-200 outline-none focus:border-slate-500"
        />

        {(['all', 'success', 'failed'] as StatusFilter[]).map((option) => (
          <button
            key={option}
            type="button"
            onClick={() => setStatusFilter(option)}
            className="rounded border px-2.5 py-1 font-mono text-[11px] uppercase tracking-widest transition-colors"
            style={
              statusFilter === option
                ? { borderColor: accent, color: accent }
                : { borderColor: '#1c2a30', color: '#7d97a3' }
            }
          >
            {option}
          </button>
        ))}

        <button
          type="button"
          onClick={exportLogs}
          className="rounded border border-hud-border px-2.5 py-1 font-mono text-[11px] uppercase tracking-widest text-slate-300 hover:border-slate-500"
        >
          Export
        </button>
      </div>

      <div className="hud-scroll flex-1 overflow-y-auto rounded border border-hud-border">
        <table className="w-full border-collapse font-mono text-xs">
          <thead className="sticky top-0 bg-hud-panel text-[10px] uppercase tracking-widest text-slate-500">
            <tr>
              <th className="px-3 py-2 text-left">Timestamp</th>
              <th className="px-3 py-2 text-left">Category</th>
              <th className="px-3 py-2 text-left">Target</th>
              <th className="px-3 py-2 text-left">Action</th>
              <th className="px-3 py-2 text-left">Status</th>
              <th className="px-3 py-2 text-left">Duration</th>
              <th className="px-3 py-2 text-left">Details</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((log) => (
              <tr key={log.id} className="border-t border-hud-border/60">
                <td className="px-3 py-2 whitespace-nowrap text-slate-400">{log.timestamp}</td>
                <td className="px-3 py-2 uppercase text-slate-400">{log.category}</td>
                <td className="px-3 py-2 text-slate-200">{log.target}</td>
                <td className="px-3 py-2 text-slate-400">{log.action}</td>
                <td className="px-3 py-2">
                  <span style={{ color: log.status === 'success' ? '#39ff14' : '#ff5c5c' }}>
                    {log.status}
                  </span>
                </td>
                <td className="px-3 py-2 text-slate-400">{log.duration}</td>
                <td className="px-3 py-2 text-slate-500">{log.details}</td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr>
                <td colSpan={7} className="px-3 py-6 text-center text-slate-600">
                  No log entries match this filter.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
