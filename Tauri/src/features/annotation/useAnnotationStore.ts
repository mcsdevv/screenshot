/**
 * Annotation editor state — Zustand store with Immer
 * Mirrors ScreenCapture/Models/AnnotationTypes.swift AnnotationState
 */
import { create } from "zustand";
import { immer } from "zustand/middleware/immer";
import type { Annotation, AnnotationTool, Point, Rect } from "./types";

const MAX_UNDO = 50;

interface AnnotationState {
  // Data
  annotations: Annotation[];
  selectedAnnotationId: string | null;
  currentTool: AnnotationTool;
  currentColor: string;
  currentStrokeWidth: number;
  currentFontSize: number;
  currentFontName: string;
  stepCounter: number;
  blurRadius: number;

  // Crop
  cropRect: Rect | null;

  // Layer panel
  isLayerPanelVisible: boolean;
  hiddenAnnotationIds: Set<string>;
  clipboard: Annotation | null;

  // Undo/redo
  _undoStack: Annotation[][];
  _redoStack: Annotation[][];

  // View
  zoom: number;
  offset: Point;

  // Computed
  canUndo: boolean;
  canRedo: boolean;

  // Actions
  _saveUndo: () => void;
  addAnnotation: (a: Annotation) => void;
  updateAnnotation: (a: Annotation) => void;
  deleteAnnotation: (id: string) => void;
  selectAnnotation: (id: string | null) => void;
  undo: () => void;
  redo: () => void;
  setTool: (t: AnnotationTool) => void;
  setColor: (c: string) => void;
  setStrokeWidth: (w: number) => void;
  setFontSize: (s: number) => void;
  setFontName: (n: string) => void;
  setBlurRadius: (r: number) => void;
  setCropRect: (r: Rect | null) => void;
  confirmCrop: () => void;
  setZoom: (z: number) => void;
  setOffset: (o: Point) => void;
  toggleLayerPanel: () => void;
  toggleVisibility: (id: string) => void;
  bringToFront: (id: string) => void;
  sendToBack: (id: string) => void;
  bringForward: (id: string) => void;
  sendBackward: (id: string) => void;
  moveAnnotation: (fromIndex: number, toIndex: number) => void;
  duplicateAnnotation: (id: string) => void;
  copyAnnotation: (id: string) => void;
  pasteAnnotation: () => void;
  nudge: (dx: number, dy: number) => void;
  renumberSteps: () => void;
}

