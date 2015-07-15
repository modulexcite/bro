@load base/frameworks/files
@load base/utils/paths
@load base/utils/queue

module OCSP;

export {
	## add one more argument to tell ocsp response or request
	redef record Files::AnalyzerArgs += {
		ocsp_type: string &optional;
	};

        ## ocsp logging
	redef enum Log::ID += { LOG };

	## type for pending ocsp request
	type PendingQueue: table[OCSP::CertId] of Queue::Queue;

	## NOTE: one file could contain several requests
	## one ocsp request record
	type Info_req: record {
		## time for the request
	        ts:                 time;
		## file id for this request
		id:                 string  &log &optional;
		## connection id
		cid:                conn_id &optional;
		## connection uid
		cuid:               string  &optional;
		## version
		version:            count   &log &optional;
		## requestor name
		requestorName:      string  &log &optional;
		## NOTE: the above are for one file which may contain
		##       several ocsp requests
		## request cert id
		certId:             OCSP::CertId &optional;
		## HTTP method
		method:             string &optional;
	};

	## NOTE: one file could contain several response
	## one ocsp response record
	type Info_resp: record {
		## time for the response
	        ts:                 time;
		## file id for this response
		id:                 string  &log;
		## connection id
		cid:                conn_id &optional;
		## connection uid
		cuid:               string  &optional;
		## responseStatus (different from cert status?)
		responseStatus:     string  &log;
		## responseType
		responseType:       string  &log;
		## version
		version:            count   &log;
		## responderID
		responderID:        string  &log;
		## producedAt
		producedAt:         string  &log;

		## NOTE: the following are specific to one cert id
		##       the above are for one file which may contain
		##       several responses
		##cert id
		certId:             OCSP::CertId  &optional;
		## certStatus (this is the response to look at)
		certStatus:         string  &log  &optional;
		## thisUpdate
		thisUpdate:         string  &log  &optional;
		## nextUpdate
		nextUpdate:         string  &log  &optional;
	};

	type Info: record {
		## timestamp for request if a corresponding request is present
		## OR timestamp for response if a corresponding request is not found
		ts:                 time          &log;

		## connection id
		cid:                conn_id       &log;

		## connection uid
		cuid:               string        &log;

		## cert id
		certId:             OCSP::CertId  &log  &optional;

		## request
		req:                Info_req      &log  &optional;

		## response timestamp
		resp_ts:            time          &log  &optional;

		## response
		resp:               Info_resp     &log  &optional;

		## HTTP method
		method:             string        &log  &optional;
	};

        ## Event for accessing logged OCSP records.
	global log_ocsp: event(rec: Info);
}

redef record HTTP::Info += {
	# there should be one request and response but use Queue here
	# just in case
	ocsp_requests:            PendingQueue  &optional;
	ocsp_responses:           PendingQueue  &optional;

	current_content_type:     string        &optional &default="";
	original_uri:             string        &optional;

	# flag for checking get uri
	checked_get:              bool          &optional &default=F;
	};

event http_request(c: connection, method: string, original_URI: string, unescaped_URI: string, version: string)
	{
	c$http$original_uri = original_URI;
	}

event http_content_type(c: connection, is_orig: bool, ty: string, subty: string)
	{
	c$http$current_content_type = to_lower(ty + "/" + subty);
	}

function check_ocsp_file(f: fa_file, meta: fa_metadata)
	{
	if ( f$source != "HTTP" || ! f?$http )
		return;

	# call OCSP file analyzer
	if ( (meta?$mime_type && meta$mime_type == "application/ocsp-request") || f$http$current_content_type == "application/ocsp-request")
		{
		Files::add_analyzer(f, Files::ANALYZER_OCSP, [$ocsp_type = "request"]);
		}
	else if ( (meta?$mime_type && meta$mime_type == "application/ocsp-response") || f$http$current_content_type == "application/ocsp-response")
		{
		Files::add_analyzer(f, Files::ANALYZER_OCSP, [$ocsp_type = "response"]);
		}
	}

event file_sniff(f: fa_file, meta: fa_metadata) &priority = 5
	{
	if (f$source == "HTTP")
		check_ocsp_file(f, meta);
	}

function update_http_info(http: HTTP::Info, req_rec: OCSP::Info_req)
	{
	if ( http?$method )
		req_rec$method = http$method;
	}

