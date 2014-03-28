-module(eis_agent).
-include("eis_main.hrl").
-export([new/3]).

new(Handle,LocalAddr,Opts)->
    ok.
add_stream(Agent,ComponetCount)->
    ok.
gather_candidates(Agent,StreamId)->
    ok.
start(Agent,Role)->
    ok.

-define(AGENT_INIT,init).
-define(AGENT_GATHER,gather).
-define(AGENT_RUNNING,running).
-define(AGENT_CONN_CHECK,conn_check).
-define(AGENT_FAILED,failed).
-define(AGENT_COMPLETED,completed).
-define(Ta,30).
-compile([export_all]).
-record(sockets,{socket,candidate}).
-record(server, {
          parent::pid(),
          mod::atom(),
	  name,
          state::any(),
	  debug::boolean(),
	  agent_state,
	  client::pid(),
	  opts,
	  local_addrs,
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
	  user,
	  pwd,
	  action::offer|answer,
	  role::controlling|controlled
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
-define(SOCKETS_LIST,socket_ets).
-define(CANDIDATES_LIST,candidate_ets).
-define(HOST_LIST,host_list).
-define(LOCAL,local).
-define(REMOTE,remote).
-define(SDP,sdp).




-define(STUN_TRANS,stun_trans).



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

get_txid()->
    Id = get(txid)+1,
    put(txid,Id),
    Id.

reply({To,Tag},Reply)->
    catch To ! {Tag,Reply}.
?AGENT_GATHER(#server{from=From,turn_servers=TS,cur_turn_server=Cur}=Server,'$agent_gather',State)->
    Que = get(?GATHER_QUE),
    case Que of
	[] ->
	    prioritize(Server),
	    reply(From,{sdp,get(?SDP)}),
	    loop(Server,?AGENT_RUNNING);
	[{#candidate{socket=S}}=Candidate|Tail] ->
	    %%todo maybe use multi turn server
	    #turn_server{ip=Ip,port=Port}=lists:nth(Cur,TS),
	    Id = increment(?TXID),
	    D = get(?STUN_TRANS),
	    put(?STUN_TRANS,dict:store(Id,Candidate,D)),
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
	    erlang:send(self(),'$agent_gather'),
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
	    Base = #ice_address{ip=Ip,port=Port},
	    Id = increment(?CANDIDATE_ID),
	    C1 = #candidate{
	      id = Id,
	      type = ?CANDIDATE_TYPE_SEVER_REFLEXIVE,
	      transport = udp,
	      addr = Addr,
	      base_addr = Base,
	      component_id = Host#candidate.component_id,
	      stream_id = Host#candidate.stream_id
	     },
	    head_list(?CANDIDATES_LIST,C1);
	_->
	    flush
    end,
    loop(Server,AgentState).

-define(FROZEN,frozen).

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
-include("sdp.hrl").
-include("media_info.hrl").
build_remote(#media_info{options=Opts})->
    Session =  proplists:get_value(sdp_session,Opts),
    C = proplists:get_all_values(candidate,Session),
    lists:map(fun(A)->
		      Ts = string:tokens(A," "),
		      case Ts of
			  [CId,Fid,Pri,Ip,Host]->
			      #candidate{};
			  []->
			      #candidate{};
			  _->
			      #candidate{}
		      end end,C).
?AGENT_RUNNING(Server,{From,ice_connect,PeerSdp},_State) ->
    Peer = sdp:decode(PeerSdp),
    Remote = build_remote(Peer),
    put(?REMOTE,Remote),
    {ok,CheckList} = build_pairs(get(?LOCAL),Remote),
    put(?CHECK_LIST,CheckList),
    put(?TRIGGER_QUE,[]),
    put(?VALIDE_LIST,[]),
    erlang:send_after(?Ta,self(),conn_check),
    loop(Server#server{peer_sdp=Peer,from=From},?AGENT_CONN_CHECK)   
	.
send_check(#server{
		   peer_sdp = PeerSdp,
		   role=Role,user=User},
	   
	   #candidate_checkpair{component_id=CId,local=Local,remote=Remote}=Pair,Attrs)->
    P = eis_ice:candiate_pair_priority(#candidate{type=?CANDIDATE_TYPE_SEVER_REFLEXIVE,component_id=CId}),
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
    L1 = proplists:get_value(session_sdp,PeerSdp),
    PeerUser = proplists:get_value('ice-ufrag',L1),
    PeerPwd = proplists:get_value('ice-pwd',L1),
    A2= [{'USERNAME',PeerUser++":"++User},{'PASSWORD',PeerPwd}],
    A3 = A1+A2 ++ Attrs,	    
    TxId = increment(?TXID),
	    #candidate{socket=Socket} = Local,
	    #candidate{addr=Addr} = Remote,
	    #ice_address{ip = Ip,port = Port} = Addr,
	    Req = #stun{
	      class = request,
	      method = binding,
	      transactionid = TxId,
	      fingerprint = true,
	      attrs = A3
	     },
    D = get(?STUN_TRANS),
    D1 = dict:store(TxId,Pair,D),
    put(?STUN_TRANS,D1),
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

?AGENT_CONN_CHECK(#server{nominate_type=Type}=Server,conn_check,State) ->
    A1 = case Type of
	     ?AGENT_NOMINATE_REGULAR ->
		 [];
	     ?AGENT_NOMINATE_AGGRESSIVE->
		 [{'USE-CANDIDATE',1}]
	     end,
    L = get(?CHECK_LIST),
    case  L of
	[]->
	    loop(Server,failed);
	[#candidate_checkpair{priority=_P,remote=_Remote}=_Pair|_T]->
	    L1 = lists:filter(fun(#candidate_checkpair{state=S1})->
				      S1 =:= ?CHECK_WAITING end,L),
	    case L1 of
		[]->
		    L2 = lists:filter(fun(#candidate_checkpair{state=S2})->
					      S2 =:= ?CHECK_FROZEN end,L),
		    case L2 of
			[]->
			    ok;
			[C2|_] ->
			    send_check(Server,C2,A1),
			    update_check_list(C2,?CHECK_IN_PROGRESS)
		    end;
		[C1|_]->
		    send_check(Server,C1,A1),
		    update_check_list(C1,?CHECK_IN_PROGRESS)
	    end,
	    erlang:send_after(?Ta,self(),conn_check),
	    loop(Server,State)
    end;
conn_check(#server{socket_ets=SocketEts}=Server,{#stun{class = binding,
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

conn_check(#server{tx_ets=TxEts}=Server,{#stun{class = success,attrs=Attrs,transactionid=Txid}
					 ,{udp,_Socket,PeerIp,PeerPort,_}}
					 ,State) ->
    case ets:lookup(TxEts,Txid) of
	[]->
	    ok;
	[{_,#candidate_checkpair{local =Local,priority=P,foundation=F,stream_id=SId,component_id=CId}}|_]->
	    L = get(check_list),
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

build_sdp(#server{components=Cs,
		  user=User,
		  pwd=Pwd,
		  stream_id=StreamId},L)->
    Default = lists:map(fun(A)->
				L1 = lists:map(fun(C1)->
						       if A == C1#candidate.component_id ->
							       true;
							  true->
							       false
						       end
					       end,L),
				L2 = lists:sort(fun(#candidate{priority=P1},#candidate{priority=P2})->
							P1 > P2
						end,L1),
				[D|_] = L2,
				{A,D} end,Cs),		 
    
    put(default,Default),
    S1 = lists:foldl(fun({Cid,#candidate{addr=Addr,base_addr=Base,type=Type,priority=P1,foundation=F1}},Acc)->
			     #ice_address{ip=Ip,port=Port} = Addr,
			     #ice_address{ip=BaseIp,port=BasePort} = Base,
			     R1 =
				 case Type of 
				     ?CANDIDATE_TYPE_HOST ->
					 {candidate,[erlang:integer_to_list(Cid),?SPACE,
						     erlang:integer_to_list(F1),?SPACE,
						     "UDP",?SPACE,
						     erlang:integer_to_list(P1),?SPACE,
						     Ip,?SPACE,
						     integer_to_list(Port),?SPACE,
						     "typ host"]}			      
					     ;
				     ?CANDIDATE_TYPE_SEVER_REFLEXIVE ->
					 {candidate,[erlang:integer_to_list(Cid),?SPACE,
						     erlang:integer_to_list(F1),?SPACE,
						     "UDP",?SPACE,
						     erlang:integer_to_list(P1),?SPACE,
						     Ip,?SPACE,
						     integer_to_list(Port),?SPACE,
						     "typ srflx raddr",?SPACE,
						     BaseIp,?SPACE,
						     integer_to_list(BasePort),?SPACE
						    ]}
				 end,
			     [R1|Acc]
				 
		     end,[],Default),
    [{_,#candidate{addr=RtpAddr}}|_] = lists:filter(fun({A,_B})->
				       A == 1 end,Default),
    #ice_address{ip=RtpIp,port=_RtpPort} = RtpAddr,
    Rtcp =
	case
	    lists:filter(fun({A,_B})->
				A == 2 end,Default) of
	    []->[];
	    [#candidate{addr=RtcpAddr}|_]->
		#ice_address{ip=_RtcpIp,port=RtcpPort} = RtcpAddr,
		{rtcp,[integer_to_list(RtcpPort)]}
	end,
    Ice = [{"ice-pwd",User},
	   {"ice-ufrag",Pwd}],
    Attrs = Ice ++ Rtcp ++ S1,
    {ok,Sdp}=eis_media:encode_sdp(RtpIp,StreamId,Attrs),
    put(default,1),
    put(?SDP,Sdp).

build_foundation(L)->
    put(tmp,L),
    L1 = lists:foldl(fun(A,{FId,Acc})->
			     T1 = get(tmp),
			     T2 = lists:delete(A,T1),
			     put(tmp,T2),
			     #candidate{type=Type,base_addr=Base,turn_servers=S} = A,
			     Ip = Base#ice_address.ip,
			     L2 = lists:filter(fun(B)->
						       #candidate{type=TypeB,base_addr=BaseB,turn_servers=SB} = B,
						       IpB = BaseB#ice_address.ip,
						       case {Type,Ip,S} of
							   {TypeB,IpB,SB}->
							       true;
						      _->
							       false
						       end
					       end,get(tmp)),
			     lists:map(fun(C)->
					       L3 = get(tmp),
					       L4 = lists:delete(C,L3),
					       put(tmp,L4) end,L2),
			     L5 = lists:map(fun(C)->
						    C#candidate{foundation=FId} end,L2),
			     L6 = [A#candidate{foundation = FId}|L5],
			     {FId+1,Acc++L6} end,{1,[]},L),
    L1.

prioritize(Server)->
    L1 = get(?CANDIDATES_LIST),
    L2 = lists:map(fun(A)->
		      P = eis_ice:candidate_ice_priority(A),
		      A#candidate{priority = P} end,L1),
    L3 = lists:filter(fun(A)->
			      not_redundant(A,L2) end,L2),
    L4 = build_foundation(L3),

    put(?LOCAL,L4),
    build_sdp(Server,L4),
    ok.



%%%% local api
build_host(#server{
		local_addrs = Addrs,
		stream_id =SId,
		components=CIds})->
    lists:map(fun(Addr)->
		      L = new_addr(Addr,CIds),
		      lists:map(fun(#ice_address{}=A2)->
					{ok,Local} = new_host_candidate(A2,SId),
					Id = increment(?CANDIDATE_ID),
					C1 = Local#candidate{id=Id},
					head_list(?HOST_LIST,C1), 
					head_list(?SOCKETS_LIST,#sockets{socket=C1#candidate.socket,candidate=C1})
				end,L)
			  
	      end ,Addrs),
    put(?GATHER_QUE,get(?HOST_LIST))
	.

new_addr(#ice_address{port = Port}=Addr,CIds)->
    L1 = lists:foldl(fun(CId,{Acc,Start})->
			     A1 = Addr#ice_address{port=Start,cid=CId},
			     {[A1|Acc],Start+1} end,{[],Port},CIds),
    L1.

new_host_candidate(#ice_address{ip=Ip,port=Port,cid=CId}=A,SId)->   
    {ok,Ip1} = inet_parse:address(Ip),
    {ok,S} = gen_udp:open(Port,[{ip,Ip1}]),
    C1 = #candidate{
      type = ?CANDIDATE_TYPE_HOST,
      transport = udp,
      addr = A#ice_address{cid=undefined},
      base_addr = A#ice_address{cid=undefined},
      socket = S,
      component_id = CId,
      stream_id = SId
     },
    {ok,C1}.

