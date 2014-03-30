-module(eis_agent).
-include("eis_main.hrl").
-export([start/1]).

start(Opts)->
    ok.
-spec offer(Pid::pid(),#agent_info{})->{ok,sdp}|{error,address_used}.
offer(Pid,#agent_info{}=Info)->
	From = {make_ref(),self()},
	gen_server:call(Pid,{'$agent_offer',From,Info}).
answer(Pid,#agent_info{},Sdp)->
	ok.
kick_off(Pid)->
	ok.
stop(Pid)->
	ok.

-define(AGENT_INIT,init).
-define(AGENT_GATHER,gather).
-define(AGENT_RUNNING,running).
-define(AGENT_CONN_CHECK,conn_check).
-define(AGENT_FAILED,failed).
-define(AGENT_COMPLETED,completed).
-define(Ta,30).
-compile([export_all]).
-record(stream,{sid,port,user,pwd,cid}).
-record(server, {
      parent::pid(),
      mod::atom(),
	  name,
      state::any(),
	  debug::boolean(),
	  agent_state,
	  client::pid(),
	  opts,
	  hosts,
	  components,
	  candidates_ets,
	  socket_ets,
	  turn_servers,
	  cur_turn_server,
	  stream_id,
	  tx_ets,
	  nominate_type,
	  from,
	  peer_sdp,
	  action::offer|answer,
	  role::controlling|controlled,
	  local_sdp
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
-define(SOCKETS_DICT,socket_dict).
-define(HOST_SOCKET,host_socket).

-define(ACTIVE_CHECKLIST_TIMER,active_checklist_timer).

-define(CANDIDATES_LIST,candidate_ets).
-define(HOST_LIST,host_list).
-define(LOCAL,local).
-define(REMOTE,remote).
-define(SDP,sdp).
-define(STUN_TRANS,stun_trans).

-define(ROLE_CONTROLLING,controlling).
-define(ROLE_CONTROLLED,controlled).
-define(CANDIDATE_FROZEN,frozen).
-define(CANDIDATE_WAITING,waiting).
-define(CANDIDATE_IN_PROGRESS,'in-progress').
-define(CANDIDATE_FAILED,failed).
-define(CANDIDATE_SUCCEEDED,succeeded).

init_it(Starter, Parent, {local, Name}, Mod, {Workers, Arg}, Options) ->
    %% R13B passes {local, Name} instead of just Name
    init_it(Starter, Parent, Name, Mod,
            {Workers, Arg}, Options);
init_it(Starter, self, Name, Mod, {OptArgs, Arg}, Options) ->
    init_it(Starter, self(), Name, Mod,
            {OptArgs, Arg}, Options);
init_it(Starter,Parent,Name,Mod,{_OptArgs,Opts},_Options) ->
    lager:info("start agent!"),
    proc_lib:init_ack(Starter, {ok, self()}),
    put(?ID,1), %%
    put(?TXID,1),
    put(?CANDIDATE_ID,1),
    put(?PAIR_ID,1),
    put(?STUN_TRANS,dict:new()),
    %%RFC5245 5.2
    random:seed(erlang:now()),
    random:uniform( 1 bsl 64),
    put(?TIE_BREAKER,2), 
    %%
    TurnServers = assert_get(turn_servers,Opts),
    Server = #server{parent = Parent,
		     mod = Mod,
		     name = Name,
		     turn_servers = TurnServers,
		     cur_turn_server = 1,
		     from = assert_get(from,Opts),
		     action = assert_get(action,Opts)
		    },
    build_host(Server),
    erlang:send(self(),'$agent_gather'),
    loop(Server,?AGENT_GATHER
	).

assert_get(Key,PropList)->
    case 
	proplists:get_value(Key,PropList) of
	undefined->
	    exit("no key:~p value in:~p",[Key,PropList]);
	Value ->
	    Value
    end.
head_list(Name,Value)->
    L = 
	case get(Name) of
	    undefined->
		[];
	    A->
		A
	end,
    put(Name,[Value|L]).

prepare_parse(_Packet)->
    exit(not_support_now),
    stun.
loop(#server{mod = _Mod,
	     state = _State,
	     debug=_Debug
	    } = Server       
     ,State)->
    receive
	Msg->
	    case Msg of 
		{udp,_Socket,_PeerIp,_PeerPort,Packet}->
		    case prepare_parse(Packet) of
			stun->
			    Req = stun:decode(Packet),
			    ?MODULE:State(Server,Req,State);
			_Rtp->
			    ?MODULE:State(Server,Msg,State)
		    end
			;
		_->?MODULE:State(Server,Msg,State)
	    end
    end.

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

reply({To,Tag},Reply)->
    catch To ! {Tag,Reply}.

?AGENT_INIT(Server,{{'$agent_action',Action},From,#agent_info{hosts=Ips,stun_servers=SS}=Info,State) 
										when Action =:= offer orelse Action=:=answer->
	try 
		Streams = get_streams(Info),
		Rtcp = false,
		build_host(Ips,Streams,UseRtcp),
		reply(From,ok),
		erlang:send(self(),'$agent_gather'),
		loop(Server#server{info=Info,action=Action,from=From,stun_servers=SS,host=Host},?AGENT_GATHER);
	catch
		_:A->
			reply(From,A),
			loop(ServerState,State);
	end,
	
	
?AGENT_GATHER(#server{from=From,turn_servers=TS,cur_turn_server=_Cur}=Server,'$agent_gather',State)->
    Que = get(?GATHER_QUE),
    case Que of
	[] ->
	    prioritize(Server),
	    reply(From,{sdp,get(?SDP)}),
	    loop(Server,?AGENT_RUNNING);
	[{#candidate{socket=S}}=Candidate|Tail] ->
	    %%todo maybe use multi turn server
		Ts = lists:nth(1,TS)
	    #turn_server{ip=Ip,port=Port}= Ts,
	    Id = increment(?TXID),
		dict_store(?STUN_TRANS,Id,Candidate#candidate{stun_server=Ts),
	    Req = #stun{
	      class = request,
	      method = binding,
	      transactionid = Id,
	      attrs = [
		      ]
	     },
	    Stun = stun:encode(Req),
	    gen_udp:send(S,Ip,Port,Stun),
	    put(?GATHER_QUE,Tail),
	    erlang:send_after(?Ta,self(),'$agent_gather'),
	    loop(Server,State)
    end;
?AGENT_GATHER(#server{}=Server,#stun{class=success,attrs=Attrs,transactionid=TxId},AgentState) ->
    D =get(?STUN_TRANS),
    case dict:find(TxId,D) of
	{ok,Host}->	    
	    #ice_address{ip=Ip,port=Port} = Host#candidate.addr,
	    {MapIp,MapPort} = proplists:get_value('XOR-MAPPED-ADDRESS',Attrs),
	    %%todo 
	    %%{ok,MapIp1}=inet_parse:address(MapIp),
	    {T1,T2,T3,T4}=MapIp,
	    MapIp1 = integer_to_list(T1)++"," ++integer_to_list(T2)++integer_to_list(T3)++integer_to_list(T4),
	    Addr = #ice_address{ip=MapIp1,port=MapPort},
	    C1 = #candidate{
	      type = ?CANDIDATE_TYPE_SEVER_REFLEXIVE,
	      transport = udp,
	      addr = Addr,
	      base_addr = Host#candidate.addr,
	      component_id = Host#candidate.component_id,
	      stream_id = Host#candidate.stream_id
	     },
	    head_list(?CANDIDATES_LIST,C1);
	_->
	    flush
    end,
    loop(Server,AgentState).

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
	Acc;
new_pair([A|T1],[B|T2],Acc)->
	L1 = 
	lists:foldl(fun(#candidate{foundation=F1,priority=P1,stream_id=Sid,component_id=C1,type=T1}=Local1,Acc1)->
			L2 = lists:filter(fun(#candidate{type=T2,component_id=C2})->
							 {T1,C1} =:= {T2,C2} end,B),
			L3 = lists:map(fun(#candidate{foundation=F3,priority=P3,stream_id=S3,component_id=C3,type=T3}=Remote1)->
				
				P = #candidate_checkpair{
				local=Local1,
				remote=Remote1,
				foundation={F1,F3},
			     state=?CANDIDATE_FROZEN,
			     component_id =C1,
			     stream_id = Sid
			    } end,B),
			Acc1++L3 end,[],A),
new_pair(T1,T2,Acc++[L1]).


%%rfc5245 5.7
forming_check_list(#server{role=Role}=Server,PeerSdp)->
	%%Local = get(?CANDIDATE_LIST),
	Remote = get_remotes(PeerSdp),
	put(?REMOTE,Remote),
	Local = get(?LOCAL),
	L1 = lists:map(fun(A)->
				lists:filter(fun(#candidate{type=Type})->
						Type =:= CANDIDATE_TYPE_HOST orelse Type =:= CANDIDATE_TYPE_RELAYED end,A)
			  end,Local),
	L2 = new_pair(L1,Remote),
	L3 = lists:map(fun(A)->
				order_pair(A,Role) end,L2),
	L4 = compute_state(L3),
	Id = 1,
	Pid = self(),
	{ok,Ref} = timer:send_interval(?Ta,Pid,{check,Id},
	store_dict(?CHECK_TIMER,Id,Ref),
	put(?CHECK_LIST,L4).
	
order_pair(L,Role)->					
	 L1 = lists:map(fun(#candidate_checkpair{local=Local,remote=Remote}=A)-> 
		Priority =
			case Role of
				?ROLE_CONTROLLING->
					 eis_ice:candiate_pair_priority(Local,Remote);
				?ROLE_CONTROLLED->
					eis_ice:candiate_pair_priority(Remote,Local)
			end,
		A#candidate_checkpair{priority=Priority} end,L),
	L2 =lists:sort(fun(#candidate_checkpair{priority=P1},#candidate_checkpair{priority=P2})->
				P1 > P2 end,L1).
%%

computing_state(L)->
	[First,Tail] = L,
	L1 = lists:map(fun(#candidate_checkpair{cid=Cid}=A)->
					case Cid of
						1->
							A#candidate_checkpair{state=?CANDIDATE_WAITING};
						_->
							A
					end end ,First),
	L2 = [L1|Tail].

?AGENT_RUNNING(Server,Msg,From},State} when Msg =:=offer orelse Msg =:= answer ->
	reply(From,{ok,get(?SDP)},
	loop(#Server{action=Msg},State);
?AGENT_RUNNING(Server,{'$set_sdp',From,PeerSdp},State} ->
	Role = determing_role(Server,PeerSdp),
	loop(Server#server{role=Role,peer_sdp=PeerSdp},State);

order_check(Server,A1,State,Id)->
	L = lists:nth(Id,get(?CHECK_LIST)),
	L1 = lists:filter(fun(candidate_checkpair{state=State})->
			State =:= ?CANDIDATE_WAITING end,L),
	case L1 of
		[H|Tail]->
			send_check(H,A1),
			update_checklist(H#candidate_checkpair{state=?CANDIDATE_IN_PROGRESS});
		[]->
			L2 = lists:filter(fun(candidate_checkpair{state=State})->
			State =:= ?CANDIDATE_FROZEN end,L),
			case L2 of
				[H1|Tail1]->
					send_check(H1,A1),
					update_checklist(H1#candidate_checkpair{state=?CANDIDATE_IN_PROGRESS});
				_->
					D = get(?CHECK_TIMER),
					{ok,Timer}= dict:find(D,Id),
					timer:cancel(Timer)
			end
	end.
trigger_check(Server,A1,Id)->
	[H|T] = get(?TRIGGER_QUE),
	send_check(H1,A1),
	update_checklist(H1#candidate_checkpair{state=?CANDIDATE_IN_PROGRESS}),
	put(?TRIGGER_QUE,T).

%%5.8	
?AGENT_RUNNING(#server{nominate_type=Type}=Server,{_,check,Id},State) ->
    A1 = case Type of
	     ?AGENT_NOMINATE_REGULAR ->
		 [];
	     ?AGENT_NOMINATE_AGGRESSIVE->
		 [{'USE-CANDIDATE',1}]
	     end,
	Q = get(?TRIGGER_QUE),
	case Q of
		[]->
			order_check(Server,A1,Id);
		[H|T]->
			trigger_check(Server,A1,Id)
	end,
loop(Server,State);


not_role(?ROLE_CONTROLLED)->
	?ROLE_CONTROLLING;
not_role(?ROLE_CONTROLLING)->
	?ROLE_CONTROLLED.	
%%failure todo add stun error 7.1.3.1

?AGENT_RUNNING(#server{}=Server,
					 ,{udp,_Socket,PeerIp,PeerPort,#stun{class = error,attrs=Attrs,transactionid=TxId}}
					 ,State) ->
	case dict_get(?STUN_TRANS,TxId) of
	[]->
	    loop(Server,State);
	{_,Role,#candidate_checkpair{id=Id,local =Local,priority=P,foundation=F,stream_id=SId,component_id=CId}=C1}->
		%%7.1.3.1
		change_checklist_prioriyt(Role)
		update_checklist_state(Id,?CANDIDATE_WAITING),
		L1 =get(?TRIGGER_QUE),
		put(?TRIGGER_QUE,L1++[C1]),
		loop(Server#server{role=not_role(Role),State}
	end;
?AGENT_RUNNING(#server{}=Server,
					 ,{udp,_Socket,PeerIp,PeerPort,#stun{class = success,attrs=Attrs,transactionid=TxId}}
					 ,State) ->
	case dict_get(?STUN_TRANS,TxId) of
	[]->
	    loop(Server,State);
	{Id,_Role,#candidate_checkpair{id=Id,local =Local,remote=Remote,
								priority=P,foundation=F,stream_id=Sid,component_id=Cid,
								user=User,
								pwd=Pwd
								}=C1}->
		%%7.1.3.2
		#ice_address{ip=PeerIp,port=PeerPort}=Remote
		ice_address{ip=LocalIp,port=LocalPort}=Local
		{Ip1,PeerFlexPort} = proplists:get_value('XOR-PEER-ADDRESS',Attrs),
		{ok,PeerFlexIp}= inet_parse:address(Ip1),
		case {LocalIp,LocalPort} of
			 {PeerFlexIp,PeerFlexPort} ->
				ok;
			 _->
				#candidate{base_addr=Base} = Local,
				NewAddr = #ice_address{ip=PeerFlexIp,port=PeerFlexPort},
				Priority = proplists:get_value('PRIORITY',Attrs),
				%%todo add foundation
				C1 = #candidate{
				foundation = F
				priority = Priority,
				type = ?CANDIDATE_TYPE_PEER_REFLEXIVE,
				transport = udp,
				addr = NewAddr,
				base_addr = Base,
				socket = Local#candidate.socket,
				component_id = Cid,
				stream_id = Sid,
				user=User,
				pwd=Pwd
				},
				head_list(?CANDIDATE_LIST)
		end
		
		loop(Server#server{role=not_role(Role),State}
	end;
	
	    L = get(?),
	    %%find peer flex
	    T1 = lists:filter(fun(#candidate_checkpair{remote=Remote})->
			      #ice_address{ip=Ip,port=Port}=Remote,
			      {Ip,Port} =:= {PeerIp,PeerPort} end,L),
	    case T1 of 
		[]->
		    {Ip1,PeerFlexPort} =  proplists:get_value('XOR-PEER-ADDRESS',Attrs),
		    {ok,PeerFlexIp}= inet_parse:address(Ip1),
		    #candidate{base_addr=Base} = Local,
		    NewAddr = #ice_address{ip=PeerFlexIp,port=PeerFlexPort},
		    Priority = proplists:get_value('PRIORITY',Attrs),
		    %%todo add foundation
		    C1 = #candidate{
		      priority = Priority,
		      type = ?CANDIDATE_TYPE_PEER_REFLEXIVE,
		      transport = udp,
		      addr = NewAddr,
		      base_addr = Base,
		      socket = Local#candidate.socket,
		      component_id = CId,
		      stream_id = SId
		     },
		    T2 = get(local),
		    T3 = [C1|T2],
		    put(local,T3)
			;
		_->
		    ok
	    end,
	    %%
	    L1= lists:map(fun(A)->
				  if A#candidate_checkpair.priority =:= P ->
					  A#candidate_checkpair{state=?CHECK_SUCCEEDED};
				     true ->
					  A
				  end
			  end,L),
	    L2 = lists:filter(fun(A)->
				      #candidate_checkpair{foundation=F1,state=State} = A,
				      F1 =:=F andalso State=/=?CHECK_SUCCEEDED end ,L1),
	    if L2 =:= [] ->
		    L3 = lists:filter(fun(#candidate_checkpair{foundation=F2})->
					      F2=:=F end,L1),
		    put(select,L3),
		    loop(Server,completed);
	       true->
		    put(check_list,L1),
		    erlang:send_after(?Ta,self(),order_check),
		    loop(Server,State)		    
	    end
    end. 
	
?AGENT_RUNNING(#server{}=Server,{#stun{class = binding,
				   transactionid = TxId,
				   method=request,attrs=Attrs},{udp,Socket,PeerIp,PeerPort,_}},State) ->

    %%trigger 
    L = get(check_list),
	    %%find peer flex
    T1 = lists:filter(fun(#candidate_checkpair{remote=Remote})->
			      #ice_address{ip=Ip,port=Port}=Remote,
			      {Ip,Port} =:= {PeerIp,PeerPort} end,L),
    [Src|_]=ets:lookup(SocketEts,Socket),
    Remote =
    case T1 of 
	[]->
	    Priority = proplists:get_value('PRIORITY',Attrs),
	    C1 = #candidate{
	      priority = Priority,
	      type = ?CANDIDATE_TYPE_PEER_REFLEXIVE,
	      transport = udp,
	      addr = #ice_address{ip=PeerIp,port=PeerPort},
	      component_id = Src#candidate.component_id,
	      stream_id = Src#candidate.stream_id,
	      foundation = erlang:ref()
	     },
	    T2 = get(remote),
	    T3 = [C1|T2],
	    put(remote,T3),
	    C1;
	[H|_]->
	    H
    end,
    N1 = #candidate_checkpair{local=Src,remote=Remote},
    head_list(?TRIGGER_QUE,N1),
    %%
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
    loop(Server,State);


completed(Server,{send,udp,CId,Packet},State)->
    L = get(select),
    L1 = lists:filter(fun(#candidate_checkpair{component_id=Id})->
			      CId =:=Id end,L),
    [#candidate_checkpair{local=Local,remote=Remote}|_]=L1,
    Addr = Remote#candidate.addr,
    #ice_address{ip=Ip,port=Port} =  Addr,
    gen_udp:send(Local#candidate.socket,Ip,Port,Packet),    
    loop(Server,State);

completed(#server{socket_ets=Ets}=Server,{udp,Socket,PeerIp,PeerPort,Packet},State)->
    ets:lookup(Ets,Socket),
    L = get(select),
    L2 = lists:filter(fun(#candidate_checkpair{remote=Remote})->
			 #ice_address{ip=Ip,port=Port} = Remote,
			 {Ip,Port} =:= {PeerIp,PeerPort} end,L),
    case L2 of
	[] ->
	    nothing;
	[#candidate_checkpair{component_id=CId}|_]->
	    erlang:send(pid,{udp,{agent,self()},CId,Packet})
    end,
    loop(Server,State).

   
    
init(#server{local_addrs=addrs}=_Server,_Msg,_State)->
    ok.



		      

gather_server_relex(#server{candidates_ets=Cets},TurnServer)->
    Cs = ets:tab2list(Cets),
    Que = lists:map(fun(A)->
			    {A,TurnServer} end,Cs),
    put(gather_que,Que),
    erlang:send_after(?Ta,self(),{gather_que}),
    ok.
not_redundant(_C,[])->
    false;
not_redundant(#candidate{addr=Addr1,base_addr=Base1,priority=P1}=C,
	     [#candidate{addr=Addr2,base_addr=Base2,priority=P2}|T]) ->
    if Addr1 == Addr2 andalso Base1 == Base2 andalso P1>P2 ->
	    false;
       true->
	    not_redundant(C,T)
    end.
-define(SPACE,<<" ">>).

build_stream_info(#stream_info{options=Opts}=S,Count,UseRtcp)->
	L = get(?LOCAL),
	Candis = lists:get(Count,L),
	Opts2 = lists:foldl(fun(#candidate{addr=Addr,base_addr=Base,type=Type,priority=P1,foundation=F1},Opts)->
								T = 
								case Type of 
								?CANDIDATE_TYPE_HOST ->
									{candidate,io_lib:format("~d ~d udp ~d ~s ~d type host",
										[F1,Cid,P1,Ip,Port]};			      
							;
								?CANDIDATE_TYPE_SEVER_REFLEXIVE ->
									candidate,io_lib:format("~d ~d udp ~d ~s ~d type srflx raddr ~s ~d",
										[F1,Cid,P1,Ip,Port,BaseIp,BasePort]}
								end,
								if Use
								Opts ++ T end,Candis),
	Opts3 =
	case UseRtcp of
		true->
			L1 = get(?DEFAULT),
			#candidate{ip=Ip,port=Port} = lists:nth(2,L1),
			Opts2 ++[{"rtcp",io_lib:format("~d IN IP4 ~s",[Ip,Port])}];
		_->
			Opts2
		end,	
	S#stream_info{options=Opts2)
	 .
build_sdp(#server{info=Info,use_rtcp=UseRtcp},L)->
	#media_info{video=Video,audio=Audio},
	put(count,0),
	V1 = lists:map(fun(A)->
				T1 = get(count) +1,
				put(count,T1),
				build_stream_info(A,T1,UseRtcp) end,Video),
	put(count,0),
	A2 = lists:map(fun(A)->
				T1 = get(count) +1,
				put(count,T1),
				build_stream_info(A,T1,UseRtcp) end,Audio),
	put(?SDP,sdp:encode(Info#media_info{video=V1,audio=A1)).
	.


computing_foundations(L)->
	put(tmp,dict:new()),
	lists:map(fun(#candidate{type=Type,tranport=T1,base_addr=#ice_address{ip=Ip},turn_server=#turn_server{ip=Sip})->
				random:seed(erlang:now()),
				Fid = random:uniform( 1 bsl 20),
				case Type of 
					?CANDIDATE_TYPE_HOST->
						dict_store(tmp,{T1,Type,Ip},Fid);
					_->
						dict_store(tmp,{T1,Type,Sip},Fid)
					end,ok end,L),
	lists:map(fun(#candidate{type=Type,tranport=T1,base_addr=#ice_address{ip=Ip},turn_server=#turn_server{ip=Sip} = C)->
				{ok,Fid} = 
				case Type of 
					?CANDIDATE_TYPE_HOST->
						dict:find(get(tmp),{T1,Type,Ip});
					_->
					dict:find(get(tmp),{T1,Type,Sip})
				end,
				C#candidate{fid=Fid} end,L).
					


prioritize(#server{info=Info}=Server)->
	#media_info{video=Video,audio=Audio) = Info,
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
		compare_type(A#candidate.type,B#candidate.type) end,L),
	lists:nth(1,L1).
										
choose_default(#server{use_rtp=false,L5)->
	lists:map(fun(A)->
				get_default(A) end,L5);
choose_default(#server{use_rtp=false,L5)->
	lists:map(fun(A)->
				 A1 = lists:map(fun(#candidate{cid=Cid)->
								Cid =:=1 end,A),
				A2 = lists:map(fun(#candidate{cid=Cid)->
								Cid =:=2 end,A),
				[get_default(A1),get_default(A2)]
				 end,L5).			


%%%% local api
build_host(Ips,Streams,UseRtcp)->
    lists:map(fun(Ip)->
		      L = new_addr(Ip,Streams,UseRtcp),
		      lists:map(fun(#stream{}=A2)->
					new_host_candidate(A2),
				end,L)
	      end ,Ips),
    put(?GATHER_QUE,get(?HOST_LIST))
	.

new_addr(Ip,Streams,UseRtcp)->
    L1 = lists:foldl(fun(#stream{port=Port}=C,Acc)->
			     C1 = C#stream{cid=1,ip=Ip},
				 if UseRtcp ->
					C2 = C#stream{port=Port + 1,cid=2},
					Acc ++ [C1,C2];
				true->
					Acc ++ [A1]
				end end ,Streams)
    L1.

new_host_candidate(#stream{sid=Sid,ip=Ip,port=Port,cid=Cid,user=User,pwd=Pwd})->   
    {ok,Ip1} = inet_parse:address(Ip),
	D = get(?HOST_SOCKET),
	Socket = 
	case dict:find({Ip,Port,udp},D) of
		{ok,S}->
			S
		_->
		case gen_udp:open(Port,[{ip,Ip1}]) of
			{ok,S} ->
				S;
			Err->
				throw(Err)
		end	
	end,
	C1 = #candidate{
			id = increment(?CANDIDATE_ID),
			type = ?CANDIDATE_TYPE_HOST,
			transport = udp,
			addr = #ice_address{ip=Ip,port=Port},
			base_addr = #ice_address{ip=Ip,port=Port},
			socket = Socket,
			component_id = Cid,
			user = User,
			pwd = Pwd,
			sid=Sid
			},		
			head_list(?HOST_LIST,C1),
			dict_store(?SOCKET_DICT,S,C1)
			dict_store(?HOST_SOCKET,{Ip,Port,udp},S)
	.
dict_store(Name,K,V)->
	D = get(Name),
	put(?SOCKET_DICT,dict:store(S,K,V)).
dict_del(Name,K,V)->
	D = get(Name),
	put(?SOCKET_DICT,dict:delete(S,K)).
pcall(K,L)->
	case properlist:get_value(K,L) of
		undefined->
			throw({no_key_error,K);
		V->
			V
	end.
get_streams(#media_info{video=Video,audio=Audio)->
	Streams =   Audio ++Video,
	lists:map(fun(#stream_info{options=Opts},stream_id=Sid)->
			#stream{sid=Sid,port=pcall(port,Opts),user=pcall('ice-ufrag',Opts),pwd=pcall('ice-pwd',Opts)}
		 end,Streams).
get_remotes(#media_info{video=Video,audio=Audio})->
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
								CANDIDATE_TYPE_PREF_SEVER_REFLEXIVE	
						end,
						#candidate{
								id = increment(?CANDIDATE_ID),
								type = ?CANDIDATE_TYPE_HOST,
								addr = #ice_address{ip=Ip,port=Port},
								base_addr = #ice_address{ip=Ip,port=Port},
								component_id = Cid,
								user = User,
								pwd = Pwd,
								sid=Sid
								} end,Cs)
		 end,Streams).
send_check(#server{},#candidate_checkpair{component_id=Cid,local=Local,remote=Remote}=Pair,Attrs)->
	%%peer reflex 
    P = eis_ice:candiate_pair_priority(#candidate{type=?CANDIDATE_TYPE_SEVER_REFLEXIVE,component_id=Cid}),
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
    TxId = increment(?TXID),
	#candidate{socket=Socket,user=User,pwd=Pwd} = Local,
	#candidate{addr=Addr,user=PeerUser,pwd=PeerPwd} = Remote,
	A2= [{'USERNAME',PeerUser++":"++User},{'PASSWORD',PeerPwd}],
    A3 = A1+A2 ++ Attrs,	
	    #ice_address{ip = Ip,port = Port} = Addr,
	    Req = #stun{
	      class = request,
	      method = binding,
	      transactionid = TxId,
	      fingerprint = true,
	      attrs = A3
	     },
	dict_store(?STUN_TRANS,TxId,Pair),
    Stun = stun:encode(Req),
    gen_udp:send(Socket,Ip,Port,Stun)
    .

update_check_list(C,State)->
    L = get(?CHECK_LIST),
    L2 = lists:map(fun(#candidate_checkpair{priority=P} =A)->
			   if P =:= C#candidate_checkpair.priority ->
				   C#candidate_checkpair{state=State};
			      true->
				   A end end ,L),
    put(?CHECK_LIST,L2)
    .

	new_pair(_A,[],Acc)->
    Acc;
new_pair(#candidate{foundation=F1,priority=P1,stream_id=SId,component_id=C1,type=Type}=A,
	 [#candidate{foundation=F2,priority=P2,component_id=C2}=H|T],Acc) when C1 =:=C2 andalso Type =/=?CANDIDATE_TYPE_SEVER_REFLEXIVE ->
    Priority = eis_ice:candiate_pair_priority(P1,P2),
    P = #candidate_checkpair{local=A,remote=H,foundation={F1,F2},
			     priority=Priority,state=?FROZEN,
			     component_id =C1,
			     stream_id = SId
			    },
    new_pair(A,T,[P|Acc]);
new_pair(A,[_H|T],Acc) ->
    new_pair(A,T,Acc).

build_pairs(Local,Remote)->
    L1 = lists:foldl(fun(A,Acc)->
			     Acc + new_pair(A,Remote,[])
		     end
		     ,[],Local),
    L2=lists:sort(fun(#candidate_checkpair{priority=A},#candidate_checkpair{priority=B})->
			  A>B end,L1),
    {ok,L2}.

