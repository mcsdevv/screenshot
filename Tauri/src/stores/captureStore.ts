import { create } from "zustand";

interface CaptureState {
  isCapturing: boolean;
  isRecording: boolean;
  recordingElapsed: number;
  recordingState: "idle" | "selecting" | "starting" | "recording" | "stopping";

  setCapturing: (v: boolean) => void;
  setRecording: (v: boolean) => void;
  setRecordingElapsed: (v: number) => void;
  setRecordingState: (v: CaptureState["recordingState"]) => void;
}

export const useCaptureStore = create<CaptureState>((set) => ({
  isCapturing: false,
  isRecording: false,
  recordingElapsed: 0,
  recordingState: "idle",

  setCapturing: (v) => set({ isCapturing: v }),
  setRecording: (v) => set({ isRecording: v }),
  setRecordingElapsed: (v) => set({ recordingElapsed: v }),
  setRecordingState: (v) => set({ recordingState: v }),
}));
