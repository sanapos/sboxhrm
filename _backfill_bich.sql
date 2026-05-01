-- Backfill PenaltyTicket + PaymentTransaction for Bích Liễu, 5/1/2026
-- Late by 28 minutes (07:58:31 vs Ca sáng 07:30:00) → tier 1 = 50,000 VND
DO $$
DECLARE
    v_employee uuid := '02adc168-1ddb-4309-b06b-4e3e1c482241';
    v_store    uuid := '985262f9-7166-47c9-9edd-1847f620a3a2';
    v_attend   uuid := '155e355c-ecc1-49e2-948f-609c81355aae';
    v_user_id  uuid;
    v_now      timestamp := now();
    v_ticket_seq int;
    v_ticket_code varchar;
BEGIN
    SELECT "ApplicationUserId" INTO v_user_id FROM "Employees" WHERE "Id"=v_employee;

    -- Skip if PenaltyTicket already exists
    IF EXISTS (SELECT 1 FROM "PenaltyTickets" WHERE "EmployeeId"=v_employee AND "ViolationDate"::date='2026-05-01' AND "Type"=0 AND "Status"<>3) THEN
        RAISE NOTICE 'PenaltyTicket already exists, skipping.';
        RETURN;
    END IF;

    SELECT COALESCE(count(*),0)+1 INTO v_ticket_seq FROM "PenaltyTickets" WHERE "StoreId"=v_store AND "ViolationDate"::date='2026-05-01';
    v_ticket_code := 'PP-20260501-' || lpad(v_ticket_seq::text, 4, '0');

    INSERT INTO "PenaltyTickets" (
        "Id","TicketCode","EmployeeId","Type","Status","Amount","ViolationDate",
        "MinutesLateOrEarly","ShiftStartTime","ShiftEndTime","ActualPunchTime",
        "PenaltyTier","RepeatCountInMonth","Description","AttendanceId","StoreId","CreatedAt","IsActive"
    ) VALUES (
        gen_random_uuid(), v_ticket_code, v_employee, 0, 0, 50000, '2026-05-01',
        28, '07:30:00', '11:30:00', '2026-05-01 07:58:31',
        1, NULL,
        'Đi trễ 28 phút (bậc 1: 50,000đ)',
        v_attend, v_store, v_now, true
    );

    -- Insert PaymentTransaction (Type='Penalty', Status='Pending')
    IF NOT EXISTS (
        SELECT 1 FROM "PaymentTransactions"
        WHERE "EmployeeId"=v_employee AND "TransactionDate"::date='2026-05-01'
          AND "Type"='Penalty' AND COALESCE("Description",'') LIKE 'Đi trễ%'
    ) THEN
        INSERT INTO "PaymentTransactions" (
            "Id","EmployeeId","EmployeeUserId","Type","ForMonth","ForYear",
            "TransactionDate","Amount","Description","Status","Note","CreatedAt","IsActive"
        ) VALUES (
            gen_random_uuid(), v_employee, v_user_id, 'Penalty', 5, 2026,
            '2026-05-01', -50000, 'Đi trễ 28 phút (bậc 1: 50,000đ)',
            'Pending', 'Tự động tạo từ chấm công | Ca: 07:30-11:30 | Thực tế: 07:58',
            v_now, true
        );
    END IF;

    RAISE NOTICE 'Inserted PenaltyTicket %', v_ticket_code;
END $$;

SELECT "TicketCode","EmployeeId","Type","Status","Amount","MinutesLateOrEarly","ViolationDate"
FROM "PenaltyTickets" WHERE "ViolationDate"::date='2026-05-01';
