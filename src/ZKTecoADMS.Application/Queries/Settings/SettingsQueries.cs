using ZKTecoADMS.Application.DTOs.Settings;

namespace ZKTecoADMS.Application.Queries.Settings;

// Get Penalty Settings Query
public record GetPenaltySettingsQuery(Guid StoreId) : IQuery<AppResponse<PenaltySettingDto>>;

public class GetPenaltySettingsHandler(
    IRepository<PenaltySetting> repository
) : IQueryHandler<GetPenaltySettingsQuery, AppResponse<PenaltySettingDto>>
{
    public async Task<AppResponse<PenaltySettingDto>> Handle(GetPenaltySettingsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                // Return default settings
                settings = new PenaltySetting();
            }
            
            return AppResponse<PenaltySettingDto>.Success(settings.Adapt<PenaltySettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<PenaltySettingDto>.Error(ex.Message);
        }
    }
}

// Get Insurance Settings Query
public record GetInsuranceSettingsQuery(Guid StoreId) : IQuery<AppResponse<InsuranceSettingDto>>;

public class GetInsuranceSettingsHandler(
    IRepository<InsuranceSetting> repository
) : IQueryHandler<GetInsuranceSettingsQuery, AppResponse<InsuranceSettingDto>>
{
    public async Task<AppResponse<InsuranceSettingDto>> Handle(GetInsuranceSettingsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                // Return default settings
                settings = new InsuranceSetting();
            }
            
            return AppResponse<InsuranceSettingDto>.Success(settings.Adapt<InsuranceSettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<InsuranceSettingDto>.Error(ex.Message);
        }
    }
}

// Get Tax Settings Query
public record GetTaxSettingsQuery(Guid StoreId) : IQuery<AppResponse<TaxSettingDto>>;

public class GetTaxSettingsHandler(
    IRepository<TaxSetting> repository
) : IQueryHandler<GetTaxSettingsQuery, AppResponse<TaxSettingDto>>
{
    public async Task<AppResponse<TaxSettingDto>> Handle(GetTaxSettingsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                // Return default settings
                settings = new TaxSetting();
            }
            
            return AppResponse<TaxSettingDto>.Success(settings.Adapt<TaxSettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<TaxSettingDto>.Error(ex.Message);
        }
    }
}

// Calculate Tax Query
public record CalculateTaxQuery(
    Guid StoreId,
    decimal GrossIncome,
    decimal InsuranceSalary,
    int NumberOfDependents) : IQuery<AppResponse<TaxCalculationDto>>;

public class CalculateTaxHandler(
    IRepository<TaxSetting> taxRepository,
    IRepository<InsuranceSetting> insuranceRepository
) : IQueryHandler<CalculateTaxQuery, AppResponse<TaxCalculationDto>>
{
    public async Task<AppResponse<TaxCalculationDto>> Handle(CalculateTaxQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var taxSettings = await taxRepository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken) ?? new TaxSetting();
            var insuranceSettings = await insuranceRepository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken) ?? new InsuranceSetting();

            // Calculate insurance deductions
            var insuranceSalary = Math.Min(request.InsuranceSalary, insuranceSettings.MaxInsuranceSalary);
            var bhxh = insuranceSalary * insuranceSettings.BhxhEmployeeRate / 100;
            var bhyt = insuranceSalary * insuranceSettings.BhytEmployeeRate / 100;
            var bhtn = insuranceSalary * insuranceSettings.BhtnEmployeeRate / 100;
            var totalInsurance = bhxh + bhyt + bhtn;

            // Calculate deductions
            var personalDeduction = taxSettings.PersonalDeduction;
            var dependentDeduction = taxSettings.DependentDeduction * request.NumberOfDependents;
            
            // Calculate taxable income
            var taxableIncome = request.GrossIncome - totalInsurance - personalDeduction - dependentDeduction;
            taxableIncome = Math.Max(0, taxableIncome);

            // Calculate tax using progressive brackets
            var taxBrackets = new List<TaxBracketCalculationDto>();
            decimal totalTax = 0;
            decimal remainingIncome = taxableIncome;

            // Bracket 1
            var bracket1Amount = Math.Min(remainingIncome, taxSettings.TaxBracket1Max);
            if (bracket1Amount > 0)
            {
                var tax1 = bracket1Amount * taxSettings.TaxRate1 / 100;
                taxBrackets.Add(new TaxBracketCalculationDto { Level = 1, TaxRate = taxSettings.TaxRate1, TaxableAmount = bracket1Amount, TaxAmount = tax1 });
                totalTax += tax1;
                remainingIncome -= bracket1Amount;
            }

            // Bracket 2
            var bracket2Max = taxSettings.TaxBracket2Max - taxSettings.TaxBracket1Max;
            var bracket2Amount = Math.Min(remainingIncome, bracket2Max);
            if (bracket2Amount > 0)
            {
                var tax2 = bracket2Amount * taxSettings.TaxRate2 / 100;
                taxBrackets.Add(new TaxBracketCalculationDto { Level = 2, TaxRate = taxSettings.TaxRate2, TaxableAmount = bracket2Amount, TaxAmount = tax2 });
                totalTax += tax2;
                remainingIncome -= bracket2Amount;
            }

            // Continue for other brackets...
            
            var result = new TaxCalculationDto
            {
                GrossIncome = request.GrossIncome,
                TotalInsurance = totalInsurance,
                PersonalDeduction = personalDeduction,
                DependentDeduction = dependentDeduction,
                TaxableIncome = taxableIncome,
                TaxAmount = totalTax,
                NetIncome = request.GrossIncome - totalInsurance - totalTax,
                TaxBrackets = taxBrackets
            };

            return AppResponse<TaxCalculationDto>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<TaxCalculationDto>.Error(ex.Message);
        }
    }
}
