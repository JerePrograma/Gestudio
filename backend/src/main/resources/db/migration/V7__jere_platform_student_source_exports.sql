CREATE TABLE public.jere_platform_student_export_snapshots (
    checkpoint UUID PRIMARY KEY,
    organization_id VARCHAR(100) NOT NULL,
    tenant_id UUID NOT NULL,
    status VARCHAR(20) NOT NULL,
    page_size INTEGER NOT NULL,
    page_count INTEGER NOT NULL,
    total_records INTEGER NOT NULL,
    created_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    version BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT fk_jere_student_export_created_by
        FOREIGN KEY (created_by) REFERENCES public.usuarios(id) ON DELETE RESTRICT,
    CONSTRAINT ck_jere_student_export_status CHECK (status = 'READY'),
    CONSTRAINT ck_jere_student_export_organization CHECK (length(trim(organization_id)) > 0),
    CONSTRAINT ck_jere_student_export_pages
        CHECK (page_size BETWEEN 1 AND 1000 AND page_count BETWEEN 1 AND 1000),
    CONSTRAINT ck_jere_student_export_total CHECK (total_records >= 0)
);

CREATE TABLE public.jere_platform_student_export_pages (
    snapshot_checkpoint UUID NOT NULL,
    page_number INTEGER NOT NULL,
    cursor_token UUID,
    next_cursor_token UUID,
    full_snapshot BOOLEAN NOT NULL,
    record_count INTEGER NOT NULL,
    payload BYTEA NOT NULL,
    payload_sha256 CHAR(64) NOT NULL,
    signature VARCHAR(71) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (snapshot_checkpoint, page_number),
    CONSTRAINT fk_jere_student_export_page_snapshot
        FOREIGN KEY (snapshot_checkpoint)
        REFERENCES public.jere_platform_student_export_snapshots(checkpoint)
        ON DELETE RESTRICT,
    CONSTRAINT uq_jere_student_export_cursor UNIQUE (cursor_token),
    CONSTRAINT ck_jere_student_export_page_number CHECK (page_number BETWEEN 1 AND 1000),
    CONSTRAINT ck_jere_student_export_page_records CHECK (record_count BETWEEN 0 AND 1000),
    CONSTRAINT ck_jere_student_export_payload_size CHECK (octet_length(payload) <= 1000000),
    CONSTRAINT ck_jere_student_export_payload_hash CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_jere_student_export_signature CHECK (signature ~ '^sha256=[0-9a-f]{64}$')
);

CREATE UNIQUE INDEX uq_jere_student_export_first_page
    ON public.jere_platform_student_export_pages(snapshot_checkpoint)
    WHERE cursor_token IS NULL;

CREATE INDEX ix_jere_student_export_mapping_created
    ON public.jere_platform_student_export_snapshots(organization_id, tenant_id, created_at DESC);

CREATE INDEX ix_jere_student_export_created_by
    ON public.jere_platform_student_export_snapshots(created_by);
