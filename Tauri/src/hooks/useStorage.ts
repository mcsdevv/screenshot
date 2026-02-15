/**
 * Bridge to Rust storage commands
 */
import { useCallback } from "react";
import * as ipc from "@/lib/ipc";
import { useHistoryStore } from "@/stores/historyStore";

export function useStorage() {
  const { setItems, setLoading } = useHistoryStore();

  const loadHistory = useCallback(async () => {
    setLoading(true);
    try {
      const history = await ipc.getHistory();
      setItems(history.items);
    } catch (err) {
      console.error("Failed to load history:", err);
    } finally {
      setLoading(false);
    }
  }, [setItems, setLoading]);

  const deleteCaptureItem = useCallback(async (id: string) => {
    await ipc.deleteCapture(id);
    useHistoryStore.getState().removeItem(id);
  }, []);

  const toggleFavoriteItem = useCallback(async (id: string) => {
    await ipc.toggleFavorite(id);
    useHistoryStore.getState().toggleFavorite(id);
  }, []);

  return { loadHistory, deleteCaptureItem, toggleFavoriteItem };
}
