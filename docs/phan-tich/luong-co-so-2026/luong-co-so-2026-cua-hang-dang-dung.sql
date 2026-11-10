-- CHỈ ĐỌC, CHƯA CHẠY THỬ (máy không có psql) — chạy trên production khi người dùng đồng ý.

-- 1) Cửa hàng đang lưu mức trần nào
SELECT "BaseSalary", "MaxInsuranceSalary", COUNT(*) AS cua_hang
FROM "InsuranceSettings"
GROUP BY 1, 2
ORDER BY 3 DESC;

-- 2) Phiếu lương từ 07/2026 đã bị chặn ở trần cũ (BHXH NLĐ 8% × 46.800.000 = 3.744.000 đ)
--    Giả định cửa hàng dùng tỷ lệ mặc định 8%; đây chỉ là danh sách để xem, không sửa phiếu.
SELECT "StoreId", COUNT(*) AS phieu, COUNT(DISTINCT "EmployeeId") AS nhan_vien
FROM "Payslips"
WHERE ("Year" > 2026 OR ("Year" = 2026 AND "Month" >= 7))
  AND "SocialInsurance" = 3744000
GROUP BY 1
ORDER BY 2 DESC;
