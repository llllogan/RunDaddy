const TIMEZONE_FORMAT_OPTIONS: Intl.DateTimeFormatOptions = {
  hour12: false,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
};

const DATE_ONLY_FORMAT_OPTIONS: Intl.DateTimeFormatOptions = {
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
};

const DATE_LABEL_FORMATTER_CACHE = new Map<string, Intl.DateTimeFormat>();

const getDateLabelFormatter = (timeZone: string) => {
  const key = `${timeZone}-en-CA`;
  if (!DATE_LABEL_FORMATTER_CACHE.has(key)) {
    DATE_LABEL_FORMATTER_CACHE.set(
      key,
      new Intl.DateTimeFormat('en-CA', {
        ...DATE_ONLY_FORMAT_OPTIONS,
        timeZone,
      }),
    );
  }
  return DATE_LABEL_FORMATTER_CACHE.get(key)!;
};

const getDateOnlyFormatter = (timeZone: string) =>
  new Intl.DateTimeFormat('en-US', {
    ...DATE_ONLY_FORMAT_OPTIONS,
    timeZone,
  });

const getDateTimeFormatter = (timeZone: string) =>
  new Intl.DateTimeFormat('en-US', {
    ...TIMEZONE_FORMAT_OPTIONS,
    timeZone,
  });

const getPartValue = (parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes) =>
  parts.find((part) => part.type === type)?.value ?? null;

const parsePartAsInt = (value: string | null): number => {
  if (!value) {
    return NaN;
  }
  return Number.parseInt(value, 10);
};

export const isValidTimezone = (value: string): boolean => {
  if (!value || typeof value !== 'string') {
    return false;
  }
  try {
    getDateTimeFormatter(value).format(new Date());
    return true;
  } catch {
    return false;
  }
};

export const convertDateToTimezoneMidnight = (date: Date, timeZone: string): Date => {
  const baseDate = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 0, 0, 0, 0),
  );

  const formatter = getDateTimeFormatter(timeZone);
  const parts = formatter.formatToParts(baseDate);

  const year = parsePartAsInt(getPartValue(parts, 'year'));
  const month = parsePartAsInt(getPartValue(parts, 'month')) - 1;
  const day = parsePartAsInt(getPartValue(parts, 'day'));
  const hour = parsePartAsInt(getPartValue(parts, 'hour'));
  const minute = parsePartAsInt(getPartValue(parts, 'minute'));
  const second = parsePartAsInt(getPartValue(parts, 'second'));

  if ([year, month, day, hour, minute, second].some((value) => !Number.isFinite(value))) {
    return date;
  }

  const asUtc = Date.UTC(year, month, day, hour, minute, second);
  const offset = asUtc - baseDate.getTime();
  return new Date(baseDate.getTime() - offset);
};

export const determineScheduledFor = (runDate: Date | null, timeZone?: string): Date => {
  if (!runDate) {
    return new Date();
  }
  if (!timeZone) {
    return runDate;
  }
  return convertDateToTimezoneMidnight(runDate, timeZone);
};

const getLocalDateParts = (reference: Date, timeZone: string) => {
  const formatter = getDateOnlyFormatter(timeZone);
  const parts = formatter.formatToParts(reference);
  const year = parsePartAsInt(getPartValue(parts, 'year'));
  const month = parsePartAsInt(getPartValue(parts, 'month'));
  const day = parsePartAsInt(getPartValue(parts, 'day'));
  return { year, month, day };
};

export interface TimezoneDayRange {
  start: Date;
  end: Date;
  label: string;
  timeZone: string;
}

export const getTimezoneDayRange = ({
  timeZone,
  dayOffset = 0,
  reference = new Date(),
}: {
  timeZone: string;
  dayOffset?: number;
  reference?: Date;
}): TimezoneDayRange => {
  const { year, month, day } = getLocalDateParts(reference, timeZone);
  const baseUtc = new Date(Date.UTC(year, month - 1, day + dayOffset, 0, 0, 0, 0));
  const start = convertDateToTimezoneMidnight(baseUtc, timeZone);
  const nextReference = new Date(baseUtc);
  nextReference.setUTCDate(nextReference.getUTCDate() + 1);
  const end = convertDateToTimezoneMidnight(nextReference, timeZone);
  const label = formatDateInTimezone(start, timeZone);

  return {
    start,
    end,
    label,
    timeZone,
  };
};

export const formatDateInTimezone = (date: Date, timeZone: string): string => {
  return getDateLabelFormatter(timeZone).format(date);
};
