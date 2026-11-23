const reportDate = (timestamp, timezone) => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone || Intl.DateTimeFormat().resolvedOptions().timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(timestamp * 1000));
  const part = type => parts.find(item => item.type === type).value;
  return `${part('year')}-${part('month')}-${part('day')}`;
};
export function reportFilename(kind, { from, to, timezone }, extension) {
  const start = reportDate(from, timezone);
  const end = reportDate(to - 1, timezone);
  return `${kind}-report-${start}${start === end ? '' : `-to-${end}`}.${extension}`;
}
export function downloadReport(data, name, type = 'text/csv;charset=utf-8') {
  const url = URL.createObjectURL(new Blob([data], { type }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
