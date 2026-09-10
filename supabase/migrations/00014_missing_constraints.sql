-- Migration 00014: Missing Constraints, Change Snapshot & Audit Trigger

-- ============================================================
-- 1. Prevent overlapping effective periods on qualification
-- ============================================================
CREATE OR REPLACE FUNCTION public.check_qualification_no_overlap()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.sm_supplier_qualification q
        WHERE q.scope_id = NEW.scope_id
          AND q.id != NEW.id
          AND q.status NOT IN ('Expired', 'Discontinued', 'Disqualified')
          AND (
              (NEW.valid_from IS NULL OR q.valid_to IS NULL OR NEW.valid_from < q.valid_to)
              AND
              (NEW.valid_to IS NULL OR q.valid_from IS NULL OR NEW.valid_to > q.valid_from)
          )
    ) THEN
        RAISE EXCEPTION 'Overlapping qualification period detected for this scope. Close the existing qualification before creating a new one.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_qualification_no_overlap
BEFORE INSERT OR UPDATE ON public.sm_supplier_qualification
FOR EACH ROW EXECUTE FUNCTION public.check_qualification_no_overlap();

-- ============================================================
-- 2. Supplier Change Snapshot Table (before/after JSON)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.sm_supplier_change_snapshot (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    request_id uuid REFERENCES public.sm_supplier_request(id),
    changed_fields text[],
    before_state jsonb NOT NULL,
    after_state jsonb NOT NULL,
    source text NOT NULL DEFAULT 'APPROVAL',
    actor_id uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now()
);

ALTER TABLE public.sm_supplier_change_snapshot ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read change snapshots" ON public.sm_supplier_change_snapshot
    FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));

-- ============================================================
-- 3. Vendor Audit Trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.trg_vendor_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.sm_supplier_audit_event (
        entity_type, entity_id, action, before_state, after_state, actor_id, source_system
    ) VALUES (
        'VENDOR', OLD.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), auth.uid(), 'SUPPLIER_PORTAL'
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_vendor_audit_on_update
AFTER UPDATE ON public.vendor
FOR EACH ROW EXECUTE FUNCTION public.trg_vendor_audit();

-- ============================================================
-- 4. Seed additional reference data
-- ============================================================
INSERT INTO public.sm_department (id, name) VALUES
    ('PROCUREMENT', 'Procurement / Mua hang'),
    ('IT', 'Information Technology'),
    ('MARKETING', 'Marketing'),
    ('FINANCE', 'Finance / Tai chinh'),
    ('OPERATIONS', 'Operations / Van hanh'),
    ('HR', 'Human Resources'),
    ('LEGAL', 'Legal / Phap ly')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sm_region (id, name) VALUES
    ('APAC', 'Asia Pacific'),
    ('VN', 'Vietnam'),
    ('SEA', 'Southeast Asia'),
    ('EU', 'Europe'),
    ('NA', 'North America'),
    ('GLOBAL', 'Global')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.mdm_category (id, name) VALUES
    ('RAW_MATERIAL', 'Nguyen vat lieu'),
    ('EQUIPMENT', 'May moc thiet bi'),
    ('IT_SOFTWARE', 'Phan mem IT'),
    ('IT_HARDWARE', 'Phan cung IT'),
    ('LOGISTICS', 'Logistics / Van chuyen'),
    ('PROFESSIONAL_SVC', 'Dich vu chuyen nghiep'),
    ('MARKETING_SVC', 'Dich vu Marketing'),
    ('FACILITY', 'Toa nha / Van phong')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 5. Seed default Risk Model Version
-- ============================================================
INSERT INTO public.sm_risk_model_version (version_name, description, valid_from, is_active)
VALUES ('v1.0', 'Initial risk model - Phase 1 baseline', now(), true)
ON CONFLICT DO NOTHING;
