-- Migration 00002: Supplier Lifecycle Foundation

-- 1. Enums for requests and decisions
CREATE TYPE supplier_request_type AS ENUM (
    'Create_Supplier',
    'Submit_Onboarding',
    'Activate_Supplier',
    'Update_Profile',
    'Change_Bank_Account',
    'Suspend_Supplier',
    'Reinstate_Supplier',
    'Disqualify_Supplier',
    'Inactivate_Supplier'
);

CREATE TYPE supplier_request_status AS ENUM (
    'Draft',
    'Submitted',
    'In_Review',
    'Approved',
    'Rejected',
    'Withdrawn',
    'Completed',
    'Failed'
);

CREATE TYPE supplier_decision_type AS ENUM (
    'Approve',
    'Reject',
    'Return_For_Edit'
);

-- 2. Lifecycle Transition Rules
CREATE TABLE public.sm_lifecycle_transition_rule (
    id serial PRIMARY KEY,
    from_status global_lifecycle_status NOT NULL,
    to_status global_lifecycle_status NOT NULL,
    allowed_request_type supplier_request_type NOT NULL,
    required_role app_role_type, -- which role can approve this transition
    is_active boolean DEFAULT true,
    UNIQUE(from_status, to_status, allowed_request_type)
);

-- Seed basic transition rules
INSERT INTO public.sm_lifecycle_transition_rule (from_status, to_status, allowed_request_type, required_role) VALUES
    ('Candidate', 'Active', 'Activate_Supplier', 'Approver'),
    ('Candidate', 'Disqualified', 'Disqualify_Supplier', 'Approver'),
    ('Candidate', 'Onboarding', 'Submit_Onboarding', 'Supplier_Manager'),
    ('Onboarding', 'Pending_Review', 'Submit_Onboarding', 'Supplier_Manager'),
    ('Onboarding', 'Disqualified', 'Disqualify_Supplier', 'Approver'),
    ('Pending_Review', 'Active', 'Activate_Supplier', 'Approver'),
    ('Pending_Review', 'Disqualified', 'Disqualify_Supplier', 'Approver'),
    ('Pending_Review', 'Onboarding', 'Update_Profile', 'Supplier_Manager'),
    ('Active', 'Suspended', 'Suspend_Supplier', 'Approver'),
    ('Active', 'Inactive', 'Inactivate_Supplier', 'Approver'),
    ('Active', 'Disqualified', 'Disqualify_Supplier', 'Approver'),
    ('Suspended', 'Active', 'Reinstate_Supplier', 'Approver'),
    ('Suspended', 'Inactive', 'Inactivate_Supplier', 'Approver');

-- 3. Supplier Request Table
CREATE TABLE public.sm_supplier_request (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_no text UNIQUE NOT NULL, -- e.g., REQ-2026-0001
    supplier_id uuid REFERENCES public.vendor(id),
    request_type supplier_request_type NOT NULL,
    status supplier_request_status NOT NULL DEFAULT 'Draft',
    proposed_payload jsonb,
    submission_key text UNIQUE, -- for idempotency
    requested_by uuid REFERENCES auth.users(id),
    current_owner uuid REFERENCES auth.users(id), -- user or role id if we expand
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- RLS for Supplier Request
ALTER TABLE public.sm_supplier_request ENABLE ROW LEVEL SECURITY;
-- Buyers/Managers can see requests
CREATE POLICY "Internal users can see requests" ON public.sm_supplier_request FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid() AND role IN ('Viewer', 'Buyer', 'Supplier_Manager', 'Approver', 'Admin'))
);
-- Supplier can see their own requests
CREATE POLICY "Supplier users can see their own requests" ON public.sm_supplier_request FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_supplier_users WHERE user_id = auth.uid() AND supplier_id = sm_supplier_request.supplier_id)
);

-- 4. Supplier Request Decision Table
CREATE TABLE public.sm_supplier_request_decision (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id uuid REFERENCES public.sm_supplier_request(id) ON DELETE CASCADE,
    decision supplier_decision_type NOT NULL,
    reason text,
    decided_by uuid REFERENCES auth.users(id),
    decided_at timestamptz DEFAULT now(),
    approval_step integer DEFAULT 1
);

ALTER TABLE public.sm_supplier_request_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see decisions for requests they can see" ON public.sm_supplier_request_decision FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.sm_supplier_request WHERE id = request_id) -- Will reuse RLS of sm_supplier_request
);

-- 5. Supplier Lifecycle History
CREATE TABLE public.sm_supplier_lifecycle_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    from_status global_lifecycle_status NOT NULL,
    to_status global_lifecycle_status NOT NULL,
    effective_date timestamptz NOT NULL DEFAULT now(),
    request_id uuid REFERENCES public.sm_supplier_request(id),
    actor_id uuid REFERENCES auth.users(id),
    reason text,
    created_at timestamptz DEFAULT now()
);

ALTER TABLE public.sm_supplier_lifecycle_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see lifecycle history" ON public.sm_supplier_lifecycle_history FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);

-- 6. Supplier Change Snapshot
CREATE TABLE public.sm_supplier_change_snapshot (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    request_id uuid REFERENCES public.sm_supplier_request(id),
    before_json jsonb,
    after_json jsonb,
    changed_fields text[],
    created_at timestamptz DEFAULT now()
);

ALTER TABLE public.sm_supplier_change_snapshot ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see change snapshots" ON public.sm_supplier_change_snapshot FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid())
);
