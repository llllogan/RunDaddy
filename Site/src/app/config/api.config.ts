declare global {
  interface Window {
    __env?: {
      apiBaseUrl?: string;
    };
  }
}

export const API_BASE_URL = (window as any).__env?.apiBaseUrl || '/api';
