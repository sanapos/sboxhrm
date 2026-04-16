using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.HrDocuments.CreateHrDocument;

public class CreateHrDocumentHandler(
    IRepository<HrDocument> documentRepository
) : ICommandHandler<CreateHrDocumentCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(
        CreateHrDocumentCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var document = new HrDocument
            {
                Id = Guid.NewGuid(),
                StoreId = request.StoreId,
                EmployeeUserId = request.EmployeeUserId,
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
