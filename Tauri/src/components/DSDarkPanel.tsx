import React from "react";
import clsx from "clsx";
import styles from "./DSDarkPanel.module.css";

interface DSDarkPanelProps {
  children: React.ReactNode;
  className?: string;
  padding?: "none" | "sm" | "md" | "lg";
}

export const DSDarkPanel: React.FC<DSDarkPanelProps> = ({
  children,
  className,
  padding = "md",
}) => (
  <div className={clsx(styles.panel, styles[`pad-${padding}`], className)}>
    {children}
  </div>
);
