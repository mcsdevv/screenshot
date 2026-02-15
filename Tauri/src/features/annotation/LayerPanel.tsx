/**
 * LayerPanel — right sidebar listing all annotations as reorderable layers.
 */
import React, { useCallback, useRef, useState } from "react";
import clsx from "clsx";
import { useAnnotationStore } from "./useAnnotationStore";
import type { Annotation } from "./types";
import { DSGlassPanel, DSIconButton } from "@/components";
import styles from "./Annotation.module.css";

export const LayerPanel: React.FC = () => {
  const store = useAnnotationStore();
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    annotationId: string;
  } | null>(null);

  // Reversed for display (top layer = last in array = first in list)
  const layers = [...store.annotations].reverse();

  const handleSelect = useCallback(
    (id: string) => {
      store.selectAnnotation(id);
      store.setTool("select");
    },
    [store]
  );

  const handleToggleVisibility = useCallback(
    (id: string) => store.toggleVisibility(id),
    [store]
  );

  const handleDelete = useCallback(
    (id: string) => store.deleteAnnotation(id),
    [store]
  );

  // Double-click to rename
  const handleStartRename = useCallback((annotation: Annotation) => {
    setEditingId(annotation.id);
    setEditName(annotation.name ?? getTypeName(annotation.type));
  }, []);

  const handleCommitRename = useCallback(() => {
    if (editingId) {
      const ann = store.annotations.find((a) => a.id === editingId);
      if (ann) {
        store.updateAnnotation({
          ...ann,
          name: editName.trim() || undefined,
        });
      }
    }
    setEditingId(null);
    setEditName("");
  }, [editingId, editName, store]);

  // Drag to reorder
  const handleDragStart = useCallback(
    (e: React.DragEvent, id: string) => {
      setDraggedId(id);
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", id);
    },
    []
  );

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }, []);

  const handleDrop = useCallback(
    (e: React.DragEvent, targetId: string) => {
      e.preventDefault();
      if (!draggedId || draggedId === targetId) return;

      // Convert display indices (reversed) to real indices
      const fromRealIdx = store.annotations.findIndex((a) => a.id === draggedId);
      const toRealIdx = store.annotations.findIndex((a) => a.id === targetId);
      if (fromRealIdx === -1 || toRealIdx === -1) return;

      store.moveAnnotation(fromRealIdx, toRealIdx);
      setDraggedId(null);
    },
    [draggedId, store]
  );

  const handleDragEnd = useCallback(() => setDraggedId(null), []);

  // Context menu
  const handleContextMenu = useCallback(
    (e: React.MouseEvent, id: string) => {
      e.preventDefault();
      setContextMenu({ x: e.clientX, y: e.clientY, annotationId: id });
    },
    []
  );

  const closeContextMenu = useCallback(() => setContextMenu(null), []);

  if (!store.isLayerPanelVisible) return null;

  return (
    <div className={styles.layerPanel}>
      {/* Header */}
      <div className={styles.layerPanelHeader}>
        <span className={styles.layerPanelTitle}>Layers</span>
        <DSIconButton
          icon={<CloseIcon />}
          size="sm"
          onClick={store.toggleLayerPanel}
          tooltip="Close"
        />
      </div>

      {/* Layer list */}
      <div className={styles.layerList}>
        {layers.length === 0 && (
          <div
            style={{
              padding: "var(--ds-spacing-lg)",
              textAlign: "center",
              font: "var(--ds-font-body-sm)",
              color: "var(--ds-text-tertiary)",
            }}
          >
            No annotations yet
          </div>
        )}

        {layers.map((annotation, displayIdx) => {
          const isSelected = annotation.id === store.selectedAnnotationId;
          const isHidden = store.hiddenAnnotationIds.has(annotation.id);
          const isDragging = annotation.id === draggedId;

          return (
            <div
              key={annotation.id}
              className={clsx(
                isSelected ? styles.layerItemSelected : styles.layerItem,
                isHidden && styles.layerItemHidden,
                isDragging && styles.layerItemDragging
              )}
              onClick={() => handleSelect(annotation.id)}
              onDoubleClick={() => handleStartRename(annotation)}
              onContextMenu={(e) => handleContextMenu(e, annotation.id)}
              draggable
              onDragStart={(e) => handleDragStart(e, annotation.id)}
              onDragOver={handleDragOver}
              onDrop={(e) => handleDrop(e, annotation.id)}
              onDragEnd={handleDragEnd}
            >
              {/* Layer number */}
              <span className={styles.layerNumber}>#{displayIdx + 1}</span>

              {/* Color dot */}
              {annotation.type !== "blur" ? (
                <span
                  className={styles.layerColorDot}
                  style={{ backgroundColor: annotation.color }}
                />
              ) : (
                <span className={styles.layerIcon}>
                  <BlurSmallIcon />
                </span>
              )}

              {/* Name (editable on double-click) */}
              {editingId === annotation.id ? (
                <input
                  className={styles.layerNameInput}
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  onBlur={handleCommitRename}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleCommitRename();
                    if (e.key === "Escape") {
                      setEditingId(null);
                      setEditName("");
                    }
                  }}
                  autoFocus
                  onClick={(e) => e.stopPropagation()}
                />
              ) : (
                <span className={styles.layerName}>
                  {annotation.name ?? getTypeName(annotation.type)}
                  {annotation.type === "numberedStep" && annotation.stepNumber != null && (
                    <span className={styles.layerSubtext}> #{annotation.stepNumber}</span>
                  )}
                  {annotation.type === "text" && annotation.text && (
                    <span className={styles.layerSubtext}>
                      {" "}
                      {annotation.text.length > 12
                        ? annotation.text.slice(0, 12) + "..."
                        : annotation.text}
                    </span>
                  )}
                </span>
              )}

              {/* Action buttons */}
              <div className={styles.layerActions}>
                <button
                  className={styles.layerActionButton}
                  onClick={(e) => {
                    e.stopPropagation();
                    store.bringForward(annotation.id);
                  }}
                  title="Move up"
                >
                  <ChevronUpIcon />
                </button>
                <button
                  className={styles.layerActionButton}
                  onClick={(e) => {
                    e.stopPropagation();
                    store.sendBackward(annotation.id);
                  }}
                  title="Move down"
                >
                  <ChevronDownIcon />
                </button>
                <button
                  className={styles.layerActionButton}
                  onClick={(e) => {
                    e.stopPropagation();
                    handleToggleVisibility(annotation.id);
                  }}
                  title={isHidden ? "Show" : "Hide"}
                >
                  {isHidden ? <EyeSlashIcon /> : <EyeIcon />}
                </button>
                <button
                  className={styles.layerActionButton}
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDelete(annotation.id);
                  }}
                  title="Delete"
                >
                  <TrashSmallIcon />
                </button>
              </div>
            </div>
          );
        })}
      </div>

      {/* Footer: renumber steps if any exist */}
      {store.annotations.some((a) => a.type === "numberedStep") && (
        <div className={styles.layerPanelFooter}>
          <button
            style={{
              background: "rgba(255,255,255,0.05)",
              border: "none",
              borderRadius: "var(--ds-radius-xs)",
              padding: "var(--ds-spacing-xxs) var(--ds-spacing-sm)",
              font: "var(--ds-font-label-sm)",
              color: "var(--ds-text-secondary)",
              cursor: "pointer",
            }}
            onClick={() => store.renumberSteps()}
          >
            Renumber All
          </button>
        </div>
      )}

      {/* Context menu */}
      {contextMenu && (
        <>
          <div className={styles.contextMenuBackdrop} onClick={closeContextMenu} />
          <div
            className={styles.contextMenu}
            style={{ left: contextMenu.x, top: contextMenu.y }}
          >
            <button
              className={styles.contextMenuItem}
              onClick={() => {
                store.bringToFront(contextMenu.annotationId);
                closeContextMenu();
              }}
            >
              Bring to Front
              <span className={styles.contextMenuShortcut}>Cmd+Shift+]</span>
            </button>
            <button
              className={styles.contextMenuItem}
              onClick={() => {
                store.sendToBack(contextMenu.annotationId);
                closeContextMenu();
              }}
            >
              Send to Back
              <span className={styles.contextMenuShortcut}>Cmd+Shift+[</span>
            </button>
            <div className={styles.contextMenuSeparator} />
            <button
              className={styles.contextMenuItem}
              onClick={() => {
                store.duplicateAnnotation(contextMenu.annotationId);
                closeContextMenu();
              }}
            >
              Duplicate
              <span className={styles.contextMenuShortcut}>Cmd+D</span>
            </button>
            <button
              className={styles.contextMenuItem}
              onClick={() => {
                const ann = store.annotations.find(
                  (a) => a.id === contextMenu.annotationId
                );
                if (ann) handleStartRename(ann);
                closeContextMenu();
              }}
            >
              Rename
            </button>
            <div className={styles.contextMenuSeparator} />
            <button
              className={clsx(styles.contextMenuItem, styles.contextMenuDanger)}
              onClick={() => {
                store.deleteAnnotation(contextMenu.annotationId);
                closeContextMenu();
              }}
            >
              Delete
              <span className={styles.contextMenuShortcut}>Del</span>
            </button>
          </div>
        </>
      )}
    </div>
  );
};

