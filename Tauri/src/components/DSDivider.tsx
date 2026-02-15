import React from "react";
import styles from "./DSDivider.module.css";
import clsx from "clsx";

interface DSDividerProps {
  orientation?: "horizontal" | "vertical";
  className?: string;
}

export const DSDivider: React.FC<DSDividerProps> = ({
  orientation = "horizontal",
  className,
}) => (
  <div className={clsx(styles.divider, styles[orientation], className)} />
);
