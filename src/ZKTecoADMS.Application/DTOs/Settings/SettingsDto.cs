namespace ZKTecoADMS.Application.DTOs.Settings;

// Penalty Settings DTOs - matching PenaltySetting Entity
public class PenaltySettingDto
{
    public Guid Id { get; set; }
    
    // Phạt đi trễ
    public int LateMinutes1 { get; set; }
    public decimal LatePenalty1 { get; set; }
    public int LateMinutes2 { get; set; }
    public decimal LatePenalty2 { get; set; }
    public int LateMinutes3 { get; set; }
    public decimal LatePenalty3 { get; set; }
    
    // Phạt về sớm
    public int EarlyMinutes1 { get; set; }
    public decimal EarlyPenalty1 { get; set; }
    public int EarlyMinutes2 { get; set; }
    public decimal EarlyPenalty2 { get; set; }
    public int EarlyMinutes3 { get; set; }
    public decimal EarlyPenalty3 { get; set; }
    
    // Phạt tái phạm
    public int RepeatCount1 { get; set; }
    public decimal RepeatPenalty1 { get; set; }
    public int RepeatCount2 { get; set; }
    public decimal RepeatPenalty2 { get; set; }
    public int RepeatCount3 { get; set; }
    public decimal RepeatPenalty3 { get; set; }
    
    // Phạt khác
    public decimal ForgotCheckPenalty { get; set; }
    public decimal UnauthorizedLeavePenalty { get; set; }
    public decimal ViolationPenalty { get; set; }
    
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class UpdatePenaltySettingDto
{
    public int LateMinutes1 { get; set; }
    public decimal LatePenalty1 { get; set; }
    public int LateMinutes2 { get; set; }
    public decimal LatePenalty2 { get; set; }
    public int LateMinutes3 { get; set; }
    public decimal LatePenalty3 { get; set; }
    
    public int EarlyMinutes1 { get; set; }
    public decimal EarlyPenalty1 { get; set; }
    public int EarlyMinutes2 { get; set; }
    public decimal EarlyPenalty2 { get; set; }
    public int EarlyMinutes3 { get; set; }
    public decimal EarlyPenalty3 { get; set; }
    
    // Phạt tái phạm
    public int RepeatCount1 { get; set; }
    public decimal RepeatPenalty1 { get; set; }
    public int RepeatCount2 { get; set; }
    public decimal RepeatPenalty2 { get; set; }
    public int RepeatCount3 { get; set; }
    public decimal RepeatPenalty3 { get; set; }
    
    // Phạt khác
    public decimal ForgotCheckPenalty { get; set; }
    public decimal UnauthorizedLeavePenalty { get; set; }
    public decimal ViolationPenalty { get; set; }
}

// Insurance Settings DTOs - matching InsuranceSetting Entity
public class InsuranceSettingDto
{
    public Guid Id { get; set; }
    
    public decimal BaseSalary { get; set; }
    public decimal MinSalaryRegion1 { get; set; }
    public decimal MinSalaryRegion2 { get; set; }
    public decimal MinSalaryRegion3 { get; set; }
    public decimal MinSalaryRegion4 { get; set; }
    public decimal MaxInsuranceSalary { get; set; }
    
    // BHXH
    public decimal BhxhEmployeeRate { get; set; }
    public decimal BhxhEmployerRate { get; set; }
    
    // BHYT
    public decimal BhytEmployeeRate { get; set; }
    public decimal BhytEmployerRate { get; set; }
    
    // BHTN
    public decimal BhtnEmployeeRate { get; set; }
    public decimal BhtnEmployerRate { get; set; }
    
    // Công đoàn
    public decimal UnionFeeEmployeeRate { get; set; }
    public decimal UnionFeeEmployerRate { get; set; }
    
    // Vùng áp dụng
    public int DefaultRegion { get; set; }
    
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class UpdateInsuranceSettingDto
{
    public decimal BaseSalary { get; set; }
    public decimal MinSalaryRegion1 { get; set; }
    public decimal MinSalaryRegion2 { get; set; }
    public decimal MinSalaryRegion3 { get; set; }
    public decimal MinSalaryRegion4 { get; set; }
    public decimal MaxInsuranceSalary { get; set; }
    
    public decimal BhxhEmployeeRate { get; set; }
    public decimal BhxhEmployerRate { get; set; }
    public decimal BhytEmployeeRate { get; set; }
    public decimal BhytEmployerRate { get; set; }
    public decimal BhtnEmployeeRate { get; set; }
    public decimal BhtnEmployerRate { get; set; }
    
    // Công đoàn
    public decimal UnionFeeEmployeeRate { get; set; }
    public decimal UnionFeeEmployerRate { get; set; }
    
    // Vùng áp dụng
    public int DefaultRegion { get; set; }
}

// Tax Settings DTOs - matching TaxSetting Entity
public class TaxSettingDto
{
    public Guid Id { get; set; }
    
    // Giảm trừ gia cảnh
    public decimal PersonalDeduction { get; set; }
    public decimal DependentDeduction { get; set; }
    
    // Biểu thuế lũy tiến 7 bậc
    public decimal TaxBracket1Max { get; set; }
    public decimal TaxRate1 { get; set; }
    public decimal TaxBracket2Max { get; set; }
    public decimal TaxRate2 { get; set; }
    public decimal TaxBracket3Max { get; set; }
    public decimal TaxRate3 { get; set; }
    public decimal TaxBracket4Max { get; set; }
    public decimal TaxRate4 { get; set; }
    public decimal TaxBracket5Max { get; set; }
    public decimal TaxRate5 { get; set; }
    public decimal TaxBracket6Max { get; set; }
    public decimal TaxRate6 { get; set; }
    public decimal TaxRate7 { get; set; }
    
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class UpdateTaxSettingDto
{
    public decimal PersonalDeduction { get; set; }
    public decimal DependentDeduction { get; set; }
    
    public decimal TaxBracket1Max { get; set; }
    public decimal TaxRate1 { get; set; }
    public decimal TaxBracket2Max { get; set; }
    public decimal TaxRate2 { get; set; }
    public decimal TaxBracket3Max { get; set; }
    public decimal TaxRate3 { get; set; }
    public decimal TaxBracket4Max { get; set; }
    public decimal TaxRate4 { get; set; }
    public decimal TaxBracket5Max { get; set; }
    public decimal TaxRate5 { get; set; }
    public decimal TaxBracket6Max { get; set; }
    public decimal TaxRate6 { get; set; }
    public decimal TaxRate7 { get; set; }
}

// Tax Calculation Summary DTO
public class TaxCalculationDto
{
    public decimal GrossIncome { get; set; }
    public decimal TotalInsurance { get; set; }
    public decimal PersonalDeduction { get; set; }
    public decimal DependentDeduction { get; set; }
    public decimal TaxableIncome { get; set; }
    public decimal TaxAmount { get; set; }
    public decimal NetIncome { get; set; }
    public List<TaxBracketCalculationDto> TaxBrackets { get; set; } = new();
}

public class TaxBracketCalculationDto
{
    public int Level { get; set; }
    public decimal TaxRate { get; set; }
    public decimal TaxableAmount { get; set; }
    public decimal TaxAmount { get; set; }
}

public class CalculateTaxDto
{
    public decimal GrossIncome { get; set; }
    public decimal InsuranceSalary { get; set; }
    public int NumberOfDependents { get; set; }
}
