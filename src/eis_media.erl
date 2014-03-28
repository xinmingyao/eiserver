-module(eis_media).

-compile([export_all]).
-include("../include/sdp.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("../include/video_frame.hrl").
-include("../include/media_info.hrl").
-include("../include/h264.hrl").
-include("../include/aac.hrl").
-include("log.hrl").

encode_sdp(Ip,StreamId,A)->
    Audio = #stream_info{
      content = audio,
      stream_id = 2,
      codec = aac,
      config = <<18,16>>, 
      params = #audio_params{channels = 2, sample_rate = 44100},
      timescale = 44.1
     },
    Attrs= A++[ 
		{type, "broadcast"},
		{control, "*"},
		recvonly,
		{range, "npt=0-"}
	      ] ,
    Session = #sdp_session{version = 0,
			   originator = #sdp_o{username = <<"-">>,
					       sessionid = <<"234234">>,
					       version = <<"546456">>,
					       netaddrtype = inet4,
					       address = Ip},
			   name = <<"ErlySession">>,
			   connect = {inet4,Ip},
			   attrs = Attrs},
    Video =   #stream_info{
      content = video,
      stream_id = StreamId,
      codec = vp8,
      config = <<1,66,0,41,255,225,0,18,103,66,0,41,227,80,20,7,182,2,220,4,4,6,144,120,145,
		 21,1,0,4,104,206,60,128>>, 
      params = #video_params{width = 640, height = 480},
      timescale = 90.0},
    Media = #media_info{audio = [Audio], video = [Video], options = [{sdp_session, Session}]},
    {ok,sdp:encode(Media)}
    .
    


