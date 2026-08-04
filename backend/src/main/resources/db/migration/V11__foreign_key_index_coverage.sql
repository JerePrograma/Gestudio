-- Cierra la cobertura de índices de claves foráneas después de la transición
-- multitenant. Primero elimina FKs legacy de una columna cuando existe una FK
-- tenant-aware equivalente con la misma semántica. Luego crea índices sólo para
-- las FKs restantes que todavía no poseen un índice con el mismo prefijo.

DO $$
DECLARE
    legacy_fk RECORD;
BEGIN
    FOR legacy_fk IN
        SELECT n.nspname AS schema_name,
               child.relname AS table_name,
               legacy.conname AS constraint_name
        FROM pg_catalog.pg_constraint legacy
        JOIN pg_catalog.pg_class child ON child.oid = legacy.conrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = child.relnamespace
        WHERE n.nspname = 'public'
          AND legacy.contype = 'f'
          AND cardinality(legacy.conkey) = 1
          AND EXISTS (
              SELECT 1
              FROM pg_catalog.pg_constraint tenant_fk
              WHERE tenant_fk.contype = 'f'
                AND tenant_fk.oid <> legacy.oid
                AND tenant_fk.conrelid = legacy.conrelid
                AND tenant_fk.confrelid = legacy.confrelid
                AND cardinality(tenant_fk.conkey) > 1
                AND legacy.conkey <@ tenant_fk.conkey
                AND legacy.confkey <@ tenant_fk.confkey
                AND tenant_fk.confdeltype = legacy.confdeltype
                AND tenant_fk.confupdtype = legacy.confupdtype
                AND tenant_fk.confmatchtype = legacy.confmatchtype
                AND tenant_fk.condeferrable = legacy.condeferrable
                AND tenant_fk.condeferred = legacy.condeferred
                AND EXISTS (
                    SELECT 1
                    FROM unnest(tenant_fk.conkey) key_column(attnum)
                    JOIN pg_catalog.pg_attribute attribute
                      ON attribute.attrelid = tenant_fk.conrelid
                     AND attribute.attnum = key_column.attnum
                    WHERE attribute.attname IN ('tenant_id', 'internal_tenant_id')
                )
          )
        ORDER BY child.relname, legacy.conname
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I DROP CONSTRAINT %I',
            legacy_fk.schema_name,
            legacy_fk.table_name,
            legacy_fk.constraint_name
        );
    END LOOP;
END;
$$;

DO $$
DECLARE
    fk RECORD;
    column_list TEXT;
    index_name TEXT;
BEGIN
    FOR fk IN
        SELECT constraint_row.oid,
               namespace_row.nspname AS schema_name,
               table_row.relname AS table_name,
               constraint_row.conname AS constraint_name,
               constraint_row.conrelid,
               constraint_row.conkey
        FROM pg_catalog.pg_constraint constraint_row
        JOIN pg_catalog.pg_class table_row
          ON table_row.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace namespace_row
          ON namespace_row.oid = table_row.relnamespace
        WHERE namespace_row.nspname = 'public'
          AND constraint_row.contype = 'f'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.pg_index index_row
              WHERE index_row.indrelid = constraint_row.conrelid
                AND index_row.indisvalid
                AND index_row.indisready
                AND index_row.indpred IS NULL
                AND index_row.indnkeyatts >= cardinality(constraint_row.conkey)
                AND NOT EXISTS (
                    SELECT 1
                    FROM unnest(constraint_row.conkey)
                         WITH ORDINALITY fk_column(attnum, ordinal_position)
                    LEFT JOIN unnest(index_row.indkey::smallint[])
                         WITH ORDINALITY index_column(attnum, ordinal_position)
                      ON index_column.ordinal_position = fk_column.ordinal_position
                    WHERE index_column.attnum IS DISTINCT FROM fk_column.attnum
                )
          )
        ORDER BY table_row.relname, constraint_row.conname
    LOOP
        SELECT string_agg(
                   format('%I', attribute.attname),
                   ', ' ORDER BY key_column.ordinal_position
               )
        INTO column_list
        FROM unnest(fk.conkey)
             WITH ORDINALITY key_column(attnum, ordinal_position)
        JOIN pg_catalog.pg_attribute attribute
          ON attribute.attrelid = fk.conrelid
         AND attribute.attnum = key_column.attnum;

        index_name :=
            left(
                'ix_' || fk.table_name || '_' ||
                regexp_replace(fk.constraint_name, '^fk_', ''),
                54
            ) || '_' ||
            substr(
                md5(
                    fk.schema_name || '.' ||
                    fk.table_name || '.' ||
                    fk.constraint_name
                ),
                1,
                8
            );

        IF pg_catalog.to_regclass(
            format('%I.%I', fk.schema_name, index_name)
        ) IS NULL THEN
            EXECUTE format(
                'CREATE INDEX %I ON %I.%I (%s)',
                index_name,
                fk.schema_name,
                fk.table_name,
                column_list
            );
        END IF;
    END LOOP;
END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint constraint_row
        JOIN pg_catalog.pg_class table_row
          ON table_row.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace namespace_row
          ON namespace_row.oid = table_row.relnamespace
        WHERE namespace_row.nspname = 'public'
          AND constraint_row.contype = 'f'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.pg_index index_row
              WHERE index_row.indrelid = constraint_row.conrelid
                AND index_row.indisvalid
                AND index_row.indisready
                AND index_row.indpred IS NULL
                AND index_row.indnkeyatts >= cardinality(constraint_row.conkey)
                AND NOT EXISTS (
                    SELECT 1
                    FROM unnest(constraint_row.conkey)
                         WITH ORDINALITY fk_column(attnum, ordinal_position)
                    LEFT JOIN unnest(index_row.indkey::smallint[])
                         WITH ORDINALITY index_column(attnum, ordinal_position)
                      ON index_column.ordinal_position = fk_column.ordinal_position
                    WHERE index_column.attnum IS DISTINCT FROM fk_column.attnum
                )
          )
    ) THEN
        RAISE EXCEPTION
            'V11 foreign keys: quedaron claves foráneas sin índice de prefijo';
    END IF;
END;
$$;
