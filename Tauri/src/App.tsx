import { Routes, Route, useParams, useSearchParams } from "react-router-dom";
import { SettingsView } from "./features/settings/SettingsView";
import { CaptureHistoryView } from "./features/history/CaptureHistoryView";
import { AnnotationEditor } from "./features/annotation/AnnotationEditor";
import { QuickAccessOverlay } from "./features/quick-access/QuickAccessOverlay";
import { SelectionOverlay } from "./features/selection/SelectionOverlay";
import { RecordingSelectionView } from "./features/selection/RecordingSelectionView";
import { RecordingControlsView } from "./features/recording/RecordingControlsView";
import { PinnedScreenshot } from "./features/pinned/PinnedScreenshot";
import { KeyboardShortcutsOverlay } from "./features/shortcuts/KeyboardShortcutsOverlay";
import { AllInOneMenu } from "./features/all-in-one/AllInOneMenu";

const closeWindow = () => {
  window.close();
};

function EditorPage() {
  const { captureId } = useParams<{ captureId: string }>();
  return <AnnotationEditor captureId={captureId} onClose={closeWindow} />;
}

function QuickAccessPage() {
  const [params] = useSearchParams();
  const capture = {
    id: params.get("id") ?? "",
    capture_type: (params.get("type") ?? "screenshot") as "screenshot" | "recording" | "gif",
    filename: params.get("filename") ?? "Screenshot",
    created_at: params.get("created_at") ?? new Date().toISOString(),
    is_favorite: false,
  };
  return (
    <QuickAccessOverlay
      capture={capture}
      thumbnailUrl={params.get("thumbnailUrl") ?? undefined}
      onDismiss={closeWindow}
    />
  );
}

function SelectionPage() {
  const [params] = useSearchParams();
  const displayId = Number(params.get("displayId") ?? 0);
  return <SelectionOverlay displayId={displayId} onCancel={closeWindow} />;
}

function RecordingSelectionPage() {
  const [params] = useSearchParams();
  const displayId = Number(params.get("displayId") ?? 0);
  return (
    <RecordingSelectionView
      displayId={displayId}
      onCancel={closeWindow}
      onStarted={closeWindow}
    />
  );
}

function PinnedPage() {
  const { imageId } = useParams<{ imageId: string }>();
  const [params] = useSearchParams();
  return (
    <PinnedScreenshot
      imageUrl={params.get("imageUrl") ?? `asset://capture/${imageId}`}
      initialWidth={Number(params.get("w") ?? 400)}
      initialHeight={Number(params.get("h") ?? 300)}
      onClose={closeWindow}
    />
  );
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<AllInOneMenu onDismiss={closeWindow} />} />
      <Route path="/settings" element={<SettingsView />} />
      <Route path="/history" element={<CaptureHistoryView />} />
      <Route path="/editor/:captureId" element={<EditorPage />} />
      <Route path="/quick-access" element={<QuickAccessPage />} />
      <Route path="/selection" element={<SelectionPage />} />
      <Route path="/recording-selection" element={<RecordingSelectionPage />} />
      <Route path="/recording-controls" element={<RecordingControlsView />} />
      <Route path="/pinned/:imageId" element={<PinnedPage />} />
      <Route
        path="/shortcuts"
        element={<KeyboardShortcutsOverlay onDismiss={closeWindow} />}
      />
      <Route
        path="/all-in-one"
        element={<AllInOneMenu onDismiss={closeWindow} />}
      />
    </Routes>
  );
}
