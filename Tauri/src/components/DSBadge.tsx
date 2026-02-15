import React from "react";
import clsx from "clsx";
import styles from "./DSBadge.module.css";

interface DSBadgeProps {
  label: string;
  variant?: "accent" | "success" | "warning" | "danger" | "neutral";
}

export const DSBadge: React.FC<DSBadgeProps> = ({ label, variant = "neutral" }) => (
  <span className={clsx(styles.badge, styles[variant])}>
    {label}
  </span>
);