function enq_request(http: HTTP::Info, req: OCSP::Request, file_id: string, req_ts: time)
	{
	if (req?$requestList)
		{
		for (x in req$requestList)
			{
			local one_req = req$requestList[x];
			local cert_id: OCSP::CertId = [$hashAlgorithm  = one_req$hashAlgorithm,
						       $issuerNameHash = one_req$issuerNameHash,
						       $issuerKeyHash  = one_req$issuerKeyHash,
						       $serialNumber   = one_req$serialNumber];
			local req_rec: OCSP::Info_req = [$ts     = req_ts,
							 $certId = cert_id,
							 $cid    = http$id,
							 $cuid   = http$uid];
			if ( |file_id| > 0 && http$method != "GET" )
				req_rec$id = file_id;
			
			if ( req?$version )
				req_rec$version = req$version;

			if ( req?$requestorName )
				req_rec$requestorName = req$requestorName;

			if ( ! http?$ocsp_requests )
				http$ocsp_requests = table();

			if ( cert_id !in http$ocsp_requests )
				http$ocsp_requests[cert_id] = Queue::init();

			update_http_info(http, req_rec);
			Queue::put(http$ocsp_requests[cert_id], req_rec);
			}
		}
	else
		{
		# no request content? this is weird but log it anyway
		local req_rec_empty: OCSP::Info_req = [$ts   = req_ts,
			                               $cid  = http$id,
						       $cuid = http$uid];
		if ( |file_id| > 0 && http$method != "GET" )
			req_rec_empty$id = file_id;
		if (req?$version)
			req_rec_empty$version = req$version;
		if (req?$requestorName)
			req_rec_empty$requestorName = req$requestorName;
		update_http_info(http, req_rec_empty);
		Log::write(LOG, [$ts=req_rec_empty$ts, $req=req_rec_empty, $cid=http$id, $cuid=http$uid, $method=http$method]);
		}
	}	

event ocsp_request(f: fa_file, req_ref: opaque of ocsp_req, req: OCSP::Request) &priority = 5
	{
        if ( ! f?$http )
		return;
	enq_request(f$http, req, f$id, network_time());
	}

event ocsp_response(f: fa_file, resp_ref: opaque of ocsp_resp, resp: OCSP::Response) &priority = 5
	{
	if ( ! f?$http )
		return;

	if (resp?$responses)
		{
		for (x in resp$responses)
			{
			local single_resp: OCSP::SingleResp = resp$responses[x];
			local cert_id: OCSP::CertId = [$hashAlgorithm  = single_resp$hashAlgorithm,
						       $issuerNameHash = single_resp$issuerNameHash,
						       $issuerKeyHash  = single_resp$issuerKeyHash,
						       $serialNumber   = single_resp$serialNumber];
			local resp_rec: Info_resp = [$ts             = network_time(),
						     $id             = f$id,
						     $cid            = f$http$id,
						     $cuid           = f$http$uid,
						     $responseStatus = resp$responseStatus,
						     $responseType   = resp$responseType,
						     $version        = resp$version,
						     $responderID    = resp$responderID,
						     $producedAt     = resp$producedAt,
						     $certId         = cert_id,
						     $certStatus     = single_resp$certStatus,
						     $thisUpdate     = single_resp$thisUpdate];
			if (single_resp?$nextUpdate)
				resp_rec$nextUpdate = single_resp$nextUpdate;

			if ( ! f$http?$ocsp_responses )
				f$http$ocsp_responses = table();
					
			if ( cert_id !in f$http$ocsp_responses )
				f$http$ocsp_responses[cert_id] = Queue::init();

			Queue::put(f$http$ocsp_responses[cert_id], resp_rec);				
			}
		}
	else
		{
                # no response content? this is weird but log it anyway
		local resp_rec_empty: Info_resp = [$ts             = network_time(),
			                           $id             = f$id,
			                           $cid            = f$http$id,
						   $cuid           = f$http$uid,
						   $responseStatus = resp$responseStatus,
						   $responseType   = resp$responseType,
						   $version        = resp$version,
						   $responderID    = resp$responderID,
						   $producedAt     = resp$producedAt];
		local info_rec: Info = [$ts      = resp_rec_empty$ts,
					$resp_ts = resp_rec_empty$ts,
					$resp    = resp_rec_empty,
					$cid     = f$http$id,
					$cuid    = f$http$uid];
		if ( f$http?$method )
			info_rec$method = f$http$method;
		Log::write(LOG, info_rec);
		}
	}

