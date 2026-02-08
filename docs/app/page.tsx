import Link from 'next/link';

const features = [
  {
    title: 'Screenshot Capture',
    description: 'Area, window, and fullscreen capture modes',
    href: '/docs/capture',
    icon: '📸',
  },
  {
    title: 'Screen Recording',
    description: 'Record video and GIFs with configurable quality',
    href: '/docs/recording',
    icon: '🎬',
  },
  {
    title: 'Annotation Editor',
    description: '14 tools including shapes, text, blur, and numbered steps',
    href: '/docs/annotation',
    icon: '✏️',
  },
  {
    title: 'OCR Text Extraction',
    description: 'Extract text from screenshots in 10+ languages',
    href: '/docs/features/ocr',
    icon: '📝',
  },
  {
    title: 'Pinned Screenshots',
    description: 'Floating always-on-top windows for reference',
    href: '/docs/features/pinned',
    icon: '📌',
  },
  {
    title: 'Keyboard Shortcuts',
    description: 'Comprehensive shortcuts for power users',
    href: '/docs/shortcuts',
    icon: '⌨️',
  },
];

export default function HomePage() {
  return (
    <main className="min-h-screen" style={{ backgroundColor: '#121217' }}>
      {/* Hero Section */}
      <div className="relative overflow-hidden">
        {/* Gradient background */}
        <div
          className="absolute inset-0 opacity-30"
          style={{
            background:
              'radial-gradient(ellipse at top, rgba(51, 200, 250, 0.15) 0%, transparent 50%)',
          }}
        />

        <div className="relative max-w-6xl mx-auto px-6 py-24 text-center">
          <h1 className="text-5xl md:text-6xl font-bold mb-6">
            <span style={{ color: '#33C8FA' }}>ScreenCapture</span>
            <br />
            <span style={{ color: 'rgba(255, 255, 255, 0.95)' }}>
              Documentation
            </span>
          </h1>
          <p
            className="text-xl md:text-2xl max-w-2xl mx-auto mb-10"
            style={{ color: 'rgba(255, 255, 255, 0.6)' }}
          >
            A comprehensive macOS screenshot and screen recording application
            with annotation tools, capture history, and system-level
            integration.
          </p>
          <div className="flex gap-4 justify-center">
            <Link
              href="/docs"
              className="px-6 py-3 rounded-lg font-semibold transition-all"
              style={{
                backgroundColor: '#33C8FA',
                color: '#121217',
              }}
            >
              Get Started
            </Link>
            <Link
              href="/docs/shortcuts"
              className="px-6 py-3 rounded-lg font-semibold transition-all"
              style={{
                backgroundColor: 'rgba(255, 255, 255, 0.08)',
                color: 'rgba(255, 255, 255, 0.95)',
                border: '1px solid rgba(255, 255, 255, 0.15)',
              }}
            >
              View Shortcuts
            </Link>
          </div>
        </div>
      </div>

      {/* Features Grid */}
      <div className="max-w-6xl mx-auto px-6 py-16">
        <h2
          className="text-2xl font-semibold mb-8 text-center"
          style={{ color: 'rgba(255, 255, 255, 0.95)' }}
        >
          Features
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((feature) => (
            <Link
              key={feature.title}
              href={feature.href}
              className="p-6 rounded-xl transition-all hover:scale-[1.02]"
              style={{
                backgroundColor: '#191921',
                border: '1px solid rgba(255, 255, 255, 0.08)',
              }}
            >
              <div className="text-3xl mb-3">{feature.icon}</div>
              <h3
                className="text-lg font-semibold mb-2"
                style={{ color: 'rgba(255, 255, 255, 0.95)' }}
              >
                {feature.title}
              </h3>
              <p style={{ color: 'rgba(255, 255, 255, 0.6)' }}>
                {feature.description}
              </p>
            </Link>
          ))}
        </div>
      </div>

      {/* Platform Badge */}
      <div className="max-w-6xl mx-auto px-6 py-8 text-center">
        <div
          className="inline-flex items-center gap-2 px-4 py-2 rounded-full"
          style={{
            backgroundColor: 'rgba(255, 255, 255, 0.05)',
            border: '1px solid rgba(255, 255, 255, 0.08)',
          }}
        >
          <span style={{ color: 'rgba(255, 255, 255, 0.6)' }}>
            Built for macOS 14.0+ with SwiftUI & ScreenCaptureKit
          </span>
        </div>
      </div>
    </main>
  );
}
