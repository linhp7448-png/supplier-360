-- Migration 00005: Phase 3 - Supplier Risk Management

-- 1. Enums
CREATE TYPE risk_decision_type AS ENUM (
    'Acceptable',
    'Accept_With_Controls',
    'Pending_Review',
    'Blocked'
);

CREATE TYPE risk_severity AS ENUM (
    'Low',
    'Medium',
    'High',
    'Critical'
);

CREATE TYPE risk_status AS ENUM (
    'Open',
    'In_Progress',
    'Mitigated',
    'Closed'
);

-- 2. Reference Data
CREATE TABLE public.sm_risk_category (
    id varchar(50) PRIMARY KEY, -- e.g., 'Tax', 'Legal', 'Financial', 'Operational', 'Quality'
    name text NOT NULL,
    description text,
    is_active boolean DEFAULT true
);

INSERT INTO public.sm_risk_category (id, name) VALUES
    ('Tax', 'Tax Risk'),
    ('Legal', 'Legal & Compliance Risk'),
    ('Financial', 'Financial Stability'),
    ('Operational', 'Operational & Delivery Risk'),
    ('Quality', 'Quality Risk'),
    ('Continuity', 'Business Continuity Risk');

-- 3. Risk Model Version (Formulas / Thresholds)
CREATE TABLE public.sm_risk_model_version (
    id serial PRIMARY KEY,
    version_name text NOT NULL,
    description text,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    is_active boolean DEFAULT false
);

-- 4. Risk Assessment
CREATE TABLE public.sm_risk_assessment (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    scope_id uuid REFERENCES public.sm_supplier_scope(id), -- Optional: if risk is tied to specific scope
    model_version_id integer REFERENCES public.sm_risk_model_version(id),
    assessed_by uuid REFERENCES auth.users(id),
    assessment_date timestamptz DEFAULT now(),
    next_review_date timestamptz,
    total_score numeric,
    overall_severity risk_severity,
    status risk_status DEFAULT 'Open',
    created_at timestamptz DEFAULT now()
);

-- 5. Risk Factor (Observations / Evidence)
CREATE TABLE public.sm_risk_factor (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id uuid REFERENCES public.sm_risk_assessment(id) ON DELETE CASCADE,
    category_id varchar(50) REFERENCES public.sm_risk_category(id),
    observation text NOT NULL,
    probability numeric, -- 0 to 1
    impact numeric, -- e.g., 1 to 5
    score numeric,
    evidence_url text,
    source_system text,
    created_at timestamptz DEFAULT now()
);

-- 6. Risk Control (Mandatory controls put in place)
CREATE TABLE public.sm_risk_control (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id uuid REFERENCES public.sm_risk_assessment(id) ON DELETE CASCADE,
    control_description text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    effectiveness text, -- e.g., 'Effective', 'Needs_Improvement'
    review_date timestamptz,
    expiry_date timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 7. Risk Issue (Problems found)
CREATE TABLE public.sm_risk_issue (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    assessment_id uuid REFERENCES public.sm_risk_assessment(id), -- Nullable if raised outside assessment
    title text NOT NULL,
    description text,
    severity risk_severity NOT NULL,
    status risk_status DEFAULT 'Open',
    assignee_id uuid REFERENCES auth.users(id),
    due_date timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 8. Risk Action (CAPA / Mitigation)
CREATE TABLE public.sm_risk_action (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id uuid REFERENCES public.sm_risk_issue(id) ON DELETE CASCADE,
    action_description text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    status risk_status DEFAULT 'Open',
    due_date timestamptz,
    completion_evidence text,
    completed_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 9. Risk Decision
CREATE TABLE public.sm_risk_decision (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    scope_id uuid REFERENCES public.sm_supplier_scope(id),
    decision risk_decision_type NOT NULL,
    rationale text,
    decided_by uuid REFERENCES auth.users(id),
    decided_at timestamptz DEFAULT now(),
    valid_until timestamptz
);

-- Enable RLS for all tables
ALTER TABLE public.sm_risk_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_model_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_assessment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_factor ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_control ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_issue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_risk_decision ENABLE ROW LEVEL SECURITY;

-- Assuming standard read policies based on roles
CREATE POLICY "Read access risk category" ON public.sm_risk_category FOR SELECT USING (true);
CREATE POLICY "Read access risk model" ON public.sm_risk_model_version FOR SELECT USING (true);
CREATE POLICY "Users can read assessment" ON public.sm_risk_assessment FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Users can read factors" ON public.sm_risk_factor FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Users can read controls" ON public.sm_risk_control FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Users can read issues" ON public.sm_risk_issue FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Users can read actions" ON public.sm_risk_action FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Users can read decisions" ON public.sm_risk_decision FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
