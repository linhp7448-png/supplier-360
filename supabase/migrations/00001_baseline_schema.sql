-- Migration 00001: Baseline & Security Containment

-- 1. Create Enums for baseline
CREATE TYPE global_lifecycle_status AS ENUM (
    'Candidate',
    'Onboarding',
    'Pending_Review',
    'Active',
    'Suspended',
    'Inactive',
    'Disqualified'
);

-- Application roles for RLS
CREATE TYPE app_role_type AS ENUM (
    'Viewer',
    'Buyer',
    'Supplier_Manager',
    'Risk_Reviewer',
    'Accounting',
    'Approver',
    'Admin',
    'Supplier_User'
);

-- 2. Create User Role Mapping Table
CREATE TABLE public.app_user_roles (
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    role app_role_type NOT NULL,
    created_at timestamptz DEFAULT now(),
    PRIMARY KEY (user_id, role)
);

-- Enable RLS on app_user_roles
ALTER TABLE public.app_user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own roles" ON public.app_user_roles FOR SELECT USING (auth.uid() = user_id);
-- Admins can manage roles (using a function to check if current user is admin)
-- We will add complex RLS policies later.

-- 3. Create Vendor Table (Supplier Golden Record)
-- Note: As per instructions, keeping legacy fields like status, relationship, etc., for v1 compatibility.
CREATE TABLE public.vendor (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_name text NOT NULL,
    tax_code text,
    
    -- Legacy Fields (to be deprecated later)
    legacy_status text,
    legacy_relationship text,
    legacy_segment text,
    
    -- New Management Columns
    lifecycle_status global_lifecycle_status NOT NULL DEFAULT 'Candidate',
    row_version integer NOT NULL DEFAULT 1,
    data_owner_email text,
    last_approved_at timestamptz,
    last_approved_by uuid REFERENCES auth.users(id),
    source_system text,
    effective_from timestamptz,
    inactive_at timestamptz,
    
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Enable RLS on vendor table
ALTER TABLE public.vendor ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS Policies for Vendor Table
-- viewers can read active vendors
CREATE POLICY "Viewers can read active vendors" 
    ON public.vendor 
    FOR SELECT 
    USING (
        EXISTS (SELECT 1 FROM public.app_user_roles WHERE user_id = auth.uid() AND role IN ('Viewer', 'Buyer', 'Supplier_Manager', 'Approver', 'Admin'))
    );

-- Only backend processes / security definer RPCs can write to vendor table.
-- Direct DML from authenticated users must be revoked/blocked.
-- We do not create INSERT/UPDATE/DELETE policies for authenticated users here.
-- Operations will be done via Security Definer RPCs (Maker-Checker).

-- Trigger to automatically increment row_version
CREATE OR REPLACE FUNCTION increment_row_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.row_version = OLD.row_version + 1;
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_vendor_version
    BEFORE UPDATE ON public.vendor
    FOR EACH ROW
    EXECUTE FUNCTION increment_row_version();

-- 5. Create Supplier Portal Mapping (app_supplier) for RLS isolation
CREATE TABLE public.app_supplier_users (
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendor(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    PRIMARY KEY (user_id, supplier_id)
);

-- Enable RLS
ALTER TABLE public.app_supplier_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Supplier users can see their own mapping" ON public.app_supplier_users FOR SELECT USING (auth.uid() = user_id);

-- Supplier User RLS Policy for Vendor Table
CREATE POLICY "Supplier users can read own profile"
    ON public.vendor
    FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.app_supplier_users WHERE user_id = auth.uid() AND supplier_id = id)
    );
