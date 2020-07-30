import ballerina/encoding;
import ballerina/http;
import ballerina/io;
import ballerina/runtime;
import ballerina/time;

const RP_V = "RP_V";
const RE_V = "RE_V";
const RE_S = "RE_S";
const RN_V = "RN_V";
const RN_VS = "RN_VS";
const RN_VSN = "RN_VSN";
const RE_SC = "RE_SC";
const RN_NC = "RN_NC";
const RN_SCNC = "RN_SCNC";

const FINAL = "FINAL";

function sendParliamentaryResults(string electionCode, http:Client rc, map<json>[] results) returns error? {

    foreach map<json> result in results {

        string resultType = result.'type.toString();
        match resultType {
            RP_V => {
                check updateByParty(<json[]>result.by_party);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, result.pd_code.toString(), result);
            }
            RE_V => {
                check updateByParty(<json[]>result.by_party);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, result.ed_code.toString(), result);
            }
            RE_S => {
                check updateByParty(<json[]>result.by_party);
                check feedResult(rc, electionCode, resultType, result.ed_code.toString(), result);
            }
            RN_V => {
                check updateByParty(<json[]>result.by_party);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
            RN_VS => {
                check updateByParty(<json[]>result.by_party);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
            RN_VSN => {
                check updateByParty(<json[]>result.by_party);
                check updateSummary(result);
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
            RE_SC => {
                check feedResult(rc, electionCode, resultType, result.ed_code.toString(), result);
            }
            RN_NC => {
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
            RN_SCNC => {
                check feedResult(rc, electionCode, resultType, FINAL, result);
            }
        }
        // delay a bit
        runtime:sleep(sleeptime);
    }
}

function updateByParty(json[] byPartyJson) returns error? {
    // add missing info in test data:
    foreach int i in 0 ..< byPartyJson.length() {
        map<json> party = <map<json>>byPartyJson[i];
        // change percentage to string
        json val = party["vote_percentage"];

        if val is float {
            party["vote_percentage"] = string `${io:sprintf ("%.2f", val * 100.0)}%`;
        } else {
            // already a string so let it go
        }
    }
}

function updateSummary(map<json> result) returns error? {
    // set the percentages in the summary
    map<json> summary = <map<json>>result.summary;
    summary["percent_valid"] = (<int>result.summary.polled == 0) ? "0.00%" : string `${io:sprintf("%.2f", <int>result.summary.valid*100.0/<int>result.summary.polled)}%`;
    summary["percent_rejected"] = (<int>result.summary.polled == 0) ? "0.00%" : string `${io:sprintf("%.2f", <int>result.summary.rejected*100.0/<int>result.summary.polled)}%`;
    summary["percent_polled"] = (<int>result.summary.electors == 0) ? "0.00%" : string `${io:sprintf("%.2f", <int>result.summary.polled*100.0/<int>result.summary.electors)}%`;
}


function feedResult(http:Client hc, string electionCode, string resType, string resCode, map<json> result) returns
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
