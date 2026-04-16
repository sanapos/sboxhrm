using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.HrDocuments;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.HrDocuments.GetExpiringDocuments;

public class GetExpiringDocumentsHandler(
    IRepository<HrDocument> documentRepository
) : IQueryHandler<GetExpiringDocumentsQuery, AppResponse<List<ExpiringDocumentDto>>>
{
    public async Task<AppResponse<List<ExpiringDocumentDto>>> Handle(
        GetExpiringDocumentsQuery request,
        CancellationToken cancellationToken)
    {
        try
        {
            var today = DateTime.UtcNow.Date;
            var futureDate = today.AddDays(request.DaysAhead);

            var documents = await documentRepository.GetAllWithIncludeAsync(
                filter: d => d.StoreId == request.StoreId
                    && d.IsActive
                    && d.ExpiryDate.HasValue
                    && d.ExpiryDate.Value >= today
                    && d.ExpiryDate.Value <= futureDate,
                orderBy: q => q.OrderBy(d => d.ExpiryDate),
                includes: q => q
                    .Include(d => d.EmployeeUser)
                        .ThenInclude(u => u!.Employee)!,
                cancellationToken: cancellationToken);

            var dtos = documents.Select(d => new ExpiringDocumentDto
            {
                Id = d.Id,
                EmployeeUserId = d.EmployeeUserId,
                EmployeeName = d.EmployeeUser != null
                    ? $"{d.EmployeeUser.LastName} {d.EmployeeUser.FirstName}"
                    : "N/A",
                EmployeeCode = d.EmployeeUser?.Employee?.EmployeeCode ?? "N/A",
                DocumentName = d.Name,
                DocumentType = d.DocumentType,
                DocumentTypeText = GetDocumentTypeText(d.DocumentType),
                ExpiryDate = d.ExpiryDate!.Value,
                DaysUntilExpiry = (int)(d.ExpiryDate.Value - today).TotalDays
            }).ToList();

            return AppResponse<List<ExpiringDocumentDto>>.Success(dtos);
        }
        catch (Exception ex)
        {
            return AppResponse<List<ExpiringDocumentDto>>.Error(
                $"Lỗi khi lấy danh sách tài liệu sắp hết hạn: {ex.Message}");
        }
    }

    private static string GetDocumentTypeText(HrDocumentType type)
    {
        return type switch
        {
            HrDocumentType.Contract => "Hợp đồng lao động",
            HrDocumentType.IdCard => "CMND/CCCD",
            HrDocumentType.Certificate => "Bằng cấp/Chứng chỉ",
            HrDocumentType.Resume => "Sơ yếu lý lịch",
            HrDocumentType.HealthCertificate => "Giấy khám sức khỏe",
            HrDocumentType.Insurance => "Hồ sơ bảo hiểm",
            HrDocumentType.Appointment => "Quyết định bổ nhiệm",
            HrDocumentType.SalaryAdjustment => "Quyết định tăng lương",
            HrDocumentType.Discipline => "Quyết định kỷ luật",
            HrDocumentType.Award => "Giấy khen/Thưởng",
            HrDocumentType.Application => "Đơn xin việc",
            HrDocumentType.Handover => "Biên bản bàn giao",
            HrDocumentType.Other => "Khác",
            _ => "Không xác định"
        };
    }
}
