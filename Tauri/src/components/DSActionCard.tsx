import React from "react";
import clsx from "clsx";
import styles from "./DSActionCard.module.css";

interface DSActionCardProps {
  icon: React.ReactNode;
  title: string;
  subtitle?: string;
  onClick?: () => void;
  className?: string;
}

export const DSActionCard: React.FC<DSActionCardProps> = ({
  icon,
  title,
  subtitle,
  onClick,
  className,
}) => (
  <button type="button" className={clsx(styles.card, className)} onClick={onClick}>
    <div className={styles.iconCircle}>{icon}</div>
    <span className={styles.title}>{title}</span>
    {subtitle && <span className={styles.subtitle}>{subtitle}</span>}
  </button>
);
