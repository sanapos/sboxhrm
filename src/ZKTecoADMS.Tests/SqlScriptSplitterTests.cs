using Xunit;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Tests;

public class SqlScriptSplitterTests
{
    [Fact]
    public void Keeps_do_block_with_inner_semicolons_as_one_statement()
    {
        var sql = """
            ALTER TABLE "A" ADD COLUMN IF NOT EXISTS "X" int;
            DO $$
            BEGIN
                IF NOT EXISTS (SELECT 1) THEN
                    ALTER TABLE "B" ADD COLUMN "Y" int;
                    UPDATE "B" SET "Y" = 1;
                END IF;
            END $$;
            CREATE INDEX IF NOT EXISTS "IX" ON "A" ("X");
            """;

        var parts = SqlScriptSplitter.Split(sql);

        Assert.Equal(3, parts.Count);
        Assert.StartsWith("DO $$", parts[1]);
        Assert.EndsWith("END $$", parts[1]);
    }

    [Fact]
    public void Ignores_semicolons_in_strings_tagged_dollar_quotes_and_comments()
    {
        var sql = """
            -- comment; with semicolon
            INSERT INTO "T" ("V") VALUES ('a;b'), ('it''s;ok');
            /* block; comment */
            DO $body$ BEGIN PERFORM 1; END $body$;
            SELECT "col;name" FROM "T" WHERE "Id" = $1;
            """;

        var parts = SqlScriptSplitter.Split(sql);

        Assert.Equal(3, parts.Count);
        Assert.Contains("('it''s;ok')", parts[0]);
        Assert.DoesNotContain("comment", parts[0]);
        Assert.Equal("DO $body$ BEGIN PERFORM 1; END $body$", parts[1]);
        Assert.Contains("\"col;name\"", parts[2]);
    }

    [Fact]
    public void Complete_schema_patch_splits_do_block_intact()
    {
        using var stream = typeof(ZKTecoDbInitializer).Assembly
            .GetManifestResourceStream("ZKTecoADMS.Infrastructure.SchemaPatches.EnsureCompleteSchema.sql");
        Assert.NotNull(stream);
        var sql = new StreamReader(stream!).ReadToEnd();

        var parts = SqlScriptSplitter.Split(sql);

        var doBlocks = parts.Where(p => p.StartsWith("DO ")).ToList();
        Assert.NotEmpty(doBlocks);
        Assert.All(doBlocks, b => Assert.EndsWith("$$", b));
        // Không câu nào bắt đầu giữa khối DO (dấu hiệu bị cắt vỡ như trước).
        Assert.DoesNotContain(parts, p => p.StartsWith("END") || p.StartsWith("UPDATE \"PosProductComboLines\""));
    }
}
