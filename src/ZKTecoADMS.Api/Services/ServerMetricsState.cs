namespace ZKTecoADMS.Api.Services;

public sealed class ServerMetricsState
{
    private volatile ServerMetricsSnapshot? _latest;
    public ServerMetricsSnapshot? Latest => _latest;
    public void Set(ServerMetricsSnapshot snapshot) => _latest = snapshot;
}
