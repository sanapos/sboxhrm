-- Index cho vòng claim của Print Agent.
-- Mỗi Agent poll 3s/lần với bộ lọc StoreId + Status=Queued + PrinterId IN (...)
-- + ExpiresAt. Hai index cũ chỉ có (StoreId,Status,CreatedAt) và
-- (PrinterId,Status) nên mỗi lượt claim vẫn quét mọi job Queued của cửa hàng.
-- CONCURRENTLY: chạy được trên DB đang bán hàng, không khóa bảng.

CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_PosPrintJobs_Claim"
    ON "PosPrintJobs" ("StoreId", "Status", "PrinterId", "ExpiresAt");

-- Heartbeat/agent-online tra theo cửa hàng + trạng thái, gọi mỗi lần enqueue.
CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_PosPrintAgents_Store_Online"
    ON "PosPrintAgents" ("StoreId", "IsOnline", "LastHeartbeatAt");
