/// Nội dung mặc định của 3 trang thông tin trong app (Markdown đơn giản: #, ##, ###, -, 1., **đậm**).
/// Dùng khi máy chủ chưa có nội dung riêng (hoặc còn bản mẫu cũ vài dòng). Superadmin vẫn sửa được
/// ở Quản trị hệ thống → Trang nội dung; bản đã sửa (đầy đủ) sẽ được ưu tiên.
///
/// Giữ khớp với trang công khai: /privacy-policy.html (HRM), /privacy-policy-pos.html, /terms-pos.html.
abstract final class AppLegalPages {
  static const updated = '05/10/2026';
  static const supportEmail = 'support@sboxhrm.com';
  static const hotline = '0973 024 042';

  static String? defaultFor(String type) => switch (type) {
        'privacy' => privacy,
        'terms' => terms,
        'help' => help,
        _ => null,
      };

  /// Bản mẫu cũ (vài dòng) hoặc trống → dùng nội dung mặc định.
  static bool isPlaceholder(String? content) {
    final c = (content ?? '').trim();
    if (c.isEmpty || c == '(Chưa có nội dung)' || c == 'Chưa có nội dung.') return true;
    return c.length < 700;
  }

  static const privacy = '''
# Chính sách bảo mật

Cập nhật lần cuối: $updated

SBOX («chúng tôi») cung cấp phần mềm quản lý nhân sự **SBOX HRM** và phần mềm bán hàng **SBOX POS** cho doanh nghiệp, cửa hàng. Chính sách này giải thích chúng tôi thu thập dữ liệu gì, dùng vào việc gì, chia sẻ với ai, lưu bao lâu và bạn có những quyền gì đối với dữ liệu của mình.

Chúng tôi xử lý dữ liệu cá nhân theo quy định của pháp luật Việt Nam về bảo vệ dữ liệu cá nhân (Nghị định 13/2023/NĐ-CP và các văn bản sửa đổi, thay thế).

## 1. Vai trò của các bên

- **Doanh nghiệp / cửa hàng** (bên đăng ký dịch vụ) quyết định dùng chức năng nào và quản lý tài khoản nhân viên — là **bên kiểm soát** dữ liệu của nhân viên, khách hàng của mình.
- **SBOX** lưu trữ và xử lý dữ liệu theo yêu cầu của doanh nghiệp — là **bên xử lý** dữ liệu.
- Nếu bạn là nhân viên, mọi yêu cầu về dữ liệu nhân sự (hồ sơ, chấm công, lương) nên gửi trước cho quản lý / bộ phận nhân sự của doanh nghiệp; SBOX hỗ trợ khi được yêu cầu.

## 2. Dữ liệu chúng tôi thu thập

### Tài khoản
- Họ tên, email, số điện thoại, mã cửa hàng, vai trò (nhân viên, quản lý, thu ngân, chủ cửa hàng).
- Mật khẩu được **băm một chiều** — không ai, kể cả SBOX, xem được mật khẩu gốc.

### Nhân sự (khi doanh nghiệp dùng SBOX HRM)
- Hồ sơ nhân viên, phòng ban, ca làm việc, giờ vào / ra, nghỉ phép, tăng ca, phiếu lương, tạm ứng.
- **Dữ liệu khuôn mặt**: chỉ khi bạn chủ động chấm công bằng khuôn mặt hoặc được quản lý đăng ký khuôn mặt — xem mục 4.
- **Vân tay / thẻ / khuôn mặt trên máy chấm công**: mẫu sinh trắc học nằm trên máy chấm công và được đồng bộ để quản lý người dùng trên máy.
- **Vị trí GPS**: chỉ tại thời điểm bạn bấm chấm công / check-in — xem mục 5.

### Bán hàng (khi cửa hàng dùng SBOX POS)
- Hàng hóa, tồn kho, hóa đơn, thanh toán, công nợ, đặt bàn, đơn online, khách hàng của cửa hàng (tên, số điện thoại, địa chỉ giao hàng).
- Khách đặt món qua **QR tại bàn / đơn online**: tên, số điện thoại, địa chỉ giao hàng do khách tự nhập để cửa hàng liên hệ và giao hàng.
- **Hội viên gym / spa**: khi cửa hàng đăng ký khách lên máy chấm công, hệ thống ghi lượt quét để tính lượt tập — tách riêng, không lẫn với chấm công nhân viên.

### Thiết bị
- Mã thông báo đẩy (để gửi thông báo), loại thiết bị, phiên bản ứng dụng, địa chỉ IP trong nhật ký thao tác.

## 3. Mục đích sử dụng

- Đăng nhập, phân quyền và bảo vệ tài khoản.
- Chấm công, tính công, nghỉ phép, tính lương, báo cáo nhân sự cho doanh nghiệp.
- Bán hàng, in hóa đơn / phiếu bếp, quản lý kho, khách hàng, giao hàng, hóa đơn điện tử, báo cáo kinh doanh.
- Gửi thông báo: đơn mới, duyệt đơn từ, lịch làm việc, nhắc việc.
- Ghi **nhật ký thao tác** (ai thêm / sửa / xóa gì, lúc nào) để chủ doanh nghiệp kiểm soát và tra cứu khi có sai sót.
- Hỗ trợ kỹ thuật khi bạn báo lỗi.

Chúng tôi **không** dùng dữ liệu của bạn để quảng cáo và **không bán** dữ liệu cá nhân.

## 4. Dữ liệu khuôn mặt

- Chỉ chụp khi bạn **chủ động** bấm Chấm công hoặc khi quản lý đăng ký khuôn mặt cho bạn.
- Dùng **duy nhất** để xác nhận đúng người khi chấm công. Ảnh chụp lúc chấm công không được giữ lại sau khi xác thực, trừ ảnh hiện trường khi chấm ngoài vị trí cho phép (giữ tối đa 30 ngày mặc định để quản lý đối chiếu, sau đó tự xóa).
- **Không chia sẻ** với bất kỳ bên thứ ba nào, kể cả dịch vụ trí tuệ nhân tạo.
- Bị **xóa vĩnh viễn** khi hồ sơ nhân viên hoặc đăng ký khuôn mặt bị xóa.
- Doanh nghiệp dùng chấm công khuôn mặt có trách nhiệm thông báo và có sự đồng ý của nhân viên trước khi đăng ký khuôn mặt.

## 5. Vị trí

- Chỉ lấy vị trí **tại thời điểm** bấm chấm công / check-in, hoặc khi bạn chủ động điền địa chỉ giao hàng.
- Ứng dụng **không theo dõi vị trí liên tục** và không truy cập vị trí khi chạy nền.

## 6. Quyền truy cập trên thiết bị

- **Camera**: chụp khuôn mặt khi chấm công, quét mã vạch, chụp ảnh hàng hóa — chỉ khi bạn chủ động dùng.
- **Micro**: chỉ khi bạn bấm nút micro trong Trợ lý AI; giọng nói được chuyển thành chữ bằng dịch vụ của hệ điều hành, ứng dụng không lưu bản ghi âm.
- **Vị trí**: như mục 5.
- **Bluetooth / mạng nội bộ**: kết nối máy in hóa đơn, máy in tem, màn hình bếp, máy chấm công.
- **Thư viện ảnh**: chọn ảnh sản phẩm, logo, đính kèm — khi bạn chủ động chọn.
- **Thông báo**: nhận thông báo đẩy.

Bạn có thể thu hồi từng quyền bất kỳ lúc nào trong phần Cài đặt của điện thoại; chức năng tương ứng sẽ tạm không dùng được.

## 7. Chia sẻ dữ liệu

Dữ liệu chỉ được chia sẻ khi cần để vận hành dịch vụ, hoặc khi doanh nghiệp / cửa hàng chủ động bật kết nối:

- **Firebase (Google)**: gửi thông báo đẩy.
- **Google Gemini**: khi bạn dùng Trợ lý AI — chỉ gửi nội dung câu hỏi và số liệu tổng hợp cần để trả lời. **Không** gửi mật khẩu, dữ liệu khuôn mặt, sinh trắc học hay thông tin thanh toán.
- **Đơn vị vận chuyển, cổng thanh toán, nhà cung cấp hóa đơn điện tử, ngân hàng (xác nhận chuyển khoản)**: chỉ những thông tin cần cho giao dịch đó, khi cửa hàng bật tính năng.
- **Cơ quan nhà nước có thẩm quyền**: khi pháp luật yêu cầu.

## 8. Lưu trữ và bảo mật

- Dữ liệu lưu trên máy chủ của SBOX đặt tại Việt Nam (sboxhrm.com, sboxpos.com).
- Mọi kết nối được mã hóa HTTPS / TLS; quyền xem dữ liệu theo vai trò; mỗi doanh nghiệp chỉ thấy dữ liệu của mình.
- Dữ liệu được sao lưu định kỳ.
- Dữ liệu nhân sự và bán hàng được lưu trong thời gian doanh nghiệp sử dụng dịch vụ và theo thời hạn lưu chứng từ, hóa đơn mà pháp luật kế toán, thuế yêu cầu.
- Nhật ký thao tác được lưu 30 ngày gần nhất.

## 9. Quyền của bạn

- **Xem và sửa** thông tin tài khoản trong ứng dụng; yêu cầu doanh nghiệp sửa hồ sơ nhân sự nếu sai.
- **Rút lại sự đồng ý** với chấm công khuôn mặt — liên hệ quản lý để xóa đăng ký khuôn mặt và dùng hình thức chấm công khác.
- **Thu hồi quyền** camera, vị trí, micro, thông báo trong Cài đặt điện thoại.
- **Xóa tài khoản** ngay trong ứng dụng: **Cài đặt → Xóa tài khoản** (nhập mật khẩu để xác nhận). Thông tin cá nhân được xóa hoặc ẩn danh; riêng chứng từ, hóa đơn phải lưu theo luật sẽ được giữ đến hết thời hạn.
- **Khiếu nại** về việc xử lý dữ liệu — liên hệ SBOX theo mục 11.

## 10. Trẻ em

Dịch vụ dành cho doanh nghiệp và người lao động, không dành cho trẻ em dưới 16 tuổi.

## 11. Liên hệ

- Email: **$supportEmail**
- Hotline / Zalo: **$hotline**
- Website: sboxhrm.com · sboxpos.com

Khi chính sách thay đổi, chúng tôi cập nhật ngày ở đầu trang và thông báo trong ứng dụng nếu thay đổi quan trọng.
''';

