-- Bổ sung 4 module POS tách riêng vào mọi gói đang có PosSell.
-- AllowedModules dạng JSON array: ["PosProducts","PosSell",...]
-- DbInitializer cũng patch lúc API boot; script này dùng khi cần chạy tay.

DO $$
DECLARE
  r RECORD;
  mods jsonb;
  addon text;
  addons text[] := ARRAY['PosCustomers','PosBooking','PosWarranty','PosCustomerDisplay'];
  changed boolean;
BEGIN
  FOR r IN SELECT "Id", "AllowedModules", "Name" FROM "ServicePackages" WHERE "IsActive" = true
  LOOP
    BEGIN
      mods := COALESCE(r."AllowedModules"::jsonb, '[]'::jsonb);
    EXCEPTION WHEN others THEN
      CONTINUE;
    END;

    IF jsonb_typeof(mods) <> 'array' THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(mods) e WHERE e = 'PosSell'
    ) THEN
      CONTINUE;
    END IF;

    changed := false;
    FOREACH addon IN ARRAY addons
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements_text(mods) e WHERE e = addon
      ) THEN
        mods := mods || jsonb_build_array(addon);
        changed := true;
      END IF;
    END LOOP;

    IF changed THEN
      UPDATE "ServicePackages"
      SET "AllowedModules" = mods::text,
          "UpdatedAt" = NOW(),
          "UpdatedBy" = 'System'
      WHERE "Id" = r."Id";
      RAISE NOTICE 'Patched package %', r."Name";
    END IF;
  END LOOP;
END $$;
