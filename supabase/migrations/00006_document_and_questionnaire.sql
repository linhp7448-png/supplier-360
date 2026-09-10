-- Migration 00006: Phase 4 - Document & Questionnaire

-- 1. Documents
CREATE TYPE document_status AS ENUM (
    'Pending_Review',
    'Approved',
    'Rejected',
    'Expired'
);

CREATE TABLE public.sm_supplier_document (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    document_type text NOT NULL, -- e.g., 'Business_License', 'ISO_9001'
    document_number text,
    issuer text,
    valid_from timestamptz,
    valid_to timestamptz,
    storage_path text NOT NULL, -- Supabase Storage reference
    status document_status DEFAULT 'Pending_Review',
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 2. Questionnaire System
CREATE TYPE question_answer_type AS ENUM (
    'Text',
    'Yes_No',
    'Multiple_Choice',
    'Number',
    'Attachment'
);

CREATE TABLE public.sm_questionnaire_template (
    id serial PRIMARY KEY,
    title text NOT NULL,
    version integer NOT NULL DEFAULT 1,
    department_id varchar(50) REFERENCES public.sm_department(id), -- Nullable for global
    region_id varchar(50) REFERENCES public.sm_region(id),       -- Nullable for global
    category_id varchar(50) REFERENCES public.mdm_category(id),   -- Nullable for global
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    UNIQUE (title, version)
);

CREATE TABLE public.sm_questionnaire_question (
    id serial PRIMARY KEY,
    template_id integer REFERENCES public.sm_questionnaire_template(id) ON DELETE CASCADE,
    question_text text NOT NULL,
    answer_type question_answer_type NOT NULL,
    is_required boolean DEFAULT true,
    weight numeric DEFAULT 1, -- For scoring
    evidence_required boolean DEFAULT false,
    options jsonb, -- For multiple choice
    sort_order integer DEFAULT 0
);

CREATE TYPE questionnaire_status AS ENUM (
    'Assigned',
    'In_Progress',
    'Submitted',
    'Under_Review',
    'Approved',
    'Rejected'
);

CREATE TABLE public.sm_questionnaire_instance (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    template_id integer REFERENCES public.sm_questionnaire_template(id),
    status questionnaire_status DEFAULT 'Assigned',
    assigned_to uuid REFERENCES auth.users(id), -- specific supplier user or internal reviewer
    due_date timestamptz,
    submitted_at timestamptz,
    reviewer_id uuid REFERENCES auth.users(id),
    reviewed_at timestamptz,
    score numeric,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.sm_questionnaire_response (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    instance_id uuid REFERENCES public.sm_questionnaire_instance(id) ON DELETE CASCADE,
    question_id integer REFERENCES public.sm_questionnaire_question(id),
    answer_text text,
    answer_number numeric,
    answer_boolean boolean,
    attachment_path text,
    respondent_id uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now(),
    UNIQUE (instance_id, question_id)
);

-- RLS Policies
ALTER TABLE public.sm_supplier_document ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_questionnaire_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_questionnaire_question ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_questionnaire_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sm_questionnaire_response ENABLE ROW LEVEL SECURITY;

-- Allow internal users to view everything
CREATE POLICY "Internal view docs" ON public.sm_supplier_document FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Internal view templates" ON public.sm_questionnaire_template FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Internal view questions" ON public.sm_questionnaire_question FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Internal view instances" ON public.sm_questionnaire_instance FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));
CREATE POLICY "Internal view responses" ON public.sm_questionnaire_response FOR SELECT USING (EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid()));

-- Supplier Isolation
CREATE POLICY "Supplier view own docs" ON public.sm_supplier_document FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_supplier_users WHERE user_id = auth.uid() AND supplier_id = sm_supplier_document.supplier_id)
);
CREATE POLICY "Supplier view assigned instances" ON public.sm_questionnaire_instance FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_supplier_users WHERE user_id = auth.uid() AND supplier_id = sm_questionnaire_instance.supplier_id)
);
CREATE POLICY "Supplier view own responses" ON public.sm_questionnaire_response FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_supplier_users WHERE user_id = auth.uid() AND supplier_id = (SELECT supplier_id FROM public.sm_questionnaire_instance WHERE id = sm_questionnaire_response.instance_id))
);