  static const terms = '''
# Điều khoản sử dụng

Có hiệu lực từ: $updated

Bằng việc đăng nhập và sử dụng ứng dụng SBOX (SBOX HRM, SBOX POS) trên điện thoại, máy tính bảng hoặc trình duyệt, bạn đồng ý với các điều khoản dưới đây.

## 1. Dịch vụ

- **SBOX HRM**: hồ sơ nhân sự, chấm công (máy chấm công, điện thoại, khuôn mặt, GPS), ca làm việc, nghỉ phép, tăng ca, tính lương, công việc, truyền thông nội bộ, báo cáo.
- **SBOX POS**: bán hàng tại quầy, gọi món QR tại bàn, đơn online, in hóa đơn / phiếu bếp, hàng hóa, bảng giá, kho, khách hàng, khuyến mãi, đặt bàn, giao hàng, hóa đơn điện tử, báo cáo kinh doanh.
- Chức năng hiển thị theo **gói dịch vụ** của doanh nghiệp và **quyền** được cấp cho tài khoản của bạn.

## 2. Tài khoản

- Chủ doanh nghiệp / cửa hàng đăng ký dịch vụ và cấp tài khoản cho nhân viên.
- Bạn chịu trách nhiệm giữ bí mật mật khẩu và mọi thao tác thực hiện bằng tài khoản của mình. Mọi thao tác thêm / sửa / xóa đều được ghi vào nhật ký thao tác.
- Khi nghi ngờ lộ mật khẩu, hãy đổi mật khẩu ngay và báo cho quản lý.
- Bạn có thể tự xóa tài khoản trong ứng dụng: **Cài đặt → Xóa tài khoản**.

## 3. Sử dụng hợp lệ

Bạn cam kết **không**:

- Dùng dịch vụ cho hoạt động trái pháp luật, bán hàng cấm, gian lận hóa đơn, thuế hoặc chấm công hộ.
- Can thiệp, dò quét, khai thác lỗi, truy cập trái phép dữ liệu của doanh nghiệp khác.
- Sao chép, dịch ngược, bán lại phần mềm khi chưa có thỏa thuận với SBOX.

## 4. Trách nhiệm của doanh nghiệp / cửa hàng

- Tính chính xác của giá bán, thuế, hóa đơn, bảng lương và thông tin nhập vào hệ thống.
- Thông báo và có sự đồng ý của nhân viên trước khi dùng chấm công khuôn mặt, GPS; có sự đồng ý của khách trước khi lưu thông tin cá nhân của khách.
- Phân quyền phù hợp cho nhân viên và thu hồi tài khoản khi nhân viên nghỉ việc.

## 5. Dữ liệu

- Dữ liệu nhân sự và bán hàng **thuộc về doanh nghiệp / cửa hàng**.
- SBOX xử lý dữ liệu theo **Chính sách bảo mật**, không bán dữ liệu cá nhân.
- Khi ngừng sử dụng dịch vụ, doanh nghiệp có thể yêu cầu xuất dữ liệu (Excel) trước khi tài khoản bị đóng.

## 6. Phí dịch vụ

- Một số chức năng thuộc gói trả phí theo bảng giá công bố trên website.
- Phí được thanh toán trực tiếp với SBOX theo hợp đồng / hóa đơn; ứng dụng không bán gói qua giao dịch trong ứng dụng.
- Hết hạn gói, một số chức năng có thể tạm khóa; dữ liệu vẫn được giữ trong thời gian gia hạn theo thỏa thuận.

## 7. Kết nối bên thứ ba

Đơn vị vận chuyển, cổng thanh toán, ngân hàng, nhà cung cấp hóa đơn điện tử, thiết bị chấm công, máy in… chỉ hoạt động khi doanh nghiệp bật và tuân theo điều khoản của bên thứ ba đó.

## 8. Giới hạn trách nhiệm

- Dịch vụ được cung cấp theo hiện trạng. SBOX nỗ lực duy trì hoạt động liên tục, sao lưu dữ liệu và khắc phục sự cố sớm nhất.
- SBOX không chịu trách nhiệm với thiệt hại gián tiếp do mất kết nối mạng, thiết bị của khách hàng hỏng, nhập sai dữ liệu hoặc sự cố của dịch vụ bên thứ ba.
- Số liệu báo cáo, bảng lương, thuế mang tính hỗ trợ; doanh nghiệp chịu trách nhiệm kiểm tra trước khi sử dụng chính thức.

## 9. Thay đổi điều khoản

Khi điều khoản thay đổi, chúng tôi cập nhật ngày hiệu lực ở đầu trang và thông báo trong ứng dụng nếu thay đổi quan trọng. Tiếp tục sử dụng sau ngày hiệu lực đồng nghĩa với việc bạn chấp nhận điều khoản mới.

## 10. Liên hệ

- Email: **$supportEmail**
- Hotline / Zalo: **$hotline**
''';

