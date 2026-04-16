namespace ZKTecoADMS.Application.Commands.ShiftTemplates.DeleteShiftTemplate;

public record DeleteShiftTemplateCommand(Guid Id) : ICommand<AppResponse<bool>>;
