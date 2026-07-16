import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Sidebar from './components/Sidebar';
import TopAppBar from './components/TopAppBar';
import DashboardView from './components/DashboardView';
import LogsView from './components/LogsView';
import ScheduleView from './components/ScheduleView';
import SettingsView from './components/SettingsView';
import { mockScheduleTasks, mockSystemConfig } from './data/mockData';
import type {
  BackendBootstrapResponse,
  BackendCurrentRunResponse,
  BackendRunSnapshot,
  BackendSummaryEvent,
  Category,
  LogEntry,
  ScheduleTask,
  SidebarCategory,
  SystemConfig,
  TerminalLine,
  UpdateItem,
  ViewName,
} from './types';
import { getFontSizeClass } from './theme';

const nowTimestamp = (): string => new Date().toISOString().slice(0, 19).replace('T', ' ');
const INITIAL_TERMINAL_LINE: TerminalLine = {
  id: 'backend-pending',
  text: 'Waiting for local sysupdate backend...',
  type: 'dim',
};

type ScheduledTerminalLine = {
  id?: string;
  text: string;
  type: TerminalLine['type'];
  delay: number;
};

const VALID_CATEGORIES: Category[] = ['system', 'node', 'python', 'rust', 'apps'];
const SUMMARY_ITEM_OVERRIDES: Record<
  string,
  Pick<UpdateItem, 'id' | 'name' | 'snippetId' | 'category' | 'typeLabel' | 'description'>
> = {
  'Calibre e-book manager': {
    id: 'apps-calibre',
    name: 'Calibre',
    snippetId: 'calibre',
    category: 'apps',
    typeLabel: 'upgrade snippet',
    description: 'E-book management suite discovered from the live sysupdate snippet scan.',
  },
  'Bash Shell': {
    id: 'system-bash',
    name: 'bash',
    snippetId: 'bash',
    category: 'system',
    typeLabel: 'upgrade snippet',
    description: 'GNU Bash shell version discovered from the live sysupdate snippet scan.',
  },
  'AWS CLI': {
    id: 'system-aws-cli',
    name: 'aws-cli',
    snippetId: 'awscli',
    category: 'system',
    typeLabel: 'upgrade snippet',
    description: 'AWS CLI version discovered from the live sysupdate snippet scan.',
  },
  'VSCode Insiders': {
    id: 'apps-vscode-insiders',
    name: 'VS Code Insiders',
    snippetId: 'vscode-insiders',
    category: 'apps',
    typeLabel: 'upgrade snippet',
    description: 'Visual Studio Code Insiders version discovered from the live sysupdate snippet scan.',
  },
  'Kitty terminal': {
    id: 'apps-kitty',
    name: 'Kitty',
    snippetId: 'kitty',
    category: 'apps',
    typeLabel: 'upgrade snippet',
    description: 'Kitty terminal version discovered from the live sysupdate snippet scan.',
  },
  'Anthropic Claude CLI': {
    id: 'apps-claude-cli',
    name: 'Claude CLI',
    snippetId: 'claude',
    category: 'apps',
    typeLabel: 'upgrade snippet',
    description: 'Anthropic Claude CLI version discovered from the live sysupdate snippet scan.',
  },
};

const PACKAGE_MANAGER_SUMMARY_CONFIG: Record<
  string,
  Pick<UpdateItem, 'id' | 'name' | 'snippetId' | 'category' | 'typeLabel' | 'description'>
