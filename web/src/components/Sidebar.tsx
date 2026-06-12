import type { SidebarCategory, SystemConfig, UpdateItem } from '../types';
import { getThemeColorHex } from '../theme';

interface SidebarItem {
  id: SidebarCategory;
  label: string;
  icon: string;
}

const SIDEBAR_ITEMS: SidebarItem[] = [
  { id: 'all', label: 'ALL', icon: '※' },
  { id: 'system', label: 'SYSTEM', icon: '■' },
  { id: 'node', label: 'NODE', icon: '▲' },
  { id: 'python', label: 'PYTHON', icon: '◆' },
  { id: 'rust', label: 'RUST', icon: '•' },
  { id: 'apps', label: 'APPS', icon: '⚙' },
];

interface SidebarProps {
  activeCategory: SidebarCategory;
  onCategoryChange: (category: SidebarCategory) => void;
  onCheckUpdates: () => void;
  isChecking: boolean;
  themeColor: SystemConfig['themeColor'];
  updateItems: UpdateItem[];
  glowEffects: boolean;
}

const pendingCount = (items: UpdateItem[], category: SidebarCategory): number => {
  const scoped = category === 'all' ? items : items.filter((item) => item.category === category);
  return scoped.filter((item) => item.status === 'ready' || item.status === 'failed').length;
};

export default function Sidebar({
  activeCategory,
  onCategoryChange,
  onCheckUpdates,
  isChecking,
  themeColor,
  updateItems,
  glowEffects,
}: SidebarProps) {
  const accent = getThemeColorHex(themeColor);

  return (
    <aside className="terminal-grid flex h-full w-48 shrink-0 flex-col border-r border-hud-border bg-hud-panel/60 px-4 py-5 font-mono">
      <div>
        <div className="text-sm font-bold tracking-widest" style={{ color: accent }}>
          MAINTENANCE
        </div>
        <div className="mt-1 text-xs text-slate-500">v4.2-stable</div>
      </div>

      <nav className="mt-8 flex flex-col gap-1">
        {SIDEBAR_ITEMS.map((item) => {
          const isActive = item.id === activeCategory;
          const count = pendingCount(updateItems, item.id);

          return (
            <button
              key={item.id}
              type="button"
              onClick={() => onCategoryChange(item.id)}
              className="flex items-center justify-between rounded px-2 py-2 text-xs tracking-wider transition-colors"
              style={
                isActive
                  ? { color: accent, backgroundColor: 'rgba(255,255,255,0.04)', borderLeft: `2px solid ${accent}` }
                  : { color: '#7d97a3', borderLeft: '2px solid transparent' }
              }
            >
              <span>
                <span className="mr-2">{item.icon}</span>
                {item.label}
              </span>
              {count > 0 && (
                <span
                  className="rounded-full px-1.5 text-[10px] font-bold"
                  style={{ backgroundColor: `${accent}33`, color: accent }}
                >
                  {count}
                </span>
              )}
            </button>
          );
        })}
      </nav>

      <button
        type="button"
        onClick={onCheckUpdates}
        disabled={isChecking}
        className={`mt-8 rounded border px-2 py-2 text-xs font-bold tracking-widest transition-opacity disabled:opacity-50 ${glowEffects ? 'glow-cyan' : ''}`}
        style={{ borderColor: accent, color: accent }}
      >
        {isChecking ? 'CHECKING...' : 'CHECK UPDATES'}
      </button>

      <div className="mt-auto pt-8 text-[11px] text-slate-600">
        <div className="cursor-pointer hover:text-slate-400">Docs</div>
        <div className="cursor-pointer hover:text-slate-400">Out</div>
      </div>
    </aside>
  );
}
