import ballerina/encoding;
import ballerina/http;
import ballerina/log;

http:Client c = new("https://postman-echo.com");

service foo on mediaListener {
    resource function bar(http:Caller caller, http:Request request) returns error? {
        http:Response|error res = c->get("/get?test=123");
        if (res is error) {
            log:printError("[ONE] ERROR: ", res);
        } else {
            log:printInfo("[ONE] " + res.getTextPayload().toString());
        }

        string url = check request.getTextPayload();
        url = check encoding:decodeUriComponent(url, "utf-8");
        http:Client c2 = new(url);
        res = c2->get("/");
        if (res is error) {
            log:printError("[TWO] ERROR: ", res);
        } else {
            log:printInfo("[TWO] " + res.getTextPayload().toString());
        }
        check caller->accepted();
    }
}
