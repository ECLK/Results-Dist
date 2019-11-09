import ballerina/http;
import ballerina/mime;
import ballerina/time;
import ballerina/xmlutils;

# Show a website for media people to get a list of all released results with
# links to each json value and the image with the signed official document.
@http:ServiceConfig {
    basePath: "/"
}
service mediaWebsite on mediaListener {
    @http:ResourceConfig {
        path: "/",
        methods: ["GET"]
    }
    resource function showAll (http:Caller caller, http:Request req) returns error? {
        string head = "<head><title>Sri Lanka Elections Commission</title></head>";
        string body = "<body>";
        body = body + "<h1>Released Results Data for Media Partners</h1>";
        string tt = check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ");
        body = body + "<p>List of all released results as of " + tt + "</p>";
        
        string tab = "<table><tr><th>Sequence No</th><th>Electoral District</th><th>Polling Division</th><th>JSON</th><th>XML</th><th>Document</th></tr>";
        int i = resultsCache.length();
        while i > 0 { // show results in reverse order of release
            i = i - 1;
            Result r = resultsCache[i];
            string seqNo = r.jsonResult.sequence_number.toString();
            string edName = r.jsonResult.ed_name.toString();
            string pdName = r.jsonResult.pd_name.toString();
            tab = tab + "<tr>" +
                        "<td>" + seqNo + "</td>" +
                        "<td>" + edName + "</td>" +
                        "<td>" + pdName + "</td>" +
                        "<td><a href='/result/" + r.election + "/" + seqNo + "?format=json'>JSON</a>" + "</td>" +
                        "<td><a href='/result/" + r.election + "/" + seqNo + "?format=xml'>XML</a>" + "</td>" +
                        "<td><a href='/release/" + r.election + "/" + seqNo + "'>Release</a>" + "</td>" +
                        "</tr>";
        }
        tab = tab + "</table>";
        body = body + tab;
        body = body + "</body>";
        string doc = "<html>" + head + body + "</html>";

        http:Response hr = new;
        hr.setPayload(doc);
        hr.setContentType(mime:TEXT_HTML);
        return caller->ok(hr);
    }

    @http:ResourceConfig {
        path: "/result/{election}/{seqNo}",
        methods: ["GET"]
    }
    resource function data (http:Caller caller, http:Request req, string election, int seqNo) returns error? {
        // what's the format they want? we'll default to json if they don't say or get messy
        string format = req.getQueryParamValue ("format") ?: "json";
        if format != "xml" && format != "json" {
            format = "json";
        }

        // find the result object and send it in the format they want
        foreach Result r in resultsCache {
            if r.election == election && r?.sequenceNo == seqNo {
                if format == "json" {
                    return caller->ok(r.jsonResult);
                } else {
                    // put the result json object into a wrapper object to get a parent element
                    // NOTE: this code must match the logic in the subscriber saving code as
                    // both add this object wrapper with the property named "result". Bit
                    // dangerous as someone can forget to change both together - hence this comment!
                    json j = { result: r.jsonResult };
                    return caller->ok(check xmlutils:fromJSON(j));
                }
            }
        }

        // bad request
        http:Response res = new;
        res.statusCode = http:STATUS_NOT_FOUND;
        return caller->respond(res);
    }

    @http:ResourceConfig {
        path: "/release/{election}/{seqNo}",
        methods: ["GET"]
    }
    resource function releaseDoc (http:Caller caller, http:Request req, string election, int seqNo) returns error? {
        http:Response hr = new;

        // find image of the release doc and return it (if its there - may not have appeared yet)
        foreach Result r in resultsCache {
            if r.election == election && r?.sequenceNo == seqNo {
                byte[]? imageData = r.imageData;
                string? imageMediaType = r.imageMediaType;

                if imageData is byte[] && imageMediaType is string {
                    hr.setBinaryPayload(imageData);
                    hr.setContentType(imageMediaType);
                    return caller->ok(hr);
                } else {
                    return caller->ok("No official release available (yet)");
                }
            }
        }

        // bad request
        http:Response res = new;
        res.statusCode = http:STATUS_NOT_FOUND;
        return caller->respond(res);
    }

    @http:ResourceConfig {
        path: "/sms/{mobileNo}",
        methods: ["GET"]
    }
    resource function smsRegistration (http:Caller caller, http:Request req, string mobileNo) returns error? {
        string mobile = sanitize(mobileNo);

        if (mobile.length() != 11) {
            http:Response res = new;
            res.statusCode = http:STATUS_BAD_REQUEST;
            res.setPayload("Invalid mobile number. Resend the request as follows: If your mobile no is 0771234567," +
                                " then send GET request to \"/sms/94771234567\"");
            return caller->respond(res);
        }

        string|error status = "";
        lock {
            status = registerAsSMSRecipient("tel:" + mobile);
        }
        if (status is error) {
            http:Response res = new;
            res.statusCode = http:STATUS_INTERNAL_SERVER_ERROR;
            res.setPayload(<string> status.detail()?.message);
            return caller->respond(res);
        }

        return caller->ok(<string> status);
    }

    @http:ResourceConfig {
        path: "/sms/{mobileNo}",
        methods: ["DELETE"]
    }
    resource function smsDeregistration (http:Caller caller, http:Request req, string mobileNo) returns error? {
        string mobile = sanitize(mobileNo);

        if (mobile.length() != 11) {
            http:Response res = new;
            res.statusCode = http:STATUS_BAD_REQUEST;
            res.setPayload("Invalid mobile number. Resend the request as follows: If your mobile no is 0771234567," +
                                " then send DELETE request to \"/sms/94771234567\"");
            return caller->respond(res);
        }

        string|error status = "";
        lock {
            status = unregisterAsSMSRecipient("tel:" + mobile);
        }
        if (status is error) {
            http:Response res = new;
            res.statusCode = http:STATUS_INTERNAL_SERVER_ERROR;
            res.setPayload(<string> status.detail()?.message);
            return caller->respond(res);
        }

        return caller->ok(<string> status);
    }
}


