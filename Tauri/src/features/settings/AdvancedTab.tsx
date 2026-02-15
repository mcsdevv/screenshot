import React from "react";
import { DSDivider, DSSecondaryButton } from "@/components";
import styles from "./Settings.module.css";

export const AdvancedTab: React.FC = () => {
  const handleResetAll = () => {
    if (window.confirm("This will reset all settings to their default values. Continue?")) {
      // TODO: invoke Tauri command to reset settings
      console.log("Reset all preferences");
    }
  };

  const handleOpenLog = () => {
    // TODO: invoke Tauri shell.open for log file
    console.log("Open debug log");
  };

  const handleRevealLogs = () => {
    // TODO: invoke Tauri shell.open for log directory
    console.log("Reveal log directory");
  };

  return (
    <>
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>Diagnostics</h3>

        <div className={styles.row}>
          <span className={styles.label}>Debug log</span>
          <div className={styles.pathRow}>
            <span className={styles.pathText}>~/Library/Logs/ScreenCapture/debug.log</span>
            <DSSecondaryButton onClick={handleOpenLog}>Open</DSSecondaryButton>
          </div>
        </div>

        <div className={styles.row}>
          <span className={styles.label}>Log directory</span>
          <DSSecondaryButton onClick={handleRevealLogs}>Reveal in Finder</DSSecondaryButton>
        </div>
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>Developer</h3>
        <div className={styles.dangerZone}>
          <DSSecondaryButton danger onClick={handleResetAll}>
            Reset All Preferences...
          </DSSecondaryButton>
        </div>
      </section>

      <DSDivider />

      <section className={styles.section} style={{ marginTop: "var(--ds-spacing-xl)" }}>
        <h3 className={styles.sectionTitle}>About</h3>

        <div className={styles.row}>
          <span className={styles.label}>App</span>
          <span className={styles.label}>ScreenCapture</span>
        </div>

        <div className={styles.row}>
          <span className={styles.label}>Version</span>
          <span className={styles.description} style={{ marginTop: 0 }}>1.0.0 (Build 1)</span>
        </div>
      </section>
    </>
  );
};
