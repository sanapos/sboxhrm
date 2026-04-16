namespace ZKTecoADMS.Domain.Entities.Base;

public class Entity<T> : IEntity<T>
{
    public T Id { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.Now;

    public DateTime? UpdatedAt { get; set; }

    public string? UpdatedBy { get; set; }

    public string? CreatedBy { get; set; }

    public override bool Equals(object? obj)
    {
        if (obj is not IEntity<T> other)
            return false;

        if (ReferenceEquals(this, other))
            return false;

        if (Id.Equals(default) || other.Id.Equals(default))
            return false;

        return Id.Equals(other.Id);
    }

}
