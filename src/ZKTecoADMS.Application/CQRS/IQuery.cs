using MediatR;

namespace ZKTecoADMS.Application.CQRS;

public interface IQuery<out TResponse> : IRequest<TResponse> where TResponse : notnull
{
}