// ---- Helpers ----

function getTypeName(type: string): string {
  const map: Record<string, string> = {
    rectangleOutline: "Rectangle",
    rectangleSolid: "Filled Rect",
    circleOutline: "Circle",
    line: "Line",
    arrow: "Arrow",
    text: "Text",
    blur: "Blur",
    pencil: "Pencil",
    highlighter: "Highlight",
    numberedStep: "Step",
  };
  return map[type] ?? type;
}

/* ---- Tiny SVG Icons ---- */

function CloseIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function ChevronUpIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 16 16" fill="none">
      <path d="M4 10l4-4 4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function ChevronDownIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 16 16" fill="none">
      <path d="M4 6l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function EyeIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 16 16" fill="none">
      <path d="M1 8s3-5 7-5 7 5 7 5-3 5-7 5-7-5-7-5Z" stroke="currentColor" strokeWidth="1.3" />
      <circle cx="8" cy="8" r="2" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  );
}

function EyeSlashIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 16 16" fill="none">
      <path d="M1 8s3-5 7-5 7 5 7 5-3 5-7 5-7-5-7-5Z" stroke="currentColor" strokeWidth="1.3" />
      <path d="M2 14L14 2" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
    </svg>
  );
}

function TrashSmallIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 16 16" fill="none">
      <path d="M3 4h10M5 4V3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1m1 0v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V4h8Z" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

function BlurSmallIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 16 16" fill="none">
      <circle cx="5" cy="5" r="1.5" fill="currentColor" opacity="0.3" />
      <circle cx="11" cy="5" r="1.5" fill="currentColor" opacity="0.5" />
      <circle cx="8" cy="8" r="2" fill="currentColor" opacity="0.7" />
      <circle cx="5" cy="11" r="1.5" fill="currentColor" opacity="0.5" />
      <circle cx="11" cy="11" r="1.5" fill="currentColor" opacity="0.3" />
    </svg>
  );
}
