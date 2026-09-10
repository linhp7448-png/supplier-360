-- Migration 00007: Phase 5 & 6 - Performance, Downstream & Audit

-- ==========================================
-- PHASE 5: Supplier Performance (Scorecards)
-- ==========================================

CREATE TABLE public.sm_performance_kpi (
    id serial PRIMARY KEY,
    name text NOT NULL,
    description text,
    formula text,
    data_source text, -- e.g., 'ERP_NAV', 'Manual_Entry'
    frequency text, -- e.g., 'Monthly', 'Quarterly'
    owner_id uuid REFERENCES auth.users(id),
    is_active boolean DEFAULT true
);

CREATE TABLE public.sm_performance_scorecard (
    id serial PRIMARY KEY,
    name text NOT NULL,
    department_id varchar(50) REFERENCES public.sm_department(id),
    region_id varchar(50) REFERENCES public.sm_region(id),
    category_id varchar(50) REFERENCES public.mdm_category(id),
    scoring_band jsonb, -- e.g., {"Excellent": 90-100, "Good": 70-89}
    is_active boolean DEFAULT true
);

CREATE TABLE public.sm_scorecard_kpi (
    scorecard_id integer REFERENCES public.sm_performance_scorecard(id) ON DELETE CASCADE,
    kpi_id integer REFERENCES public.sm_performance_kpi(id) ON DELETE CASCADE,
    weight numeric NOT NULL DEFAULT 1,
    PRIMARY KEY (scorecard_id, kpi_id)
);

CREATE TABLE public.sm_performance_evaluation (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    scorecard_id integer REFERENCES public.sm_performance_scorecard(id),
    evaluation_period text NOT NULL, -- e.g., 'Q3-2026'
    total_score numeric,
    grade text,
    evaluator_id uuid REFERENCES auth.users(id),
    status text DEFAULT 'Draft', -- Draft, Published
    published_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE (supplier_id, scorecard_id, evaluation_period)
);

CREATE TABLE public.sm_performance_score (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    evaluation_id uuid REFERENCES public.sm_performance_evaluation(id) ON DELETE CASCADE,
    kpi_id integer REFERENCES public.sm_performance_kpi(id),
    raw_value numeric,
    score numeric,
    source_evidence text,
    created_at timestamptz DEFAULT now(),
    UNIQUE (evaluation_id, kpi_id)
);

-- ==========================================
-- PHASE 6: Downstream, Crosswalk & Audit
-- ==========================================

-- 1. Canonical Audit Event (Immutable)
CREATE TABLE public.sm_supplier_audit_event (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    correlation_id uuid, -- Links back to request_id
    entity_type text NOT NULL, -- 'VENDOR', 'SCOPE', 'QUALIFICATION', etc.
    entity_id uuid NOT NULL,
    action text NOT NULL, -- 'CREATE', 'UPDATE', 'DELETE'
    before_state jsonb,
    after_state jsonb,
    actor_id uuid,
    source_system text DEFAULT 'SUPPLIER_PORTAL',
    timestamp timestamptz DEFAULT now()
);

-- 2. Transactional Outbox (For safe async delivery to ERP)
CREATE TABLE public.sm_supplier_outbox (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type text NOT NULL, -- e.g., 'SUPPLIER_ACTIVATED', 'BANK_CHANGED'
    payload jsonb NOT NULL,
    status text DEFAULT 'Pending', -- 'Pending', 'Claimed', 'Processed', 'Failed'
    retry_count integer DEFAULT 0,
    worker_id text,
    error_message text,
    created_at timestamptz DEFAULT now(),
    processed_at timestamptz
);

-- 3. Supplier Crosswalk (ID mapping between systems)
CREATE TABLE public.sm_supplier_crosswalk (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    target_system text NOT NULL, -- e.g., 'NAV', 'VISTA'
    external_id text NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE (supplier_id, target_system)
);

-- 4. Downstream Sync Audit
CREATE TABLE public.sm_supplier_sync_audit (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    outbox_id uuid REFERENCES public.sm_supplier_outbox(id),
    target_system text NOT NULL,
    sync_status text NOT NULL,
    response_payload jsonb,
    sync_time timestamptz DEFAULT now()
);

-- Basic RLS
ALTER TABLE public.sm_performance_kpi ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_performance_scorecard ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_scorecard_kpi ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_performance_evaluation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_performance_score ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.sm_supplier_audit_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_crosswalk ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_supplier_sync_audit ENABLE ROW LEVEL SECURITY;

-- Admins and internal users can read performance
CREATE POLICY "Internal read perf" ON public.sm_performance_evaluation FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));

-- Only internal can see audits and outbox
CREATE POLICY "Internal read audit" ON public.sm_supplier_audit_event FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Internal read crosswalk" ON public.sm_supplier_crosswalk FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
