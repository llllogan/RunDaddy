import {
  convertDateToTimezoneMidnight,
  formatDateInTimezone,
  getLocalDateParts,
  getTimezoneDayRange,
  getWeekdayIndexInTimezone,
} from '../../lib/timezone.js';

export const ONE_DAY_MS = 24 * 60 * 60 * 1000;

export type StatsPeriod = 'week' | 'month' | 'quarter';

export const PERIOD_DAY_COUNTS: Record<StatsPeriod, number> = {
  week: 7,
  month: 30,
  quarter: 90,
};

export type PeriodBucket = {
  key: string;
  label: string;
  start: Date;
  end: Date;
  startMs: number;
  endMs: number;
};

const MONTH_NAME_FORMATTER_CACHE = new Map<string, Intl.DateTimeFormat>();

export function buildPercentageChange(currentTotal: number, previousTotal: number) {
  if (currentTotal === 0 && previousTotal === 0) {
    return null;
  }

  if (previousTotal === 0 && currentTotal > 0) {
    return { value: 100, trend: 'up' as const };
  }

  if (previousTotal > 0 && currentTotal === 0) {
    return { value: -100, trend: 'down' as const };
  }

  const percentageChange = ((currentTotal - previousTotal) / previousTotal) * 100;
  const trend =
    percentageChange > 0.5 ? 'up' : percentageChange < -0.5 ? 'down' : 'neutral';

  return {
    value: Math.round(percentageChange * 10) / 10,
    trend,
  };
}

export function buildPeriodRange(period: StatsPeriod, reference: Date, timeZone: string) {
  const todayRange = getTimezoneDayRange({ timeZone, dayOffset: 0, reference });
  const { year, month } = getLocalDateParts(reference, timeZone);

  let start: Date;
  switch (period) {
    case 'week': {
      const weekday = getWeekdayIndexInTimezone(reference, timeZone);
      const offsetFromMonday = (weekday + 6) % 7;
      start = new Date(todayRange.start);
      start.setUTCDate(start.getUTCDate() - offsetFromMonday);
      break;
    }
    case 'month': {
      const candidate = new Date(Date.UTC(year, month - 1, 1));
      start = convertDateToTimezoneMidnight(candidate, timeZone);
      break;
    }
    case 'quarter': {
      const quarterStartMonth = Math.floor((month - 1) / 3) * 3;
      const candidate = new Date(Date.UTC(year, quarterStartMonth, 1));
      start = convertDateToTimezoneMidnight(candidate, timeZone);
      break;
    }
  }

  const end = new Date(start);
  switch (period) {
    case 'week':
      end.setUTCDate(end.getUTCDate() + 7);
      break;
    case 'month':
      end.setUTCMonth(end.getUTCMonth() + 1);
      break;
    case 'quarter':
      end.setUTCMonth(end.getUTCMonth() + 3);
      break;
  }

  const dayCount = Math.round((end.getTime() - start.getTime()) / ONE_DAY_MS);
  return { start, end, dayCount };
}

export function buildChartRange(
  period: StatsPeriod,
  periodRange: { start: Date; end: Date },
  timeZone: string,
  reference: Date,
) {
  if (period === 'week') {
    const todayRange = getTimezoneDayRange({ timeZone, dayOffset: 0, reference });
    const startRange = getTimezoneDayRange({
      timeZone,
      dayOffset: -6,
      reference: todayRange.start,
    });
    const tomorrowRange = getTimezoneDayRange({
      timeZone,
      dayOffset: 1,
      reference: todayRange.start,
    });

    return {
      start: startRange.start,
      end: tomorrowRange.end,
    };
  }

  if (period === 'month') {
    const start = getWeekStart(periodRange.start, timeZone);
    const endWeekStart = getWeekStart(periodRange.end, timeZone);
    const end = new Date(endWeekStart);
    end.setUTCDate(end.getUTCDate() + 7);
    return { start, end };
  }

  return {
    start: new Date(periodRange.start),
    end: new Date(periodRange.end),
  };
}

