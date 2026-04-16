namespace ZKTecoADMS.Domain.Entities.Base;

public interface IEntity<T>
{
    T Id { get; set; }

    DateTime CreatedAt { get; set; }

    string? CreatedBy { get; set; }

    DateTime? UpdatedAt { get; set; }

    string? UpdatedBy { get; set; }
}
