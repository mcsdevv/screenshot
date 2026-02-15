import React, { useState } from "react";
import clsx from "clsx";
import { DSGlassPanel, DSTrafficLightButtons } from "@/components";
import { GeneralTab } from "./GeneralTab";
import { ShortcutsTab } from "./ShortcutsTab";
import { CaptureTab } from "./CaptureTab";
import { RecordingTab } from "./RecordingTab";
import { StorageTab } from "./StorageTab";
import { AdvancedTab } from "./AdvancedTab";
import styles from "./Settings.module.css";

type TabId = "general" | "shortcuts" | "capture" | "recording" | "storage" | "advanced";

interface Tab {
  id: TabId;
  label: string;
  icon: string;
}

const TABS: Tab[] = [
  { id: "general", label: "General", icon: "\u2699\uFE0F" },
  { id: "shortcuts", label: "Shortcuts", icon: "\u2318" },
  { id: "capture", label: "Capture", icon: "\uD83D\uDCF7" },
  { id: "recording", label: "Recording", icon: "\uD83C\uDFA5" },
  { id: "storage", label: "Storage", icon: "\uD83D\uDCC1" },
  { id: "advanced", label: "Advanced", icon: "\uD83D\uDD27" },
];

const TAB_COMPONENTS: Record<TabId, React.FC> = {
  general: GeneralTab,
  shortcuts: ShortcutsTab,
  capture: CaptureTab,
  recording: RecordingTab,
  storage: StorageTab,
  advanced: AdvancedTab,
};

export const SettingsView: React.FC = () => {
  const [activeTab, setActiveTab] = useState<TabId>("general");
  const ActiveComponent = TAB_COMPONENTS[activeTab];

  return (
    <DSGlassPanel padding="none" className={styles.container}>
      <div className={styles.sidebar}>
        <div className={styles.trafficLights}>
          <DSTrafficLightButtons onClose={() => window.close()} />
        </div>
        <nav className={styles.tabList}>
          {TABS.map((tab) => (
            <button
              key={tab.id}
              className={clsx(styles.tabItem, activeTab === tab.id && styles.tabItemActive)}
              onClick={() => setActiveTab(tab.id)}
            >
              <span className={styles.tabIcon}>{tab.icon}</span>
              {tab.label}
            </button>
          ))}
        </nav>
      </div>
      <main className={styles.content}>
        <ActiveComponent />
      </main>
    </DSGlassPanel>
  );
};
