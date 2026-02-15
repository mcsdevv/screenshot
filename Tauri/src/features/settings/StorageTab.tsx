import React, { useEffect, useState } from "react";
import clsx from "clsx";
import { DSDivider, DSSecondaryButton } from "@/components";
import { useSettingsStore } from "@/stores/settingsStore";
import { CLEANUP_DAY_OPTIONS } from "@/lib/constants";
import { open as dialogOpen } from "@tauri-apps/plugin-dialog";
import { open as shellOpen } from "@tauri-apps/plugin-shell";
import * as ipc from "@/lib/ipc";
import styles from "./Settings.module.css";

const STORAGE_OPTIONS = [
  { value: "default" as const, label: "Default (App Support)" },
  { value: "desktop" as const, label: "Desktop" },
  { value: "custom" as const, label: "Custom Folder" },
];

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${units[i]}`;
}

export const StorageTab: React.FC = () => {
  const { storageLocation, autoCleanup, cleanupDays, setSetting } = useSettingsStore();
  const [storageInfo, setStorageInfo] = useState<ipc.StorageInfo | null>(null);

  useEffect(() => {
    ipc.getStorageInfo().then(setStorageInfo).catch(() => {});
  }, []);

  const handleLocationChange = async (value: "default" | "desktop" | "custom") => {
    setSetting("storageLocation", value);
    if (value !== "custom") {
      try {
        await ipc.setStorageLocation(value);
        const info = await ipc.getStorageInfo();
        setStorageInfo(info);
      } catch { /* noop */ }
    }
  };

  const handleBrowse = async () => {
    const selected = await dialogOpen({ directory: true, title: "Choose Screenshots Folder" });
    if (selected) {
      try {
        await ipc.setStorageLocation({ custom: { path: selected as string } });
        const info = await ipc.getStorageInfo();
        setStorageInfo(info);
      } catch { /* noop */ }
    }
  };

  const handleReveal = async () => {
    if (storageInfo?.path) {
      await shellOpen(`file://${storageInfo.path}`).catch(() => {});
    }
  };

  const handleClearAll = async () => {
    if (window.confirm("This will permanently delete all screenshots and recordings. This action cannot be undone.")) {
      try {
        const history = await ipc.getHistory();
        for (const item of history.items) {
          await ipc.deleteCapture(item.id);
        }
        const info = await ipc.getStorageInfo();
        setStorageInfo(info);
      } catch { /* noop */ }
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
            onChange={(e) => handleLocationChange(e.target.value as "default" | "desktop" | "custom")}
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
          <span className={styles.pathText}>{storageInfo?.path ?? "Loading..."}</span>
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
          <span className={styles.description} style={{ marginTop: 0 }}>
            {storageInfo
              ? `${storageInfo.total_items} items, ${formatBytes(storageInfo.total_size_bytes)}`
              : "Calculating..."}
          </span>
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
