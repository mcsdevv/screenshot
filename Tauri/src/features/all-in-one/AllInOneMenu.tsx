import React, { useEffect, useState } from "react";
import { DSGlassPanel, DSDivider } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import * as ipc from "@/lib/ipc";
import styles from "./AllInOne.module.css";

interface AllInOneMenuProps {
  onDismiss: () => void;
  onOpenSettings?: () => void;
}

interface MenuItem {
  icon: string;
  label: string;
  safeShortcut: string;
  nativeShortcut: string;
  action: () => void;
}

export const AllInOneMenu: React.FC<AllInOneMenuProps> = ({
  onDismiss,
  onOpenSettings,
}) => {
  const shortcutMode = useSettingsStore((s) => s.shortcutMode);
  const isNative = shortcutMode === "native";

  const [recentCaptures, setRecentCaptures] = useState<ipc.CaptureItem[]>([]);

  // Load recent captures
  useEffect(() => {
    ipc.getHistory().then((history) => {
      setRecentCaptures(history.items.slice(0, 3));
    }).catch(() => {});
  }, []);

  // Escape to dismiss
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") onDismiss();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onDismiss]);

  const doAction = (fn: () => void) => {
    fn();
    onDismiss();
  };

  const openOverlayWindow = async (label: string, path: string) => {
    const existing = await WebviewWindow.getByLabel(label);
    if (existing) {
      await existing.show();
      await existing.setFocus();
      return;
    }
    new WebviewWindow(label, {
      url: path,
      fullscreen: true,
      decorations: false,
      alwaysOnTop: true,
    });
  };

  const screenshotItems: MenuItem[] = [
    {
      icon: "\u{1F5BC}",
      label: "Capture Fullscreen",
      safeShortcut: "\u2303\u21E73",
      nativeShortcut: "\u2318\u21E73",
      action: () => doAction(() => ipc.captureFullscreen()),
    },
    {
      icon: "\u2B1C",
      label: "Capture Area",
      safeShortcut: "\u2303\u21E74",
      nativeShortcut: "\u2318\u21E74",
      action: () => doAction(() => {
        openOverlayWindow("selection", "/selection");
      }),
    },
    {
      icon: "\u{1FA9F}",
      label: "Capture Window",
      safeShortcut: "\u2303\u21E75",
      nativeShortcut: "\u2318\u21E75",
      action: () => doAction(() => {
        openOverlayWindow("window-picker", "/selection?mode=window");
      }),
    },
  ];

  const recordingItems: MenuItem[] = [
    {
      icon: "\u{1F7E5}",
      label: "Record Area",
      safeShortcut: "\u2303\u21E77",
      nativeShortcut: "\u2318\u21E77",
      action: () => doAction(() => {
        openOverlayWindow("recording-selection", "/recording-selection?mode=area");
      }),
    },
    {
      icon: "\u{1F534}",
      label: "Record Fullscreen",
      safeShortcut: "\u2303\u21E79",
      nativeShortcut: "\u2318\u21E79",
      action: () => doAction(() => {
        openOverlayWindow("recording-selection", "/recording-selection");
      }),
    },
  ];

  const toolItems: MenuItem[] = [
    {
      icon: "\u{1F50D}",
      label: "Capture Text (OCR)",
      safeShortcut: "\u2303\u21E7O",
      nativeShortcut: "\u2318\u21E7O",
      action: () => doAction(async () => {
        try {
          const item = await ipc.captureFullscreen();
          const info = await ipc.getStorageInfo();
          const fullPath = `${info.path}/${item.filename}`;
          const blocks = await ipc.recognizeText(fullPath);
          const text = blocks.map((b) => b.text).join("\n");
          await navigator.clipboard.writeText(text);
        } catch { /* noop */ }
      }),
    },
    {
      icon: "\u{1F3A8}",
      label: "Color Picker",
      safeShortcut: "",
      nativeShortcut: "",
      action: () => doAction(() => {
        openOverlayWindow("color-picker", "/selection?mode=color");
      }),
    },
  ];

  const renderSection = (title: string, items: MenuItem[]) => (
    <div className={styles.section}>
      <div className={styles.sectionTitle}>{title}</div>
      {items.map((item) => (
        <button
          key={item.label}
          type="button"
          className={styles.menuItem}
          onClick={item.action}
        >
          <span className={styles.menuItemIcon}>{item.icon}</span>
          <span className={styles.menuItemLabel}>{item.label}</span>
          {(isNative ? item.nativeShortcut : item.safeShortcut) && (
            <span className={styles.shortcutHint}>
              {isNative ? item.nativeShortcut : item.safeShortcut}
            </span>
          )}
        </button>
      ))}
    </div>
  );

  return (
    <div className={styles.backdrop} onClick={onDismiss}>
      <DSGlassPanel className={styles.menu} padding="sm">
        <div onClick={(e) => e.stopPropagation()}>
          {renderSection("Screenshot", screenshotItems)}
          <div className={styles.divider} />
          {renderSection("Recording", recordingItems)}
          <div className={styles.divider} />
          {renderSection("Tools", toolItems)}

          {/* Recent captures */}
          {recentCaptures.length > 0 && (
            <>
              <div className={styles.divider} />
              <div className={styles.recentSection}>
                <div className={styles.recentTitle}>Recent</div>
                <div className={styles.recentRow}>
                  {recentCaptures.map((c) => (
                    <img
                      key={c.id}
                      className={styles.recentThumb}
                      src={`asset://localhost/${c.filename}`}
                      alt={c.filename}
                      onClick={() => {
                        window.dispatchEvent(
                          new CustomEvent("open-capture", { detail: c })
                        );
                        onDismiss();
                      }}
                    />
                  ))}
                </div>
              </div>
            </>
          )}

          {/* Settings footer */}
          <div className={styles.footer}>
            <button
              type="button"
              className={styles.settingsButton}
              onClick={() => {
                onOpenSettings?.();
                onDismiss();
              }}
            >
              {"\u2699\uFE0F"} Settings
            </button>
          </div>
        </div>
      </DSGlassPanel>
    </div>
  );
};
