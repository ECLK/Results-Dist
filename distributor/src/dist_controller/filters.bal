import ballerina/http;
import ballerina/log;

const WWW_AUTHENTICATE_HEADER = "WWW-Authenticate";

# Filter to challenge authentication.
public type AuthChallengeFilter object {
    *http:RequestFilter;

    public function filterRequest(http:Caller caller, http:Request request, http:FilterContext context) 
                        returns boolean {
        if request.hasHeader(http:AUTH_HEADER) || request.rawPath != "/" {
            return true;
        }

        http:Response res = new;
        res.statusCode = 401;
        res.addHeader(WWW_AUTHENTICATE_HEADER, "Basic realm=\"EC Media Results Delivery\"");
        error? err =  caller->respond(res);
        if (err is error) {
            log:printError("error responding with auth challenge", err);
        }
        return false;
    }
};
