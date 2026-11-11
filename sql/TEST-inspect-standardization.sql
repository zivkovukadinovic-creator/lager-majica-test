-- READ ONLY. Run manually ONLY in the confirmed TEST project SQL editor.
-- Do not run against production. No data/schema/permissions are changed.
BEGIN TRANSACTION READ ONLY;

-- Verify identity locally against the TEST dashboard (do not publish connection secrets).
SELECT current_database(), current_user;

-- Inspect the actual add RPC, other routines mentioning majice, and trigger functions.
SELECT p.oid::regprocedure AS signature, p.prosecdef AS security_definer,
       pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
  AND (p.proname = 'dodaj_majice_sa_minimumom'
       OR p.prosrc ILIKE '%majice%');

SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'majice'
ORDER BY ordinal_position;

-- Include incoming foreign keys: they affect any future duplicate resolution.
SELECT conname, conrelid::regclass AS on_table, confrelid::regclass AS referenced_table,
       pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.majice'::regclass OR confrelid = 'public.majice'::regclass;

SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'majice';
SELECT tgname, pg_get_triggerdef(oid) AS definition
FROM pg_trigger WHERE tgrelid = 'public.majice'::regclass AND NOT tgisinternal;

-- Duplicate candidates only. No SUM/MAX policy is applied to quantities or minima.
-- Preserve exact color spelling, matching the browser's existing color behavior.
WITH keys AS (
  SELECT id, model, boja, velicina, kolicina, minimalna_kolicina,
    CASE lower(translate(regexp_replace(model, '[[:space:]]', '', 'g'),
                         'šŠžŽčČćĆ', 'sSzZcCcC'))
      WHEN 'muska' THEN 'Muška' WHEN 'zenska' THEN 'Ženska'
      WHEN 'djecja' THEN 'Dječija' WHEN 'djecija' THEN 'Dječija'
      ELSE model END AS canonical_model,
    upper(btrim(velicina)) AS size_key
  FROM public.majice
), normalized AS (
  SELECT *, CASE
    WHEN size_key IN ('XS','S','M','L','XL') THEN size_key
    WHEN size_key ~ '^X{2,}L$' THEN (length(size_key)-1)::text || 'XL'
    WHEN size_key = '1XL' THEN 'XL'
    WHEN size_key ~ '^[1-9][0-9]*XL$' THEN size_key
    ELSE velicina END AS canonical_size
  FROM keys
)
SELECT canonical_model, boja, canonical_size, count(*) AS row_count,
       jsonb_agg(jsonb_build_object('id', id, 'model', model, 'velicina', velicina,
         'kolicina', kolicina, 'minimalna_kolicina', minimalna_kolicina) ORDER BY id) AS rows_to_review
FROM normalized
GROUP BY canonical_model, boja, canonical_size HAVING count(*) > 1;
ROLLBACK;
