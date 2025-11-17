import { prisma } from '../../lib/prisma.js';
import { isValidTimezone } from '../../lib/timezone.js';

export async function resolveCompanyTimezone(companyId: string, override?: string): Promise<string> {
  if (override) {
    return override;
  }

  const company = await prisma.company.findUnique({
    where: { id: companyId },
    select: { timeZone: true },
  });

  if (company?.timeZone && isValidTimezone(company.timeZone)) {
    return company.timeZone;
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
