import React, { useEffect } from "react";
import clsx from "clsx";
import { DSGlassPanel } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import styles from "./Shortcuts.module.css";

interface KeyboardShortcutsOverlayProps {
  onDismiss: () => void;
}

interface ShortcutDef {
  description: string;
  safeKeys: string[];
  nativeKeys: string[];
}

const CAPTURE_SHORTCUTS: ShortcutDef[] = [
  { description: "Capture Area", safeKeys: ["\u2303", "\u21E7", "3"], nativeKeys: ["\u2318", "\u21E7", "3"] },
  { description: "Capture Window", safeKeys: ["\u2303", "\u21E7", "4"], nativeKeys: ["\u2318", "\u21E7", "4"] },
  { description: "Capture Fullscreen", safeKeys: ["\u2303", "\u21E7", "5"], nativeKeys: ["\u2318", "\u21E7", "5"] },
];

const RECORDING_SHORTCUTS: ShortcutDef[] = [
  { description: "Record Area", safeKeys: ["\u2303", "\u21E7", "6"], nativeKeys: ["\u2318", "\u21E7", "6"] },
  { description: "Record Window", safeKeys: ["\u2303", "\u21E7", "7"], nativeKeys: ["\u2318", "\u21E7", "7"] },
  { description: "Record Fullscreen", safeKeys: ["\u2303", "\u21E7", "8"], nativeKeys: ["\u2318", "\u21E7", "8"] },
];

const APP_SHORTCUTS: ShortcutDef[] = [
  { description: "Capture Text (OCR)", safeKeys: ["\u2303", "\u21E7", "O"], nativeKeys: ["\u2318", "\u21E7", "O"] },
  { description: "Pin Screenshot", safeKeys: ["\u2303", "\u21E7", "P"], nativeKeys: ["\u2318", "\u21E7", "P"] },
  { description: "All-in-One Menu", safeKeys: ["\u2303", "\u21E7", "A"], nativeKeys: ["\u2318", "\u21E7", "A"] },
  { description: "Open Folder", safeKeys: ["\u2303", "\u21E7", "F"], nativeKeys: ["\u2318", "\u21E7", "F"] },
  { description: "Preferences", safeKeys: ["\u2303", "\u21E7", ","], nativeKeys: ["\u2318", "\u21E7", ","] },
];

function ShortcutSection({
  title,
  shortcuts,
  isNative,
}: {
  title: string;
  shortcuts: ShortcutDef[];
  isNative: boolean;
}) {
  return (
    <div className={styles.section}>
      <div className={styles.sectionTitle}>{title}</div>
      {shortcuts.map((s) => (
        <div key={s.description} className={styles.shortcutRow}>
          <span className={styles.description}>{s.description}</span>
          <span className={styles.keys}>
            {(isNative ? s.nativeKeys : s.safeKeys).map((k, i) => (
              <span key={i} className={styles.key}>{k}</span>
            ))}
          </span>
        </div>
      ))}
    </div>
  );
}

export const KeyboardShortcutsOverlay: React.FC<KeyboardShortcutsOverlayProps> = ({
  onDismiss,
}) => {
  const shortcutMode = useSettingsStore((s) => s.shortcutMode);
  const isNative = shortcutMode === "native";

  // Dismiss on any key press or click outside
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      e.preventDefault();
      onDismiss();
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [onDismiss]);

  return (
    <div className={styles.backdrop} onClick={onDismiss}>
      <DSGlassPanel
        className={styles.overlay}
        padding="lg"
      >
        <div onClick={(e) => e.stopPropagation()}>
          {/* Header */}
          <div className={styles.header}>
            <span className={styles.title}>Keyboard Shortcuts</span>
            <span className={clsx(styles.modeBadge, isNative ? styles.modeNative : styles.modeSafe)}>
              {isNative ? "Standard" : "Safe"} Mode
            </span>
          </div>

          {/* Two-column grid */}
          <div className={styles.grid}>
            <div>
              <ShortcutSection title="Capture" shortcuts={CAPTURE_SHORTCUTS} isNative={isNative} />
              <ShortcutSection title="Recording" shortcuts={RECORDING_SHORTCUTS} isNative={isNative} />
            </div>
            <div>
              <ShortcutSection title="App" shortcuts={APP_SHORTCUTS} isNative={isNative} />
            </div>
          </div>

          <div className={styles.hint}>
            Press any key or click outside to dismiss
          </div>
        </div>
      </DSGlassPanel>
    </div>
  );
};
