import React, { useEffect, useRef, useCallback } from "react";
import clsx from "clsx";
import { DSGlassPanel, DSBadge, DSTrafficLightButtons } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import type { CaptureItem } from "@/lib/ipc";
import * as ipc from "@/lib/ipc";
import styles from "./QuickAccess.module.css";

interface QuickAccessOverlayProps {
  capture: CaptureItem;
  thumbnailUrl?: string;
  onDismiss: () => void;
}

const AUTO_DISMISS_MS = 5000;

interface ActionDef {
  key: string;
  icon: string;
  label: string;
  shortcut?: string;
  destructive?: boolean;
}

const ACTIONS: ActionDef[] = [
  { key: "copy", icon: "\u{1F4CB}", label: "Copy", shortcut: "Cmd+C" },
  { key: "reveal", icon: "\u{1F4C1}", label: "Reveal", shortcut: "Cmd+S" },
  { key: "edit", icon: "\u270F\uFE0F", label: "Edit", shortcut: "Cmd+E" },
  { key: "pin", icon: "\u{1F4CC}", label: "Pin", shortcut: "Cmd+P" },
  { key: "ocr", icon: "\u{1F50D}", label: "OCR", shortcut: "Cmd+T" },
  { key: "delete", icon: "\u{1F5D1}", label: "Delete", destructive: true },
];

export const QuickAccessOverlay: React.FC<QuickAccessOverlayProps> = ({
  capture,
  thumbnailUrl,
  onDismiss,
}) => {
  const popupCorner = useSettingsStore((s) => s.popupCorner);
  const quickAccessDuration = useSettingsStore((s) => s.quickAccessDuration);
  const timerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const duration = quickAccessDuration > 0 ? quickAccessDuration * 1000 : AUTO_DISMISS_MS;

  const dismiss = useCallback(() => {
    if (timerRef.current) clearTimeout(timerRef.current);
    onDismiss();
  }, [onDismiss]);

  // Auto-dismiss timer
  useEffect(() => {
    timerRef.current = setTimeout(dismiss, duration);
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [dismiss, duration]);

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        dismiss();
        return;
      }
      if (e.metaKey) {
        switch (e.key.toLowerCase()) {
          case "c": e.preventDefault(); handleAction("copy"); return;
          case "s": e.preventDefault(); handleAction("reveal"); return;
          case "e": e.preventDefault(); handleAction("edit"); return;
          case "p": e.preventDefault(); handleAction("pin"); return;
          case "t": e.preventDefault(); handleAction("ocr"); return;
        }
        if (e.key === "Backspace") { e.preventDefault(); handleAction("delete"); }
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [capture.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleAction = async (action: string) => {
    switch (action) {
      case "copy":
        // Copy is handled by Rust side -- invoke copy_to_clipboard
        try {
          await ipc.captureFullscreen(); // placeholder -- real copy IPC
        } catch { /* noop */ }
        break;
      case "reveal":
        // Reveal in finder
        break;
      case "edit":
        // Open annotation editor via event
        window.dispatchEvent(new CustomEvent("open-annotation-editor", { detail: capture }));
        break;
      case "pin":
        // Pin screenshot
        window.dispatchEvent(new CustomEvent("pin-screenshot", { detail: capture }));
        break;
      case "ocr":
        try {
          const blocks = await ipc.recognizeText(capture.filename);
          const text = blocks.map((b) => b.text).join("\n");
          await navigator.clipboard.writeText(text);
        } catch { /* noop */ }
        break;
      case "delete":
        try {
          await ipc.deleteCapture(capture.id);
        } catch { /* noop */ }
        break;
    }
    dismiss();
  };

  const badgeLabel = capture.capture_type.toUpperCase();
  const badgeStyle = capture.capture_type === "screenshot" ? "accent" : "warning";

  return (
    <div className={clsx(styles.overlay, styles[popupCorner])}>
      {/* Click-outside backdrop */}
      <div className={styles.backdrop} onClick={dismiss} />

      <DSGlassPanel className={styles.panel} padding="none">
        {/* Header with traffic lights */}
        <div className={styles.header}>
          <DSTrafficLightButtons onClose={dismiss} />
        </div>

        {/* Thumbnail area */}
        <div className={styles.thumbnailWrap}>
          {thumbnailUrl ? (
            <img src={thumbnailUrl} alt="Capture preview" className={styles.preview} />
          ) : (
            <div className={styles.previewPlaceholder}>
              <span>{capture.capture_type === "recording" ? "\u{1F3AC}" : "\u{1F4F7}"}</span>
              <span>Loading preview...</span>
            </div>
          )}

          <div className={styles.badge}>
            <DSBadge label={badgeLabel} variant={badgeStyle} />
          </div>

          {/* Action buttons overlaid at bottom */}
          <div className={styles.actions}>
            {ACTIONS.map((a) => (
              <button
                key={a.key}
                type="button"
                className={clsx(styles.actionButton, a.destructive && styles.destructive)}
                onClick={() => handleAction(a.key)}
                title={`${a.label}${a.shortcut ? ` (${a.shortcut})` : ""}`}
              >
                {a.icon}
              </button>
            ))}
          </div>
        </div>

        {/* Auto-dismiss progress bar */}
        <div className={styles.timer}>
          <div
            className={styles.timerBar}
            style={{ "--qa-duration": `${duration}ms` } as React.CSSProperties}
          />
        </div>
      </DSGlassPanel>
    </div>
  );
};
