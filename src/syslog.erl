-module(syslog).
-author('tobbe@serc.rmit.edu.au').
%%%----------------------------------------------------------------------
%%% File    : syslog.erl
%%% Author  : Torbjorn Tornkvist <tobbe@serc.rmit.edu.au>
%%% Purpose : Interface to the Unix syslog facility.
%%% Created : 2 Dec 1998 by Torbjorn Tornkvist <tobbe@serc.rmit.edu.au>
%%% Function: See also the man page for syslog.conf
%%%
%%% Modified by Andrei Soroker On Wed Sep 30 2009
%%%           - It makes sense for syslog to be started by
%%%             a supervisor: rename start to start_link
%%%           - Added Host, Port init parameters
%%%           - Fixed priority/facility encoding logic
%%%
%%%           syslog:start_link()
%%%           syslog:stop()  
%%%           syslog:send(Program, Level, Msg)
%%%           syslog:send(Facility, Program, Level, Msg)
%%%
%%% Examples: syslog:send(my_ppp, syslog:debug(), "LCP link established")
%%%           syslog:send(syslog:mail(), my_mailer, syslog:err(), Msg)
%%%           syslog:send(17, my_service, syslog:info(), Msg) % 17 -> local1
%%%
%%%----------------------------------------------------------------------
%% Exported
-export([start_link/0, start_link/1, start_link/2, stop/0, version/0, send/3, send/4]).
-export([emergency/0, alert/0, critical/0, error/0, warning/0,
	 notice/0, info/0, debug/0]).
-export([kern/0, user/0, mail/0, daemon/0, auth/0, syslog/0, lpr/0,
	 news/0, uucp/0, cron/0, authpriv/0, ftp/0]).
%% Internal
-export([init/2]).

-define(SERVER_NAME, syslog_server).

version() -> "1.7".

start_link() -> 
    start_link(local_host(), syslog_port()).

start_link({Host, Port}) ->
    start_link(Host, Port);

start_link(Val) when is_integer(Val) ->
    start_link(local_host(), Val);

start_link(Val) when is_list(Val) ->
    {ok, InetName} = inet:getaddr(Val, inet),
    start_link(InetName, syslog_port()).

start_link(Host, Port) -> 
    case whereis(?SERVER_NAME) of
	    Pid when is_pid(Pid) ->
            {ok, Pid};
	    _ ->
	        Pid = spawn_link(?MODULE, init, [Host, Port]),
	        register(?SERVER_NAME, Pid),
            {ok, Pid}
    end.

stop() ->
    ?SERVER_NAME ! {self(), stop},
    receive stopped -> ok end.

send(Who, Level, Msg) when is_atom(Who), is_integer(Level) ->
    ?SERVER_NAME ! {send, {Who, Level, Msg}}.

send(Facility, Who, Level, Msg) 
  when is_integer(Facility), is_atom(Who), is_integer(Level) ->
    ?SERVER_NAME ! {send, {Facility, Who, Level, Msg}}.

%% Convenient routines for specifying levels.

emergency() -> 0. % system is unusable 
alert()     -> 1. % action must be taken immediately 
critical()  -> 2. % critical conditions 
error()     -> 3. % error conditions 
warning()   -> 4. % warning conditions 
notice()    -> 5. % normal but significant condition 
info()      -> 6. % informational
debug()     -> 7. % debug-level messages 

%% Convenient routines for specifying facility codes

kern()     -> (0 bsl 3) . % kernel messages 
user()     -> (1 bsl 3) . % random user-level messages 
mail()     -> (2 bsl 3) . % mail system 
daemon()   -> (3 bsl 3) . % system daemons 
auth()     -> (4 bsl 3) . % security/authorization messages 
syslog()   -> (5 bsl 3) . % messages generated internally by syslogd 
lpr()      -> (6 bsl 3) . % line printer subsystem 
news()     -> (7 bsl 3) . % network news subsystem 
uucp()     -> (8 bsl 3) . % UUCP subsystem 
cron()     -> (9 bsl 3) . % clock daemon 
authpriv() -> (10 bsl 3). % security/authorization messages (private) 
ftp()      -> (11 bsl 3). % ftp daemon 

	  
%% ----------
%% The server
%% ----------

init(Host, Port) ->
    process_flag(trap_exit, true),
    {ok, S} = gen_udp:open(0),
    loop(S, Host, Port).

loop(S, Host, Port) ->
    receive
	{send, What} ->
	    do_send(S, Host, Port, What),
	    loop(S, Host, Port);
	{From, stop} ->
	    From ! stopped;
	_ ->
	    loop(S, Host, Port)
    end.

%% priorities/facilities are encoded into a single 32-bit 
%% quantity, where the bottom 3 bits are the priority (0-7) 
%% and the top 28 bits are the facility (0-big number).    

do_send(S, Host, Port, {Who, Level, Msg}) ->
    % Packet = "<" ++ i2l(Level) ++ "> " ++ a2l(Who) ++ ": " ++ Msg ++ "\n",
    Packet = packet(Level, Who, Msg),
    gen_udp:send(S, Host, Port, Packet);
do_send(S, Host, Port, {Facil, Who, Level, Msg}) ->
    FacilLev = i2l((Facil bsl 3) bor Level),
    % Packet = "<" ++ FacilLev ++ "> " ++ a2l(Who) ++ ": " ++ Msg ++ "\n",
    Packet = packet(FacilLev, Who, Msg),
    gen_udp:send(S, Host, Port, Packet).

packet(Level, Who, Msg) when is_binary(Msg) ->
    iolist_to_binary([<<"<">>, Level, <<">">>, a2l(Who), <<": ">>, Msg, <<"\n">>]);
packet(Level, Who, Msg) when is_list(Msg) ->
    "<" ++ Level ++ "> " ++ a2l(Who) ++ ": " ++ Msg ++ "\n".

local_host() ->
    {ok, Hname} = inet:gethostname(),
    Hname.

syslog_port() -> 514.

i2l(Int) -> integer_to_list(Int).

a2l(Atom) -> atom_to_list(Atom).
