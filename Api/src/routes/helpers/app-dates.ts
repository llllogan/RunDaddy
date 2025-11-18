import { formatDateInTimezone } from '../../lib/timezone.js';

const coerceToDate = (value: Date | string): Date => {
  if (value instanceof Date) {
    return value;
  }
  return new Date(value);
};

export const formatAppDate = (
  value: Date | string,
  timeZone: string,
): string => {
  return formatDateInTimezone(coerceToDate(value), timeZone);
};

export const formatAppNullableDate = (
  value: Date | string | null | undefined,
  timeZone: string,
): string | null => {
  if (!value) {
    return null;
  }
  return formatAppDate(value, timeZone);
};

export const formatAppExclusiveRange = (
  range: { start: Date | string; end: Date | string },
  timeZone: string,
): { start: string; end: string } => {
  const startDate = coerceToDate(range.start);
  const endDate = coerceToDate(range.end);
  const endMs = endDate.getTime();
  const startMs = startDate.getTime();
  const adjustedEnd = endMs > startMs ? new Date(endMs - 1) : endDate;

  return {
    start: formatDateInTimezone(startDate, timeZone),
    end: formatDateInTimezone(adjustedEnd, timeZone),
  };
};
