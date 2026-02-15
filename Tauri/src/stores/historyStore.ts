import { create } from "zustand";
import type { CaptureItem } from "@/lib/ipc";

interface HistoryState {
  items: CaptureItem[];
  isLoading: boolean;
  searchQuery: string;
  filterType: "all" | "screenshot" | "recording" | "gif";
  sortBy: "newest" | "oldest" | "name";
  viewMode: "grid" | "list";

  setItems: (items: CaptureItem[]) => void;
  addItem: (item: CaptureItem) => void;
  removeItem: (id: string) => void;
  toggleFavorite: (id: string) => void;
  setSearchQuery: (q: string) => void;
  setFilterType: (t: HistoryState["filterType"]) => void;
  setSortBy: (s: HistoryState["sortBy"]) => void;
  setViewMode: (m: HistoryState["viewMode"]) => void;
  setLoading: (v: boolean) => void;
}

export const useHistoryStore = create<HistoryState>((set) => ({
  items: [],
  isLoading: false,
  searchQuery: "",
  filterType: "all",
  sortBy: "newest",
  viewMode: "grid",

  setItems: (items) => set({ items }),
  addItem: (item) => set((s) => ({ items: [item, ...s.items] })),
  removeItem: (id) => set((s) => ({ items: s.items.filter((i) => i.id !== id) })),
  toggleFavorite: (id) =>
    set((s) => ({
      items: s.items.map((i) => (i.id === id ? { ...i, is_favorite: !i.is_favorite } : i)),
    })),
  setSearchQuery: (q) => set({ searchQuery: q }),
  setFilterType: (t) => set({ filterType: t }),
  setSortBy: (s) => set({ sortBy: s }),
  setViewMode: (m) => set({ viewMode: m }),
  setLoading: (v) => set({ isLoading: v }),
}));
