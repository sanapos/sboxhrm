using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.Communications.DeleteCommunication;

public class DeleteCommunicationHandler(
    IRepository<InternalCommunication> communicationRepository
) : ICommandHandler<DeleteCommunicationCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        DeleteCommunicationCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var communication = await communicationRepository.GetByIdAsync(request.Id, cancellationToken: cancellationToken);
            
            if (communication == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy bài truyền thông");
            }

            if (communication.StoreId != request.StoreId)
            {
                return AppResponse<bool>.Error("Bạn không có quyền xóa bài viết này");
            }

            await communicationRepository.DeleteAsync(communication, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi xóa bài truyền thông: {ex.Message}");
        }
    }
}
