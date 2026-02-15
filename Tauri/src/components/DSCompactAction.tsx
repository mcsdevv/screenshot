import React from "react";
import clsx from "clsx";
import styles from "./DSCompactAction.module.css";

interface DSCompactActionProps {
  icon: React.ReactNode;
  label: string;
  onClick?: () => void;
  shortcut?: string;
  className?: string;
}

export const DSCompactAction: React.FC<DSCompactActionProps> = ({
  icon,
  label,
  onClick,
  shortcut,
  className,
}) => (
  <button type="button" className={clsx(styles.action, className)} onClick={onClick}>
    <span className={styles.icon}>{icon}</span>
    <span className={styles.label}>{label}</span>
    {shortcut && <span className={styles.shortcut}>{shortcut}</span>}
  </button>
);
