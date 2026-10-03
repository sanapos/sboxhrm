---
site: pos
slug: cach-tinh-gia-von-mon-an
title: Cách tính giá vốn món ăn, đồ uống và tỷ lệ food cost chuẩn
metaTitle: Cách tính giá vốn món ăn, đồ uống, food cost chuẩn
metaDescription: Hướng dẫn tính giá vốn từng món từ định lượng nguyên liệu, tỷ lệ food cost hợp lý cho quán cà phê, nhà hàng, cách định giá bán và tải bảng định lượng Excel miễn phí.
keywords: cách tính giá vốn món ăn, food cost, giá vốn đồ uống, định lượng món ăn, cách tính giá bán món ăn, công thức tính food cost, giá vốn ly cà phê
summary: Không biết giá vốn từng món thì không biết món nào thật sự có lãi. Bài viết hướng dẫn lập định lượng, tính giá vốn, tỷ lệ food cost tham khảo và cách định giá bán — kèm file Excel miễn phí.
category: Kinh nghiệm kinh doanh
cover: /images/landing/pos/pos-reports.jpg
sortOrder: 60
---
Rất nhiều quán đông khách nhưng cuối tháng không còn tiền. Một nguyên nhân phổ biến: **giá bán được đặt theo cảm tính** hoặc theo quán bên cạnh, trong khi giá vốn từng món chưa bao giờ được tính kỹ. Giá nguyên liệu tăng dần, lãi mỏng dần mà chủ quán không nhận ra.

**[Tải miễn phí bảng định lượng & giá vốn món Excel](/tai-lieu)**

## Giá vốn món là gì?

Giá vốn món (food cost / beverage cost) là **tổng chi phí nguyên liệu** để làm ra một phần ăn hoặc một ly đồ uống — gồm cả bao bì như ly, nắp, ống hút, hộp mang đi. Giá vốn chưa gồm tiền thuê mặt bằng, lương nhân viên, điện nước (những khoản này là chi phí vận hành).

## Bước 1 — Lập định lượng chuẩn cho từng món

Định lượng (recipe) ghi rõ từng nguyên liệu và **lượng dùng chính xác** cho một phần:

| Cà phê sữa đá | Lượng dùng |
|---|---|
| Cà phê bột | 25 g |
| Sữa đặc | 30 g |
| Đá viên | 200 g |
| Ly + nắp + ống hút | 1 bộ |

Định lượng phải được **cân, đong thực tế** khi pha chế, và nhân viên làm theo cùng một chuẩn.

## Bước 2 — Quy đổi giá nguyên liệu ra đơn vị dùng

Nguyên liệu mua theo kg, lon, hộp nhưng dùng theo gram, ml:

> Giá / đơn vị dùng = Giá mua ÷ Số đơn vị dùng trong một đơn vị mua

Ví dụ: cà phê bột 220.000 đ/kg → 220 đ/g. Sữa đặc 24.000 đ/lon 380 g → khoảng 63 đ/g.

## Bước 3 — Tính giá vốn món

> Giá vốn món = Σ (Lượng dùng × Giá / đơn vị dùng)

| Nguyên liệu | Lượng | Đơn giá | Thành tiền |
|---|---|---|---|
| Cà phê bột | 25 g | 220 đ | 5.500 đ |
| Sữa đặc | 30 g | 63 đ | 1.890 đ |
| Đá viên | 200 g | 1,5 đ | 300 đ |
| Ly + nắp + ống hút | 1 | 1.500 đ | 1.500 đ |
| **Giá vốn** | | | **9.190 đ** |

## Bước 4 — Tính tỷ lệ food cost

> Food cost % = Giá vốn ÷ Giá bán × 100%

Ly cà phê sữa đá bán 29.000 đ: 9.190 ÷ 29.000 ≈ **31,7%**.

### Tỷ lệ tham khảo

| Loại hình | Food cost thường gặp |
|---|---|
| Đồ uống pha chế (cà phê, trà) | 20 – 35% |
| Nhà hàng món Á | 30 – 40% |
| Lẩu, nướng | 35 – 45% |
| Bánh, tráng miệng | 20 – 30% |

Con số phù hợp còn tùy định vị, mặt bằng và chi phí nhân sự của bạn — quan trọng là **theo dõi đều đặn** và biết món nào vượt ngưỡng.

## Bước 5 — Định giá bán

> Giá bán tối thiểu = Giá vốn ÷ Food cost mục tiêu

Muốn food cost 30% cho món giá vốn 9.190 đ → giá bán ≥ 30.600 đ. Sau đó làm tròn theo thị trường và định vị của quán.

## Giá vốn lý thuyết và giá vốn thực tế

Giá vốn theo định lượng là **lý thuyết**. Giá vốn thực tế cao hơn do hao hụt, làm hỏng, nhân viên pha quá tay, nguyên liệu hết hạn. So sánh hai con số mỗi tháng qua [kiểm kê kho](/bai-viet/kiem-ke-kho-cuoi-thang) để tìm thất thoát.

## Tự động với phần mềm

Với [SBOX POS](/tinh-nang/phan-mem-quan-ly-quan-cafe), bạn khai báo định lượng một lần: mỗi món bán ra **tự trừ nguyên liệu trong kho**, giá vốn cập nhật theo giá nhập bình quân, báo cáo **lãi gộp theo món** có ngay mỗi ngày. Xem thêm [quản lý kho nguyên liệu](/tinh-nang/phan-mem-quan-ly-kho-hang).

[Đăng ký dùng thử SBOX POS miễn phí](/register) — không cần thẻ thanh toán, bán hàng thử ngay trên điện thoại, tablet hoặc máy POS; cần hỗ trợ cài đặt, gọi hoặc nhắn Zalo 0973 024 042.

## Câu hỏi thường gặp

### Food cost bao nhiêu là hợp lý?
Quán đồ uống thường ở mức 20–35%, nhà hàng 30–40%. Tỷ lệ phù hợp phụ thuộc mô hình, định vị giá và chi phí vận hành; quan trọng là theo dõi đều và kiểm soát món vượt ngưỡng.

### Giá vốn có tính ly, hộp, ống hút không?
Có. Bao bì dùng cho từng phần bán ra nên được tính vào giá vốn món, đặc biệt với đồ mang đi.

### Giá nguyên liệu thay đổi thì có phải tính lại không?
Có. Nên cập nhật giá nguyên liệu mỗi lần nhập hàng; phần mềm bán hàng có định lượng sẽ tự tính lại giá vốn theo giá nhập mới.
