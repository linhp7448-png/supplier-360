-- Migration 00013: Withdraw Request RPC

CREATE OR REPLACE FUNCTION public.sm_withdraw_supplier_request(
    p_request_id uuid,
    p_reason text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_request sm_supplier_request%ROWTYPE;
BEGIN
    SELECT * INTO v_request FROM sm_supplier_request WHERE id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Request not found';
    END IF;

    -- Only requester can withdraw
    IF v_request.requested_by != auth.uid() THEN
        RAISE EXCEPTION 'Only the requester can withdraw this request';
    END IF;

    -- Update request status to Withdrawn
    UPDATE sm_supplier_request SET status = 'Withdrawn', updated_at = now() WHERE id = p_request_id;
    
    RETURN true;
END;
$$;
