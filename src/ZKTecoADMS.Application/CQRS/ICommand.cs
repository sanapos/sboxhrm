using MediatR;

namespace ZKTecoADMS.Application.CQRS;

public interface ICommand : ICommand<Unit>
{

}

public interface ICommand<out TResponse> : IRequest<TResponse>
{
}