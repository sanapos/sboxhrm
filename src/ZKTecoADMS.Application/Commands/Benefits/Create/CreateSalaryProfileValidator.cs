using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Benefits.Create;

public class CreateSalaryProfileValidator : AbstractValidator<CreateBenefitCommand>
{
    public CreateSalaryProfileValidator()
    {
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("Name is required")
            .MaximumLength(200).WithMessage("Name must not exceed 200 characters");

        RuleFor(x => x.Description)
            .MaximumLength(500).WithMessage("Description must not exceed 500 characters");

        RuleFor(x => x.RateType)
            .IsInEnum().WithMessage("Invalid rate type");

        RuleFor(x => x.Rate)
            .GreaterThan(0).WithMessage("Rate must be greater than 0");

        RuleFor(x => x.Currency)
            .NotEmpty().WithMessage("Currency is required")
            .MaximumLength(10).WithMessage("Currency must not exceed 10 characters");

        RuleFor(x => x.OvertimeMultiplier)
            .GreaterThanOrEqualTo(0).When(x => x.OvertimeMultiplier.HasValue)
            .WithMessage("Overtime multiplier must be greater than or equal to 0");

        RuleFor(x => x.HolidayMultiplier)
            .GreaterThanOrEqualTo(0).When(x => x.HolidayMultiplier.HasValue)
            .WithMessage("Holiday multiplier must be greater than or equal to 0");

        RuleFor(x => x.NightShiftMultiplier)
            .GreaterThanOrEqualTo(0).When(x => x.NightShiftMultiplier.HasValue)
            .WithMessage("Night shift multiplier must be greater than or equal to 0");
    }
}
