/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{html,ts}'],
  theme: {
    extend: {
      colors: {
        'rd-background': '#fbf7ef',
        'rd-surface': '#ffffff',
        'rd-card': 'rgba(253, 230, 171, 0.75)',
        'rd-accent': '#f97316',
        'rd-accent-strong': '#ea580c',
        'rd-teal': '#0f766e',
        'rd-muted': '#8b9388',
        'rd-secondary': '#475569',
        'rd-primary': '#111827',
      },
      boxShadow: {
        'rd-card': '0 24px 55px -35px rgba(149, 108, 10, 0.35)',
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
