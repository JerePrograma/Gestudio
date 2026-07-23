\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE _demo_pricing_config ON COMMIT DROP AS
SELECT make_date(
    extract(year FROM :'demo_business_date'::date)::integer,
    1,
    1
) AS year_start;

CREATE TEMP TABLE _demo_pricing_disciplines ON COMMIT DROP AS
SELECT id
FROM public.disciplinas
WHERE nombre IN (
    'Ballet Inicial (4 a 6 años)',
    'Jazz Infantil (7 a 10 años)',
    'Danza Urbana Teen',
    'Danza Contemporánea',
    'Ritmos Latinos Adultos',
    'Entrenamiento Escénico'
);

DO $guard$
BEGIN
    IF (SELECT count(*) FROM _demo_pricing_disciplines) <> 6 THEN
        RAISE EXCEPTION 'No se resolvieron las seis disciplinas demo';
    END IF;

    IF EXISTS (
        SELECT d.id
        FROM _demo_pricing_disciplines d
        LEFT JOIN public.disciplina_tarifas t
          ON t.disciplina_id = d.id
        GROUP BY d.id
        HAVING count(t.id) <> 2
    ) THEN
        RAISE EXCEPTION 'Las disciplinas demo no contienen exactamente dos tarifas cada una';
    END IF;
END
$guard$;

WITH earliest AS (
    SELECT DISTINCT ON (t.disciplina_id)
           t.id,
           t.disciplina_id,
           t.vigente_desde
    FROM public.disciplina_tarifas t
    JOIN _demo_pricing_disciplines d
      ON d.id = t.disciplina_id
    ORDER BY t.disciplina_id, t.vigente_desde, t.id
)
UPDATE public.disciplina_tarifas t
SET vigente_desde = c.year_start,
    motivo = CASE
        WHEN t.motivo = 'Arancel histórico conservado para trazabilidad.'
            THEN 'Arancel histórico desde el inicio del año demo.'
        ELSE t.motivo
    END
FROM earliest e
CROSS JOIN _demo_pricing_config c
WHERE t.id = e.id
  AND e.vigente_desde > c.year_start
  AND NOT EXISTS (
      SELECT 1
      FROM public.disciplina_tarifas existing
      WHERE existing.disciplina_id = e.disciplina_id
        AND existing.vigente_desde = c.year_start
  );

DO $verify$
BEGIN
    IF EXISTS (
        SELECT d.id
        FROM _demo_pricing_disciplines d
        CROSS JOIN _demo_pricing_config c
        LEFT JOIN public.disciplina_tarifas t
          ON t.disciplina_id = d.id
        GROUP BY d.id, c.year_start
        HAVING count(t.id) <> 2
            OR min(t.vigente_desde) > c.year_start
    ) THEN
        RAISE EXCEPTION 'La cobertura tarifaria demo no alcanza el inicio del año';
    END IF;
END
$verify$;

COMMIT;

SELECT count(DISTINCT d.id) || '|' || count(t.id) || '|' || min(t.vigente_desde)
FROM _demo_pricing_disciplines d
JOIN public.disciplina_tarifas t
  ON t.disciplina_id = d.id;
