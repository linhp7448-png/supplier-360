-- Migration 00004: Phase 2 - Scope, Qualification & Classification

-- 1. Create Enums
CREATE TYPE qualification_status AS ENUM (
    'Not_Assessed',
    'Pending',
    'Qualified',
    'Conditional',
    'Disqualified',
    'Expired',
    'Discontinued'
);

-- 2. Reference Data Tables (Master Data)
CREATE TABLE public.sm_department (
    id varchar(50) PRIMARY KEY, -- Allow 'ALL' or specific IDs like 'IT', 'MKT'
    name text NOT NULL,
    is_active boolean DEFAULT true
);

CREATE TABLE public.sm_region (
    id varchar(50) PRIMARY KEY, -- Allow 'ALL' or specific IDs like 'APAC', 'EU'
    name text NOT NULL,
    is_active boolean DEFAULT true
);

CREATE TABLE public.mdm_category (
    id varchar(50) PRIMARY KEY, -- Allow 'ALL' or specific IDs like 'SW', 'HW'
    name text NOT NULL,
    is_active boolean DEFAULT true
);

CREATE TABLE public.sm_classification_tier (
    id varchar(50) PRIMARY KEY, -- e.g., 'Strategic', 'Preferred', 'Approved'
    name text NOT NULL,
    rank integer NOT NULL, -- To determine priority
    is_active boolean DEFAULT true
);

-- Seed initial "ALL" reference data
INSERT INTO public.sm_department (id, name) VALUES ('ALL', 'All Departments');
INSERT INTO public.sm_region (id, name) VALUES ('ALL', 'All Regions');
INSERT INTO public.mdm_category (id, name) VALUES ('ALL', 'All Categories');
INSERT INTO public.sm_classification_tier (id, name, rank) VALUES 
    ('Strategic', 'Strategic Partner', 1),
    ('Preferred', 'Preferred Supplier', 2),
    ('Approved', 'Approved Supplier', 3),
    ('Transactional', 'Transactional', 4),
    ('Watchlist', 'Watchlist', 5);

-- 3. Supplier Scope Table
CREATE TABLE public.sm_supplier_scope (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    department_id varchar(50) REFERENCES public.sm_department(id),
    region_id varchar(50) REFERENCES public.sm_region(id),
    category_id varchar(50) REFERENCES public.mdm_category(id),
    owner_id uuid REFERENCES auth.users(id),
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    -- Unique constraint ensuring one active scope definition per combination per supplier
    UNIQUE(supplier_id, department_id, region_id, category_id)
);

ALTER TABLE public.sm_supplier_scope ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view scopes" ON public.sm_supplier_scope FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);

-- 4. Supplier Qualification Table (Versioned / Effective-Dated)
CREATE TABLE public.sm_supplier_qualification (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_id uuid REFERENCES public.sm_supplier_scope(id) ON DELETE CASCADE,
    status qualification_status NOT NULL DEFAULT 'Not_Assessed',
    valid_from timestamptz,
    valid_to timestamptz,
    conditions text,
    assessment_reference text, -- Link to assessment or evidence ID
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Function to ensure only one active qualification exists per scope
CREATE OR REPLACE FUNCTION check_active_qualification()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.valid_to IS NULL OR NEW.valid_to > now() THEN
        IF EXISTS (
            SELECT 1 FROM public.sm_supplier_qualification 
            WHERE scope_id = NEW.scope_id 
            AND id != NEW.id 
            AND (valid_to IS NULL OR valid_to > now())
        ) THEN
            RAISE EXCEPTION 'An active qualification already exists for this scope.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ensure_single_active_qualification
    BEFORE INSERT OR UPDATE ON public.sm_supplier_qualification
    FOR EACH ROW EXECUTE FUNCTION check_active_qualification();

ALTER TABLE public.sm_supplier_qualification ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view qualifications" ON public.sm_supplier_qualification FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);

-- 5. Supplier Classification Table (Versioned / Effective-Dated)
CREATE TABLE public.sm_supplier_classification (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_id uuid REFERENCES public.sm_supplier_scope(id) ON DELETE CASCADE,
    tier_id varchar(50) REFERENCES public.sm_classification_tier(id),
    rationale text,
    valid_from timestamptz,
    valid_to timestamptz,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Trigger for active classification
CREATE OR REPLACE FUNCTION check_active_classification_tier()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.valid_to IS NULL OR NEW.valid_to > now() THEN
        IF EXISTS (
            SELECT 1 FROM public.sm_supplier_classification 
            WHERE scope_id = NEW.scope_id 
            AND id != NEW.id 
            AND (valid_to IS NULL OR valid_to > now())
        ) THEN
            RAISE EXCEPTION 'An active classification already exists for this scope.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ensure_single_active_classification_tier
    BEFORE INSERT OR UPDATE ON public.sm_supplier_classification
    FOR EACH ROW EXECUTE FUNCTION check_active_classification_tier();

ALTER TABLE public.sm_supplier_classification ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view classifications" ON public.sm_supplier_classification FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);

-- 6. Scope History (Audit)
CREATE TABLE public.sm_supplier_scope_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_id uuid REFERENCES public.sm_supplier_scope(id),
    event_type text NOT NULL, -- e.g., 'SCOPE_CREATED', 'QUALIFICATION_UPDATED', 'CLASSIFICATION_UPDATED'
    before_state jsonb,
    after_state jsonb,
    actor_id uuid REFERENCES auth.users(id),
    timestamp timestamptz DEFAULT now()
);

ALTER TABLE public.sm_supplier_scope_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view scope history" ON public.sm_supplier_scope_history FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);
