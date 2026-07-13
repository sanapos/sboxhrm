-- Ensure BusinessTrip modules are in HRM/full packages (not POS-only).
UPDATE "ServicePackages" sp
SET "AllowedModules" = (
    SELECT COALESCE(jsonb_agg(to_jsonb(m) ORDER BY m), '[]'::jsonb)::text
    FROM (
        SELECT DISTINCT trim(both '"' from elem::text) AS m
        FROM jsonb_array_elements_text(sp."AllowedModules"::jsonb) AS elem
        UNION
        SELECT 'BusinessTripExpense'
        UNION
        SELECT 'BusinessTripReport'
    ) u
    WHERE m <> ''
)
WHERE sp."Name" <> 'Sbox POS'
  AND (
      sp."AllowedModules" NOT LIKE '%BusinessTripExpense%'
      OR sp."AllowedModules" NOT LIKE '%BusinessTripReport%'
  );
