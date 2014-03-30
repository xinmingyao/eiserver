
%%stun

-include("stun.hrl").
-include("rtp.hrl").
-include("rtcp.hrl").
-include("srtp.hrl").
-include("sdp.hrl").
-include("media_info.hrl").
%%ice see 

-define(SUTN_USAGE_ICE_COMPATIBILITY_RFC5245,0).
-define(SUTN_USAGE_ICE_COMPATIBILITY_GOOGLE,1).
-define(SUTN_USAGE_ICE_COMPATIBILITY_MSN,2).
-define(SUTN_USAGE_ICE_COMPATIBILITY_WLM2009,3).
-define(SUTN_USAGE_ICE_COMPATIBILITY_DRAFT19,4).

-define(SUTN_USAGE_ICE_RETURN_SUCCESS,0).
-define(SUTN_USAGE_ICE_RETURN_ERROR,1).
-define(SUTN_USAGE_ICE_RETURN_INVALID,2).
-define(SUTN_USAGE_ICE_RETURN_ROLE_CONFLICT,3).
-define(SUTN_USAGE_ICE_RETURN_INVALID_REQUEST,4).
-define(SUTN_USAGE_ICE_RETURN_INVALID_METHOD,5).
-define(SUTN_USAGE_ICE_RETURN_MEMORY_ERROR,6).
-define(SUTN_USAGE_ICE_RETURN_INVALID_ADDRESS,7).
-define(SUTN_USAGE_ICE_RETURN_NO_MAPPED_ADDRESS,8).

%%candidate

-define(CANDIDATE_TYPE_PREF_HOST,120).
-define(CANDIDATE_TYPE_PREF_PEER_REFLEXIVE,110).
-define(CANDIDATE_TYPE_PREF_SEVER_REFLEXIVE,100).
-define(CANDIDATE_TYPE_PREF_RELAYED,60).

-define(CANDIDATE_TYPE_HOST,0).
-define(CANDIDATE_TYPE_SEVER_REFLEXIVE,1).
-define(CANDIDATE_TYPE_PEER_REFLEXIVE,2).
-define(CANDIDATE_TYPE_RELAYED,3).

-define(CANDIDATE_TRANSPORT_UDP,0).

-define(RELAY_TYPE_TURN_UDP,0).
-define(RELAY_TYPE_TURN_TCP,0).
-define(RELAY_TYPE_TURN_TLS,0).
-record(ice_address,{ip,port,type=udp,cid::component_id}).
-record(turn_server,{ip,port,user,pwd,type=udp}).
-record(candidate,{
	  id,
	  type,
	  transport=udp,
		   addr,
		   base_addr,
		   priority,
		   stream_id,
		   component_id,
		   foundation,
		   user,
		   pwd,
		   turn_server,
		   socket
		  }).

-define(CHECK_WAITING,1).
-define(CHECK_IN_PROGRESS,2).
-define(CHECK_SUCCEEDED,3).
-define(CHECK_FAILED,4).
-define(CHECK_FROZEN,5).
-define(CHECK_CANCELLED,6).
-define(CHECK_DISCOVERED,7).

-define(AGENT_ROLE_CONTROLLING,1).
-define(AGENT_ROLE_CONTRLLEND,2).
-define(AGENT_NOMINATE_REGULAR,regular).
-define(AGENT_NOMINATE_AGGRESSIVE,aggressive).

-record(candidate_checkpair,{
	  agent,
	  stream_id,
	  component_id,
	  local,
	  remote,
	  foundation,
	  state,
	  is_nominated,
	  is_controlling,
	  is_timer_restarted,
	  priority,
	  next_tick,
	  stun_msg
	 }).
-record(agent_video,{port,attrs}.
-record(agent_audio,{port,attrs}.
-record(agent_info,{media::#media_info{},hosts,stun_servers}).




















