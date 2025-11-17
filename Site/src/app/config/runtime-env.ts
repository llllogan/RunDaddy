type RuntimeEnv = {
  apiBaseUrl?: string;
};

declare global {
  interface Window {
    __env?: RuntimeEnv;
  }
}

const normalizeBaseUrl = (value?: string): string => {
  if (!value) {
    return '';
  }
  return value.endsWith('/') ? value.replace(/\/+$/, '') : value;
};

const runtimeEnv = typeof window !== 'undefined' ? window.__env ?? {} : {};

export const environment = {
  apiBaseUrl: normalizeBaseUrl(runtimeEnv.apiBaseUrl),
};

export const buildApiUrl = (path: string): string => {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  if (!environment.apiBaseUrl) {
    return normalizedPath;
  }
  return `${environment.apiBaseUrl}${normalizedPath}`;
};
