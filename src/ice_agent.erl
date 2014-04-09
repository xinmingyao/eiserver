%%%-------------------------------------------------------------------
%%% @author  <yaoxinming@gmail.com>
%%% @copyright (C) 2014, 
%%% @doc
%%%
%%% @end
%%% Created : 31 Mar 2014 by  <>
%%%-------------------------------------------------------------------
-module(ice_agent).
-behaviour(gen_server).
%% API
-export([start_link/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 
-include("eis_main.hrl").
-record(state, {server,fsm}).
-spec offer(Pid::pid(),#agent_info{})->{ok,sdp}|{error,address_used}.
offer(Pid,#agent_info{}=Info)->
	call(Pid,Info).
stop(_Pid)->
	ok.
call(Pid,Msg)->
    call(Pid,Msg,3000).
call(Pid,Msg,_TimeOut)->
    From = {make_ref(),self()},
    Pid!{'$agent',From,Msg}.
cast(Pid,Msg)->
    From = {make_ref(),self()},
    Pid!{'$agent',From,Msg}.
info(Pid,Msg)->
    From = {make_ref(),self()},
    Pid!{'$agent',From,Msg}.
info(Pid,Msg,Time)->
    From = {make_ref(),self()},
    erlang:send_after(Time,Pid,{'$agent',From,Msg}).
-define(AGENT_INIT,init).
-define(AGENT_GATHER,gather).
-define(AGENT_RUNNING,running).
-define(AGENT_CONN_CHECK,conn_check).
-define(AGENT_FAILED,failed).
-define(AGENT_COMPLETED,completed).
-define(Ta,30).
-compile([export_all]).
-record(stream,{sid,ip,port,user,pwd,cid}).
-record(check_info,{pair,sid,role,is_trigger=false,remote}).
-record(trigger,{pair,sid}).
-record(socket_info,{ip,port,type,streams=[]}).
-record(checklist_info,{sid,timer,state}).
-record(check_rto_info,{sid,timer,count,pair}).

-record(server, {
	  fsm::any(),
	  agent_state,
	  opts,
	  hosts,
	  rtcp,
	  turn_servers,
	  nominate_type,
	  client,
	  peer_media_info,
	  action::offer|answer,
	  role::controlling|controlled,
	  local_media_info,
	  ice_state
         }).

-define(ID,id).
-define(TXID,txid).
-define(CANDIDATE_ID,candidate_id).
-define(PAIR_ID,pair_id).
-define(GATHER_QUE,gather_que).
-define(TIE_BREAKER,tie_breaker).
-define(CHECK_LIST,check_list).
-define(VALIDE_LIST,valid_list).
-define(TRIGGER_QUE,trigger_que).
-define(TA_TIMER,ta_timer).
-define(SOCKET_DICT,socket_dict).
-define(HOST_SOCKET,host_socket).
-define(ACTIVE_CHECKLIST_TIMER,active_checklist_timer).
-define(CANDIDATES_LIST,candidate_ets).
-define(HOST_LIST,host_list).
-define(LOCAL,local).
-define(REMOTE,remote).
-define(LOCAL_SDP,sdp).
-define(DEFAULT,default).

%%re send time dict
-define(GATHER_RTO_DICT,gather_rto_dict).
-define(CHECK_RTO_DICT,check_rto_dict).
-define(STUN_REQ_TRANS,stun_req_trans).

-define(ROLE_CONTROLLING,controlling).
-define(ROLE_CONTROLLED,controlled).
-define(CANDIDATE_FROZEN,frozen).
-define(CANDIDATE_WAITING,waiting).
-define(CANDIDATE_IN_PROGRESS,'in-progress').
-define(CANDIDATE_FAILED,failed).
-define(CANDIDATE_SUCCEEDED,succeeded).
-define(CHECKLIST_ACTIVE,checklist_active).
-define(CHECKLIST_FROZEN,checklist_frozen).
-define(CHECKLIST_RUNNING,checklist_running).
-define(CHECKLIST_COMPLETED,checklist_completed).
-define(CHECKLIST_FAILED,checklist_failed).

-define(CHECKLIST_STATE_DICT,checklist_state_dict).




%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Opts]) ->
    
    Server=#server{opts=Opts,hosts=pcall(hosts,Opts),turn_servers=pcall(turn_servers,Opts)},
    {ok, #state{server=Server,fsm=?AGENT_INIT}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_info({'$agent',From,Msg}, #state{fsm=FSM,server=Server}=State) ->
    case FSM(From,Msg,Server) of
	nochange->
	    {noreply,State};
	{Server1,FSM}->
	    {noreply,State#state{fsm=FSM,server=Server1}}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
reply({To,Tag},Reply)->
    catch To ! {Tag,Reply}.


-spec rtcp_info(MediaInfo::sdp)->
		       no_rctp|rtcp|mux.
rtcp_info(MediaInfo)->
    mux.

?AGENT_INIT(From,{'action',Action,MediaInfo},#server{hosts=Ips}=Server) 
  when Action =:= offer orelse Action=:=answer->
    try 
	Streams = get_streams(MediaInfo),
	build_host(Ips,Streams,rtcp_info(MediaInfo)),
	info(self(),gather),
	{Server#server{action=Action,rtcp=rtcp_info(MediaInfo),client=From},?AGENT_GATHER}
    catch
	_:A->
	    reply(From,A),
	    nochange
    end.

?AGENT_GATHER(_From,{gather_rto,Id,{S,Ip,Port,Stun}},_Server)->
    {Timer,Count} = dict_find(?GATHER_RTO_DICT,Id),
    if Count >1 ->
	    %%stop and next candidate
	    info(self(),gather,?Ta),
	    ok;
	ture->
	    {ok,Timer} = timer:send_after(?Ta,self(),{'$agent',from,{gather_rto,Id,{S,Ip,Port,Stun}}}),
	    dict_store(?GATHER_RTO_DICT,Id,{Timer,Count+1}),
	    gen_udp:send(S,Ip,Port,Stun)
    end,
    nochange;
?AGENT_GATHER(_From,gather,#server{client=Client,turn_servers=TS}=Server)->
    Que = get(?GATHER_QUE),
    case Que of
	[] ->
	    prioritize(Server),
	    reply(Client,{ok,sdp,get(?LOCAL_SDP)}),
	    {Server,?AGENT_RUNNING};
	[{#candidate{socket=S}}=Candidate|Tail] ->
	    %%todo maybe use multi turn server
	    Ts = lists:nth(1,TS),
	    #turn_server{ip=Ip,port=Port}= Ts,
	    Id = increment(?TXID),
	    dict_store(?STUN_REQ_TRANS,Id,Candidate#candidate{server=Ts}),
	    Req = #stun{
	      class = request,
	      method = binding,
	      transactionid = Id,
	      attrs = [
		      ]
	     },
	    Stun = stun:encode(Req),
	    gen_udp:send(S,Ip,Port,Stun),
	    {ok,Timer} = timer:send_after(?Ta,self(),{'$agent',from,{gather_rto,Id,{S,Ip,Port,Stun}}}),
	    dict_store(?GATHER_RTO_DICT,Id,{Timer,1}),
	    put(?GATHER_QUE,Tail),
	    info(self(),gather,?Ta),
	    nochange
    end;
?AGENT_GATHER(_From,#stun{class=success,attrs=Attrs,transactionid=TxId},_Server) ->
    case dict_find(?STUN_REQ_TRANS,TxId) of
	{ok,Host}->	    
	    {Timer,_Count} = dict_find(?GATHER_RTO_DICT,TxId),
	    timer:cancel(Timer),
	    %%#ice_addr{ip=Ip,port=Port} = Host#candidate.addr,
	    {MapIp,MapPort} = proplists:get_value('XOR-MAPPED-ADDRESS',Attrs),
	    %%todo 
	    %%{ok,MapIp1}=inet_parse:address(MapIp),
	    {T1,T2,T3,T4}=MapIp,
	    MapIp1 = integer_to_list(T1)++"," ++integer_to_list(T2)++integer_to_list(T3)++integer_to_list(T4),
	    Addr = #ice_addr{ip=MapIp1,port=MapPort},
	    C1 = #candidate{
	      type = ?CANDIDATE_TYPE_SEVER_REFLEXIVE,
	      transport = udp,
	      addr = Addr,
	      base_addr = Host#candidate.addr,
	      cid = Host#candidate.cid,
	      sid = Host#candidate.sid
	     },
	    list_head(?CANDIDATES_LIST,C1);
	_->
	    flush
    end,
    nochange.

?AGENT_RUNNING(From,{set_sdp,PeerSdp},Server) ->
    Role = determing_role(Server,PeerSdp),
    New = Server#server{role=Role,client=From,peer_media_info=PeerSdp},
    forming_check_list(New,PeerSdp),
    {New,?AGENT_RUNNING};

%%5.8	
?AGENT_RUNNING(_From,{check_rto,Sid,Socket,Ip,Port,Stun},#server{client=Client,nominate_type=_Type}=Server) ->
    {ok,#check_rto_info{pair=Pair,timer=Ref,count=Count}=Info}=dict_find(?CHECK_RTO_DICT,Sid),
    if Count >=2 ->
	    Id = Pair#checkpair.id,
	    update_checklist_state(Sid,Id,?CANDIDATE_FAILED),
	    timer:cancel(Ref),
	    case do_check_false() of
		true->
		    reply(Client,{false,check_failed});
		_->
		    ok
	    end,
	    {Server,?AGENT_FAILED};
       true->
	    gen_udp:send(Socket,Ip,Port,Stun),   
	    dict_store(?CHECK_RTO_DICT,Sid,Info#check_rto_info{count=Count+1})
    end,
    nochange
    ;
?AGENT_RUNNING(_From,{check,Id},#server{nominate_type=_Type}=Server) ->
    
    Q = get(?TRIGGER_QUE),
    case Q of
	[]->
	    order_check(Server,Id);
	[_H|_T]->
	    trigger_check(Server,Id)
    end,
    nochange;

%%failure todo add stun error 7.1.3.1
?AGENT_RUNNING(_From
	       ,{udp,_Socket,_PeerIp,_PeerPort,#stun{class = error,attrs=_Attrs,transactionid=TxId}}
	       ,Server) ->
    case dict_find(?STUN_REQ_TRANS,TxId) of
	error->
	    nochange;
	{ok,#check_info{sid=ListId,pair=Pair,role=Role}}->
	    #checkpair{id=Id}=Pair,
	    %%7.1.3.1
	    %% change_checklist_priority,
	    L = get(?CHECK_LIST),
	    L2 = lists:map(fun({T1,T2})->
				   {T1,order_pair(T2,not_role(Role))} end ,L),
	    put(?CHECK_LIST,L2),
	    update_checklist_state(ListId,Id,?CANDIDATE_WAITING),
	    L1 =get(?TRIGGER_QUE),
	    put(?TRIGGER_QUE,L1++[#trigger{pair=Pair,sid=ListId}]),
	    {Server#server{role=not_role(Role)},?AGENT_RUNNING}
    end;
?AGENT_RUNNING(_From
	       ,{udp,_Socket,PeerIp,PeerPort,#stun{class = success,attrs=Attrs,transactionid=TxId}}
	       ,#server{client=Client}=Server) ->
    case dict_find(?STUN_REQ_TRANS,TxId) of
	error->
	    nochange;
	{ok,#check_info{pair=#checkpair{id=Id,local =Local,remote=Remote,
					fid=Fid,sid=Sid,cid=Cid,is_nominated=Nominated
				       }=Pair,is_trigger=_Trigger}}->
	    
	    %%7.1.3.2
	    #ice_addr{ip=PeerIp,port=PeerPort}=Remote#candidate.addr,
	    #ice_addr{ip=LocalIp,port=LocalPort}=Local#candidate.addr,
	    {Ip1,PeerFlexPort} = proplists:get_value('XOR-PEER-ADDRESS',Attrs),
	    {ok,PeerFlexIp}= inet_parse:address(Ip1),
	    ValidPair = 
	    case {LocalIp,LocalPort} of
		{PeerFlexIp,PeerFlexPort} ->
		    Pair;
		_-> 
		    #candidate{base_addr=Base} = Local,
		    NewAddr = #ice_addr{ip=PeerFlexIp,port=PeerFlexPort},
		    Priority = proplists:get_value('PRIORITY',Attrs),
		    %%todo add foundation
		    C1 = #candidate{
		      fid = Fid,
		      priority = Priority,
		      type = ?CANDIDATE_TYPE_PEER_REFLEXIVE,
		      transport = udp,
		      addr = NewAddr,
		      base_addr = Base,
		      socket = Local#candidate.socket,
		      cid = Cid,
		      sid = Sid,
		      user=Local#candidate.user,
		      pwd=Local#candidate.pwd
		     },
		    list_head(?CANDIDATES_LIST,C1),
		    P2 = #checkpair{sid=Sid,is_nominated=Nominated,local=C1,remote=Remote,fid=Fid,cid=Cid},
		    P2
	    end,
	    case dict_find(?VALIDE_LIST,Sid) of
		error->
		    dict_store(?VALIDE_LIST,Sid,ValidPair);
		{ok,V1}->
		    dict_store(?VALIDE_LIST,Sid,[ValidPair|V1])
	    end,
	    update_checklist_state(Sid,Id,?CANDIDATE_SUCCEEDED),
	    update_pair_states(Sid,Fid),
	    case do_check_true() of
		true->
		    reply(Client,ok),
		    {Server,?AGENT_COMPLETED};
		
		_->nochange
	    end
    end
;
	

?AGENT_RUNNING(_From,{udp,Socket,PeerIp,PeerPort,#stun{class = binding,
						      transactionid = TxId,
						      method=request,attrs=Attrs}  },#server{role=Role}) ->
	  
    {ok,Ip} = inet_parse:address(PeerIp),
    RepAttrs = [{'XOR-PEER-ADDRESS',{Ip,PeerPort}}],
    Rep = #stun{
      class = success,
      method = binding,
      transactionid = TxId,
      integrity = true,
      key = "passord",
      fingerprint = false,
      attrs = RepAttrs
     },
    Stun = stun:encode(Rep),
    gen_udp:send(Socket,Stun),

    %%trigger 
    L = get(?CHECK_LIST),
    %%find peer flex
    T1 = lists:filter(fun(#checkpair{remote=Remote})->
			      #ice_addr{ip=Ip,port=Port}=Remote,
			      {Ip,Port} =:= {PeerIp,PeerPort} end,L),
    {ok,#socket_info{streams=Streams}} = dict_find(?SOCKET_DICT,Socket),
    case T1 of 
	[]->
	    lists:map(fun(#candidate{cid=Cid,sid=Sid}=Local)->
			      Priority = proplists:get_value('PRIORITY',Attrs),
			      C1 = #candidate{
				priority = Priority,
				type = ?CANDIDATE_TYPE_PEER_REFLEXIVE,
				transport = udp,
				addr = #ice_addr{ip=PeerIp,port=PeerPort},
				cid = Cid,
				sid = Sid,
				fid = erlang:ref()
			       },
			      T2 = get(?REMOTE),
			      T3 = [C1|T2],
			      put(?REMOTE,T3),
			      PairPrority =
				  case Role of
				      ?ROLE_CONTROLLING ->
					  eis_ice:candiate_pair_priority(Local#candidate.priority,Priority);
				      ?ROLE_CONTROLLED ->
					  eis_ice:candiate_pair_priority(Priority,Local#candidate.priority)
				  end,
			      Pair = #checkpair{priority=PairPrority,sid=Sid,cid=Cid,remote=C1,local=Local,state=?CANDIDATE_WAITING},
			      insert_checkpair(Sid,Pair,Role),
			      L2 = get(?TRIGGER_QUE),
			      L3 = L2 ++ [Pair],
			      put(?TRIGGER_QUE,L3),
			      C1 end,Streams);
	_->%%7.2.1.4
	    lists:map(fun(#checkpair{state=State1,id=Id}=Pair)->
			      case State1 of
				  ?CANDIDATE_SUCCEEDED ->
				      do_nothing;
				  A when A=:= ?CANDIDATE_WAITING orelse A=:=?CANDIDATE_FROZEN ->
				      append_trigger_que(Pair);
				  ?CANDIDATE_FAILED ->
				      ok;
				  ?CANDIDATE_IN_PROGRESS ->
				      ok
			      end end,T1)
		      end,
    nochange.

?AGENT_COMPLETED(From,{send,udp,Sid,Cid,Packet},_Server)->
    L = get(?VALIDE_LIST),
    L1 = lists:filter(fun(#checkpair{cid=Cid1,sid=Sid1})->
			      Cid =:= Cid1 andalso Sid=:=Sid1 end,L),
    [#checkpair{local=Local,remote=Remote}|_]=L1,
    Addr = Remote#candidate.addr,
    #ice_addr{ip=Ip,port=Port} =  Addr,
    gen_udp:send(Local#candidate.socket,Ip,Port,Packet),    
    reply(From,ok),
    nochange;

?AGENT_COMPLETED(_From,{udp,Socket,_PeerIp,_PeerPort,Packet},#server{client=Client})->
    {ok,Port} = inet:port(Socket),
    {_Tag,Pid}=Client,
    erlang:send(Pid,{udp,{agent,self()},Port,Packet}),
    nochange.

?AGENT_FAILED(From,{send,udp,_CId,_Packet},_S) ->
    reply(From,{error,agent_failed}),
    nochange.

not_redundant(_C,[])->
    false;
not_redundant(#candidate{addr=Addr1,base_addr=Base1,priority=P1}=C,
	     [#candidate{addr=Addr2,base_addr=Base2,priority=P2}|T]) ->
    if Addr1 == Addr2 andalso Base1 == Base2 andalso P1>P2 ->
	    false;
       true->
	    not_redundant(C,T)
    end.

build_stream_info(#stream_info{options=Opts}=S,Count,UseRtcp)->
    L = get(?LOCAL),
    Candis = lists:get(Count,L),
    Opts2 = lists:foldl(fun(#candidate{addr=Addr,base_addr=Base,type=Type,priority=P1,cid=Cid,fid=F1},Acc)->
				#ice_addr{ip=Ip,port=Port} = Addr,
				T = 
				    case Type of 
					?CANDIDATE_TYPE_HOST ->
					    {candidate,io_lib:format("~b ~b udp ~b ~s ~b type host",
								     [F1,Cid,P1,Ip,Port])}			      
						;
					?CANDIDATE_TYPE_SEVER_REFLEXIVE ->
					    #ice_addr{ip=BaseIp,port=BasePort} = Base,
					    {candidate,io_lib:format("~b ~b udp ~b ~s ~b type srflx raddr ~s ~b",
								     [F1,Cid,P1,Ip,Port,BaseIp,BasePort])}
				    end,
				Acc ++ T end,[],Candis),
    Opts3 =
	case UseRtcp of
	    true->
		L1 = get(?DEFAULT),
		#candidate{addr=#ice_addr{ip=Ip1,port=Port2}} = lists:nth(2,L1),
		Opts2 ++[{"rtcp",io_lib:format("~b IN IP4 ~s",[Ip1,Port2])}];
	    _->
		Opts2
	end,	
    S#stream_info{options=Opts++Opts3}
	.

build_sdp(#server{local_media_info=Info,rtcp=UseRtcp},_L)->
    #media_info{video=Video,audio=Audio}=Info,
    put(count,0),
    V1 = lists:map(fun(A)->
			   T1 = get(count) +1,
			   put(count,T1),
			   build_stream_info(A,T1,UseRtcp) end,Video),
    put(count,0),
    A1 = lists:map(fun(A)->
			   T1 = get(count) +1,
			   put(count,T1),
			   build_stream_info(A,T1,UseRtcp) end,Audio),
    put(?LOCAL_SDP,sdp:encode(Info#media_info{video=V1,audio=A1})).


computing_foundations(L)->
    put(tmp,dict:new()),
    lists:map(fun(#candidate{type=Type,transport=T1,base_addr=#ice_addr{ip=Ip},server=#turn_server{ip=Sip}})->
		      random:seed(erlang:now()),
		      Fid = random:uniform( 1 bsl 20),
		      case Type of 
			  ?CANDIDATE_TYPE_HOST->
			      dict_store(tmp,{T1,Type,Ip},Fid);
			  _->
			      dict_store(tmp,{T1,Type,Sip},Fid)
		      end,ok end,L),
    lists:map(fun(#candidate{type=Type,transport=T1,base_addr=#ice_addr{ip=Ip},server=#turn_server{ip=Sip}} = C)->
		      {ok,Fid} = 
			  case Type of 
			      ?CANDIDATE_TYPE_HOST->
				  dict:find(get(tmp),{T1,Type,Ip});
			      _->
				  dict:find(get(tmp),{T1,Type,Sip})
			  end,
		      C#candidate{fid=Fid} end,L).

prioritize(#server{local_media_info=Info}=Server)->
    #media_info{video=Video,audio=Audio} = Info,
    Streams =   Audio ++Video,
    L1 = get(?CANDIDATES_LIST),
    L2 = lists:map(fun(A)->
			   P = eis_ice:candidate_ice_priority(A),
			   A#candidate{priority = P} end,L1),
    L3 = lists:filter(fun(A)->
			      not_redundant(A,L2) end,L2),
    L4 = computing_foundations(L3),
	
    %% 
    L5 = lists:map(fun(#stream_info{stream_id=Sid})->
					lists:filter(fun(#candidate{sid=S2})->
									S2 =:= Sid end,L4) end,Streams),
    put(?LOCAL,L5),
    L6 = choose_default(Server,L5),
    put(?DEFAULT,L6),
    build_sdp(Server,L5),
    ok.

compare_type({CANDIDATE_TYPE_PREF_RELAYED,_})->
	true;
compare_type({CANDIDATE_TYPE_PREF_SEVER_REFLEXIVE,CANDIDATE_TYPE_PREF_SEVER_REFLEXIVE})->
	false;
compare_type({CANDIDATE_TYPE_PREF_SEVER_REFLEXIVE,_})->
	true;
compare_type({CANDIDATE_TYPE_PREF_HOST,_})->
	false.
	
get_default(L)->
	L1 = lists:sort(fun(A,B)->
		compare_type({A#candidate.type,B#candidate.type}) end,L),
	lists:nth(1,L1).
										
choose_default(#server{},L5)->
	lists:map(fun(A)->
				get_default(A) end,L5);
choose_default(#server{},L5)->
	lists:map(fun(A)->
				 A1 = lists:map(fun(#candidate{cid=Cid})->
								Cid =:=1 end,A),
				A2 = lists:map(fun(#candidate{cid=Cid})->
								Cid =:=2 end,A),
				[get_default(A1),get_default(A2)]
				 end,L5).			




pcall(K,L)->
	case properlist:get_value(K,L) of
		undefined->
		throw({no_key_error,K});
		V->
		V
	end.
get_streams(#media_info{video=Video,audio=Audio})->
    Streams =   Audio ++Video,
    lists:map(fun(#stream_info{options=Opts},stream_id=Sid)->
		      #stream{sid=Sid,port=pcall(port,Opts),user=pcall('ice-ufrag',Opts),pwd=pcall('ice-pwd',Opts)}
	      end,Streams).
get_remotes(#media_info{video=Video,audio=Audio})->
    Streams =   Audio ++Video,
    lists:map(fun(#stream_info{options=Opts},stream_id=Sid)->
		      User=pcall('ice-ufrag',Opts),Pwd=pcall('ice-pwd',Opts),
		      Cs = proplists:get_all_values(candidate,Opts),
		      lists:map(fun(A)->
					Tokens = string:tokens(A," "),
					Type = lists:nth(8,Tokens),
					Fid = lists:nth(1),
					Cid = lists:nth(2),
					P = lists:nth(4),
					Ip = lists:nth(5),
					Port = lists:nth(6),
					T1 = 
					    case Type of
						"host" ->
						    ?CANDIDATE_TYPE_HOST;
							_->%%todo add relay support
						    ?CANDIDATE_TYPE_PREF_SEVER_REFLEXIVE	
					    end,
					#candidate{
					      id = increment(?CANDIDATE_ID),
					      fid = Fid,
					      type = T1,
					      priority=P,
					      addr = #ice_addr{ip=Ip,port=Port},
					      base_addr = #ice_addr{ip=Ip,port=Port},
					      cid = Cid,
					      user = User,
					      pwd = Pwd,
					      sid=Sid
					     } end,Cs)
	      end,Streams).

increment(Name)->
    Id = 
    case get(Name) of
	undefined->
	    1;
	T->
	    T+1
    end,
    put(Name,Id),
    Id.


build_host(Ips,Streams,Rtcp)->
    lists:map(fun(Ip)->
		      L = new_addr(Ip,Streams,Rtcp),
		      lists:map(fun(#stream{}=A2)->
					new_host_candidate(A2)
				end,L)
	      end ,Ips),
    put(?GATHER_QUE,get(?HOST_LIST)).


new_addr(Ip,Streams,Rtcp)->
    L1 = lists:foldl(fun(#stream{port=Port}=C,Acc)->
			     C1 = C#stream{cid=1,ip=Ip},
			     case  Rtcp of
				 rtcp->
				     C2 = C#stream{port=Port + 1,cid=2},
				     Acc ++ [C1,C2];
				_->
				     Acc ++ [C1]
			     end end ,Streams),
    L1.

new_host_candidate(#stream{sid=Sid,ip=Ip,port=Port,cid=Cid,user=User,pwd=Pwd}=Stream)->   
    {ok,Ip1} = inet_parse:address(Ip),
    Socket  = 
	case dict_find(?HOST_SOCKET,{Ip,Port,udp}) of
	    {ok,S}->
		S
		;
	    _->
		case gen_udp:open(Port,[{ip,Ip1}]) of
		    {ok,S} ->
			S
			;
		    Err->
			throw(Err)
		end	
	end,
    Host = #candidate{
      id = increment(?CANDIDATE_ID),
      type = ?CANDIDATE_TYPE_HOST,
      transport = udp,
      addr = #ice_addr{ip=Ip,port=Port},
      base_addr = #ice_addr{ip=Ip,port=Port},
      socket = Socket,
      cid = Cid,
      user = User,
      pwd = Pwd,
      sid=Sid
     },
    case dict_find(?SOCKET_DICT,Socket) of
	{ok,Info}->
	    Candis = Info#socket_info.streams,
	    dict_store(?SOCKET_DICT,Socket,Info#socket_info{streams=[Host|Candis]});
	_->
	    dict_store(?SOCKET_DICT,Socket,#socket_info{streams=[Host]})
    end,
    list_head(?HOST_LIST,Host),
    dict_store(?HOST_SOCKET,{Ip,Port,udp},Socket)
	.
dict_store(Name,K,V)->
    D = 
	case get(Name) of
	    undefined->dict:new();
	    D1 ->
		D1
	end,
    put(Name,dict:store(K,V,D)).
dict_del(Name,K)->
    D = get(Name),
    put(Name,dict:delete(K,D)).
dict_find(Name,K)->
    case get(Name) of
	undefined->undefined;
	D ->
	    D = get(Name),
	    dict:find(K,D)
    end.
list_head(Name,Value)->
    L = 
	case get(Name) of
	    undefined->
		[];
	    A->
		A
	end,
    put(Name,[Value|L]).


send_check(#server{role=Role,nominate_type=Type},#checkpair{cid=Cid,local=Local,remote=Remote}=P1,Attrs,Sid)->
	%%peer reflex 
    P = eis_ice:candiate_pair_priority(#candidate{type=?CANDIDATE_TYPE_SEVER_REFLEXIVE,cid=Cid}),
    A1=
	case Role of
	    ?AGENT_ROLE_CONTROLLING->
		[
		 {'PRIORITY',P},
		 {'ICE-CONTROLLING',1}
		];
	    _->
		[
		 {'PRIORITY',P},
		 {'ICE-CONTROLLED',1}
		]
	end,
    %%
    Nominate = case Type of
	     ?AGENT_NOMINATE_REGULAR ->
		 {false,[]};
	     ?AGENT_NOMINATE_AGGRESSIVE->
		 {true,[{'USE-CANDIDATE',1}]}
	 end,
    TxId = increment(?TXID),
    #candidate{socket=Socket,user=User} = Local,
    #candidate{addr=Addr,user=PeerUser,pwd=PeerPwd} = Remote,
    A2= [{'USERNAME',PeerUser++":"++User},{'PASSWORD',PeerPwd}],
    A3 = A1+A2 ++ Attrs,	
    #ice_addr{ip = Ip,port = Port} = Addr,
    Req = #stun{
      class = request,
      method = binding,
      transactionid = TxId,
      fingerprint = true,
      attrs = A3
     },
    Pair =P1#checkpair{is_nominated=Nominate},
    dict_store(?STUN_REQ_TRANS,TxId,#check_info{pair=Pair,sid=Sid,role=Role}),
    Stun = stun:encode(Req),
    gen_udp:send(Socket,Ip,Port,Stun),
    {ok,Ref} = timer(?Ta,{check_rto,Sid,Socket,Ip,Port,Stun}),
    dict_store(?CHECK_RTO_DICT,TxId,#check_rto_info{timer=Ref,count=1,pair=Pair})
	.
timer(Time,Msg)->
    timer:send_after(Time,self(),{'$agent',from,Msg}).
send_interval(?Ta,Pid,Msg)->
    timer:send_interval(?Ta,Pid,{'$agent',from,Msg}).
%%rfc 7.3.1.2.2
construct_valid(ListId,Valid)->
    ok.
    

%%rfc5245 5.2
determing_role(#server{action=Action},#media_info{options=Opts})->
	#sdp_session{attrs=Attrs} = pcall(Opts,sdp_session),
	PeerIce = 
	case properlist:get_value(Attrs,'ice-lite') of
		undefined->
			full;
			_->
			lite
		end,
	case {PeerIce,Action} of
		{lite,_}->
			?ROLE_CONTROLLING;
		{full,'offer'}->
			?ROLE_CONTROLLING;
		{full,'answer'}->
			?ROLE_CONTROLLED
	end.
	
	
	
new_pair([],[],Acc)->
	lists:reverse(Acc);
new_pair([A|Tail1],[B|Tail2],Acc)->
    L1 = 
	lists:foldl(fun(#candidate{fid=F1,sid=Sid,cid=C1,type=T1}=Local1,Acc1)->
			    L2 = lists:filter(fun(#candidate{type=T2,cid=C2})->
						      {T1,C1} =:= {T2,C2} end,B),
			    L3 = lists:map(fun(#candidate{fid=F3,sid=_S3,cid=_C3,type=_T3}=Remote1)->
						   #checkpair{
						local=Local1,
						remote=Remote1,
						fid={F1,F3},
						state=?CANDIDATE_FROZEN,
						cid =C1,
						sid = Sid
					       } end,L2),
			    Acc1++L3 end,[],A),
    new_pair(Tail1,Tail2,[L1|Acc]).


%%rfc5245 5.7
forming_check_list(#server{role=Role}=_Server,PeerSdp)->
    %%Local = get(?CANDIDATE_LIST),
    Remote = get_remotes(PeerSdp),
    put(?REMOTE,Remote),
    Local = get(?LOCAL),
    L1 = lists:map(fun(A)->
			   lists:filter(fun(#candidate{type=Type})->
						Type =:= ?CANDIDATE_TYPE_HOST orelse Type =:= ?CANDIDATE_TYPE_RELAYED end,A)
		   end,Local),
    L2 = new_pair(L1,Remote,[]),
    L3 = lists:map(fun(A)->
			   order_pair(A,Role) end,L2),
    L4 = computing_state(L3),
    Pid = self(),
    L5 = lists:map(fun(A)->
			   #checkpair{sid=Sid} = lists:nth(1,A),
			   {Sid,A} end,L4),
    lists:map(fun({T,_})->
		      dict_store(?CHECKLIST_STATE_DICT,T,?CHECKLIST_RUNNING) end,L5),
    {Sid,_} = lists:nth(1,L5), 
    {ok,Ref} = send_interval(?Ta,Pid,{check,Sid}),
    dict_store(?ACTIVE_CHECKLIST_TIMER,Sid,#checklist_info{timer=Ref}),
    %%init checklist state
    put(?CHECK_LIST,L5).
	
order_pair(L,Role)->					
    L1 = lists:map(fun(#checkpair{local=Local,remote=Remote}=A)-> 
			   Priority =
			       case Role of
				   ?ROLE_CONTROLLING->
				       eis_ice:candiate_pair_priority(Local,Remote);
				   ?ROLE_CONTROLLED->
				       eis_ice:candiate_pair_priority(Remote,Local)
			end,
		A#checkpair{priority=Priority} end,L),
    lists:sort(fun(#checkpair{priority=P1},#checkpair{priority=P2})->
				P1 > P2 end,L1).
%%

computing_state(L)->
    [First,Tail] = L,
    L1 = lists:map(fun(#checkpair{cid=Cid}=A)->
			   case Cid of
			       1->
				   A#checkpair{state=?CANDIDATE_WAITING};
			       _->
				   A
			   end end ,First),
    [L1|Tail].
order_check(#server{nominate_type=Type}=Server,ListId)->
    A1 = case Type of
	     ?AGENT_NOMINATE_REGULAR ->
		 {false,[]};
	     ?AGENT_NOMINATE_AGGRESSIVE->
		 {true,[{'USE-CANDIDATE',1}]}
	 end,
    {ListId,L} = proplists:get_value(ListId,get(?CHECK_LIST)),
    L1 = lists:filter(fun(#checkpair{state=State})->
			      State =:= ?CANDIDATE_WAITING end,L),
    case L1 of
	[#checkpair{id=Id}=H|_Tail]->
	    send_check(Server,H,A1,Id),
	    update_checklist_state(ListId,Id,?CANDIDATE_IN_PROGRESS)
	    ;
	[]->
	    L2 = lists:filter(fun(#checkpair{state=State})->
				      State =:= ?CANDIDATE_FROZEN end,L),
	    case L2 of
		[#checkpair{id=Id1}=H1|_Tail1]->
		    send_check(Server,H1,A1,ListId),
		    update_checklist_state(ListId,Id1,?CANDIDATE_IN_PROGRESS);
		_->
		    {ok,Timer}= dict_find(?ACTIVE_CHECKLIST_TIMER,ListId),
		    timer:cancel(Timer)
	    end
    end.

trigger_check(#server{nominate_type=Type}=Server,ListId)->
    A1 = case Type of
	     ?AGENT_NOMINATE_REGULAR ->
		 {false,[]};
	     ?AGENT_NOMINATE_AGGRESSIVE->
		 {true,[{'USE-CANDIDATE',1}]}
	 end,
    [#checkpair{id=Id}=H|T] = get(?TRIGGER_QUE),
    send_check(Server,H,A1,Id),
    update_checklist_state(ListId,Id,?CANDIDATE_IN_PROGRESS),
    put(?TRIGGER_QUE,T).


not_role(?ROLE_CONTROLLED)->
	?ROLE_CONTROLLING;
not_role(?ROLE_CONTROLLING)->
	?ROLE_CONTROLLED.	


update_checklist_state(ListId,Id,State)->
    L = get(?CHECK_LIST), 
    L1 = lists:map(fun(#checkpair{id=Id1}=A)->
			   case Id of
			       Id1 ->
				   A#checkpair{state=State};
			       _->
				   A
			   end end ,L),
    dict_store(?CHECKLIST_STATE_DICT,ListId,get_checklist_state(L)),
    L2 = lists:keyreplace(ListId,1,L,{ListId,L1}),
    put(?CHECK_LIST,L2).

lists_find(_Cid,[])->
    false;
lists_find(H,[H|_T]) ->
    true;
lists_find(Cid,[_H|T]) ->
    lists_find(Cid,T).
get_checklist_state(L)->
    L1 = lists:filter(fun(#checkpair{state=State})->
			      State=:=?CANDIDATE_SUCCEEDED orelse State=:=?CANDIDATE_FAILED end,L),
    if length(L1) =:= length(L) ->
	    L2 = get(?VALIDE_LIST),
	    R = lists:foldl(fun(#checkpair{cid=Cid},Acc)->
				    Acc andalso lists_find(Cid,L2) end,true,L1),
	    if R ->
		    L3 = lists:filter(fun(#checkpair{is_nominated=N})->
					    N =:=true end,L2),
		    if length(L3) =:= length(L2)->			    
			    ?CHECKLIST_COMPLETED;
		       true->
			    ?CHECKLIST_RUNNING
		    end;
	       true ->
		    ?CHECKLIST_FAILED
	    end;
       true ->
	    ?CHECKLIST_RUNNING
    end.

checklist_type(L)->
    case 
    lists:filter(fun(#checkpair{state=State})->
			 State =:=?CANDIDATE_WAITING end,L) of
	[]->
	    L1 = lists:filter(fun(#checkpair{state=State})->
				      State =:=?CANDIDATE_WAITING end,L),
	    if length(L1) =:= length(L) ->
		    frozen;
	       true->
		    other
	    end;
	_ ->
	    active
    end.
		
insert_checkpair(Sid,Pair,Role)->
    L1 = get(?CHECK_LIST),
    {_,L2} = proplists:get_value(Sid,L1),
    L3 = [L2|L1],
    L4 = order_pair(L3,Role),
    L5=lists:keyreplace(Sid,1,L1,{Sid,L4}),
    put(?CHECK_LIST,L5).
update_same_foundation_frozen_2_waiting(Sid,Fid,L)->
    L1 = get(?CHECK_LIST),
    L2 = lists:map(fun(#checkpair{fid=F1,state=State}=A)->
			   case {Fid,?CANDIDATE_FROZEN} of
			       {F1,State} ->
				   A#checkpair{state=?CANDIDATE_WAITING};
			       _ ->
				   A end end,L),
    L3=lists:keyreplace(Sid,1,L1,{Sid,L2}),
    put(?CHECK_LIST,L3).
%%7.1.3.2.3
update_pair_states(Sid,Fid)->
    L = get(?CHECK_LIST),
    {_,L1} = proplists:get_value(Sid,L),
    update_same_foundation_frozen_2_waiting(Sid,Fid,L1),
    L4 = lists:filter(fun({T,_})->
			      T =/=Sid end,L),
    
    lists:map(fun({T1,L5})->
		      case checklist_type(L5) of
			  active->
			      update_same_foundation_frozen_2_waiting(T1,Fid,L5);
			  frozen->
			      %%todo
			      update_same_foundation_frozen_2_waiting(T1,Fid,L5),
			      {ok,Ref} = send_interval(?Ta,self(),{check,T1}),
			      dict_store(?ACTIVE_CHECKLIST_TIMER,T1,#checklist_info{timer=Ref})
			      ;			  
			  _->
			      donothing
		      end end,L4)
	.

update(Sid,List)->
    L = get(?CHECK_LIST),
    L1 = lists:keyreplace(Sid,1,L,{Sid,List}),
    put(?CHECK_LIST,L1).

do_check_false()->
    L = get(?CHECK_LIST),
    R = lists:foldl(fun({Sid,_},Acc)->
			    {ok,S}=dict_find(?CHECKLIST_STATE_DICT,Sid),
			    case S of
				?CHECKLIST_FAILED ->
				    false;
				_->
				    Acc andalso true
			    end end,true,L),
    not R.

do_check_true()->
    L = get(?CHECK_LIST),
    L2 = lists:filter(fun({Sid,_})->
			    {ok,S}=dict_find(?CHECKLIST_STATE_DICT,Sid),
			    case S of
				?CHECKLIST_COMPLETED ->
				    true;
				_->
				    false
			    end end,L),
    length(L2) =:=length(L).
    
