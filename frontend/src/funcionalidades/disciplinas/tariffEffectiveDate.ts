export const canUseTariffEffectiveDate = (
  effectiveDate: string,
  today: string,
  canCreateHistorical: boolean,
): boolean => canCreateHistorical || !effectiveDate || effectiveDate >= today;

export const currentDateInTimeZone = (timeZone: string, now = new Date()): string => {
  const parts = new Intl.DateTimeFormat("en", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const value = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value;
  return `${value("year")}-${value("month")}-${value("day")}`;
};
