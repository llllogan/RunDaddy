/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{html,ts}'],
  theme: {
    extend: {
      colors: {
        'rd-background': '#05070d',
        'rd-surface': 'rgba(12, 16, 28, 0.92)',
        'rd-card': 'rgba(15, 20, 34, 0.9)',
        'rd-accent': '#5f6cfb',
        'rd-accent-strong': '#8b5bff',
        'rd-teal': '#78f5d0',
        'rd-muted': '#8a92a9',
        'rd-secondary': '#c0c6d9',
        'rd-primary': '#f2f6ff',
      },
      boxShadow: {
        'rd-card': '0 30px 60px -40px rgba(0, 0, 0, 0.6)',
      },
      fontFamily: {
        sans: [
          '"Inter"',
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Roboto',
          'Helvetica',
          'Arial',
          'sans-serif',
        ],
      },
    },
  },
  plugins: [],
}
