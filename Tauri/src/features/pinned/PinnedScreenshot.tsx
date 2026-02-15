import React, { useState, useRef, useCallback, useEffect } from "react";
import clsx from "clsx";
import styles from "./Pinned.module.css";

interface PinnedScreenshotProps {
  /** URL or data: URI of the image */
  imageUrl: string;
  /** Initial size */
  initialWidth?: number;
  initialHeight?: number;
  onClose: () => void;
}

type ResizeCorner = "tl" | "tr" | "bl" | "br";

const OPACITY_OPTIONS = [100, 80, 60, 40, 20];
const MIN_SIZE = 100;
const MAX_SCALE = 3;

export const PinnedScreenshot: React.FC<PinnedScreenshotProps> = ({
  imageUrl,
  initialWidth = 400,
  initialHeight = 300,
  onClose,
}) => {
  const aspectRatio = initialWidth / initialHeight;

  const [size, setSize] = useState({ w: initialWidth, h: initialHeight });
  const [opacity, setOpacity] = useState(1);
  const [isLocked, setIsLocked] = useState(false);
  const [showOpacityMenu, setShowOpacityMenu] = useState(false);
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number } | null>(null);

  const resizeDragRef = useRef<{
    corner: ResizeCorner;
    startX: number;
    startY: number;
    startW: number;
    startH: number;
  } | null>(null);

  // Zoom in/out
  const zoomIn = useCallback(() => {
    setSize((prev) => {
      const scale = Math.min(MAX_SCALE, prev.w / initialWidth + 0.1);
      return { w: initialWidth * scale, h: initialHeight * scale };
    });
  }, [initialWidth, initialHeight]);

  const zoomOut = useCallback(() => {
    setSize((prev) => {
      const scale = Math.max(MIN_SIZE / initialWidth, prev.w / initialWidth - 0.1);
      return { w: initialWidth * scale, h: initialHeight * scale };
    });
  }, [initialWidth, initialHeight]);

  const copyToClipboard = useCallback(async () => {
    try {
      const resp = await fetch(imageUrl);
      const blob = await resp.blob();
      await navigator.clipboard.write([
        new ClipboardItem({ [blob.type]: blob }),
      ]);
    } catch { /* noop */ }
  }, [imageUrl]);

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") { onClose(); return; }
      if (e.metaKey) {
        if (e.key === "-") { e.preventDefault(); zoomOut(); }
        if (e.key === "=" || e.key === "+") { e.preventDefault(); zoomIn(); }
        if (e.key.toLowerCase() === "l") { e.preventDefault(); setIsLocked((p) => !p); }
        if (e.key.toLowerCase() === "c") { e.preventDefault(); copyToClipboard(); }
      }
      if (e.key.toLowerCase() === "o" && !e.metaKey) {
        setShowOpacityMenu((p) => !p);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose, zoomIn, zoomOut, copyToClipboard]);

  // Close opacity/context menus on outside click
  useEffect(() => {
    const handler = () => {
      setShowOpacityMenu(false);
      setContextMenu(null);
    };
    window.addEventListener("click", handler);
    return () => window.removeEventListener("click", handler);
  }, []);

  // Corner resize drag handler
  const handleResizeStart = (corner: ResizeCorner) => (e: React.MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();

    resizeDragRef.current = {
      corner,
      startX: e.clientX,
      startY: e.clientY,
      startW: size.w,
      startH: size.h,
    };

    const handleMove = (ev: MouseEvent) => {
      const ref = resizeDragRef.current;
      if (!ref) return;
      const dx = ev.clientX - ref.startX;
      const dy = ev.clientY - ref.startY;

      // Use the larger delta for aspect-ratio-locked resize
      let primaryDelta: number;
      switch (ref.corner) {
        case "tl": primaryDelta = Math.max(-dx, -dy); break;
        case "tr": primaryDelta = Math.max(dx, -dy); break;
        case "bl": primaryDelta = Math.max(-dx, dy); break;
        case "br": primaryDelta = Math.max(dx, dy); break;
      }

      const newW = Math.min(
        Math.max(ref.startW + primaryDelta, MIN_SIZE),
        initialWidth * MAX_SCALE
      );
      setSize({ w: newW, h: newW / aspectRatio });
    };

    const handleEnd = () => {
      resizeDragRef.current = null;
      window.removeEventListener("mousemove", handleMove);
      window.removeEventListener("mouseup", handleEnd);
    };

    window.addEventListener("mousemove", handleMove);
    window.addEventListener("mouseup", handleEnd);
  };

  // Right-click context menu
  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    setContextMenu({ x: e.clientX, y: e.clientY });
  };

  return (
    <>
      <div
        className={styles.window}
        style={{ width: size.w, height: size.h }}
        onContextMenu={handleContextMenu}
        data-tauri-drag-region={!isLocked ? "" : undefined}
      >
        <img
          src={imageUrl}
          alt="Pinned screenshot"
          className={styles.image}
          style={{ opacity }}
          draggable={false}
        />

        {/* Hover controls */}
        <div className={styles.controls} onClick={(e) => e.stopPropagation()}>
          <button
            type="button"
            className={styles.controlBtn}
            onClick={zoomOut}
            title="Zoom Out (Cmd-)"
          >
            -
          </button>
          <button
            type="button"
            className={styles.controlBtn}
            onClick={zoomIn}
            title="Zoom In (Cmd=)"
          >
            +
          </button>

          <div className={styles.controlDivider} />

          <button
            type="button"
            className={styles.controlBtn}
            onClick={() => setIsLocked((p) => !p)}
            title={isLocked ? "Unlock (Cmd+L)" : "Lock (Cmd+L)"}
          >
            {isLocked ? "\u{1F512}" : "\u{1F513}"}
          </button>

          <div style={{ position: "relative" }}>
            <button
              type="button"
              className={styles.controlBtn}
              onClick={(e) => {
                e.stopPropagation();
                setShowOpacityMenu((p) => !p);
              }}
              title="Opacity (O)"
            >
              {"\u25D0"}
            </button>
            {showOpacityMenu && (
              <div className={styles.opacityMenu} onClick={(e) => e.stopPropagation()}>
                {OPACITY_OPTIONS.map((val) => (
                  <button
                    key={val}
                    type="button"
                    className={styles.opacityOption}
                    onClick={() => {
                      setOpacity(val / 100);
                      setShowOpacityMenu(false);
                    }}
                  >
                    {val}%
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className={styles.controlDivider} />

          <button
            type="button"
            className={styles.controlBtn}
            onClick={copyToClipboard}
            title="Copy (Cmd+C)"
          >
            {"\u{1F4CB}"}
          </button>
          <button
            type="button"
            className={styles.controlBtn}
            onClick={onClose}
            title="Close (Esc)"
          >
            {"\u2715"}
          </button>
        </div>

        {/* Corner resize handles */}
        <div
          className={clsx(styles.resizeHandle, styles.handleTL)}
          onMouseDown={handleResizeStart("tl")}
        />
        <div
          className={clsx(styles.resizeHandle, styles.handleTR)}
          onMouseDown={handleResizeStart("tr")}
        />
        <div
          className={clsx(styles.resizeHandle, styles.handleBL)}
          onMouseDown={handleResizeStart("bl")}
        />
        <div
          className={clsx(styles.resizeHandle, styles.handleBR)}
          onMouseDown={handleResizeStart("br")}
        />
      </div>

      {/* Right-click context menu */}
      {contextMenu && (
        <div
          className={styles.contextMenu}
          style={{ left: contextMenu.x, top: contextMenu.y }}
          onClick={() => setContextMenu(null)}
        >
          <button type="button" className={styles.contextMenuItem} onClick={copyToClipboard}>
            <span className={styles.contextMenuIcon}>{"\u{1F4CB}"}</span>
            Copy to Clipboard
          </button>
          <button type="button" className={styles.contextMenuItem} onClick={zoomIn}>
            <span className={styles.contextMenuIcon}>+</span>
            Zoom In
          </button>
          <button type="button" className={styles.contextMenuItem} onClick={zoomOut}>
            <span className={styles.contextMenuIcon}>-</span>
            Zoom Out
          </button>
          <button
            type="button"
            className={styles.contextMenuItem}
            onClick={() => setIsLocked((p) => !p)}
          >
            <span className={styles.contextMenuIcon}>{isLocked ? "\u{1F512}" : "\u{1F513}"}</span>
            {isLocked ? "Unlock Position" : "Lock Position"}
          </button>
          <button type="button" className={styles.contextMenuItem} onClick={onClose}>
            <span className={styles.contextMenuIcon}>{"\u2715"}</span>
            Close
          </button>
        </div>
      )}
    </>
  );
};
