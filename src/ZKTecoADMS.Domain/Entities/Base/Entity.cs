namespace ZKTecoADMS.Domain.Entities.Base;

public class Entity<T> : IEntity<T>
{
    public T Id { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? UpdatedAt { get; set; }

    public string? UpdatedBy { get; set; }

    public string? CreatedBy { get; set; }

    public override bool Equals(object? obj)
    {
        if (obj is not IEntity<T> other)
            return false;

        // Cùng một object phải bằng nhau — trước đây trả false nên List.Remove / Contains / Dictionary
        // không tìm lại được chính entity đó (tách bàn / gộp bàn giữ tổng cũ, báo cáo hủy món bếp ra 0đ).
        if (ReferenceEquals(this, other))
            return true;

        if (Id.Equals(default) || other.Id.Equals(default))
            return false;

        return Id.Equals(other.Id);
    }

}
