import React from "react";
import clsx from "clsx";
import styles from "./DSGlassPanel.module.css";

interface DSGlassPanelProps {
  children: React.ReactNode;
  className?: string;
  padding?: "none" | "sm" | "md" | "lg";
}

export const DSGlassPanel: React.FC<DSGlassPanelProps> = ({
  children,
  className,
  padding = "md",
}) => (
  <div className={clsx(styles.panel, styles[`pad-${padding}`], className)}>
    {children}
  </div>
);
