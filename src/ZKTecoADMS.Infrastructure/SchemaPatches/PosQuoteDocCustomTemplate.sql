-- Mẫu riêng của từng chứng từ báo giá / hợp đồng (sửa toàn bộ lời văn, số liệu vẫn tự cập nhật)
ALTER TABLE "PosQuoteDocuments" ADD COLUMN IF NOT EXISTS "CustomTemplateHtml" text NULL;
ALTER TABLE "PosQuoteDocumentRevisions" ADD COLUMN IF NOT EXISTS "CustomTemplateHtml" text NULL;
