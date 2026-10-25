-- Create Feedbacks table
CREATE TABLE IF NOT EXISTS "Feedbacks" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "SenderEmployeeId" uuid,
    "IsAnonymous" boolean NOT NULL DEFAULT false,
    "RecipientEmployeeId" uuid,
    "Title" character varying(300) NOT NULL DEFAULT '',
    "Content" character varying(5000) NOT NULL DEFAULT '',
    "Category" character varying(50) NOT NULL DEFAULT 'General',
    "Status" character varying(30) NOT NULL DEFAULT 'Pending',
    "Response" character varying(5000),
    "RespondedByEmployeeId" uuid,
    "RespondedAt" timestamp without time zone,
    "StoreId" uuid,
    -- AuditableEntity fields
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    -- Entity fields
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_Feedbacks" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_Feedbacks_Employees_Sender" FOREIGN KEY ("SenderEmployeeId") REFERENCES "Employees"("Id"),
    CONSTRAINT "FK_Feedbacks_Employees_Recipient" FOREIGN KEY ("RecipientEmployeeId") REFERENCES "Employees"("Id"),
    CONSTRAINT "FK_Feedbacks_Employees_RespondedBy" FOREIGN KEY ("RespondedByEmployeeId") REFERENCES "Employees"("Id"),
    CONSTRAINT "FK_Feedbacks_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id")
);

CREATE INDEX IF NOT EXISTS "IX_Feedbacks_StoreId" ON "Feedbacks" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_Feedbacks_SenderEmployeeId" ON "Feedbacks" ("SenderEmployeeId");
CREATE INDEX IF NOT EXISTS "IX_Feedbacks_RecipientEmployeeId" ON "Feedbacks" ("RecipientEmployeeId");
CREATE INDEX IF NOT EXISTS "IX_Feedbacks_Status" ON "Feedbacks" ("Status");
CREATE INDEX IF NOT EXISTS "IX_Feedbacks_Deleted" ON "Feedbacks" ("Deleted");

-- Add Feedback permission module
INSERT INTO "Permissions" ("Id", "Module", "DisplayName", "Description", "SortOrder", "IsActive", "CreatedAt")
VALUES (gen_random_uuid(), 'Feedback', 'Phản ánh / Ý kiến', 'Phản ánh, góp ý ẩn danh hoặc công khai', 45, true, NOW())
ON CONFLICT DO NOTHING;