export function buildChartBuckets(
  period: StatsPeriod,
  chartStart: Date,
  chartEnd: Date,
  timeZone: string,
): PeriodBucket[] {
  switch (period) {
    case 'week':
      return buildDailyBuckets(chartStart, chartEnd, timeZone);
    case 'month':
      return buildWeeklyBuckets(chartStart, chartEnd, timeZone);
    case 'quarter':
      return buildMonthlyBuckets(chartStart, chartEnd, timeZone);
    default:
      return buildDailyBuckets(chartStart, chartEnd, timeZone);
  }
}

export function parseLocalDate(dateString: string, timeZone: string): Date {
  const [yearPart, monthPart, dayPart] = dateString.split('-');

  if (!yearPart || !monthPart || !dayPart) {
    throw new Error(`Invalid local date: ${dateString}`);
  }

  const year = Number(yearPart);
  const month = Number(monthPart);
  const day = Number(dayPart);
  const candidate = new Date(Date.UTC(year, month - 1, day));
  return convertDateToTimezoneMidnight(candidate, timeZone);
}

function buildDailyBuckets(start: Date, end: Date, timeZone: string): PeriodBucket[] {
  const buckets: PeriodBucket[] = [];
  let cursor = new Date(start);

  while (cursor < end) {
    const bucketStart = new Date(cursor);
    const bucketEnd = new Date(bucketStart);
    bucketEnd.setUTCDate(bucketEnd.getUTCDate() + 1);

    buckets.push(
      createBucket(formatDateInTimezone(bucketStart, timeZone), bucketStart, bucketEnd),
    );

    cursor = bucketEnd;
  }

  return buckets;
}

function buildWeeklyBuckets(start: Date, end: Date, timeZone: string): PeriodBucket[] {
  const buckets: PeriodBucket[] = [];
  let cursor = getWeekStart(start, timeZone);

  while (cursor < end) {
    const bucketStart = new Date(cursor);
    const bucketEnd = new Date(bucketStart);
    bucketEnd.setUTCDate(bucketEnd.getUTCDate() + 7);

    buckets.push(
      createBucket(formatDateInTimezone(bucketStart, timeZone), bucketStart, bucketEnd),
    );

    cursor = bucketEnd;
  }

  return buckets;
}

function buildMonthlyBuckets(start: Date, end: Date, timeZone: string): PeriodBucket[] {
  const buckets: PeriodBucket[] = [];
  let cursor = getMonthStart(start, timeZone);

  while (cursor < end) {
    const bucketStart = new Date(cursor);
    const bucketEnd = getNextMonthStart(bucketStart, timeZone);

    buckets.push(createBucket(formatMonthName(bucketStart, timeZone), bucketStart, bucketEnd));
    cursor = bucketEnd;
  }

  return buckets;
}

function createBucket(label: string, start: Date, end: Date): PeriodBucket {
  return {
    key: start.toISOString(),
    label,
    start,
    end,
    startMs: start.getTime(),
    endMs: end.getTime(),
  };
}

function getWeekStart(date: Date, timeZone: string): Date {
  const weekday = getWeekdayIndexInTimezone(date, timeZone);
  const offsetFromMonday = (weekday + 6) % 7;
  const start = new Date(date);
  start.setUTCDate(start.getUTCDate() - offsetFromMonday);
  return start;
}

function formatMonthName(date: Date, timeZone: string) {
  const key = `${timeZone}-month`;
  if (!MONTH_NAME_FORMATTER_CACHE.has(key)) {
    MONTH_NAME_FORMATTER_CACHE.set(
      key,
      new Intl.DateTimeFormat('en-US', { month: 'long', timeZone }),
    );
  }
  return MONTH_NAME_FORMATTER_CACHE.get(key)!.format(date);
}

function getMonthStart(date: Date, timeZone: string): Date {
  const { year, month } = getLocalDateParts(date, timeZone);
  const candidate = new Date(Date.UTC(year, month - 1, 1));
  return convertDateToTimezoneMidnight(candidate, timeZone);
}

function getNextMonthStart(date: Date, timeZone: string): Date {
  const { year, month } = getLocalDateParts(date, timeZone);
  const candidate = new Date(Date.UTC(year, month, 1));
  return convertDateToTimezoneMidnight(candidate, timeZone);
}
