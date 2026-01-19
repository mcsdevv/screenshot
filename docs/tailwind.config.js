/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    './components/**/*.{ts,tsx}',
    './app/**/*.{ts,tsx}',
    './content/**/*.{md,mdx}',
    './mdx-components.tsx',
    './node_modules/fumadocs-ui/dist/**/*.js',
  ],
  theme: {
    extend: {
      colors: {
        // Prismatic Dark Theme - Deep Obsidian backgrounds
        background: {
          DEFAULT: '#121217',
          elevated: '#191921',
          secondary: '#212129',
          tertiary: '#292931',
        },
        // Electric Cyan accent
        accent: {
          DEFAULT: '#33C8FA',
          muted: 'rgba(51, 200, 250, 0.7)',
          glow: 'rgba(51, 200, 250, 0.3)',
        },
        // Warm accent
        warm: {
          DEFAULT: '#FF9433',
        },
        // Status colors
        success: '#4DD880',
        danger: '#FF5A66',
      },
      borderColor: {
        subtle: 'rgba(255, 255, 255, 0.08)',
        active: 'rgba(255, 255, 255, 0.15)',
        accent: 'rgba(51, 200, 250, 0.5)',
      },
      boxShadow: {
        glow: '0 0 12px rgba(51, 200, 250, 0.3)',
        'glow-lg': '0 0 24px rgba(51, 200, 250, 0.4)',
      },
    },
  },
  plugins: [],
};
