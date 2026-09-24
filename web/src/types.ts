export type Category = 'system' | 'node' | 'python' | 'rust' | 'apps';

export type ScheduleCategory = Category | 'all';

export interface UpdateItem {
  id: string;
  name: string;
  snippetId?: string;
  category: Category;
  currentVersion: string;
  latestVersion: string;
  typeLabel: string;
  // 'blocked' = the install itself is broken or the host is out of room; the
  // snippet cannot fix it, so the card must not offer a retry.
  status: 'ready' | 'up_to_date' | 'updating' | 'failed' | 'self_managed' | 'blocked';
  severity: 'info' | 'minor' | 'major';
  description: string;
  changelog: string[];
  // Host-side fix for a 'blocked' item, taken verbatim from the CLI's
  // `remediation` event field. The dashboard never invents one.
  remediation?: string;
}

// Palette role for an update card's action button.
export type ActionTone = 'accent' | 'muted' | 'danger' | 'warning';

export interface TerminalLine {
  id: string;
  text: string;
  type: 'prompt' | 'info' | 'success' | 'warning' | 'error' | 'output' | 'dim';
}

export interface BackendTerminalLine extends TerminalLine {
  source?: string;
}

export interface LogEntry {
  id: string;
  timestamp: string;
  category: Category;
  target: string;
  action: string;
  status: 'success' | 'failed';
  details: string;
  duration: string;
}

export interface ScheduleTask {
  id: string;
  name: string;
  cron: string;
  category: ScheduleCategory;
  lastRun: string;
  nextRun: string;
  enabled: boolean;
  command: string;
}

export interface BackendRunPrompt {
  status: 'requested' | 'resolved';
  promptType: string;
  message: string;
  defaultResponse?: string;
  options?: string;
  response?: string;
  responseSource?: string;
}

// A sudo password prompt raised by the CLI the bridge spawned. The bridge
// relays sudo's askpass call to the dashboard; the password itself never
// appears in a snapshot.
export interface BackendSudoPrompt {
  requestId: string;
  prompt: string;
  // True when sudo asked the same invocation again: the last answer was wrong.
  rejected: boolean;
  status: 'requested' | 'resolved' | 'cancelled' | 'expired';
  requestedAt?: string;
}

export interface BackendSummaryEvent {
  event_type: 'summary.updates';
  summary_name: string;
  target?: string;
  status?: string;
  [key: string]: string | number | boolean | undefined;
}

export interface BackendRunSnapshot {
  id: string;
  status: 'starting' | 'running' | 'completed' | 'failed';
  args: string[];
  command: string;
  startedAt: string;
  completedAt: string | null;
  exitCode: number | null;
  pid: number | null;
  runId: string | null;
  prompt: BackendRunPrompt | null;
  lastLogEntry: Record<string, unknown> | null;
  sudoPrompt?: BackendSudoPrompt | null;
  terminalLines: BackendTerminalLine[];
  summaries: BackendSummaryEvent[];
}

export interface BackendBootstrapResponse {
  backend: {
    name: string;
    host: string;
    port: number;
    websocketPath: string;
    supports: string[];
  };
  logs: Array<Record<string, unknown>>;
  run: BackendRunSnapshot | null;
}

export interface BackendCurrentRunResponse {
  run: BackendRunSnapshot | null;
}

export interface BackendLogsResponse {
  logs: Array<Record<string, unknown>>;
}

export interface SystemConfig {
  autoUpdate: boolean;
  notifyOnSuccess: boolean;
  notifyOnFailure: boolean;
  silentMode: boolean;
  glowEffects: boolean;
  fontSize: 'sm' | 'md' | 'lg';
  themeColor: 'cyan' | 'magenta' | 'emerald' | 'amber';
  // Corrected from DESIGN.md's { brew, apt, npm, pip, cargo }: this project has no
  // Homebrew/macOS support, but supports both apt and pacman (web/CONTEXT.md).
  repositories: {
    apt: string;
    pacman: string;
    npm: string;
    pip: string;
    cargo: string;
  };
}

export type ViewName = 'dashboard' | 'logs' | 'schedule' | 'settings';

export type SidebarCategory = Category | 'all';
