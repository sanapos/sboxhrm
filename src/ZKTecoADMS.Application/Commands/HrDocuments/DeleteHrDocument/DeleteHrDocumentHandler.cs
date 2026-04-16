using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.HrDocuments.DeleteHrDocument;

public class DeleteHrDocumentHandler(
    IRepository<HrDocument> documentRepository
) : ICommandHandler<DeleteHrDocumentCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        DeleteHrDocumentCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var document = await documentRepository.GetSingleAsync(
                filter: d => d.Id == request.DocumentId && d.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (document == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy tài liệu");
            }

            // Soft delete
            document.IsActive = false;
            document.UpdatedAt = DateTime.UtcNow;
            await documentRepository.UpdateAsync(document, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi xóa tài liệu: {ex.Message}");
        }
    }
}
