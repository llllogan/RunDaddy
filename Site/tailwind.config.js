/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{html,ts}'],
  theme: {
    extend: {
      colors: {
        'rd-background': '#fdf9f2',
        'rd-surface': '#ffffff',
        'rd-card': 'rgba(255, 244, 214, 0.65)',
        'rd-accent': '#f2b134',
        'rd-accent-strong': '#e79607',
        'rd-teal': '#2f8f9d',
        'rd-muted': '#f3e5c0',
        'rd-secondary': '#5d6168',
        'rd-primary': '#222b38',
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
