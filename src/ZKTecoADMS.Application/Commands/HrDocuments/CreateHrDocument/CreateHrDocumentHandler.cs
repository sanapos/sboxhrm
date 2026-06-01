using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.HrDocuments.CreateHrDocument;

public class CreateHrDocumentHandler(
    IRepository<HrDocument> documentRepository,
    IRepository<Employee> employeeRepository
) : ICommandHandler<CreateHrDocumentCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(
        CreateHrDocumentCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var employeeUserId = request.EmployeeUserId;
            if (request.EmployeeId.HasValue)
            {
                var employee = await employeeRepository.GetSingleAsync(
                    e => e.Id == request.EmployeeId.Value && e.StoreId == request.StoreId && e.Deleted == null,
                    cancellationToken: cancellationToken);
                if (employee == null)
                    return AppResponse<Guid>.Error("Không tìm thấy nhân viên");
                if (!employee.ApplicationUserId.HasValue)
                    return AppResponse<Guid>.Error(
                        "Nhân viên chưa có tài khoản đăng nhập. Vui lòng tạo tài khoản trước khi ghi nhận khen thưởng/kỷ luật.");
                employeeUserId = employee.ApplicationUserId.Value;
            }
            else if (employeeUserId == Guid.Empty)
            {
                return AppResponse<Guid>.Error("Thiếu thông tin nhân viên (employeeId hoặc employeeUserId).");
            }

            var document = new HrDocument
            {
                Id = Guid.NewGuid(),
                StoreId = request.StoreId,
                EmployeeUserId = employeeUserId,
                Name = request.Name,
                Description = request.Description,
                DocumentType = request.DocumentType,
                FilePath = request.FilePath,
                FileName = request.FileName,
                ContentType = request.ContentType,
                FileSize = request.FileSize,
                EffectiveDate = request.EffectiveDate,
                ExpiryDate = request.ExpiryDate,
                DocumentNumber = request.DocumentNumber,
                IssuedBy = request.IssuedBy,
                Notes = request.Notes,
                UploadedByUserId = request.CurrentUserId,
                IsActive = true,
                CreatedAt = DateTime.UtcNow
            };

            await documentRepository.AddAsync(document, cancellationToken);

            return AppResponse<Guid>.Success(document.Id);
        }
        catch (Exception ex)
        {
            return AppResponse<Guid>.Error($"Lỗi khi tạo tài liệu: {ex.Message}");
        }
    }
}
