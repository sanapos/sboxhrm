using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Query.SqlExpressions;
using ZKTecoADMS.Application.Helpers;

namespace ZKTecoADMS.Infrastructure;

/// <summary>Dịch <see cref="VnSearch.Fold"/> sang SQL: translate(lower(x), có dấu, không dấu).</summary>
public static class VnSearchEf
{
    public static void Register(ModelBuilder modelBuilder)
    {
        var has = typeof(VnSearch).GetMethod(nameof(VnSearch.Has), [typeof(string), typeof(string)])!;
        modelBuilder.HasDbFunction(has).HasTranslation(args =>
        {
            var text = args[0];
            var term = args[1];
            var tm = text.TypeMapping;
            SqlExpression Str(string v) => new SqlConstantExpression(Expression.Constant(v), tm);
            SqlExpression Fn(string n, params SqlExpression[] a) =>
                new SqlFunctionExpression(n, a, nullable: true, argumentsPropagateNullability: a.Select(_ => true), typeof(string), tm);
            var lower = Fn("lower", text);
            var folded = new SqlFunctionExpression(
                "translate",
                [lower, Str(VnSearch.From + VnSearch.Combining), Str(VnSearch.To)],
                nullable: true,
                argumentsPropagateNullability: [true, false, false],
                typeof(string),
                tm);
            // Thoát \ % _ trong từ khóa rồi bọc %…%
            var esc = Fn("replace", Fn("replace", Fn("replace", term, Str("\\"), Str("\\\\")), Str("%"), Str("\\%")), Str("_"), Str("\\_"));
            var pattern = new SqlBinaryExpression(ExpressionType.Add,
                new SqlBinaryExpression(ExpressionType.Add, Str("%"), esc, typeof(string), tm), Str("%"), typeof(string), tm)!;
            return new LikeExpression(folded, pattern, Str("\\"), null);
        });

        var method = typeof(VnSearch).GetMethod(nameof(VnSearch.Fold), [typeof(string)])!;
        modelBuilder.HasDbFunction(method).HasTranslation(args =>
        {
            var arg = args[0];
            var tm = arg.TypeMapping;
            var lower = new SqlFunctionExpression("lower", [arg], nullable: true, argumentsPropagateNullability: [true], typeof(string), tm);
            return new SqlFunctionExpression(
                "translate",
                [lower, new SqlConstantExpression(Expression.Constant(VnSearch.From + VnSearch.Combining), tm), new SqlConstantExpression(Expression.Constant(VnSearch.To), tm)],
                nullable: true,
                argumentsPropagateNullability: [true, false, false],
                typeof(string),
                tm);
        });
    }
}