function log_unmatched_reqs_queue(q: Queue::Queue)
	{
	local reqs: vector of Info_req;
	Queue::get_vector(q, reqs);
	for ( i in reqs )
		{
		local info_rec: Info = [$ts     = reqs[i]$ts,
			                $certId = reqs[i]$certId,
					$req    = reqs[i],
					$cid    = reqs[i]$cid,
					$cuid   = reqs[i]$cuid];
		if ( reqs[i]?$method )
			info_rec$method = reqs[i]$method;
		Log::write(LOG, info_rec);
		}
	}

function log_unmatched_reqs(reqs: PendingQueue)
	{
	for ( cert_id in reqs )
		log_unmatched_reqs_queue(reqs[cert_id]);
	clear_table(reqs);
	}

function remove_first_slash(s: string): string
	{
	local s_len = |s|;
	if (s[0] == "/")
		return s[1:s_len];
	else
		return s;
	}

function get_uri_prefix(s: string): string
	{
	s = remove_first_slash(s);
	local w = split_string(s, /\//);
	if (|w| > 1)
		return w[0];
	else
		return "";
	}			

function check_ocsp_request_uri(http: HTTP::Info): OCSP::Request
	{
	local parsed_req: OCSP::Request;
	if ( ! http?$original_uri )
		return parsed_req;;

	local uri: string = remove_first_slash(http$uri);
	local uri_prefix: string = get_uri_prefix(http$original_uri);
	local ocsp_req_str: string;
	
	if ( |uri_prefix| == 0 )
		{
		ocsp_req_str = uri;
		}
	else if (|uri_prefix| > 0)
		{
		uri_prefix += "/";
		ocsp_req_str = uri[|uri_prefix|:];
		}
	parsed_req = ocsp_parse_request(decode_base64(ocsp_req_str));
	return parsed_req;
	}

function start_log_ocsp(http: HTTP::Info)
	{
	if ( ! http?$ocsp_requests && ! http?$ocsp_responses )
		return;

	if ( ! http?$ocsp_responses )
		{
		log_unmatched_reqs(http$ocsp_requests);
		return;
		}
	
	for ( cert_id in http$ocsp_responses )
		{
		while ( Queue::len(http$ocsp_responses[cert_id]) != 0 )
			{
			# have unmatched responses
			local resp_rec: Info_resp = Queue::get(http$ocsp_responses[cert_id]);
			local info_rec: Info = [$ts      = resp_rec$ts,
			                        $certId  = resp_rec$certId,
						$resp_ts = resp_rec$ts,
						$resp    = resp_rec,
						$cid     = http$id,
						$cuid    = http$uid,
						$method  = http$method];				

			if ( http?$ocsp_requests && cert_id in http$ocsp_requests )
				{
				# find a match
				local req_rec: Info_req = Queue::get(http$ocsp_requests[cert_id]);
				info_rec$req = req_rec;
				info_rec$ts  = req_rec$ts;
				if (Queue::len(http$ocsp_requests[cert_id]) == 0)
					delete http$ocsp_requests[cert_id];
				}
			else
				{
				if ( http$method == "GET" && ! http$checked_get )
					{
					http$checked_get = T;
					local req_get: OCSP::Request = check_ocsp_request_uri(http);
					enq_request(http, req_get, "", http$ts);
					if ( http?$ocsp_requests && cert_id in http$ocsp_requests )
						{
						# find a match
						local req_rec_tmp: Info_req = Queue::get(http$ocsp_requests[cert_id]);
						info_rec$req = req_rec_tmp;
						info_rec$ts  = req_rec_tmp$ts;
						if (Queue::len(http$ocsp_requests[cert_id]) == 0)
							delete http$ocsp_requests[cert_id];
						}
					}
				}
			Log::write(LOG, info_rec);
			}
		if ( Queue::len(http$ocsp_responses[cert_id]) == 0 )
			delete http$ocsp_responses[cert_id];
		}
	if ( http?$ocsp_requests && |http$ocsp_requests| != 0 )
		log_unmatched_reqs(http$ocsp_requests);
	}
	
# log OCSP information
event HTTP::log_http(rec: HTTP::Info)
	{
	start_log_ocsp(rec);
	}

event bro_init() &priority=5
	{
	Log::create_stream(LOG, [$columns=Info, $ev=log_ocsp, $path="ocsp"]);
	}
