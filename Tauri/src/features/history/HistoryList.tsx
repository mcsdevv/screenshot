import React, { useCallback, useState } from "react";
import clsx from "clsx";
import { DSBadge, DSIconButton } from "@/components";
import { useHistoryStore } from "@/stores/historyStore";
import { deleteCapture, toggleFavorite } from "@/lib/ipc";
import type { CaptureItem } from "@/lib/ipc";
import styles from "./History.module.css";

interface HistoryListProps {
  items: CaptureItem[];
  sortBy: "newest" | "oldest" | "name";
  onSortChange: (s: "newest" | "oldest" | "name") => void;
}

const TYPE_BADGE_VARIANT: Record<CaptureItem["capture_type"], "accent" | "success" | "warning"> = {
  screenshot: "accent",
  recording: "success",
  gif: "warning",
};

function captureTypeLabel(type: CaptureItem["capture_type"]): string {
  switch (type) {
    case "screenshot": return "Screenshot";
    case "recording": return "Recording";
    case "gif": return "GIF";
  }
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  }) + " " + d.toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
}

type SortableColumn = "date" | "name";

export const HistoryList: React.FC<HistoryListProps> = ({ items, sortBy, onSortChange }) => {
  const { toggleFavorite: storeFav, removeItem } = useHistoryStore();
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const handleColumnSort = useCallback(
    (col: SortableColumn) => {
      if (col === "date") {
        onSortChange(sortBy === "newest" ? "oldest" : "newest");
      } else {
        onSortChange("name");
      }
    },
    [sortBy, onSortChange],
  );

  const handleOpen = useCallback((item: CaptureItem) => {
    console.log("Open capture:", item.id);
  }, []);

  const handleDelete = useCallback(
    async (item: CaptureItem) => {
      try {
        await deleteCapture(item.id);
        removeItem(item.id);
      } catch (err: unknown) {
        console.error("Delete failed:", err);
      }
    },
    [removeItem],
  );

  const handleFavorite = useCallback(
    async (item: CaptureItem) => {
      try {
        await toggleFavorite(item.id);
        storeFav(item.id);
      } catch (err: unknown) {
        console.error("Favorite toggle failed:", err);
      }
    },
    [storeFav],
  );

  const handleCopy = useCallback(async (item: CaptureItem) => {
    try {
      await navigator.clipboard.writeText(item.filename);
    } catch (err: unknown) {
      console.error("Copy failed:", err);
    }
  }, []);

  const activeDateSort = sortBy === "newest" || sortBy === "oldest";
  const activeNameSort = sortBy === "name";

  return (
    <div className={styles.list}>
      {/* Column headers */}
      <div className={styles.listHeader}>
        {/* Thumbnail — not sortable */}
        <span className={styles.listHeaderCell} />

        {/* Name */}
        <button
          type="button"
          className={clsx(styles.listHeaderCell, activeNameSort && styles.listHeaderCellActive)}
          onClick={() => handleColumnSort("name")}
        >
          Name
          {activeNameSort && <span className={styles.sortArrow}>&#9650;</span>}
        </button>

        {/* Date */}
        <button
          type="button"
          className={clsx(styles.listHeaderCell, activeDateSort && styles.listHeaderCellActive)}
          onClick={() => handleColumnSort("date")}
        >
          Date
          {activeDateSort && (
            <span className={styles.sortArrow}>
              {sortBy === "newest" ? "\u25BC" : "\u25B2"}
            </span>
          )}
        </button>

        {/* Type */}
        <span className={styles.listHeaderCell}>Type</span>

        {/* Size */}
        <span className={styles.listHeaderCell}>Size</span>

        {/* Actions — spacer */}
        <span className={styles.listHeaderCell} />
      </div>

      {/* Rows */}
      {items.map((item) => (
        <div
          key={item.id}
          className={clsx(styles.listItem, selectedId === item.id && styles.listItemSelected)}
          onClick={() => setSelectedId(item.id)}
          onDoubleClick={() => handleOpen(item)}
        >
          {/* Thumbnail */}
          <img
            src={`asset://localhost/${item.filename}`}
            alt={item.filename}
            className={styles.listThumb}
            onError={(e) => {
              // Replace with placeholder on load failure
              const el = e.currentTarget;
              el.style.display = "none";
              const placeholder = document.createElement("div");
              placeholder.className = styles.listThumbPlaceholder;
              placeholder.textContent = item.capture_type === "recording" ? "\u25B6" : "\uD83D\uDDBC";
              el.parentNode?.insertBefore(placeholder, el);
            }}
          />

          {/* Name + favorite */}
          <div className={styles.listName}>
            <div className={styles.listNameFav}>
              <span className={styles.listFilename}>{item.filename}</span>
              {item.is_favorite && <span className={styles.favStar}>&#9733;</span>}
            </div>
          </div>

          {/* Date */}
          <span className={styles.listDate}>{formatDate(item.created_at)}</span>

          {/* Type badge */}
          <DSBadge
            label={captureTypeLabel(item.capture_type)}
            variant={TYPE_BADGE_VARIANT[item.capture_type]}
          />

          {/* Size (placeholder — IPC does not expose file size yet) */}
          <span className={styles.listSize}>--</span>

          {/* Hover actions — stopPropagation on wrapper to prevent row click */}
          {/* eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions */}
          <div className={styles.listActions} onClick={(e) => e.stopPropagation()}>
            <DSIconButton
              icon={<OpenIcon />}
              onClick={() => handleOpen(item)}
              size="sm"
              tooltip="Open"
            />
            <DSIconButton
              icon={<CopyIcon />}
              onClick={() => handleCopy(item)}
              size="sm"
              tooltip="Copy"
            />
            <DSIconButton
              icon={<TrashIcon />}
              onClick={() => handleDelete(item)}
              size="sm"
              tooltip="Delete"
            />
          </div>
        </div>
      ))}
    </div>
  );
};

/* ── Inline SVG icons ── */

const OpenIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6" />
    <polyline points="15 3 21 3 21 9" />
    <line x1="10" y1="14" x2="21" y2="3" />
  </svg>
);

const CopyIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
    <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
  </svg>
);

const TrashIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="3 6 5 6 21 6" />
    <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2" />
  </svg>
);
