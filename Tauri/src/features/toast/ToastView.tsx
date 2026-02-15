import React from "react";
import styles from "./Toast.module.css";

interface ToastViewProps {
  icon: string;
  message: string;
  color: string;
}

export const ToastView: React.FC<ToastViewProps> = ({ icon, message, color }) => (
  <div className={styles.toast} style={{ "--toast-color": color } as React.CSSProperties}>
    <span className={styles.icon}>{icon}</span>
    <span className={styles.message}>{message}</span>
  </div>
);
