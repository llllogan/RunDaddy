const SLUG_SAFE_PATTERN = /[^a-z0-9]+/g;

export const buildCompanySlug = (name: string): string => {
  const base = name.trim().toLowerCase().replace(SLUG_SAFE_PATTERN, '-').replace(/^-+|-+$/g, '') || 'company';
  return base;
};
