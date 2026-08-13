{
  "name": "{{ACTIVITY_ID}}",
  "description": "{{ACTIVITY_NAME}} — FreeDeepAgents Static Preview frontend.",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "engines": {
    "node": ">=20 <23",
    "npm": ">=10 <11"
  },
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "lint": "tsc --noEmit"
  },
  "dependencies": {
    "@tailwindcss/vite": "^4.1.14",
    "@vitejs/plugin-react": "^5.0.4",
    "react": "^19.0.1",
    "react-dom": "^19.0.1",
    "vite": "^6.2.3"
  },
  "devDependencies": {
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "tailwindcss": "^4.1.14",
    "typescript": "~5.8.2"
  }
}
