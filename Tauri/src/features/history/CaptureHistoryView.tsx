import React, { useCallback, useEffect, useMemo } from "react";
import {
  DSTrafficLightButtons,
  DSTextField,
  DSIconButton,
  DSChip,
  DSDivider,
  DSPrimaryButton,
} from "@/components";
import { useHistoryStore } from "@/stores/historyStore";
import { getHistory, getStorageInfo } from "@/lib/ipc";
import type { CaptureItem, StorageInfo } from "@/lib/ipc";
import { HistoryGrid } from "./HistoryGrid";
import { HistoryList } from "./HistoryList";
import styles from "./History.module.css";

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / 1024 ** i;
  return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

const FILTER_OPTIONS = [
  { label: "All", value: "all" as const },
  { label: "Screenshots", value: "screenshot" as const },
  { label: "Recordings", value: "recording" as const },
  { label: "GIFs", value: "gif" as const },
] satisfies { label: string; value: "all" | "screenshot" | "recording" | "gif" }[];

export const CaptureHistoryView: React.FC = () => {
  const {
    items,
    isLoading,
    searchQuery,
    filterType,
    sortBy,
    viewMode,
    setItems,
    setSearchQuery,
    setFilterType,
    setSortBy,
    setViewMode,
    setLoading,
  } = useHistoryStore();

  const [storageInfo, setStorageInfo] = React.useState<StorageInfo | null>(null);

  // Fetch history and storage info on mount
  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      setLoading(true);
      try {
        const [history, storage] = await Promise.all([getHistory(), getStorageInfo()]);
        if (!cancelled) {
          setItems(history.items);
          setStorageInfo(storage);
        }
      } catch (err: unknown) {
        console.error("Failed to load history:", err);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    load();
    return () => { cancelled = true; };
  }, [setItems, setLoading]);

  // Derived: filtered + sorted items
  const filteredItems = useMemo(() => {
    let result = items;

    // Filter by type
    if (filterType !== "all") {
      result = result.filter((i) => i.capture_type === filterType);
    }

    // Filter by search
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      result = result.filter((i) => i.filename.toLowerCase().includes(q));
    }

    // Sort
    result = [...result].sort((a, b) => {
      switch (sortBy) {
        case "newest":
          return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
        case "oldest":
          return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
        case "name":
          return a.filename.localeCompare(b.filename);
        default:
          return 0;
      }
    });

    return result;
  }, [items, filterType, searchQuery, sortBy]);

  // Favorites count for display
  const favCount = useMemo(() => items.filter((i) => i.is_favorite).length, [items]);

  const handleClose = useCallback(() => {
    // Tauri window close
    import("@tauri-apps/api/window").then(({ getCurrentWindow }) => {
      getCurrentWindow().close();
    });
  }, []);

  return (
    <div className={styles.container}>
      {/* ── Toolbar ── */}
      <div className={styles.toolbar}>
        <DSTrafficLightButtons onClose={handleClose} />

        <div className={styles.titleBlock}>
          <span className={styles.title}>Capture History</span>
          <span className={styles.subtitle}>
            {isLoading ? "Loading..." : `${filteredItems.length} items`}
          </span>
        </div>

        <div className={styles.searchBar}>
          <DSTextField
            value={searchQuery}
            onChange={setSearchQuery}
            placeholder="Search captures..."
            type="search"
            icon={<SearchIcon />}
          />
        </div>

        {/* Sort */}
        <select
          className={styles.sortSelect}
          value={sortBy}
          onChange={(e) => setSortBy(e.target.value as "newest" | "oldest" | "name")}
        >
          <option value="newest">Newest First</option>
          <option value="oldest">Oldest First</option>
          <option value="name">Name A-Z</option>
        </select>

        {/* View toggle */}
        <div className={styles.viewToggle}>
          <DSIconButton
            icon={<GridIcon />}
            onClick={() => setViewMode("grid")}
            selected={viewMode === "grid"}
            size="sm"
            tooltip="Grid view"
          />
          <DSIconButton
            icon={<ListIcon />}
            onClick={() => setViewMode("list")}
            selected={viewMode === "list"}
            size="sm"
            tooltip="List view"
          />
        </div>
      </div>

      <DSDivider />

      {/* ── Filter chips ── */}
      <div className={styles.filterBar}>
        {FILTER_OPTIONS.map((f) => (
          <DSChip
            key={f.value}
            label={f.label}
            selected={filterType === f.value}
            onClick={() => setFilterType(f.value)}
          />
        ))}
      </div>

      <DSDivider />

      {/* ── Content ── */}
      {filteredItems.length === 0 && !isLoading ? (
        <EmptyState hasItems={items.length > 0} />
      ) : (
        <div className={styles.content}>
          {viewMode === "grid" ? (
            <HistoryGrid items={filteredItems} />
          ) : (
            <HistoryList items={filteredItems} sortBy={sortBy} onSortChange={setSortBy} />
          )}
        </div>
      )}

      {/* ── Footer stats ── */}
      <div className={styles.stats}>
        <div className={styles.statsLeft}>
          <span>{items.length} captures</span>
          <span className={styles.statsDot}>&middot;</span>
          <span>{favCount} favorites</span>
        </div>
        <span>
          {storageInfo
            ? `${formatBytes(storageInfo.total_size_bytes)} used`
            : "Calculating..."}
        </span>
      </div>
    </div>
  );
};

/* ── Empty state ── */

const EmptyState: React.FC<{ hasItems: boolean }> = ({ hasItems }) => (
  <div className={styles.empty}>
    <div className={styles.emptyIcon}>
      <CameraIcon />
    </div>
    <span className={styles.emptyTitle}>
      {hasItems ? "No Matches" : "No Captures Yet"}
    </span>
    <span className={styles.emptyText}>
      {hasItems
        ? "Try adjusting your search or filters."
        : "Your screenshots and recordings will appear here."}
    </span>
    {!hasItems && (
      <DSPrimaryButton onClick={() => {}} icon={<CameraIcon />}>
        Take a Screenshot
      </DSPrimaryButton>
    )}
  </div>
);

/* ── Inline SVG icons ── */

const SearchIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="11" cy="11" r="8" />
    <line x1="21" y1="21" x2="16.65" y2="16.65" />
  </svg>
);

const GridIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="3" width="7" height="7" />
    <rect x="14" y="3" width="7" height="7" />
    <rect x="3" y="14" width="7" height="7" />
    <rect x="14" y="14" width="7" height="7" />
  </svg>
);

const ListIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <line x1="8" y1="6" x2="21" y2="6" />
    <line x1="8" y1="12" x2="21" y2="12" />
    <line x1="8" y1="18" x2="21" y2="18" />
    <line x1="3" y1="6" x2="3.01" y2="6" />
    <line x1="3" y1="12" x2="3.01" y2="12" />
    <line x1="3" y1="18" x2="3.01" y2="18" />
  </svg>
);

const CameraIcon = () => (
  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M23 19a2 2 0 01-2 2H3a2 2 0 01-2-2V8a2 2 0 012-2h4l2-3h6l2 3h4a2 2 0 012 2z" />
    <circle cx="12" cy="13" r="4" />
  </svg>
);
