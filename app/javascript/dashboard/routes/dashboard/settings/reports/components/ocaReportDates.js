const DAY = 86400;
const SG_OFFSET = 8 * 3600;
export const MAX_REPORT_DAYS = 93;

// Date picker values represent selected calendar dates, not instants.
export const singaporeRange = dates => {
  const midnight = date =>
    Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 1000 -
    SG_OFFSET;
  const from = midnight(dates[0]);
  const to = midnight(dates[1]) + DAY;
  if (
    !Number.isFinite(from) ||
    !Number.isFinite(to) ||
    to <= from ||
    to - from > MAX_REPORT_DAYS * DAY
  ) {
    throw new RangeError('invalid_range');
  }
  return { from, to };
};

export const singaporeToday = (now = new Date()) => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Singapore',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const value = type => Number(parts.find(part => part.type === type).value);
  return new Date(value('year'), value('month') - 1, value('day'));
};

export const singaporePreset = offset => {
  const end = singaporeToday();
  const start = new Date(end);
  start.setDate(start.getDate() - offset);
  return singaporeRange([start, end]);
};
