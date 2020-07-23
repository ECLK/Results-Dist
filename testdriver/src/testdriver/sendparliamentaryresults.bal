import ballerina/io;
import ballerina/http;
import ballerina/time;
import ballerina/runtime;
import ballerina/encoding;

const R_V = "R_V";
const R_S = "R_S";
const R_VS = "R_VS";
const R_VSN = "R_VSN";
const R_SC = "R_SC";
const R_NC = "R_NC";
const R_SCNC = "R_SCNC";

const FINAL = "FINAL";

function sendParliamentaryResults(string electionCode, http:Client rc, map<json>[] results) returns error? {

    foreach map<json> result in results {

        string resultType = result.'type.toString();
        match resultType {
            R_V => {
                check updateByParty(result);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, result.pd_code.toString(), result);
            }
            R_S => {
                check updateByParty(result);
                check feedResult(rc, electionCode, resultType, result.ed_code.toString(), result);
            }
            R_VS => {
                check updateByParty(result);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
            R_VSN => {
                check updateByParty(result);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
            R_SC => {
                check feedResult(rc, electionCode, resultType, result.ed_code.toString(), result);
            }
            R_NC => {
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
            R_SCNC => {
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
        }
        // delay a bit
        runtime:sleep(sleeptime);
    }
}

function updateByParty(map<json> result) returns error? {
    // add missing info in test data: party_name and candidate for each party result if needed only (2019 set has it)
    json[] pr = <json[]>result.by_party;
    foreach int i in 0 ..< pr.length() {
        map<json> onePr = <map<json>>pr[i];
        if pr[i].party_name is string {
            continue;
        }
        onePr["party_name"] = (pr[i].party_name is string) ? check pr[i].party_name : "Party " + <string>pr[i].party_code;
        onePr["candidate"] = (pr[i].candidate is string) ? check pr[i].candidate : "Candidate " + <string>pr[i].party_code;
        // change percentage to string
        var val = trap <float>pr[i].vote_percentage;
        if val is error {
            // already a string so let it go
        } else {
            onePr["vote_percentage"] = io:sprintf ("%.2f", val);
        }
    }
}

function updateSummary(map<json> result) returns error? {
    // set the percentages in the summary
    map<json> summary = <map<json>>result.summary;
    summary["percent_valid"] = (<int>result.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", <int>result.summary.valid*100.0/<int>result.summary.polled);
    summary["percent_rejected"] = (<int>result.summary.polled == 0) ? "0.00" : io:sprintf("%.2f", <int>result.summary.rejected*100.0/<int>result.summary.polled);
    summary["percent_polled"] = (<int>result.summary.electors == 0) ? "0.00" : io:sprintf("%.2f", <int>result.summary.polled*100.0/<int>result.summary.electors);

}


function feedResult (http:Client hc, string electionCode, string resType, string resCode, map<json> result) returns
error? {
    // reset time stamp of the result to now
    result["timestamp"] = check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ");
    http:Response hr;

    // sent alert
    string params = "/?level=" + <string>result.level;
    if result.ed_name is string {
        params += "&ed_name=" + check encoding:encodeUriComponent(<string>result.ed_name, "UTF-8");
        if result.pd_name is string {
            params += "&pd_name=" + check encoding:encodeUriComponent(<string>result.pd_name, "UTF-8");
        }
    }
    hr = check hc->post ("/result/notification/" + electionCode + "/" + resType + "/" + resCode + params, <json>{});
    if hr.statusCode != http:STATUS_ACCEPTED {
        io:println("Error while posting result notification to: /result/notification/" + electionCode + "/" + resType + "/" + resCode + params);
        io:println("\tstatus=", hr.statusCode, ", contentType=", hr.getContentType(), " payload=", hr.getTextPayload());
        return error ("Unable to post notification for " + resCode);
    }

    hr = check hc->post ("/result/data/" + electionCode + "/" + resType + "/" + resCode, result);
    if hr.statusCode != http:STATUS_ACCEPTED {
        io:println("Error while posting result to: /result/data/" + electionCode + "/" + resType + "/" + resCode);
        io:println("\tstatus=", hr.statusCode, ", contentType=", hr.getContentType(), " payload=", hr.getTextPayload());
        return error ("Unable to post result for " + resCode);
    }
}
