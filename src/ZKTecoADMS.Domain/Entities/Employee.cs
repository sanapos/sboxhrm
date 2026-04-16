using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Employee : AuditableEntity<Guid>
{
    // 1. Thông tin định danh (Identity Information)
    [Required]
    [MaxLength(20)]
    public string EmployeeCode { get; set; } = string.Empty; // Mã nhân viên

    [Required]
    [MaxLength(100)]
    public string FirstName { get; set; } = string.Empty; // Họ

    [Required]
    [MaxLength(100)]
    public string LastName { get; set; } = string.Empty; // Tên

    [MaxLength(10)]
    public string? Gender { get; set; } // Giới tính

    public DateTime? DateOfBirth { get; set; } // Ngày sinh

    [MaxLength(500)]
    public string? PhotoUrl { get; set; } // Ảnh đại diện

    [MaxLength(50)]
    public string? NationalIdNumber { get; set; } // Số CCCD/CMND/Hộ chiếu

    public DateTime? NationalIdIssueDate { get; set; } // Ngày cấp

    [MaxLength(200)]
    public string? NationalIdIssuePlace { get; set; } // Nơi cấp

    // 2. Thông tin liên hệ (Contact Information)
    [MaxLength(20)]
    public string? PhoneNumber { get; set; } // Số điện thoại

    [MaxLength(200)]
    public string? PersonalEmail { get; set; } // Email cá nhân

    [MaxLength(200)]
    [Required]
    public string CompanyEmail { get; set; } = string.Empty; // Email công ty

    [MaxLength(500)]
    public string? PermanentAddress { get; set; } // Địa chỉ thường trú

    [MaxLength(500)]
    public string? TemporaryAddress { get; set; } // Địa chỉ tạm trú

    [MaxLength(200)]
    public string? EmergencyContactName { get; set; } // Người liên hệ khẩn cấp

    [MaxLength(20)]
    public string? EmergencyContactPhone { get; set; } // SĐT người liên hệ khẩn cấp

    [MaxLength(50)]
    public string? MaritalStatus { get; set; } // Tình trạng hôn nhân (Độc thân / Đã kết hôn / Ly hôn)

    [MaxLength(100)]
    public string? Hometown { get; set; } // Quê quán (tỉnh/thành phố)

    [MaxLength(100)]
    public string? EducationLevel { get; set; } // Trình độ học vấn

    // 3. Thông tin ngân hàng (Bank Information)
    [MaxLength(100)]
    public string? BankName { get; set; } // Tên ngân hàng

    [MaxLength(200)]
    public string? BankAccountName { get; set; } // Tên tài khoản ngân hàng

    [MaxLength(50)]
    public string? BankAccountNumber { get; set; } // Số tài khoản ngân hàng

    [MaxLength(50)]
    public string? BankBranch { get; set; } // Chi nhánh ngân hàng

    // 4. Ảnh CCCD
    [MaxLength(500)]
    public string? IdCardFrontUrl { get; set; } // Ảnh mặt trước CCCD

    [MaxLength(500)]
    public string? IdCardBackUrl { get; set; } // Ảnh mặt sau CCCD

    // 5. Thông tin công việc (Work Information)
    [MaxLength(100)]
    public string? Department { get; set; } // Phòng ban

    [MaxLength(100)]
    public string? Position { get; set; } // Chức danh

    [MaxLength(50)]
    public string? Level { get; set; } // Cấp bậc (Junior / Senior / Lead...)

    public DateTime? JoinDate { get; set; } // Ngày vào làm

    public DateTime? ProbationEndDate { get; set; } // Ngày hết thử việc

    public EmployeeWorkStatus WorkStatus { get; set; } // Trạng thái làm việc (Đang làm / Nghỉ phép / Nghỉ việc)
    
    public DateTime? ResignationDate { get; set; } // Ngày nghỉ việc

    [MaxLength(500)]
    public string? ResignationReason { get; set; } // Lý do nghỉ việc

    public EmploymentType EmploymentType { get; set; }

    public Guid? ApplicationUserId { get; set; }
    public virtual ApplicationUser? ApplicationUser { get; set; }

    public Guid? DirectManagerEmployeeId { get; set; }
    public virtual Employee? DirectManagerEmployee { get; set; }

    public Guid ManagerId {get;set; }
    public virtual ApplicationUser Manager {get;set; } = null!;
    
    /// <summary>
    /// Cửa hàng mà nhân viên thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Many-to-many relationship with Benefits through EmployeeBenefit
    public virtual ICollection<EmployeeBenefit> EmployeeBenefits { get; set; } = new List<EmployeeBenefit>();
    public virtual ICollection<Benefit> Benefits { get; set; } = new List<Benefit>();
    
    public virtual ICollection<DeviceUser> DeviceUsers { get; set; } = new List<DeviceUser>();
    
    public Guid? DepartmentId { get; set; }
    
    public Guid? BranchId { get; set; }
    public virtual Branch? Branch { get; set; }
}
