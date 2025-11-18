import { prisma } from '../../lib/prisma.js';
import { isValidTimezone } from '../../lib/timezone.js';

type ResolveCompanyTimezoneOptions = {
  persistIfMissing?: boolean;
};

export async function resolveCompanyTimezone(
  companyId: string,
  override?: string,
  options?: ResolveCompanyTimezoneOptions,
): Promise<string> {
  const persistIfMissing = options?.persistIfMissing ?? false;
  const normalizedOverride = override && isValidTimezone(override) ? override : undefined;
  let companyTimeZone: string | null | undefined;

  // Fetch the company timezone when we need a fallback or we might persist it.
  if (!normalizedOverride || persistIfMissing) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
      select: { timeZone: true },
    });
    companyTimeZone = company?.timeZone ?? null;
  }

  if (normalizedOverride) {
    if (persistIfMissing && !companyTimeZone) {
      await prisma.company.update({
        where: { id: companyId },
        data: { timeZone: normalizedOverride },
      });
    }
    return normalizedOverride;
  }

  if (companyTimeZone && isValidTimezone(companyTimeZone)) {
    return companyTimeZone;
  }

  return 'UTC';
}

export function parseTimezoneQueryParam(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed || undefined;
}