export const useAnnotationStore = create<AnnotationState>()(
  immer((set, get) => ({
    annotations: [],
    selectedAnnotationId: null,
    currentTool: "select",
    currentColor: "#FF3B30",
    currentStrokeWidth: 3,
    currentFontSize: 16,
    currentFontName: "system-ui",
    stepCounter: 0,
    blurRadius: 10,
    cropRect: null,
    isLayerPanelVisible: false,
    hiddenAnnotationIds: new Set(),
    clipboard: null,
    _undoStack: [],
    _redoStack: [],
    zoom: 1,
    offset: { x: 0, y: 0 },
    canUndo: false,
    canRedo: false,

    _saveUndo: () =>
      set((s) => {
        s._undoStack.push(structuredClone(s.annotations));
        if (s._undoStack.length > MAX_UNDO) s._undoStack.shift();
        s.canUndo = true;
      }),

    addAnnotation: (a) =>
      set((s) => {
        s._undoStack.push(structuredClone(s.annotations));
        if (s._undoStack.length > MAX_UNDO) s._undoStack.shift();
        s._redoStack = [];
        s.annotations.push(a);
        s.selectedAnnotationId = a.id;
        s.canUndo = true;
        s.canRedo = false;
      }),

    updateAnnotation: (a) =>
      set((s) => {
        const idx = s.annotations.findIndex((x) => x.id === a.id);
        if (idx !== -1) s.annotations[idx] = a;
      }),

    deleteAnnotation: (id) =>
      set((s) => {
        s._undoStack.push(structuredClone(s.annotations));
        if (s._undoStack.length > MAX_UNDO) s._undoStack.shift();
        s._redoStack = [];
        s.annotations = s.annotations.filter((x) => x.id !== id);
        if (s.selectedAnnotationId === id) s.selectedAnnotationId = null;
        s.canUndo = true;
        s.canRedo = false;
      }),

    selectAnnotation: (id) => set({ selectedAnnotationId: id }),

    undo: () =>
      set((s) => {
        if (s._undoStack.length === 0) return;
        s._redoStack.push(structuredClone(s.annotations));
        s.annotations = s._undoStack.pop()!;
        s.selectedAnnotationId = null;
        s.canUndo = s._undoStack.length > 0;
        s.canRedo = true;
      }),

    redo: () =>
      set((s) => {
        if (s._redoStack.length === 0) return;
        s._undoStack.push(structuredClone(s.annotations));
        s.annotations = s._redoStack.pop()!;
        s.selectedAnnotationId = null;
        s.canUndo = true;
        s.canRedo = s._redoStack.length > 0;
      }),

    setTool: (t) => set({ currentTool: t, selectedAnnotationId: null }),
    setColor: (c) => set({ currentColor: c }),
    setStrokeWidth: (w) => set({ currentStrokeWidth: w }),
    setFontSize: (s) => set({ currentFontSize: s }),
    setFontName: (n) => set({ currentFontName: n }),
    setBlurRadius: (r) => set({ blurRadius: r }),
    setCropRect: (r) => set({ cropRect: r }),
    confirmCrop: () => set((s) => { s.cropRect = null; }),
    setZoom: (z) => set({ zoom: Math.max(0.25, Math.min(4, z)) }),
    setOffset: (o) => set({ offset: o }),
    toggleLayerPanel: () => set((s) => ({ isLayerPanelVisible: !s.isLayerPanelVisible })),

    toggleVisibility: (id) =>
      set((s) => {
        const set_ = new Set(s.hiddenAnnotationIds);
        if (set_.has(id)) set_.delete(id);
        else set_.add(id);
        s.hiddenAnnotationIds = set_;
      }),

    bringToFront: (id) =>
      set((s) => {
        const idx = s.annotations.findIndex((x) => x.id === id);
        if (idx === -1 || idx === s.annotations.length - 1) return;
        s._saveUndo();
        const [item] = s.annotations.splice(idx, 1);
        s.annotations.push(item);
      }),

    sendToBack: (id) =>
      set((s) => {
        const idx = s.annotations.findIndex((x) => x.id === id);
        if (idx <= 0) return;
        get()._saveUndo();
        const [item] = s.annotations.splice(idx, 1);
        s.annotations.unshift(item);
      }),

    bringForward: (id) =>
      set((s) => {
        const idx = s.annotations.findIndex((x) => x.id === id);
        if (idx === -1 || idx === s.annotations.length - 1) return;
        get()._saveUndo();
        [s.annotations[idx], s.annotations[idx + 1]] = [s.annotations[idx + 1], s.annotations[idx]];
      }),

    sendBackward: (id) =>
      set((s) => {
        const idx = s.annotations.findIndex((x) => x.id === id);
        if (idx <= 0) return;
        get()._saveUndo();
        [s.annotations[idx], s.annotations[idx - 1]] = [s.annotations[idx - 1], s.annotations[idx]];
      }),

    moveAnnotation: (fromIndex, toIndex) =>
      set((s) => {
        if (fromIndex === toIndex) return;
        get()._saveUndo();
        const [item] = s.annotations.splice(fromIndex, 1);
        s.annotations.splice(toIndex, 0, item);
      }),

    duplicateAnnotation: (id) =>
      set((s) => {
        const src = s.annotations.find((x) => x.id === id);
        if (!src) return;
        const dup = {
          ...structuredClone(src),
          id: crypto.randomUUID(),
          rect: { ...src.rect, x: src.rect.x + 20, y: src.rect.y + 20 },
        };
        get()._saveUndo();
        s.annotations.push(dup);
        s.selectedAnnotationId = dup.id;
      }),

    copyAnnotation: (id) =>
      set((s) => {
        const src = s.annotations.find((x) => x.id === id);
        if (src) s.clipboard = structuredClone(src);
      }),

    pasteAnnotation: () =>
      set((s) => {
        if (!s.clipboard) return;
        const pasted = {
          ...structuredClone(s.clipboard),
          id: crypto.randomUUID(),
          rect: { ...s.clipboard.rect, x: s.clipboard.rect.x + 20, y: s.clipboard.rect.y + 20 },
        };
        get()._saveUndo();
        s.annotations.push(pasted);
        s.selectedAnnotationId = pasted.id;
        s.clipboard = pasted;
      }),

    nudge: (dx, dy) =>
      set((s) => {
        const sel = s.annotations.find((x) => x.id === s.selectedAnnotationId);
        if (!sel) return;
        get()._saveUndo();
        sel.rect.x += dx;
        sel.rect.y += dy;
      }),

    renumberSteps: () =>
      set((s) => {
        let n = 1;
        for (const a of s.annotations) {
          if (a.type === "numberedStep" && !a.isNumberLocked) {
            a.stepNumber = n++;
          }
        }
      }),
  }))
);
