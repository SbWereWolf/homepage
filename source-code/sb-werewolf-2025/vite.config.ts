import {defineConfig} from 'vite'
import tailwindcss from '@tailwindcss/vite'
import {glob} from 'glob';

export default defineConfig({
    plugins: [
        tailwindcss(),
    ],
    build: {
        rollupOptions: {
            input: glob.sync('./**/*.html')
        }
    }
})
