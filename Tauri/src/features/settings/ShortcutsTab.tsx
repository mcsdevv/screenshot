import React from "react";
import clsx from "clsx";
import { DSChip, DSDivider, DSSecondaryButton } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import styles from "./Settings.module.css";

interface ShortcutDef {
  name: string;
  safeBinding: string;
  nativeBinding: string;
}

const SCREENSHOT_SHORTCUTS: ShortcutDef[] = [
  { name: "Capture Area", safeBinding: "\u2303\u21E7 3", nativeBinding: "\u2318\u21E7 3" },
  { name: "Capture Window", safeBinding: "\u2303\u21E7 4", nativeBinding: "\u2318\u21E7 4" },
  { name: "Capture Fullscreen", safeBinding: "\u2303\u21E7 5", nativeBinding: "\u2318\u21E7 5" },
];

const RECORDING_SHORTCUTS: ShortcutDef[] = [
  { name: "Record Area", safeBinding: "\u2303\u21E7 6", nativeBinding: "\u2318\u21E7 6" },
  { name: "Record Window", safeBinding: "\u2303\u21E7 7", nativeBinding: "\u2318\u21E7 7" },
  { name: "Record Fullscreen", safeBinding: "\u2303\u21E7 8", nativeBinding: "\u2318\u21E7 8" },
];

const TOOL_SHORTCUTS: ShortcutDef[] = [
  { name: "Capture Text (OCR)", safeBinding: "\u2303\u21E7 O", nativeBinding: "\u2318\u21E7 O" },
  { name: "Pin Screenshot", safeBinding: "\u2303\u21E7 P", nativeBinding: "\u2318\u21E7 P" },
  { name: "All-in-One Menu", safeBinding: "\u2303\u21E7 A", nativeBinding: "\u2318\u21E7 A" },
  { name: "Open Screenshots Folder", safeBinding: "\u2303\u21E7 F", nativeBinding: "\u2318\u21E7 F" },
  { name: "Preferences", safeBinding: "\u2303\u21E7 ,", nativeBinding: "\u2318\u21E7 ," },
];

function ShortcutGroup({ title, shortcuts, isNative }: { title: string; shortcuts: ShortcutDef[]; isNative: boolean }) {
  return (
    <section className={styles.section}>
      <h3 className={styles.sectionTitle}>{title}</h3>
      {shortcuts.map((s) => (
        <div key={s.name} className={styles.shortcutRow}>
          <span className={styles.shortcutName}>{s.name}</span>
          <span className={styles.shortcutBinding}>
            {isNative ? s.nativeBinding : s.safeBinding}
          </span>
        </div>
      ))}
    </section>
  );
}

export const ShortcutsTab: React.FC = () => {
  const { shortcutMode, setSetting } = useSettingsStore();
  const isNative = shortcutMode === "native";

  return (
    <>
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>Shortcut Mode</h3>
        <div className={styles.row}>
          <div>
            <span className={styles.label}>Current mode</span>
            <p className={styles.description}>
              {isNative
                ? "Using standard macOS shortcuts (\u2318\u21E7)"
                : "Using safe shortcuts (\u2303\u21E7) to avoid conflicts"}
            </p>
          </div>
          <span className={clsx(styles.modeBadge, isNative ? styles.modeNative : styles.modeSafe)}>
            {isNative ? "Standard" : "Safe"}
          </span>
        </div>

        {isNative && (
          <p className={styles.description} style={{ paddingBottom: "var(--ds-spacing-sm)" }}>
            Disable built-in Screenshot shortcuts in System Settings &rarr; Keyboard &rarr; Keyboard Shortcuts &rarr; Screenshots.
          </p>
        )}

        <DSSecondaryButton onClick={() => setSetting("shortcutMode", isNative ? "safe" : "native")}>
          {isNative ? "Switch to Safe Shortcuts" : "Switch to Standard Shortcuts"}
        </DSSecondaryButton>
      </section>

      <DSDivider />

      <ShortcutGroup title="Screenshot Shortcuts" shortcuts={SCREENSHOT_SHORTCUTS} isNative={isNative} />
      <ShortcutGroup title="Recording Shortcuts" shortcuts={RECORDING_SHORTCUTS} isNative={isNative} />
      <ShortcutGroup title="Tool Shortcuts" shortcuts={TOOL_SHORTCUTS} isNative={isNative} />
    </>
  );
};
