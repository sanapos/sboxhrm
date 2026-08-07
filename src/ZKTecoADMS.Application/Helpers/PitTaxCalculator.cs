namespace ZKTecoADMS.Application.Helpers;

using ZKTecoADMS.Domain.Entities;

/// Biểu thuế TNCN lũy tiến — mặc định 5 bậc (Luật TNCN 2025, từ 2026).
public static class PitTaxCalculator
{
    public static decimal Calculate(TaxSetting settings, decimal taxableIncome)
    {
        if (taxableIncome <= 0) return 0;

        var caps = new[]
        {
            settings.TaxBracket1Max,
            settings.TaxBracket2Max,
            settings.TaxBracket3Max,
            settings.TaxBracket4Max,
            settings.TaxBracket5Max,
            settings.TaxBracket6Max
        };
        var rates = new[]
        {
            settings.TaxRate1,
            settings.TaxRate2,
            settings.TaxRate3,
            settings.TaxRate4,
            settings.TaxRate5,
            settings.TaxRate6,
            settings.TaxRate7
        };

        decimal prev = 0;
        decimal remaining = taxableIncome;
        decimal tax = 0;
        var rateIdx = 0;

        foreach (var cap in caps)
        {
            if (cap <= prev) continue;
            if (rateIdx >= rates.Length) break;
            var width = cap - prev;
            var amount = Math.Min(remaining, width);
            if (amount > 0)
            {
                tax += amount * rates[rateIdx] / 100m;
                remaining -= amount;
            }
            prev = cap;
            rateIdx++;
            if (remaining <= 0) return tax;
        }

        if (remaining > 0)
        {
            var topIdx = Math.Clamp(rateIdx, 0, rates.Length - 1);
            tax += remaining * rates[topIdx] / 100m;
        }

        return tax;
    }
}