  static const help = '''
# Trợ giúp

Hướng dẫn nhanh các việc hay làm. Không tìm thấy câu trả lời? Gọi hotline **$hotline** (có Zalo) hoặc gửi **Báo lỗi & Góp ý** trong phần Thiết lập.

## Bắt đầu

- **Đăng nhập**: nhập mã cửa hàng (vd: sanapos), email hoặc số điện thoại và mật khẩu do quản lý cấp.
- **Quên mật khẩu**: ở màn đăng nhập bấm **Quên mật khẩu?** → nhận mã OTP → đặt mật khẩu mới.
- **Tìm chức năng nhanh**: trên máy tính bấm **Ctrl + K** rồi gõ tên chức năng (vd: nhập hàng, bảng lương). Trên điện thoại mở **Thêm** ở thanh dưới.
- **Thanh dưới điện thoại**: nhấn giữ thanh dưới để đổi các ô theo nhu cầu.
- **Nút thao tác**: trên điện thoại, các thao tác của trang (thêm mới, xuất Excel…) nằm ở **nút tròn góc dưới bên phải**.

## Chấm công & nghỉ phép

- **Chấm công bằng điện thoại**: mở **Chấm công** → bấm nút chấm → cho phép camera / vị trí khi được hỏi. Cần đứng trong phạm vi địa điểm làm việc.
- **Quên chấm / máy không ghi nhận**: gửi yêu cầu **Quên chấm công — bổ sung giờ vào/ra** để quản lý duyệt.
- **Xin nghỉ**: **Nghỉ phép → Tạo đơn**, chọn loại nghỉ, ngày, lý do. Theo dõi trạng thái ở tab chờ duyệt.
- **Xem phiếu lương**: mở **Phiếu lương** — xem chi tiết công, phụ cấp, khấu trừ từng tháng.
- **Máy chấm công**: quản lý thêm nhân viên lên máy và lấy vân tay / khuôn mặt ở phần **Máy chấm công**. Một số dòng máy cần lấy vân tay trực tiếp trên máy.

## Bán hàng (POS)

- **Bán tại quầy**: mở **Bán hàng** → chọn món (hoặc chọn bàn với nhà hàng) → **Thanh toán (F9)**.
- **Bảng giá**: tạo giá sỉ, giá VIP, giá khuyến mãi theo ngày ở **Trang chủ → POS → Bảng giá**. Khi bán, chọn bảng giá ở ô **Bảng giá**; bảng **Mặc định** tự áp cho hóa đơn mới, đơn QR và đơn online.
- **Voucher**: tạo mã giảm giá ở **POS → Voucher** (giảm % tối đa 100%, hoặc giảm số tiền).
- **Trả hàng**: **Trả hàng bán → Trả hàng mới**, chọn hóa đơn và số lượng trả.
- **Hủy hóa đơn / phiếu trả**: chỉ người có quyền; mọi lần hủy được ghi vào **Lịch sử hủy / trả**.

## Gọi món QR & đơn online

- **QR tại bàn**: in mã QR từng bàn ở **Menu QR / Online**. Khách quét mã để gọi món; món vào thẳng đơn của bàn.
- **Đơn online**: khách đặt qua đường link online của cửa hàng. Đơn đi qua các bước: Chờ xác nhận → Đang chuẩn bị → Đang giao → Giao thành công.
- **Thu tiền đơn online**: bấm **Thanh toán** trên đơn, hoặc chuyển sang **Giao thành công** — hệ thống tự ghi nhận thu tiền khi giao (COD), trừ kho và ghi sổ quỹ.

## Kho

- **Nhập hàng**: **Nhập hàng NCC → Tạo phiếu nhập**. Phiếu tạm chưa cộng kho; bấm **Hoàn thành** mới cộng.
- **Kiểm kho**: **Kiểm kho → Tạo phiếu kiểm**, nhập số đếm thực tế; hệ thống tính chênh lệch.
- **Kho chi nhánh / Chuyển kho**: xem tồn từng chi nhánh; bấm một mặt hàng để xem tồn ở mọi chi nhánh và tạo phiếu chuyển.

## Báo cáo

- **Báo cáo POS**: 23 báo cáo chia theo nhóm Bán hàng · Tài chính · Hàng hóa & kho · Nhân viên. Có ô tìm báo cáo.
- **Lịch sử thao tác**: ai thêm / sửa / xóa gì, lúc nào — lưu 30 ngày; bấm một dòng để xem trước / sau.
- **Xuất Excel**: dùng nút thao tác (góc dưới bên phải trên điện thoại).

## Máy in

- **Máy in hóa đơn / bếp**: **Thiết lập → Máy in**. Máy in mạng, Bluetooth hoặc máy in qua **SBOX Print Agent** trên máy tính Windows.
- **In không ra**: kiểm tra máy in bật, cùng mạng, còn giấy; với Print Agent, kiểm tra ứng dụng Agent đang chạy trên máy tính.

## Câu hỏi thường gặp

- **Không thấy một chức năng?** Chức năng hiển thị theo gói dịch vụ và quyền của tài khoản — liên hệ chủ cửa hàng / quản lý.
- **Số liệu báo cáo khác danh sách hóa đơn?** Kiểm tra cùng khoảng thời gian và bộ lọc trạng thái; báo cáo tính doanh thu sau khi trừ hàng trả.
- **Dữ liệu có an toàn không?** Dữ liệu lưu tại máy chủ ở Việt Nam, mã hóa khi truyền và sao lưu định kỳ — xem **Chính sách bảo mật**.

## Liên hệ hỗ trợ

- Hotline / Zalo: **$hotline**
- Email: **$supportEmail**
''';
}
