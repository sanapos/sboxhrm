using ZKTecoADMS.Application.DTOs.Settings;

namespace ZKTecoADMS.Application.Commands.Settings;

// Get or Create Penalty Settings Command (Singleton pattern per Store)
public record GetOrCreatePenaltySettingsCommand(Guid StoreId) : ICommand<AppResponse<PenaltySettingDto>>;

public class GetOrCreatePenaltySettingsHandler(
    IRepository<PenaltySetting> repository
) : ICommandHandler<GetOrCreatePenaltySettingsCommand, AppResponse<PenaltySettingDto>>
{
    public async Task<AppResponse<PenaltySettingDto>> Handle(GetOrCreatePenaltySettingsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                // Create default settings for this store
                settings = new PenaltySetting { StoreId = request.StoreId };
                settings = await repository.AddAsync(settings, cancellationToken);
            }
            
            return AppResponse<PenaltySettingDto>.Success(settings.Adapt<PenaltySettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<PenaltySettingDto>.Error(ex.Message);
        }
    }
}

// Update Penalty Settings Command
public record UpdatePenaltySettingsCommand(
    Guid StoreId,
    int LateMinutes1, decimal LatePenalty1,
    int LateMinutes2, decimal LatePenalty2,
    int LateMinutes3, decimal LatePenalty3,
    int EarlyMinutes1, decimal EarlyPenalty1,
    int EarlyMinutes2, decimal EarlyPenalty2,
    int EarlyMinutes3, decimal EarlyPenalty3,
    int RepeatCount1, decimal RepeatPenalty1,
    int RepeatCount2, decimal RepeatPenalty2,
    int RepeatCount3, decimal RepeatPenalty3,
    decimal ForgotCheckPenalty,
    decimal UnauthorizedLeavePenalty,
    decimal ViolationPenalty) : ICommand<AppResponse<PenaltySettingDto>>;

public class UpdatePenaltySettingsHandler(
    IRepository<PenaltySetting> repository
) : ICommandHandler<UpdatePenaltySettingsCommand, AppResponse<PenaltySettingDto>>
{
    public async Task<AppResponse<PenaltySettingDto>> Handle(UpdatePenaltySettingsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                settings = new PenaltySetting { StoreId = request.StoreId };
                settings = await repository.AddAsync(settings, cancellationToken);
            }

            settings.LateMinutes1 = request.LateMinutes1;
            settings.LatePenalty1 = request.LatePenalty1;
            settings.LateMinutes2 = request.LateMinutes2;
            settings.LatePenalty2 = request.LatePenalty2;
            settings.LateMinutes3 = request.LateMinutes3;
            settings.LatePenalty3 = request.LatePenalty3;
            settings.EarlyMinutes1 = request.EarlyMinutes1;
            settings.EarlyPenalty1 = request.EarlyPenalty1;
            settings.EarlyMinutes2 = request.EarlyMinutes2;
            settings.EarlyPenalty2 = request.EarlyPenalty2;
            settings.EarlyMinutes3 = request.EarlyMinutes3;
            settings.EarlyPenalty3 = request.EarlyPenalty3;
            settings.RepeatCount1 = request.RepeatCount1;
            settings.RepeatPenalty1 = request.RepeatPenalty1;
            settings.RepeatCount2 = request.RepeatCount2;
            settings.RepeatPenalty2 = request.RepeatPenalty2;
            settings.RepeatCount3 = request.RepeatCount3;
            settings.RepeatPenalty3 = request.RepeatPenalty3;
            settings.ForgotCheckPenalty = request.ForgotCheckPenalty;
            settings.UnauthorizedLeavePenalty = request.UnauthorizedLeavePenalty;
            settings.ViolationPenalty = request.ViolationPenalty;

            await repository.UpdateAsync(settings, cancellationToken);
            
            return AppResponse<PenaltySettingDto>.Success(settings.Adapt<PenaltySettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<PenaltySettingDto>.Error(ex.Message);
        }
    }
}

// Get or Create Insurance Settings Command
public record GetOrCreateInsuranceSettingsCommand(Guid StoreId) : ICommand<AppResponse<InsuranceSettingDto>>;

public class GetOrCreateInsuranceSettingsHandler(
    IRepository<InsuranceSetting> repository
) : ICommandHandler<GetOrCreateInsuranceSettingsCommand, AppResponse<InsuranceSettingDto>>
{
    public async Task<AppResponse<InsuranceSettingDto>> Handle(GetOrCreateInsuranceSettingsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                settings = new InsuranceSetting { StoreId = request.StoreId };
                settings = await repository.AddAsync(settings, cancellationToken);
            }
            
            return AppResponse<InsuranceSettingDto>.Success(settings.Adapt<InsuranceSettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<InsuranceSettingDto>.Error(ex.Message);
        }
    }
}

// Update Insurance Settings Command
public record UpdateInsuranceSettingsCommand(
    Guid StoreId,
    decimal BaseSalary,
    decimal MinSalaryRegion1,
    decimal MinSalaryRegion2,
    decimal MinSalaryRegion3,
    decimal MinSalaryRegion4,
    decimal MaxInsuranceSalary,
    decimal BhxhEmployeeRate, decimal BhxhEmployerRate,
    decimal BhytEmployeeRate, decimal BhytEmployerRate,
    decimal BhtnEmployeeRate, decimal BhtnEmployerRate,
    decimal UnionFeeEmployeeRate, decimal UnionFeeEmployerRate,
    int DefaultRegion) : ICommand<AppResponse<InsuranceSettingDto>>;

