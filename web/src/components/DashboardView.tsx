import { useEffect, useRef } from 'react';
import type { SystemConfig, TerminalLine, UpdateItem } from '../types';
import { getActionToneColor, getSeverityColor, getThemeColorHex } from '../theme';
import { toCardAffordances } from '../updateCard';

interface DashboardViewProps {
  items: UpdateItem[];
  onUpgrade: (id: string) => void;
  autoUpdateIds: Set<string>;
  onToggleAutoUpdate: (id: string) => void;
  /** When true, items already at their latest version are left out of `items`. */
  hideUpToDate: boolean;
  /** How many up-to-date items the toggle is hiding in the active category. */
  hiddenUpToDateCount: number;
  onToggleHideUpToDate: () => void;
  terminalLines: TerminalLine[];
  isProcessing: boolean;
  pendingTotal: number;
  themeColor: SystemConfig['themeColor'];
}

const TERMINAL_LINE_COLOR: Record<TerminalLine['type'], string> = {
  prompt: '#39ff14',
  info: '#00f3ff',
  success: '#39ff14',
  warning: '#ffb800',
  error: '#ff5c5c',
  output: '#d6f6ff',
  dim: '#5c7480',
};

function UpdateItemCard({
  item,
  onUpgrade,
  autoUpdate,
  onToggleAutoUpdate,
  themeColor,
}: {
  item: UpdateItem;
  onUpgrade: (id: string) => void;
  autoUpdate: boolean;
  onToggleAutoUpdate: (id: string) => void;
  themeColor: SystemConfig['themeColor'];
}) {
  const accent = getThemeColorHex(themeColor);
  const severityColor = getSeverityColor(item.severity);
  // What this card may offer — which button, whether the version transition is
  // real, and what to show instead (updateCard.ts, unit-tested).
  const affordances = toCardAffordances(item);
  const actionColor = getActionToneColor(affordances.actionTone, themeColor);

  return (
    <div className="rounded border border-hud-border bg-hud-panel/40 p-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-2">
            <span className="font-mono text-sm font-semibold text-slate-100">{item.name}</span>
            <span
              className="rounded px-1.5 py-0.5 font-mono text-[10px] font-bold uppercase tracking-wider"
              style={{ color: severityColor, border: `1px solid ${severityColor}66` }}
            >
              {item.severity}
            </span>
          </div>
          <div className="mt-0.5 font-mono text-[11px] text-slate-500">{item.typeLabel}</div>
        </div>

        <button
          type="button"
          onClick={() => onUpgrade(item.id)}
          disabled={!affordances.actionEnabled}
          className="shrink-0 rounded border px-3 py-1 font-mono text-[11px] font-bold uppercase tracking-widest transition-opacity disabled:opacity-50"
          style={{ borderColor: actionColor, color: actionColor }}
        >
          {affordances.actionLabel}
        </button>
      </div>

      <p className="mt-2 font-mono text-xs text-slate-400">{item.description}</p>

      {affordances.remediation ? (
        <p className="mt-2 font-mono text-xs" style={{ color: actionColor }}>
          {affordances.remediation}
        </p>
      ) : (
        <div className="mt-2 flex items-center gap-2 font-mono text-xs">
          <span className="text-slate-500">{item.currentVersion}</span>
          {affordances.showVersions && (
            <>
              <span className="text-slate-600">→</span>
              <span style={{ color: accent }}>{item.latestVersion}</span>
            </>
          )}
        </div>
      )}

      {item.changelog.length > 0 && (
        <ul className="mt-2 space-y-0.5 border-l border-hud-border pl-2 font-mono text-[11px] text-slate-500">
          {item.changelog.map((entry, idx) => (
            <li key={idx}>· {entry}</li>
          ))}
        </ul>
      )}

      {affordances.autoUpdateSupported ? (
        <label className="mt-3 flex cursor-pointer select-none items-center gap-2 border-t border-hud-border pt-2 font-mono text-[11px] uppercase tracking-wider text-slate-400">
          <input
            type="checkbox"
            checked={autoUpdate}
            onChange={() => onToggleAutoUpdate(item.id)}
            className="h-3.5 w-3.5 cursor-pointer"
            style={{ accentColor: accent }}
          />
          <span>Update automatically</span>
        </label>
      ) : (
        // Nothing sysupdate runs could ever upgrade this item, so a checkbox
        // here would tick, persist, and silently never fire. Say why instead.
        <p className="mt-3 border-t border-hud-border pt-2 font-mono text-[11px] text-slate-600">
          {affordances.autoUpdateNote}
        </p>
      )}
    </div>
  );
}

