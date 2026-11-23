export const browserTimezone = () =>
  Intl.DateTimeFormat().resolvedOptions().timeZone;

// Calendar arithmetic preserves 23/25-hour days at daylight-saving transitions.
export const browserRange = dates => {
  if (
    !Array.isArray(dates) ||
    dates.length !== 2 ||
    dates.some(date => !(date instanceof Date))
  ) {
    throw new RangeError('invalid_range');
  }
  const midnight = date =>
    new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const start = midnight(dates[0]);
  const end = midnight(dates[1]);
  end.setDate(end.getDate() + 1);
  const from = start.getTime() / 1000;
  const to = end.getTime() / 1000;
  if (!Number.isFinite(from) || !Number.isFinite(to) || to <= from)
    throw new RangeError('invalid_range');
  return { from, to, timezone: browserTimezone() };
};

export const browserPreset = offset => {
  const end = new Date();
  const start = new Date(end);
  start.setDate(start.getDate() - offset);
  return browserRange([start, end]);
};
