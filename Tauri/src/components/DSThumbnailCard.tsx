import React from "react";
import clsx from "clsx";
import styles from "./DSThumbnailCard.module.css";

interface DSThumbnailCardProps {
  src: string;
  title: string;
  subtitle?: string;
  onClick?: () => void;
  isFavorite?: boolean;
  onFavoriteToggle?: () => void;
  className?: string;
}

export const DSThumbnailCard: React.FC<DSThumbnailCardProps> = ({
  src,
  title,
  subtitle,
  onClick,
  isFavorite,
  onFavoriteToggle,
  className,
}) => (
  <div className={clsx(styles.card, className)} onClick={onClick}>
    <div className={styles.imageWrapper}>
      <img src={src} alt={title} className={styles.image} />
      <div className={styles.overlay}>
        {onFavoriteToggle && (
          <button
            className={clsx(styles.favoriteBtn, isFavorite && styles.favorited)}
            onClick={(e) => {
              e.stopPropagation();
              onFavoriteToggle();
            }}
          >
            {isFavorite ? "★" : "☆"}
          </button>
        )}
      </div>
    </div>
    <div className={styles.info}>
      <span className={styles.title}>{title}</span>
      {subtitle && <span className={styles.subtitle}>{subtitle}</span>}
    </div>
  </div>
);
