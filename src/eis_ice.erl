-module(eis_ice).
-include("eis_main.hrl").
-compile([export_all]).
candidate_ice_priority(Candidate)->
    Type = Candidate#candidate.type,
    CId = Candidate#candidate.component_id,
    TypeRef = 
	case Type of
	    ?CANDIDATE_TYPE_HOST ->
		?CANDIDATE_TYPE_PREF_HOST;
	    ?CANDIDATE_TYPE_PEER_REFLEXIVE ->
		?CANDIDATE_TYPE_PREF_PEER_REFLEXIVE;
	    ?CANDIDATE_TYPE_SEVER_REFLEXIVE ->
		?CANDIDATE_TYPE_PREF_SEVER_REFLEXIVE;
	    ?CANDIDATE_TYPE_RELAYED ->
		?CANDIDATE_TYPE_PREF_RELAYED
	end,
    candidate_ice_priority_full(TypeRef,1,CId)
    .
candidate_ice_priority_full(TypePreference,LocalPreference,ComponentId)->
    16#1000000 * TypePreference +
	16#100 * LocalPreference +
	16#100 - ComponentId.
candiate_pair_priority(Local,Remote)->
    {Max,Min,Value} = 
	if Local > Remote ->
		{Local,Remote,1}; 
	   ture ->
		{Remote,Local,0}
	end,
    1 bsl 32 * Min + 2 * Max + Value.




