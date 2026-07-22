export const canUseTariffEffectiveDate = (
  effectiveDate: string,
  today: string,
  canCreateHistorical: boolean,
): boolean => canCreateHistorical || !effectiveDate || effectiveDate >= today;

export { currentDateInTimeZone } from "../../utils/civilDate";
