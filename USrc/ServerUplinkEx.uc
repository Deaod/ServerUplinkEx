class ServerUplinkEx extends UdpLink
    config;

// Master Uplink Config.
struct MasterServerConfig {
    var() config string Address;       // Address of the master server
    var() config int    Port;          // Optional port that the master server is listening on
};
var() config array<MasterServerConfig> MasterServers;
var() config int                       UpdateMinutes; // Period of update (in minutes)

struct MasterServerData {
    var() Resolver Resolver;
    var() IpAddr   Address;
    var() int      CurrentQueryNum;
};
var() array<MasterServerData> MasterServersData;
var() name                    TargetQueryName;        // Name of the query server object to use.
var string                    HeartbeatMessage;       // The message that is sent to the master server.
var UdpServerQuery            Query;                  // The query object.

// Initialize.
function PreBeginPlay() {
    local int I;
    local int UplinkPort;

    // If master server uplink isn't wanted, exit.
    if (MasterServers.Length == 0) {
        Log("No Master Servers configured.  Not connecting to Master Server.");
        return;
    }

    foreach AllActors(class'UdpServerQuery', Query, TargetQueryName)
        break;

    if (Query == none) {
        Log("ServerUplinkEx: Could not find a UdpServerQuery object, aborting.");
        return;
    }

    // Precalculate heartbeat message now, since it will not change
    HeartbeatMessage = "\\heartbeat\\"$Query.Port$"\\gamename\\"$Query.GameName;

    MasterServersData.Insert(0, MasterServers.Length);

    for (I = 0; I < MasterServers.Length; ++i) {
        if (MasterServers[i].Address == "")
            continue;

        if (MasterServers[i].Port == 0) MasterServers[i].Port = 27900;

        MasterServersData[i].Resolver = Spawn(class'Resolver');
        MasterServersData[i].Address.Port = MasterServers[i].Port;
        MasterServersData[i].CurrentQueryNum = 1;

        MasterServersData[i].Resolver.ResolveAddr(MasterServers[i].Address, self, i);
    }

    // Bind the local port.
    UplinkPort = BindPort(Query.Port + 1, true);
    if (UplinkPort == 0) {
        Log( "ServerUplinkEx: Error binding port, aborting. ["$(Query.Port + 1)$"]" );
        return;
    }
    Log("ServerUplinkEx: Port "$UplinkPort$" successfully bound.");
}

function ResolvedAddr(int Id, IpAddr Addr) {
    if (Addr.Addr == 0) {
        Log("ServerUplinkEx: Invalid master server address, aborting.");
        return;
    }

    MasterServersData[Id].Address.Addr = Addr.Addr;

    Log("ServerUplinkEx: Master Server is "$MasterServersData[Id].Address.Addr$":"$MasterServersData[Id].Address.Port);

    SendHeartbeat(Id);
    if (TimerRate == 0)
        SetTimer(UpdateMinutes * 60 * Level.TimeDilation, true);
}

function ResolveAddrFailed(int Id) {
    Log("ServerUplinkEx: Failed to resolve master server address, aborting. ("$MasterServers[Id].Address$")");
}

function SendHeartbeat(int Id) {
    local bool Result;

    Result = SendText(MasterServersData[Id].Address, HeartbeatMessage);
    if (!Result)
        Log("Failed to send heartbeat to master server"@MasterServers[Id].Address$":"$MasterServers[Id].Port@".");
}

function Timer() {
    local int Id;

    for (Id = 0; Id < MasterServersData.Length; Id++)
        if (MasterServersData[Id].Address.Addr != 0)
            SendHeartbeat(Id);
}

function Halt() {
    SetTimer(0.0, false);
}

function int FindMasterServerId(IpAddr Addr) {
    local int Id;

    if (Addr.Addr == 0 || Addr.Port == 0)
        return -1;

    for (Id = 0; Id < MasterServersData.Length; Id++)
        if (MasterServersData[Id].Address.Addr == Addr.Addr /*&& MasterServersData[Id].Address.Port == Addr.Port*/)
            return Id;
    
    return -1;
}


// Received a query request.
event ReceivedText(IpAddr Addr, string Text) {
    local string Query;
    local int  QueryNum, PacketNum;
    local int  Id;

    Id = FindMasterServerId(Addr);
    if (Id == -1) {
        Log("ServerUplinkEx: Received query from unknown master server "$Addr.Addr$":"$Addr.Port);
        return;
    }

    // Assign this packet a unique value from 1 to 100
    MasterServersData[Id].CurrentQueryNum++;
    if (MasterServersData[Id].CurrentQueryNum > 100)
        MasterServersData[Id].CurrentQueryNum = 1;
    QueryNum = MasterServersData[Id].CurrentQueryNum;

    Query = Text;
    while (Query != "")
        Query = ParseQuery(Addr, Query, QueryNum, PacketNum);
}

function bool ParseNextQuery(string Query, out string QueryType, out string QueryValue, out string QueryRest, out string FinalPacket) {
    local string TempQuery;
    local int ClosingSlash;

    if (Query == "")
        return false;

    // Query should be:
    //   \[type]\<value>
    if (Left(Query, 1) == "\\") {
        // Check to see if closed.
        ClosingSlash = InStr(Right(Query, Len(Query)-1), "\\");
        if (ClosingSlash == 0)
            return false;

        TempQuery = Query;

        // Query looks like:
        //  \[type]\
        QueryType = Right(Query, Len(Query)-1);
        QueryType = Left(QueryType, ClosingSlash);

        QueryRest = Right(Query, Len(Query) - (Len(QueryType) + 2));

        if ((QueryRest == "") || (Len(QueryRest) == 1)) {
            FinalPacket = "final";
            return true;
        } else if (Left(QueryRest, 1) == "\\") {
            return true;    // \type\\
        }

        // Query looks like:
        //  \type\value
        ClosingSlash = InStr(QueryRest, "\\");
        if (ClosingSlash >= 0)
            QueryValue = Left(QueryRest, ClosingSlash);
        else
            QueryValue = QueryRest;

        QueryRest = Right(Query, Len(Query) - (Len(QueryType) + Len(QueryValue) + 3));
        if (QueryRest == "") {
            FinalPacket = "final";
            return true;
        } else {
            return true;
        }
    } else {
        return false;
    }
}

function string ParseQuery(IpAddr Addr, coerce string QueryStr, int QueryNum, out int PacketNum) {
    local string QueryType, QueryValue, QueryRest, ValidationString;
    local bool Result;
    local string FinalPacket;
    
    Result = ParseNextQuery(QueryStr, QueryType, QueryValue, QueryRest, FinalPacket);
    if( !Result )
        return "";

    if (QueryType == "basic") {
        // Ignore.
        Result = true;
    } else if (QueryType == "secure") {
        ValidationString = "\\validate\\"$Validate(QueryValue, Query.GameName);
        Result = SendQueryPacket(Addr, ValidationString, QueryNum, ++PacketNum, FinalPacket);
    }
    return QueryRest;
}

// SendQueryPacket is a wrapper for SendText that allows for packet numbering.
function bool SendQueryPacket(IpAddr Addr, coerce string SendString, int QueryNum, int PacketNum, string FinalPacket) {
    local bool Result;
    if (FinalPacket == "final") {
        SendString $= "\\final\\";
    }
    SendString $= "\\queryid\\"$QueryNum$"."$PacketNum;

    Result = SendText(Addr, SendString);

    return Result;
}

defaultproperties {
    UpdateMinutes=1
    TargetQueryName=MasterUplink
    RemoteRole=ROLE_None
}
