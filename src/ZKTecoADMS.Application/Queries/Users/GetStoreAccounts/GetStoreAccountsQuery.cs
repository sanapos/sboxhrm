using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Queries.Users.GetStoreAccounts;

public record GetStoreAccountsQuery(Guid StoreId) : IQuery<AppResponse<IEnumerable<AccountDto>>>;