public class UpdateInsuranceSettingsHandler(
    IRepository<InsuranceSetting> repository
) : ICommandHandler<UpdateInsuranceSettingsCommand, AppResponse<InsuranceSettingDto>>
{
    public async Task<AppResponse<InsuranceSettingDto>> Handle(UpdateInsuranceSettingsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                settings = new InsuranceSetting { StoreId = request.StoreId };
                settings = await repository.AddAsync(settings, cancellationToken);
            }

            settings.BaseSalary = request.BaseSalary;
            settings.MinSalaryRegion1 = request.MinSalaryRegion1;
            settings.MinSalaryRegion2 = request.MinSalaryRegion2;
            settings.MinSalaryRegion3 = request.MinSalaryRegion3;
            settings.MinSalaryRegion4 = request.MinSalaryRegion4;
            settings.MaxInsuranceSalary = request.MaxInsuranceSalary;
            settings.BhxhEmployeeRate = request.BhxhEmployeeRate;
            settings.BhxhEmployerRate = request.BhxhEmployerRate;
            settings.BhytEmployeeRate = request.BhytEmployeeRate;
            settings.BhytEmployerRate = request.BhytEmployerRate;
            settings.BhtnEmployeeRate = request.BhtnEmployeeRate;
            settings.BhtnEmployerRate = request.BhtnEmployerRate;
            settings.UnionFeeEmployeeRate = request.UnionFeeEmployeeRate;
            settings.UnionFeeEmployerRate = request.UnionFeeEmployerRate;
            settings.DefaultRegion = request.DefaultRegion;

            await repository.UpdateAsync(settings, cancellationToken);
            
            return AppResponse<InsuranceSettingDto>.Success(settings.Adapt<InsuranceSettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<InsuranceSettingDto>.Error(ex.Message);
        }
    }
}

// Get or Create Tax Settings Command
public record GetOrCreateTaxSettingsCommand(Guid StoreId) : ICommand<AppResponse<TaxSettingDto>>;

public class GetOrCreateTaxSettingsHandler(
    IRepository<TaxSetting> repository
) : ICommandHandler<GetOrCreateTaxSettingsCommand, AppResponse<TaxSettingDto>>
{
    public async Task<AppResponse<TaxSettingDto>> Handle(GetOrCreateTaxSettingsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                settings = new TaxSetting { StoreId = request.StoreId };
                settings = await repository.AddAsync(settings, cancellationToken);
            }
            
            return AppResponse<TaxSettingDto>.Success(settings.Adapt<TaxSettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<TaxSettingDto>.Error(ex.Message);
        }
    }
}

// Update Tax Settings Command
public record UpdateTaxSettingsCommand(
    Guid StoreId,
    decimal PersonalDeduction,
    decimal DependentDeduction,
    decimal TaxBracket1Max, decimal TaxRate1,
    decimal TaxBracket2Max, decimal TaxRate2,
    decimal TaxBracket3Max, decimal TaxRate3,
    decimal TaxBracket4Max, decimal TaxRate4,
    decimal TaxBracket5Max, decimal TaxRate5,
    decimal TaxBracket6Max, decimal TaxRate6,
    decimal TaxRate7) : ICommand<AppResponse<TaxSettingDto>>;

public class UpdateTaxSettingsHandler(
    IRepository<TaxSetting> repository
) : ICommandHandler<UpdateTaxSettingsCommand, AppResponse<TaxSettingDto>>
{
    public async Task<AppResponse<TaxSettingDto>> Handle(UpdateTaxSettingsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Filter by StoreId for multi-tenant data isolation
            var settings = await repository.GetSingleAsync(
                s => s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (settings == null)
            {
                settings = new TaxSetting { StoreId = request.StoreId };
                settings = await repository.AddAsync(settings, cancellationToken);
            }

            settings.PersonalDeduction = request.PersonalDeduction;
            settings.DependentDeduction = request.DependentDeduction;
            settings.TaxBracket1Max = request.TaxBracket1Max;
            settings.TaxRate1 = request.TaxRate1;
            settings.TaxBracket2Max = request.TaxBracket2Max;
            settings.TaxRate2 = request.TaxRate2;
            settings.TaxBracket3Max = request.TaxBracket3Max;
            settings.TaxRate3 = request.TaxRate3;
            settings.TaxBracket4Max = request.TaxBracket4Max;
            settings.TaxRate4 = request.TaxRate4;
            settings.TaxBracket5Max = request.TaxBracket5Max;
            settings.TaxRate5 = request.TaxRate5;
            settings.TaxBracket6Max = request.TaxBracket6Max;
            settings.TaxRate6 = request.TaxRate6;
            settings.TaxRate7 = request.TaxRate7;

            await repository.UpdateAsync(settings, cancellationToken);
            
            return AppResponse<TaxSettingDto>.Success(settings.Adapt<TaxSettingDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<TaxSettingDto>.Error(ex.Message);
        }
    }
}
