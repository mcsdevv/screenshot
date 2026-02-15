import React from "react";
import clsx from "clsx";
import { DSDivider } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import type { AfterCaptureAction, ScreenCorner } from "@/lib/constants";
import styles from "./Settings.module.css";

const AFTER_CAPTURE_OPTIONS: { value: AfterCaptureAction; label: string }[] = [
  { value: "quickAccess", label: "Show Quick Access" },
  { value: "clipboard", label: "Copy to Clipboard" },
  { value: "save", label: "Save to File" },
  { value: "editor", label: "Open in Editor" },
];

const QUICK_ACCESS_DURATIONS = [
  { value: 3, label: "3 seconds" },
  { value: 5, label: "5 seconds" },
  { value: 10, label: "10 seconds" },
  { value: 0, label: "Never" },
];

const POPUP_CORNERS: { value: ScreenCorner; label: string }[] = [
  { value: "topLeft", label: "Top Left" },
  { value: "topRight", label: "Top Right" },
  { value: "bottomLeft", label: "Bottom Left" },
  { value: "bottomRight", label: "Bottom Right" },
];

export const GeneralTab: React.FC = () => {
  const {
    launchAtLogin,
    showMenuBarIcon,
    playSound,
    showQuickAccess,
    quickAccessDuration,
    popupCorner,
    afterCaptureAction,
    setSetting,
  } = useSettingsStore();

  return (
    <>
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>Startup</h3>
        <div className={styles.row}>
          <span className={styles.label}>Launch at login</span>
          <button
            className={clsx(styles.toggle, launchAtLogin && styles.toggleOn)}
            onClick={() => setSetting("launchAtLogin", !launchAtLogin)}
          />
        </div>
        <div className={styles.row}>
          <span className={styles.label}>Show icon in menu bar</span>
          <button
            className={clsx(styles.toggle, showMenuBarIcon && styles.toggleOn)}
            onClick={() => setSetting("showMenuBarIcon", !showMenuBarIcon)}
          />
        </div>
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>Feedback</h3>
        <div className={styles.row}>
          <span className={styles.label}>Play sound after capture</span>
          <button
            className={clsx(styles.toggle, playSound && styles.toggleOn)}
            onClick={() => setSetting("playSound", !playSound)}
          />
        </div>
        <div className={styles.row}>
          <span className={styles.label}>Show Quick Access overlay</span>
          <button
            className={clsx(styles.toggle, showQuickAccess && styles.toggleOn)}
            onClick={() => setSetting("showQuickAccess", !showQuickAccess)}
          />
        </div>

        {showQuickAccess && (
          <>
            <div className={styles.row}>
              <span className={styles.label}>Auto-dismiss after</span>
              <select
                className={styles.select}
                value={quickAccessDuration}
                onChange={(e) => setSetting("quickAccessDuration", Number(e.target.value))}
              >
                {QUICK_ACCESS_DURATIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Popup position</span>
              <select
                className={styles.select}
                value={popupCorner}
                onChange={(e) => setSetting("popupCorner", e.target.value as ScreenCorner)}
              >
                {POPUP_CORNERS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </div>
          </>
        )}
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>Default Actions</h3>
        <div className={styles.row}>
          <span className={styles.label}>After capture</span>
          <select
            className={styles.select}
            value={afterCaptureAction}
            onChange={(e) => setSetting("afterCaptureAction", e.target.value as AfterCaptureAction)}
          >
            {AFTER_CAPTURE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>
      </section>
    </>
  );
};
