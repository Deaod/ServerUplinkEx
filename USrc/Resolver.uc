class Resolver extends InternetLink;

var ServerUplinkEx Source;
var int MasterServerId;

function ResolveAddr(string Addr, ServerUplinkEx Src, int Id) {
	Source = Src;
	MasterServerId = Id;
	Resolve(Addr);
}

function Resolved(IpAddr Addr) {
	Source.ResolvedAddr(MasterServerId, Addr);
}

function ResolveFailed() {
	Source.ResolveAddrFailed(MasterServerId);
}
