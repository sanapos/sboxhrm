using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.HrDocuments;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.HrDocuments.GetHrDocuments;

public class GetHrDocumentsHandler(
    IRepository<HrDocument> documentRepository
) : IQueryHandler<GetHrDocumentsQuery, AppResponse<PagedResult<HrDocumentDto>>>
{
    public async Task<AppResponse<PagedResult<HrDocumentDto>>> Handle(
        GetHrDocumentsQuery request,
        CancellationToken cancellationToken)
    {
        try
        {
            var today = DateTime.UtcNow.Date;
            var thirtyDaysFromNow = today.AddDays(30);

            var documents = await documentRepository.GetAllWithIncludeAsync(
                filter: d => d.StoreId == request.StoreId
                    && d.IsActive
                    && (!request.EmployeeUserId.HasValue || d.EmployeeUserId == request.EmployeeUserId.Value)
                    && (!request.DocumentType.HasValue || d.DocumentType == request.DocumentType.Value)
                    && (!request.ExpiredOnly.HasValue || !request.ExpiredOnly.Value || (d.ExpiryDate.HasValue && d.ExpiryDate.Value < today))
                    && (!request.ExpiringOnly.HasValue || !request.ExpiringOnly.Value || (d.ExpiryDate.HasValue && d.ExpiryDate.Value >= today && d.ExpiryDate.Value <= thirtyDaysFromNow))
                    && (string.IsNullOrEmpty(request.SearchTerm) || d.Name.Contains(request.SearchTerm) || (d.DocumentNumber != null && d.DocumentNumber.Contains(request.SearchTerm))),
                orderBy: q => q.OrderByDescending(d => d.CreatedAt),
                includes: q => q
                    .Include(d => d.EmployeeUser)
                        .ThenInclude(u => u!.Employee)
                    .Include(d => d.UploadedByUser)!,
                skip: (request.PaginationRequest.PageNumber - 1) * request.PaginationRequest.PageSize,
                take: request.PaginationRequest.PageSize,
                cancellationToken: cancellationToken);

            var totalCount = await documentRepository.CountAsync(
                filter: d => d.StoreId == request.StoreId
                    && d.IsActive
                    && (!request.EmployeeUserId.HasValue || d.EmployeeUserId == request.EmployeeUserId.Value)
                    && (!request.DocumentType.HasValue || d.DocumentType == request.DocumentType.Value)
                    && (!request.ExpiredOnly.HasValue || !request.ExpiredOnly.Value || (d.ExpiryDate.HasValue && d.ExpiryDate.Value < today))
                    && (!request.ExpiringOnly.HasValue || !request.ExpiringOnly.Value || (d.ExpiryDate.HasValue && d.ExpiryDate.Value >= today && d.ExpiryDate.Value <= thirtyDaysFromNow))
                    && (string.IsNullOrEmpty(request.SearchTerm) || d.Name.Contains(request.SearchTerm) || (d.DocumentNumber != null && d.DocumentNumber.Contains(request.SearchTerm))),
                cancellationToken: cancellationToken);

            var dtos = documents.Select(d =>
            {
                var isExpired = d.ExpiryDate.HasValue && d.ExpiryDate.Value < today;
                var daysUntilExpiry = d.ExpiryDate.HasValue ? (int)(d.ExpiryDate.Value - today).TotalDays : int.MaxValue;

                return new HrDocumentDto
                {
                    Id = d.Id,
                    StoreId = d.StoreId ?? Guid.Empty,
                    EmployeeUserId = d.EmployeeUserId,
                    EmployeeName = d.EmployeeUser != null
                        ? $"{d.EmployeeUser.LastName} {d.EmployeeUser.FirstName}"
                        : "N/A",
                    EmployeeCode = d.EmployeeUser?.Employee?.EmployeeCode ?? "N/A",
                    Name = d.Name,
                    Description = d.Description,
                    DocumentType = d.DocumentType,
                    DocumentTypeText = GetDocumentTypeText(d.DocumentType),
                    FilePath = d.FilePath,
                    FileName = d.FileName,
                    ContentType = d.ContentType,
                    FileSize = d.FileSize,
                    FileSizeText = FormatFileSize(d.FileSize),
                    EffectiveDate = d.EffectiveDate,
                    ExpiryDate = d.ExpiryDate,
                    IsExpired = isExpired,
                    DaysUntilExpiry = daysUntilExpiry,
                    DocumentNumber = d.DocumentNumber,
                    IssuedBy = d.IssuedBy,
                    Notes = d.Notes,
                    UploadedByUserId = d.UploadedByUserId,
                    UploadedByName = d.UploadedByUser != null
                        ? $"{d.UploadedByUser.LastName} {d.UploadedByUser.FirstName}"
                        : null,
                    CreatedAt = d.CreatedAt,
                    UpdatedAt = d.UpdatedAt
                };
            }).ToList();

            var pagedResult = new PagedResult<HrDocumentDto>(
                dtos,
                totalCount,
                request.PaginationRequest.PageNumber,
                request.PaginationRequest.PageSize);

            return AppResponse<PagedResult<HrDocumentDto>>.Success(pagedResult);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<HrDocumentDto>>.Error(
                $"Lỗi khi lấy danh sách tài liệu: {ex.Message}");
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

    private static string FormatFileSize(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024 * 1024) return $"{bytes / 1024.0:F1} KB";
        if (bytes < 1024 * 1024 * 1024) return $"{bytes / (1024.0 * 1024.0):F1} MB";
        return $"{bytes / (1024.0 * 1024.0 * 1024.0):F1} GB";
    }
}
