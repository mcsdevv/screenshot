import React from "react";
import clsx from "clsx";
import { DSDivider, DSSecondaryButton } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import { CLEANUP_DAY_OPTIONS } from "@/lib/constants";
import styles from "./Settings.module.css";

const STORAGE_OPTIONS = [
  { value: "default" as const, label: "Default (App Support)" },
  { value: "desktop" as const, label: "Desktop" },
  { value: "custom" as const, label: "Custom Folder" },
];

export const StorageTab: React.FC = () => {
  const { storageLocation, autoCleanup, cleanupDays, setSetting } = useSettingsStore();

  const handleBrowse = () => {
    // TODO: invoke Tauri file dialog
    console.log("Browse for custom folder");
  };

  const handleReveal = () => {
    // TODO: invoke Tauri shell.open for screenshots directory
    console.log("Reveal in Finder");
  };

  const handleClearAll = () => {
    if (window.confirm("This will permanently delete all screenshots and recordings. This action cannot be undone.")) {
      // TODO: invoke Tauri command to clear captures
      console.log("Clear all captures");
    }
  };

  return (
    <>
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>Storage Location</h3>

        <div className={styles.row}>
          <span className={styles.label}>Save screenshots to</span>
          <select
            className={styles.select}
            value={storageLocation}
            onChange={(e) =>
              setSetting("storageLocation", e.target.value as "default" | "desktop" | "custom")
            }
          >
            {STORAGE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>

        {storageLocation === "custom" && (
          <div className={styles.row}>
            <span className={styles.label}>Custom folder</span>
            <DSSecondaryButton onClick={handleBrowse}>Choose Folder...</DSSecondaryButton>
          </div>
        )}

        <div className={styles.row}>
          <span className={styles.label}>Current location</span>
          <span className={styles.pathText}>~/Library/Application Support/ScreenCapture</span>
        </div>

        <div className={styles.row}>
          <DSSecondaryButton onClick={handleReveal}>Reveal in Finder</DSSecondaryButton>
        </div>
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>Storage Management</h3>

        <div className={styles.row}>
          <span className={styles.label}>Storage used</span>
          <span className={styles.description} style={{ marginTop: 0 }}>Calculating...</span>
        </div>

        <div className={styles.row}>
          <span className={styles.label}>Auto-delete old captures</span>
          <button
            className={clsx(styles.toggle, autoCleanup && styles.toggleOn)}
            onClick={() => setSetting("autoCleanup", !autoCleanup)}
          />
        </div>

        {autoCleanup && (
          <div className={styles.row}>
            <span className={styles.label}>Delete after</span>
            <select
              className={styles.select}
              value={cleanupDays}
              onChange={(e) => setSetting("cleanupDays", Number(e.target.value))}
            >
              {CLEANUP_DAY_OPTIONS.map((days) => (
                <option key={days} value={days}>
                  {days} days
                </option>
              ))}
            </select>
          </div>
        )}

        <div className={styles.dangerZone}>
          <DSSecondaryButton danger onClick={handleClearAll}>
            Clear All Captures...
          </DSSecondaryButton>
        </div>
      </section>
    </>
  );
};
