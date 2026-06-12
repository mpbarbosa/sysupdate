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
  status: 'ready' | 'up_to_date' | 'updating' | 'failed';
  severity: 'info' | 'minor' | 'major';
  description: string;
  changelog: string[];
}

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
