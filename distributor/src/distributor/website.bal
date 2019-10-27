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
        
        string tab = "<table><tr><th>Sequence No</th><th>Electoral District</th><th>Polling Division</th><th>JSON</th><th>Document</th></tr>";
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
                    return caller->ok (r.jsonResult);
                } else {
                    json j = { result: r.jsonResult };
                    return caller->ok(check xmlutils:fromJSON(j));
                }
            }
        }

        // bad request
        return caller->ok ("Not found!");
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
                if r.imageData is byte[] && r.imageMediaType is string {
                    hr.setBinaryPayload(r.imageData ?: []); // not needed .. type guard is not being propagated
                    hr.setContentType(r.imageMediaType ?: "text/plain"); // not needed
                    return caller->ok(hr);
                } else {
                    return caller->ok ("No official release available (yet)");
                }
            }
        }

        // bad request
        return caller->ok ("Not found!");
    }
}


