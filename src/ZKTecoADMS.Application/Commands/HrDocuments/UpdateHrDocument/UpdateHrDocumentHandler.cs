using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.HrDocuments.UpdateHrDocument;

public class UpdateHrDocumentHandler(
    IRepository<HrDocument> documentRepository
) : ICommandHandler<UpdateHrDocumentCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        UpdateHrDocumentCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var document = await documentRepository.GetSingleAsync(
                filter: d => d.Id == request.DocumentId && d.StoreId == request.StoreId && d.IsActive,
                cancellationToken: cancellationToken);

            if (document == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy tài liệu");
            }

            document.Name = request.Name;
            document.Description = request.Description;
            document.DocumentType = request.DocumentType;
            document.EffectiveDate = request.EffectiveDate;
            document.ExpiryDate = request.ExpiryDate;
            document.DocumentNumber = request.DocumentNumber;
            document.IssuedBy = request.IssuedBy;
            document.Notes = request.Notes;
            document.UpdatedAt = DateTime.UtcNow;

            await documentRepository.UpdateAsync(document, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi cập nhật tài liệu: {ex.Message}");
        }
    }
}
