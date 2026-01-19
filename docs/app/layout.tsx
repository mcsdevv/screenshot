import './globals.css';
import { RootProvider } from 'fumadocs-ui/provider/next';
import type { ReactNode } from 'react';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: {
    default: 'ScreenCapture Documentation',
    template: '%s | ScreenCapture',
  },
  description:
    'Documentation for ScreenCapture - A comprehensive macOS screenshot and screen recording application.',
  icons: {
    icon: '/favicon.ico',
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark" suppressHydrationWarning>
      <body
        className="flex flex-col min-h-screen"
        style={{ backgroundColor: '#121217' }}
      >
        <RootProvider
          theme={{
            enabled: false,
            defaultTheme: 'dark',
          }}
        >
          {children}
        </RootProvider>
      </body>
    </html>
  );
}
