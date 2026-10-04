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