> = {
  apt_updates: {
    id: 'manager-apt',
    name: 'APT packages',
    snippetId: 'apt',
    category: 'system',
    typeLabel: 'package manager',
    description: 'APT package update inventory discovered from the live sysupdate package check.',
  },
  npm_updates: {
    id: 'manager-npm',
    name: 'Global npm packages',
    snippetId: 'npm-packages',
    category: 'node',
    typeLabel: 'package manager',
    description: 'Global npm package update inventory discovered from the live sysupdate package check.',
  },
  pip_updates: {
    id: 'manager-pip',
    name: 'User pip packages',
    snippetId: 'pip',
    category: 'python',
    typeLabel: 'package manager',
    description: 'User pip package update inventory discovered from the live sysupdate package check.',
  },
  cargo_updates: {
    id: 'manager-cargo',
    name: 'Cargo packages',
    snippetId: 'cargo',
    category: 'rust',
    typeLabel: 'package manager',
    description: 'Cargo package update inventory discovered from the live sysupdate package check.',
  },
  snap_updates: {
    id: 'manager-snap',
    name: 'Snap packages',
    snippetId: 'snap',
    category: 'apps',
    typeLabel: 'package manager',
    description: 'Snap package update inventory discovered from the live sysupdate package check.',
  },
  firmware_updates: {
    id: 'manager-firmware',
    name: 'Firmware updates',
    snippetId: 'fwupd',
    category: 'system',
    typeLabel: 'device firmware',
    description: 'Firmware update inventory discovered from the live sysupdate fwupd check.',
  },
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const asRunSnapshot = (value: unknown): BackendRunSnapshot | null => {
  return isRecord(value) ? (value as unknown as BackendRunSnapshot) : null;
};

const slugify = (value: string): string =>
  value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

const AUTO_UPDATE_STORAGE_KEY = 'sysupdate.autoUpdateIds';

// Per-item "update automatically" preference. There is no backend for this yet,
// so it is persisted client-side in localStorage, keyed by the stable item id.
const loadAutoUpdateIds = (): Set<string> => {
  try {
    const raw = localStorage.getItem(AUTO_UPDATE_STORAGE_KEY);
    if (!raw) {
      return new Set();
    }
    const parsed: unknown = JSON.parse(raw);
    return Array.isArray(parsed) ? new Set(parsed.filter((id): id is string => typeof id === 'string')) : new Set();
  } catch {
    return new Set();
  }
};

const saveAutoUpdateIds = (ids: Set<string>): void => {
  try {
    localStorage.setItem(AUTO_UPDATE_STORAGE_KEY, JSON.stringify([...ids]));
  } catch {
    // Storage unavailable (private mode / quota) — preference stays in-memory only.
  }
};

const isCheckOnlyRun = (args: string[]): boolean => args.includes('--check-only');

const getRunSnippetId = (args: string[]): string | null => {
  const snippetFlagIndex = args.indexOf('--snippet');
  if (snippetFlagIndex === -1) {
    return null;
  }

  const snippetId = args[snippetFlagIndex + 1];
  return typeof snippetId === 'string' && snippetId.length > 0 ? snippetId : null;
};

function App() {
  const websocketRef = useRef<WebSocket | null>(null);
  const refreshAfterUpgradeRef = useRef(false);
  // Auto-upgrade orchestration: after a check-only scan, ticked items with an
  // available update are upgraded one at a time (the backend runs one job).
  const autoUpgradeQueueRef = useRef<{ itemId: string; snippetId: string; name: string }[]>([]);
  const autoUpgradeInProgressRef = useRef(false);
  const handledScanIdRef = useRef<string | null>(null);
  const advancedRunIdRef = useRef<string | null>(null);
  const runNextAutoUpgradeRef = useRef<() => void>(() => {});
  // `${itemId}@${latestVersion}` already auto-attempted — prevents an item that
  // cannot advance (e.g. apt kept-back) from looping, while a genuinely new
  // target version re-enables auto-upgrade.
  const attemptedAutoUpgradeRef = useRef<Set<string>>(new Set());
  const [activeView, setActiveView] = useState<ViewName>('dashboard');
  const [activeCategory, setActiveCategory] = useState<SidebarCategory>('all');
  const [updateItems, setUpdateItems] = useState<UpdateItem[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [scheduleTasks, setScheduleTasks] = useState<ScheduleTask[]>(mockScheduleTasks);
  const [config, setConfig] = useState<SystemConfig>(mockSystemConfig);
  const [terminalLines, setTerminalLines] = useState<TerminalLine[]>([INITIAL_TERMINAL_LINE]);
  const [isProcessing, setIsProcessing] = useState(false);
  const [currentRun, setCurrentRun] = useState<BackendRunSnapshot | null>(null);
  const [autoUpdateIds, setAutoUpdateIds] = useState<Set<string>>(loadAutoUpdateIds);

  const handleToggleAutoUpdate = useCallback((id: string) => {
    setAutoUpdateIds((previous) => {
      const next = new Set(previous);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      saveAutoUpdateIds(next);
      return next;
    });
  }, []);

  const normalizeCategory = useCallback((value: unknown): Category => {
    return typeof value === 'string' && VALID_CATEGORIES.includes(value as Category)
      ? (value as Category)
      : 'system';
  }, []);

  const normalizeLogEntry = useCallback(
    (entry: Record<string, unknown>): LogEntry | null => {
      const id = typeof entry.id === 'string' ? entry.id : null;
      const timestamp = typeof entry.timestamp === 'string' ? entry.timestamp : null;
      const target = typeof entry.target === 'string' ? entry.target : null;
      const action = typeof entry.action === 'string' ? entry.action : null;
      const details = typeof entry.details === 'string' ? entry.details : null;
      const duration = typeof entry.duration === 'string' ? entry.duration : null;
      const status = entry.status === 'failed' ? 'failed' : 'success';

      if (!id || !timestamp || !target || !action || !details || !duration) {
        return null;
      }

      return {
        id,
        timestamp,
        category: normalizeCategory(entry.category),
        target,
        action,
        status,
        details,
        duration,
      };
    },
    [normalizeCategory],
  );

  const mergeLogs = useCallback(
    (incoming: Array<Record<string, unknown>>) => {
      const normalized = incoming
        .map((entry) => normalizeLogEntry(entry))
        .filter((entry): entry is LogEntry => entry !== null);

      if (normalized.length === 0) {
        return;
      }

      setLogs((previous) => {
        const byId = new Map(previous.map((entry) => [entry.id, entry]));
        normalized.forEach((entry) => {
          byId.set(entry.id, entry);
        });

        return Array.from(byId.values()).sort((left, right) => right.timestamp.localeCompare(left.timestamp));
      });
    },
    [normalizeLogEntry],
  );

  const mergeSummaryItems = useCallback((summaries: BackendSummaryEvent[], replaceExisting: boolean) => {
    const toUpdateStatus = (status: unknown): UpdateItem['status'] => {
      switch (status) {
        case 'update_available':
          return 'ready';
        case 'not_installed':
        case 'invalid_installation':
        case 'unknown':
        case 'insufficient_efi_space':
          return 'failed';
        default:
          return 'up_to_date';
      }
    };

    const toSeverity = (status: unknown, totalUpdates?: number): UpdateItem['severity'] => {
      if (status === 'update_available') {
        if ((totalUpdates ?? 0) >= 10) {
          return 'major';
        }
        return 'minor';
      }

      if (
        status === 'not_installed' ||
        status === 'invalid_installation' ||
        status === 'unknown' ||
        status === 'insufficient_efi_space'
      ) {
        return 'major';
      }

      return 'info';
    };

    const nextItems: UpdateItem[] = [];

    for (const summary of summaries) {
      if (summary.summary_name === 'version_check' && typeof summary.target === 'string') {
        const target = summary.target;
        const override = SUMMARY_ITEM_OVERRIDES[target];
        const currentVersion =
          summary.current_version === undefined ? 'unknown' : String(summary.current_version);
        const latestVersion =
          summary.latest_version === undefined ? currentVersion : String(summary.latest_version);

        nextItems.push({
          id: override?.id ?? `apps-${slugify(target)}`,
          name: override?.name ?? target,
          snippetId:
            override?.snippetId ?? (typeof summary.snippet_id === 'string' ? summary.snippet_id : undefined),
          category: override?.category ?? 'apps',
          currentVersion,
          latestVersion,
          typeLabel: override?.typeLabel ?? 'upgrade snippet',
          status: toUpdateStatus(summary.status),
          severity: toSeverity(summary.status),
          description:
            override?.description ?? 'Status discovered from the live sysupdate snippet scan.',
          changelog: [],
        });
        continue;
      }

      const managerConfig = PACKAGE_MANAGER_SUMMARY_CONFIG[summary.summary_name];
      if (!managerConfig) {
        continue;
      }

      const parsedTotal =
        typeof summary.total_updates === 'number'
          ? summary.total_updates
          : Number.parseInt(String(summary.total_updates ?? '0'), 10);
      const totalUpdates = Number.isFinite(parsedTotal) ? parsedTotal : 0;
      const currentVersion = summary.status === 'update_available' ? 'pending updates' : 'checked';
      const latestVersion =
        summary.status === 'update_available'
          ? `${totalUpdates} update${totalUpdates === 1 ? '' : 's'}`
          : 'up to date';

      nextItems.push({
        ...managerConfig,
        currentVersion,
        latestVersion,
        status: toUpdateStatus(summary.status),
        severity: toSeverity(summary.status, totalUpdates),
        changelog: [],
      });
    }

    setUpdateItems((previous) => {
      if (replaceExisting) {
        return nextItems;
      }

      const mergedItems = new Map(previous.map((item) => [item.id, item]));
      nextItems.forEach((item) => {
        mergedItems.set(item.id, item);
      });
      return Array.from(mergedItems.values());
    });
  }, []);

  const applyRunSnapshot = useCallback((run: BackendRunSnapshot | null) => {
    setCurrentRun(run);
    if (!run) {
      setIsProcessing(false);
      return false;
    }

    const nextLines = run.terminalLines.map(({ id, text, type }) => ({ id, text, type }));
    setTerminalLines(nextLines.length > 0 ? nextLines : [INITIAL_TERMINAL_LINE]);
    setIsProcessing(run.status === 'starting' || run.status === 'running');
    mergeSummaryItems(run.summaries, !run.args.includes('--snippet'));
    if (isRecord(run.lastLogEntry)) {
      mergeLogs([run.lastLogEntry]);
    }

    const runSnippetId = getRunSnippetId(run.args);
    if (runSnippetId && !isCheckOnlyRun(run.args) && (run.status === 'starting' || run.status === 'running')) {
      setUpdateItems((previous) =>
        previous.map((item) => (item.snippetId === runSnippetId ? { ...item, status: 'updating' } : item)),
      );
    }

    return true;
  }, [mergeLogs, mergeSummaryItems]);

  const startBackendCheckOnlyRun = useCallback(async (snippetId?: string) => {
    const response = await fetch('/api/runs/check-only', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(snippetId ? { snippetId } : {}),
    });

    if (response.status === 409) {
      const currentRunResponse = await fetch('/api/runs/current');
      if (!currentRunResponse.ok) {
        throw new Error('Backend refused to start a run and current run state could not be loaded.');
      }

      const currentRunPayload = (await currentRunResponse.json()) as BackendCurrentRunResponse;
      applyRunSnapshot(currentRunPayload.run);
      return;
    }

    if (!response.ok) {
      throw new Error(`Backend check-only run failed with HTTP ${response.status}.`);
    }

    const payload = (await response.json()) as BackendCurrentRunResponse;
    applyRunSnapshot(payload.run);
  }, [applyRunSnapshot]);

  const startBackendUpgradeRun = useCallback(async (snippetId: string) => {
    const response = await fetch('/api/runs/upgrade', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ snippetId }),
    });

    if (response.status === 409) {
      const currentRunResponse = await fetch('/api/runs/current');
      if (!currentRunResponse.ok) {
        throw new Error('Backend refused to start an upgrade and current run state could not be loaded.');
      }

      const currentRunPayload = (await currentRunResponse.json()) as BackendCurrentRunResponse;
      applyRunSnapshot(currentRunPayload.run);
      return;
    }

    if (!response.ok) {
      const payload = (await response.json().catch(() => null)) as { error?: string } | null;
      throw new Error(payload?.error ?? `Backend upgrade run failed with HTTP ${response.status}.`);
    }

    const payload = (await response.json()) as BackendCurrentRunResponse;
    applyRunSnapshot(payload.run);
  }, [applyRunSnapshot]);

  // Pull the next item off the auto-upgrade queue and start its upgrade run.
  // Queue advancement on completion is handled by the effect watching currentRun.
  const runNextAutoUpgrade = useCallback(() => {
    const next = autoUpgradeQueueRef.current.shift();
    if (!next) {
      autoUpgradeInProgressRef.current = false;
      // Final read-only re-scan so cards reflect post-upgrade versions.
      window.setTimeout(() => {
        void startBackendCheckOnlyRun().catch(() => {
          /* surfaced via the standard check-only error path */
        });
      }, 500);
      return;
    }

    setUpdateItems((previous) =>
      previous.map((entry) => (entry.id === next.itemId ? { ...entry, status: 'updating' } : entry)),
    );
    setTerminalLines((previous) => [
      ...previous,
      {
        id: `auto-upgrade-${next.snippetId}-${Date.now()}`,
        text: `Auto-update: upgrading ${next.name}...`,
        type: 'dim',
      },
    ]);

    void startBackendUpgradeRun(next.snippetId).catch((error: unknown) => {
      const message = error instanceof Error ? error.message : 'Unknown backend error.';
      setUpdateItems((previous) =>
        previous.map((entry) => (entry.id === next.itemId ? { ...entry, status: 'failed' } : entry)),
      );
      setTerminalLines((previous) => [
        ...previous,
        {
          id: `auto-upgrade-error-${Date.now()}`,
          text: `Auto-update failed for ${next.name}: ${message}`,
          type: 'error',
        },
      ]);
      // A start failure produces no run to complete on, so advance the queue here.
      runNextAutoUpgradeRef.current();
    });
  }, [startBackendUpgradeRun, startBackendCheckOnlyRun]);

  useEffect(() => {
    runNextAutoUpgradeRef.current = runNextAutoUpgrade;
  }, [runNextAutoUpgrade]);

  useEffect(() => {
    let cancelled = false;

    const bootstrap = async () => {
      try {
        const response = await fetch('/api/bootstrap');
        if (!response.ok) {
          throw new Error(`Bootstrap request failed with HTTP ${response.status}.`);
        }

        const payload = (await response.json()) as BackendBootstrapResponse;
        if (cancelled) {
          return;
        }

        mergeLogs(payload.logs);

        const hasActiveSnapshot = applyRunSnapshot(payload.run);
        const shouldRefreshRun =
          !payload.run || payload.run.status === 'completed' || payload.run.status === 'failed';
        if (!hasActiveSnapshot || shouldRefreshRun) {
          setTerminalLines([
            {
              id: 'backend-starting-run',
              text: 'Starting live sysupdate read-only run...',
              type: 'dim',
            },
          ]);
          await startBackendCheckOnlyRun();
        }
      } catch (error) {
        if (cancelled) {
          return;
        }

        const message = error instanceof Error ? error.message : 'Unknown backend error.';
        setTerminalLines([
          {
            id: 'backend-unavailable',
            text: `Local backend unavailable: ${message}`,
            type: 'error',
          },
        ]);
        setIsProcessing(false);
      }
    };

    void bootstrap();

    return () => {
      cancelled = true;
    };
  }, [applyRunSnapshot, mergeLogs, startBackendCheckOnlyRun]);

  useEffect(() => {
    if (!refreshAfterUpgradeRef.current || !currentRun) {
      return;
    }

    if (isCheckOnlyRun(currentRun.args) || currentRun.status === 'starting' || currentRun.status === 'running') {
      return;
    }

    refreshAfterUpgradeRef.current = false;
    const refreshTimer = window.setTimeout(() => {
      void startBackendCheckOnlyRun().catch((error: unknown) => {
        const message = error instanceof Error ? error.message : 'Unknown backend error.';
        setTerminalLines((previous) => [
          ...previous,
          {
            id: `backend-post-upgrade-refresh-${Date.now()}`,
            text: `Unable to refresh live update inventory after upgrade: ${message}`,
            type: 'error',
          },
        ]);
      });
    }, 500);

    return () => {
      window.clearTimeout(refreshTimer);
    };
  }, [currentRun, startBackendCheckOnlyRun]);

  // Auto-upgrade orchestration. Runs when a run finishes (not while active).
  useEffect(() => {
    if (!currentRun) {
      return;
    }
    if (currentRun.status === 'starting' || currentRun.status === 'running') {
      return;
    }

    const checkOnly = isCheckOnlyRun(currentRun.args);

    // 1) A queued auto-upgrade run just finished — advance to the next item.
    //    Guarded by run id so repeated snapshots of the same run advance once.
    if (
      autoUpgradeInProgressRef.current &&
      !checkOnly &&
      advancedRunIdRef.current !== currentRun.id
    ) {
      advancedRunIdRef.current = currentRun.id;
      runNextAutoUpgrade();
      return;
    }

    // 2) A check-only scan finished — enqueue every ticked item that has an
    //    available update and a live snippet, and upgrade them one at a time.
    if (
      checkOnly &&
      !autoUpgradeInProgressRef.current &&
      handledScanIdRef.current !== currentRun.id
    ) {
      handledScanIdRef.current = currentRun.id;
      const eligible = updateItems.filter(
        (item) =>
          item.status === 'ready' &&
          Boolean(item.snippetId) &&
          autoUpdateIds.has(item.id) &&
          !attemptedAutoUpgradeRef.current.has(`${item.id}@${item.latestVersion}`),
      );
      if (eligible.length > 0) {
        autoUpgradeInProgressRef.current = true;
        autoUpgradeQueueRef.current = eligible.map((item) => ({
          itemId: item.id,
          snippetId: item.snippetId as string,
          name: item.name,
        }));
        eligible.forEach((item) =>
          attemptedAutoUpgradeRef.current.add(`${item.id}@${item.latestVersion}`),
        );
        setTerminalLines((previous) => [
          ...previous,
          {
            id: `auto-update-batch-${currentRun.id}`,
            text: `Auto-update: ${eligible.length} item(s) queued — ${eligible
              .map((item) => item.name)
              .join(', ')}`,
            type: 'dim',
          },
        ]);
        runNextAutoUpgrade();
      }
    }
  }, [currentRun, updateItems, autoUpdateIds, runNextAutoUpgrade]);

  useEffect(() => {
    const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const socket = new WebSocket(`${protocol}://${window.location.host}/ws`);
    websocketRef.current = socket;

    socket.onmessage = (event) => {
      try {
        const payload = JSON.parse(event.data) as {
          type?: string;
          payload?: unknown;
        };

        if (payload.type === 'snapshot') {
          applyRunSnapshot(asRunSnapshot(payload.payload));
          return;
        }

        if (payload.type === 'cli.event' && isRecord(payload.payload)) {
          if (payload.payload.event_type === 'log.entry') {
            mergeLogs([payload.payload]);
          }
        }
      } catch {
        // Ignore malformed websocket messages from the local bridge.
      }
    };

    socket.onclose = () => {
      websocketRef.current = null;
    };

    return () => {
      socket.close();
      websocketRef.current = null;
    };
  }, [applyRunSnapshot, mergeLogs]);

  const schedulePrint = (
    lines: ScheduledTerminalLine[],
    onFinished?: () => void,
  ) => {
    if (lines.length === 0) {
      if (onFinished) onFinished();
      return;
    }

    setIsProcessing(true);
    let cumulativeDelay = 0;

    lines.forEach((line, idx) => {
      cumulativeDelay += line.delay;
      window.setTimeout(() => {
        setTerminalLines((prev) => [
          ...prev,
          { id: line.id ?? `dyn-${Date.now()}-${idx}`, text: line.text, type: line.type },
        ]);
        if (idx === lines.length - 1) {
          setIsProcessing(false);
          if (onFinished) onFinished();
        }
      }, cumulativeDelay);
    });
  };

  const handleUpgrade = (id: string) => {
    if (isProcessing) return;
    const item = updateItems.find((entry) => entry.id === id);
    if (!item || item.status === 'up_to_date' || item.status === 'updating') return;

    if (!item.snippetId) {
      setTerminalLines((previous) => [
        ...previous,
        {
          id: `backend-upgrade-unavailable-${Date.now()}`,
          text: `No live sysupdate snippet is wired for ${item.name}.`,
          type: 'warning',
        },
      ]);
      return;
    }

    refreshAfterUpgradeRef.current = true;
    setUpdateItems((previous) =>
      previous.map((entry) => (entry.id === id ? { ...entry, status: 'updating' } : entry)),
    );
    setTerminalLines([
      {
        id: `backend-upgrade-${item.snippetId}`,
        text: `Starting live sysupdate upgrade for ${item.name}...`,
        type: 'dim',
      },
    ]);
    setIsProcessing(true);

    void startBackendUpgradeRun(item.snippetId).catch((error: unknown) => {
      refreshAfterUpgradeRef.current = false;
      const message = error instanceof Error ? error.message : 'Unknown backend error.';
      setUpdateItems((previous) =>
        previous.map((entry) => (entry.id === id ? { ...entry, status: 'failed' } : entry)),
      );
      setTerminalLines([
        {
          id: `backend-upgrade-error-${Date.now()}`,
          text: `Unable to start live upgrade for ${item.name}: ${message}`,
          type: 'error',
        },
      ]);
      setIsProcessing(false);
    });
  };

  const handleRunAll = () => {
    setTerminalLines((previous) => [
      ...previous,
      {
        id: `backend-run-all-unavailable-${Date.now()}`,
        text: 'Run All is not wired to a live backend upgrade yet. Use individual Upgrade actions for live snippet runs.',
        type: 'warning',
      },
    ]);
  };

  const handleCheckUpdates = () => {
    if (isProcessing) return;
    setTerminalLines([
      {
        id: 'backend-refresh-checks',
        text: 'Starting live sysupdate read-only run...',
        type: 'dim',
      },
    ]);
    setIsProcessing(true);
    void startBackendCheckOnlyRun().catch((error: unknown) => {
      const message = error instanceof Error ? error.message : 'Unknown backend error.';
      setTerminalLines([
        {
          id: 'backend-check-error',
          text: `Unable to start live check-only run: ${message}`,
          type: 'error',
        },
      ]);
      setIsProcessing(false);
    });
  };

  const handleRefresh = () => {
    if (isProcessing) return;
    handleCheckUpdates();
  };

  const handleToggleScheduleTask = (id: string) => {
    setScheduleTasks((prev) => prev.map((task) => (task.id === id ? { ...task, enabled: !task.enabled } : task)));
  };

  const handleRunScheduleTaskNow = (id: string) => {
    if (isProcessing) return;
    const task = scheduleTasks.find((entry) => entry.id === id);
    if (!task) return;

    schedulePrint(
      [
        { text: `$ ${task.command}`, type: 'prompt', delay: 150 },
        { text: `Running scheduled task "${task.name}"...`, type: 'info', delay: 500 },
        { text: 'Done.', type: 'success', delay: 400 },
      ],
      () => {
        setScheduleTasks((prev) =>
          prev.map((entry) => (entry.id === id ? { ...entry, lastRun: nowTimestamp() } : entry)),
        );
        setLogs((prev) => [
          {
            id: `log-${Date.now()}`,
            timestamp: nowTimestamp(),
            category: task.category === 'all' ? 'system' : task.category,
            target: task.name,
            action: 'scheduled-run',
            status: 'success',
            details: `Manually triggered "${task.command}".`,
            duration: '~1s',
          },
          ...prev,
        ]);
      },
    );
  };

  const filteredItems = useMemo(
    () => (activeCategory === 'all' ? updateItems : updateItems.filter((item) => item.category === activeCategory)),
    [updateItems, activeCategory],
  );

  const pendingTotal = useMemo(
    () => updateItems.filter((item) => item.status === 'ready' || item.status === 'failed').length,
    [updateItems],
  );

  const progress = useMemo(() => {
    if (updateItems.length === 0) return 100;
    const settled = updateItems.filter((item) => item.status === 'up_to_date').length;
    return Math.round((settled / updateItems.length) * 100);
  }, [updateItems]);

  return (
    <div className={`flex h-screen flex-col overflow-hidden ${getFontSizeClass(config.fontSize)}`}>
      <TopAppBar
        activeView={activeView}
        onViewChange={setActiveView}
        onRefresh={handleRefresh}
        onRunAll={handleRunAll}
        isProcessing={isProcessing}
        progress={progress}
        pendingTotal={pendingTotal}
        themeColor={config.themeColor}
        glowEffects={config.glowEffects}
      />

      <div className="flex min-h-0 flex-1">
        <Sidebar
          activeCategory={activeCategory}
          onCategoryChange={setActiveCategory}
          onCheckUpdates={handleCheckUpdates}
          isChecking={isProcessing}
          themeColor={config.themeColor}
          updateItems={updateItems}
          glowEffects={config.glowEffects}
        />

        {activeView === 'dashboard' && (
          <DashboardView
            items={filteredItems}
            onUpgrade={handleUpgrade}
            autoUpdateIds={autoUpdateIds}
            onToggleAutoUpdate={handleToggleAutoUpdate}
            terminalLines={terminalLines}
            isProcessing={isProcessing}
            pendingTotal={pendingTotal}
            themeColor={config.themeColor}
          />
        )}

        {activeView === 'logs' && <LogsView logs={logs} themeColor={config.themeColor} />}

        {activeView === 'schedule' && (
          <ScheduleView
            tasks={scheduleTasks}
            onToggle={handleToggleScheduleTask}
            onRunNow={handleRunScheduleTaskNow}
            isProcessing={isProcessing}
            themeColor={config.themeColor}
          />
        )}

        {activeView === 'settings' && (
          <SettingsView config={config} onChange={setConfig} scheduleTasks={scheduleTasks} />
        )}
      </div>
    </div>
  );
}

export default App;
