using Xunit;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>NV cũ chưa gắn chi nhánh được tính là của trụ sở khi lọc theo chi nhánh.</summary>
public class BranchQueryHelperTests
{
    static readonly Guid Hq = Guid.NewGuid();
    static readonly Guid BranchA = Guid.NewGuid();

    static IQueryable<Employee> Staff() => new List<Employee>
    {
        new() { Id = Guid.NewGuid(), FirstName = "Cũ", BranchId = null },
        new() { Id = Guid.NewGuid(), FirstName = "Trụ sở", BranchId = Hq },
        new() { Id = Guid.NewGuid(), FirstName = "Chi nhánh A", BranchId = BranchA },
    }.AsQueryable();

    [Fact]
    public void Loc_tru_so_gom_ca_nhan_vien_chua_gan_chi_nhanh()
    {
        var names = BranchQueryHelper.FilterByBranchIds(Staff(), [Hq], Hq).Select(e => e.FirstName).ToList();
        Assert.Equal(["Cũ", "Trụ sở"], names);
    }

    [Fact]
    public void Loc_chi_nhanh_khac_khong_gom_nhan_vien_chua_gan()
    {
        var names = BranchQueryHelper.FilterByBranchIds(Staff(), [BranchA], Hq).Select(e => e.FirstName).ToList();
        Assert.Equal(["Chi nhánh A"], names);
    }

    [Fact]
    public void Khong_biet_tru_so_thi_giu_hanh_vi_cu()
    {
        var names = BranchQueryHelper.FilterByBranchIds(Staff(), [Hq]).Select(e => e.FirstName).ToList();
        Assert.Equal(["Trụ sở"], names);
    }
}
