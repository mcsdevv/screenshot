import React, { useState, useRef } from "react";
import styles from "./DSTooltip.module.css";
import clsx from "clsx";

interface DSTooltipProps {
  text: string;
  children: React.ReactNode;
  position?: "top" | "bottom" | "left" | "right";
}

export const DSTooltip: React.FC<DSTooltipProps> = ({ text, children, position = "top" }) => {
  const [visible, setVisible] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const show = () => {
    timeoutRef.current = setTimeout(() => setVisible(true), 500);
  };

  const hide = () => {
    clearTimeout(timeoutRef.current);
    setVisible(false);
  };

  return (
    <div className={styles.wrapper} onMouseEnter={show} onMouseLeave={hide}>
      {children}
      {visible && (
        <div className={clsx(styles.tooltip, styles[position])}>
          {text}
        </div>
      )}
    </div>
  );
};
