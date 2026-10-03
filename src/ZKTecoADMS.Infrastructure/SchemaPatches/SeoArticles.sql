-- Bài viết SEO công khai (/bai-viet) cho sboxhrm.com / sboxpos.com
CREATE TABLE IF NOT EXISTS "SeoArticles" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "Site" character varying(10) NOT NULL DEFAULT 'hrm',
    "Slug" character varying(200) NOT NULL,
    "Title" character varying(300) NOT NULL,
    "MetaTitle" character varying(300) NULL,
    "MetaDescription" character varying(500) NULL,
    "Keywords" character varying(500) NULL,
    "Summary" character varying(1000) NULL,
    "ContentMarkdown" text NOT NULL DEFAULT '',
    "CoverImageUrl" character varying(500) NULL,
    "Category" character varying(100) NULL,
    "AuthorName" character varying(200) NULL,
    "IsPublished" boolean NOT NULL DEFAULT false,
    "PublishedAt" timestamp without time zone NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "ViewCount" integer NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_SeoArticles_Site_Slug" ON "SeoArticles" ("Site", "Slug");
CREATE INDEX IF NOT EXISTS "IX_SeoArticles_Site_Published" ON "SeoArticles" ("Site", "IsPublished", "PublishedAt");

-- Loại trang: article (/bai-viet) · feature (/tinh-nang)
ALTER TABLE "SeoArticles" ADD COLUMN IF NOT EXISTS "PageType" character varying(20) NOT NULL DEFAULT 'article';
