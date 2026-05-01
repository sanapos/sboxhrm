SELECT "Id","StoreId","LateMinutes1","LatePenalty1","LateMinutes2","LatePenalty2","LateMinutes3","LatePenalty3",
       "EarlyMinutes1","EarlyPenalty1","RepeatCount1","RepeatPenalty1"
FROM "PenaltySettings"
WHERE "StoreId"='985262f9-7166-47c9-9edd-1847f620a3a2'::uuid;
