DO $$
DECLARE
    v_employee uuid := '02adc168-1ddb-4309-b06b-4e3e1c482241';
    v_store    uuid := '985262f9-7166-47c9-9edd-1847f620a3a2';
    v_attend   uuid := '5cbf6e4c-0351-4c84-83e7-b6fa00a8c610';
    v_user_id  uuid;
    v_now      timestamp := now();
    v_seq      int;
    v_code     varchar;
BEGIN
    SELECT "ApplicationUserId" INTO v_user_id FROM "Employees" WHERE "Id"=v_employee;

    IF EXISTS (SELECT 1 FROM "PenaltyTickets" WHERE "EmployeeId"=v_employee AND "ViolationDate"::date='2026-04-30' AND "Type"=0 AND "Status"<>3) THEN
        RAISE NOTICE 'Already exists, skipping.'; RETURN;
    END IF;

    SELECT COALESCE(count(*),0)+1 INTO v_seq FROM "PenaltyTickets" WHERE "StoreId"=v_store AND "ViolationDate"::date='2026-04-30';
    v_code := 'PP-20260430-' || lpad(v_seq::text, 4, '0');

    INSERT INTO "PenaltyTickets" (
        "Id","TicketCode","EmployeeId","Type","Status","Amount","ViolationDate",
        "MinutesLateOrEarly","ShiftStartTime","ShiftEndTime","ActualPunchTime",
        "PenaltyTier","RepeatCountInMonth","Description","AttendanceId","StoreId","CreatedAt","IsActive"
    ) VALUES (
        gen_random_uuid(), v_code, v_employee, 0, 0, 50000, '2026-04-30',
        15, '13:00:00', '17:00:00', '2026-04-30 13:15:00',
        1, NULL,
        'Đi trễ 15 phút (bậc 1: 50,000đ)',
        v_attend, v_store, v_now, true
    );

    INSERT INTO "PaymentTransactions" (
        "Id","EmployeeId","EmployeeUserId","Type","ForMonth","ForYear",
        "TransactionDate","Amount","Description","Status","Note","CreatedAt","IsActive"
    ) VALUES (
        gen_random_uuid(), v_employee, v_user_id, 'Penalty', 4, 2026,
        '2026-04-30', -50000, 'Đi trễ 15 phút (bậc 1: 50,000đ)',
        'Pending', 'Tự động tạo từ chấm công | Ca: 13:00-17:00 | Thực tế: 13:15',
        v_now, true
    );

    RAISE NOTICE 'Inserted %', v_code;
END $$;

SELECT "TicketCode","Type","Status","Amount","MinutesLateOrEarly","ViolationDate"
FROM "PenaltyTickets"
WHERE "EmployeeId"='02adc168-1ddb-4309-b06b-4e3e1c482241'::uuid
ORDER BY "ViolationDate";
