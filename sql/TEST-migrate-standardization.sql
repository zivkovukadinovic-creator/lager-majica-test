-- ONLY TEST project lager-majica-test. MANUAL execution after backup and audit.
-- NOT executed by Codex. Confirm the dashboard project/ref before uncommenting below.
-- Collisions abort the transaction: no rows are merged or deleted.
BEGIN;
-- SET LOCAL app.standardization_test_confirmed = 'lager-majica-test';
DO $$
BEGIN
  IF current_setting('app.standardization_test_confirmed', true) IS DISTINCT FROM 'lager-majica-test' THEN
    RAISE EXCEPTION 'Confirm TEST project in dashboard and uncomment the SET LOCAL guard.';
  END IF;
END $$;
LOCK TABLE public.majice IN ACCESS EXCLUSIVE MODE;

CREATE FUNCTION public.majice_canonical_model_v4(value text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
SET search_path = pg_catalog
AS $$
  SELECT CASE lower(regexp_replace(regexp_replace(normalize(value, NFD),
    '[̀-ͯ]', '', 'g'), '[[:space:]]', '', 'g'))
    WHEN 'muska' THEN 'Muška' WHEN 'zenska' THEN 'Ženska'
    WHEN 'djecja' THEN 'Dječija' WHEN 'djecija' THEN 'Dječija'
    ELSE value END
$$;

CREATE FUNCTION public.majice_canonical_size_v4(value text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
SET search_path = pg_catalog
AS $$
  SELECT CASE
    WHEN upper(btrim(value)) IN ('XS','S','M','L','XL') THEN upper(btrim(value))
    WHEN upper(btrim(value)) ~ '^X{2,}L$' THEN (length(btrim(value))-1)::text || 'XL'
    WHEN upper(btrim(value)) = '1XL' THEN 'XL'
    WHEN upper(btrim(value)) ~ '^[1-9][0-9]*XL$' THEN upper(btrim(value))
    ELSE value END
$$;

-- Report every row's exact quantity and minimum. A collision is NOT permission to sum.
SELECT lower(btrim(public.majice_canonical_model_v4(model))) AS model_key,
       lower(btrim(boja)) AS color_key,
       upper(btrim(public.majice_canonical_size_v4(velicina))) AS size_key,
       jsonb_agg(jsonb_build_object('id',id,'model',model,'boja',boja,
         'velicina',velicina,'kolicina',kolicina,
         'minimalna_kolicina',minimalna_kolicina) ORDER BY id) AS rows_to_review
FROM public.majice
GROUP BY 1,2,3 HAVING count(*) > 1;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.majice
    GROUP BY lower(btrim(public.majice_canonical_model_v4(model))),
             lower(btrim(boja)), upper(btrim(public.majice_canonical_size_v4(velicina)))
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Equivalent TEST rows exist. Review IDs, quantities and minima; no merge performed. ROLLBACK, resolve separately, then rerun.';
  END IF;
END $$;

-- With no collisions, only spelling changes; IDs, quantities and minima stay intact.
UPDATE public.majice
SET model = public.majice_canonical_model_v4(model),
    velicina = public.majice_canonical_size_v4(velicina)
WHERE model IS DISTINCT FROM public.majice_canonical_model_v4(model)
   OR velicina IS DISTINCT FROM public.majice_canonical_size_v4(velicina);

-- Keep the existing unique index: the RPC's ON CONFLICT still uses it.
-- This extra index also enforces canonical equivalence for every direct writer.
CREATE UNIQUE INDEX majice_canonical_unique_v4 ON public.majice (
  lower(btrim(public.majice_canonical_model_v4(model))),
  lower(btrim(boja)),
  upper(btrim(public.majice_canonical_size_v4(velicina)))
);

CREATE FUNCTION public.majice_canonical_write_v4()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog
AS $$
BEGIN
  NEW.model := public.majice_canonical_model_v4(NEW.model);
  NEW.velicina := public.majice_canonical_size_v4(NEW.velicina);
  RETURN NEW;
END $$;
CREATE TRIGGER majice_canonical_write_v4
BEFORE INSERT OR UPDATE OF model, velicina ON public.majice
FOR EACH ROW EXECUTE FUNCTION public.majice_canonical_write_v4();

-- Replace only the reviewed function body, retaining its exact signature,
-- return type, owner, SECURITY mode, SET options and existing grants.
-- Refuse unexpected overloads/parameter names/body: inspect rather than guessing.
DO $migration$
DECLARE
  target oid;
  definition text;
  old_body text;
  new_body text := $body$
BEGIN
    IF p_model IS NULL OR btrim(p_model) = ''
       OR p_boja IS NULL OR btrim(p_boja) = ''
       OR p_velicina IS NULL OR btrim(p_velicina) = ''
       OR p_kolicina IS NULL OR p_kolicina <= 0
       OR p_minimalna_kolicina IS NULL OR p_minimalna_kolicina < 0
    THEN
        RAISE EXCEPTION 'Neispravni podaci o majicama.';
    END IF;
    INSERT INTO public.majice (model, boja, velicina, kolicina, minimalna_kolicina)
    VALUES (
        public.majice_canonical_model_v4(btrim(p_model)), btrim(p_boja),
        public.majice_canonical_size_v4(upper(btrim(p_velicina))),
        p_kolicina, p_minimalna_kolicina
    )
    ON CONFLICT (lower(trim(model)), lower(trim(boja)), upper(trim(velicina)))
    DO UPDATE SET
        kolicina = majice.kolicina + EXCLUDED.kolicina,
        minimalna_kolicina = EXCLUDED.minimalna_kolicina;
END;
$body$;
BEGIN
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='dodaj_majice_sa_minimumom') <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one reviewed add RPC; inspect overloads.';
  END IF;
  SELECT p.oid, pg_get_functiondef(p.oid), p.prosrc
  INTO target, definition, old_body
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  JOIN pg_language l ON l.oid=p.prolang
  WHERE n.nspname='public' AND p.proname='dodaj_majice_sa_minimumom'
    AND l.lanname='plpgsql' AND p.prokind='f' AND p.pronargs=5
    AND p.proargnames = ARRAY['p_model','p_boja','p_velicina','p_kolicina','p_minimalna_kolicina']::text[];
  IF target IS NULL OR strpos(definition,old_body)=0
     OR old_body NOT ILIKE '%minimalna_kolicina = EXCLUDED.minimalna_kolicina%'
     OR old_body NOT ILIKE '%kolicina = majice.kolicina + EXCLUDED.kolicina%' THEN
    RAISE EXCEPTION 'RPC metadata/body differs from reviewed definition; inspect before migration.';
  END IF;
  EXECUTE replace(definition, old_body, new_body);
END $migration$;
COMMIT;
-- On any error: issue ROLLBACK. Nothing from the transaction should be retained.
-- No DROP INDEX, DELETE, RLS, role, authentication or GRANT changes.
