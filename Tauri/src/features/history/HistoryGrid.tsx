import React, { useCallback, useRef, useState } from "react";
import { DSThumbnailCard, DSBadge } from "@/components";
import { useHistoryStore } from "@/stores/historyStore";
import { deleteCapture, toggleFavorite } from "@/lib/ipc";
import type { CaptureItem } from "@/lib/ipc";
import styles from "./History.module.css";

interface HistoryGridProps {
  items: CaptureItem[];
}

interface ContextMenuState {
  x: number;
  y: number;
  item: CaptureItem;
}

const TYPE_BADGE_VARIANT: Record<CaptureItem["capture_type"], "accent" | "success" | "warning"> = {
  screenshot: "accent",
  recording: "success",
  gif: "warning",
};

function formatRelativeDate(iso: string): string {
  const date = new Date(iso);
  const now = Date.now();
  const diffMs = now - date.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDay = Math.floor(diffHr / 24);

  if (diffSec < 60) return "just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHr < 24) return `${diffHr}h ago`;
  if (diffDay < 7) return `${diffDay}d ago`;

  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function captureTypeLabel(type: CaptureItem["capture_type"]): string {
  switch (type) {
    case "screenshot": return "Screenshot";
    case "recording": return "Recording";
    case "gif": return "GIF";
  }
}

export const HistoryGrid: React.FC<HistoryGridProps> = ({ items }) => {
  const { toggleFavorite: storeFav, removeItem } = useHistoryStore();
  const [contextMenu, setContextMenu] = useState<ContextMenuState | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  const handleContextMenu = useCallback(
    (e: React.MouseEvent, item: CaptureItem) => {
      e.preventDefault();
      setContextMenu({ x: e.clientX, y: e.clientY, item });
    },
    [],
  );

  const closeMenu = useCallback(() => setContextMenu(null), []);

  // Close context menu when clicking elsewhere
  React.useEffect(() => {
    if (!contextMenu) return;

    const handleClick = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        closeMenu();
      }
    };

    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [contextMenu, closeMenu]);

  const handleOpen = useCallback((item: CaptureItem) => {
    // Open in editor via IPC — placeholder for routing
    console.log("Open capture:", item.id);
  }, []);

  const handleCopy = useCallback(async (item: CaptureItem) => {
    try {
      await navigator.clipboard.writeText(item.filename);
    } catch (err: unknown) {
      console.error("Copy failed:", err);
    }
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

  return (
    <>
      <div className={styles.grid}>
        {items.map((item) => (
          <div
            key={item.id}
            className={styles.gridCard}
            onContextMenu={(e) => handleContextMenu(e, item)}
          >
            <DSThumbnailCard
              src={`asset://localhost/${item.filename}`}
              title={item.filename}
              subtitle={formatRelativeDate(item.created_at)}
              onClick={() => handleOpen(item)}
              isFavorite={item.is_favorite}
              onFavoriteToggle={() => handleFavorite(item)}
            />
            <div className={styles.gridBadge}>
              <DSBadge label={captureTypeLabel(item.capture_type)} variant={TYPE_BADGE_VARIANT[item.capture_type]} />
            </div>
          </div>
        ))}
      </div>

      {/* Context menu */}
      {contextMenu && (
        <div
          ref={menuRef}
          className={styles.contextMenu}
          style={{ top: contextMenu.y, left: contextMenu.x }}
        >
          <button
            className={styles.contextMenuItem}
            onClick={() => { handleOpen(contextMenu.item); closeMenu(); }}
          >
            <OpenIcon /> Open
          </button>
          <button
            className={styles.contextMenuItem}
            onClick={() => { handleCopy(contextMenu.item); closeMenu(); }}
          >
            <CopyIcon /> Copy
          </button>
          <div className={styles.contextMenuDivider} />
          <button
            className={styles.contextMenuItem}
            onClick={() => { handleFavorite(contextMenu.item); closeMenu(); }}
          >
            <StarIcon />
            {contextMenu.item.is_favorite ? "Remove Favorite" : "Add to Favorites"}
          </button>
          <div className={styles.contextMenuDivider} />
          <button
            className={`${styles.contextMenuItem} ${styles.contextMenuDanger}`}
            onClick={() => { handleDelete(contextMenu.item); closeMenu(); }}
          >
            <TrashIcon /> Delete
          </button>
        </div>
      )}
    </>
  );
};

/* ── Inline SVG icons for context menu ── */

const OpenIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6" />
    <polyline points="15 3 21 3 21 9" />
    <line x1="10" y1="14" x2="21" y2="3" />
  </svg>
);

const CopyIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
    <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" />
  </svg>
);

const StarIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
  </svg>
);

const TrashIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="3 6 5 6 21 6" />
    <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2" />
  </svg>
);