export default function DashboardView({
  items,
  onUpgrade,
  autoUpdateIds,
  onToggleAutoUpdate,
  hideUpToDate,
  hiddenUpToDateCount,
  onToggleHideUpToDate,
  terminalLines,
  isProcessing,
  pendingTotal,
  themeColor,
}: DashboardViewProps) {
  const terminalEndRef = useRef<HTMLDivElement>(null);
  const filterColor = getActionToneColor(hideUpToDate ? 'accent' : 'muted', themeColor);

  useEffect(() => {
    terminalEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [terminalLines]);

  return (
    <div className="flex h-full min-h-0 flex-1 gap-4 p-4">
      <section className="flex w-[400px] shrink-0 flex-col">
        <div className="mb-2 flex items-center justify-between gap-2">
          <h2 className="font-mono text-xs font-bold uppercase tracking-widest text-slate-400">
            Available Updates
          </h2>
          <button
            type="button"
            onClick={onToggleHideUpToDate}
            aria-pressed={hideUpToDate}
            title={hideUpToDate ? 'Show items that are already up to date' : 'Hide items that are already up to date'}
            className="flex shrink-0 items-center gap-1.5 rounded border px-2 py-0.5 font-mono text-[10px] font-bold uppercase tracking-widest transition-colors"
            style={{ borderColor: filterColor, color: filterColor }}
          >
            <span aria-hidden="true">{hideUpToDate ? '◉' : '○'}</span>
            <span>Hide up to date</span>
          </button>
        </div>
        <div className="hud-scroll flex flex-1 flex-col gap-2 overflow-y-auto pr-1">
          {items.length === 0 ? (
            <p className="font-mono text-xs text-slate-500">
              {hiddenUpToDateCount > 0
                ? `All ${hiddenUpToDateCount} item${hiddenUpToDateCount === 1 ? '' : 's'} in this category are up to date.`
                : 'No items in this category.'}
            </p>
          ) : (
            items.map((item) => (
              <UpdateItemCard
                key={item.id}
                item={item}
                onUpgrade={onUpgrade}
                autoUpdate={autoUpdateIds.has(item.id)}
                onToggleAutoUpdate={onToggleAutoUpdate}
                themeColor={themeColor}
              />
            ))
          )}
          {items.length > 0 && hiddenUpToDateCount > 0 && (
            <p className="mt-1 font-mono text-[11px] text-slate-600">
              {hiddenUpToDateCount} up-to-date item{hiddenUpToDateCount === 1 ? '' : 's'} hidden
            </p>
          )}
        </div>
      </section>

      <section className="terminal-grid flex min-h-0 flex-1 flex-col rounded border border-hud-border bg-black/40">
        <div className="border-b border-hud-border px-3 py-2 font-mono text-xs font-bold uppercase tracking-widest text-slate-400">
          Live Output Console
        </div>

        <div className="hud-scroll flex-1 overflow-y-auto px-3 py-2 font-mono text-xs leading-relaxed">
          {terminalLines.map((line, idx) => (
            <div key={line.id} className="flex gap-3">
              <span className="select-none text-slate-700">{String(idx + 1).padStart(2, '0')}</span>
              <span style={{ color: TERMINAL_LINE_COLOR[line.type] }} className="whitespace-pre-wrap">
                {line.text}
              </span>
            </div>
          ))}
          {isProcessing && (
            <div className="flex gap-3">
              <span className="select-none text-slate-700">{String(terminalLines.length + 1).padStart(2, '0')}</span>
              <span className="cursor-blink text-slate-300">█</span>
            </div>
          )}
          <div ref={terminalEndRef} />
        </div>

        <div className="flex items-center justify-between border-t border-hud-border px-3 py-1.5 font-mono text-[10px] uppercase tracking-widest text-slate-500">
          <span style={{ color: isProcessing ? '#ffb800' : '#39ff14' }}>
            {isProcessing ? 'Processing' : 'Ready'}
          </span>
          <span>{pendingTotal} updates pending</span>
          <span>UTF-8</span>
        </div>
      </section>
    </div>
  );
}
