import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    // Safari Web Extensions on iOS have known issues with ES modules (type="module")
    // Output IIFE format so scripts load via <script src=""> instead of type="module"
    target: 'es2020', // Safari 14+ compatible
    modulePreload: false, // Avoid modulepreload (Safari extension context issues)
    rollupOptions: {
      input: {
        popup: resolve(__dirname, 'popup.html'),
        dashboard: resolve(__dirname, 'dashboard.html'),
      },
      output: {
        format: 'iife',
        // Inline all dependencies into each entry - no shared chunks with import statements
        inlineDynamicImports: false,
        manualChunks: undefined,
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },
})