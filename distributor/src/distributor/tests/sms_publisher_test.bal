import ballerina/auth;
import ballerina/http;
import ballerina/stringutils;
import ballerina/test;

// Before enabling following test, update ballerina.conf with auth users
//
// [b7a.users.test]
// password="password"
@test:Config { enable: false }
function testSubscriberRegistration() {
    auth:OutboundBasicAuthProvider outboundBasicAuthProvider1 = new({ username: "test", password: "password" });
    http:BasicAuthHandler outboundBasicAuthHandler1 = new(outboundBasicAuthProvider1);
    http:Client httpEndpoint = new("http://localhost:9090", {
        auth: {
            authHandler: outboundBasicAuthHandler1
        }
    });
    http:Request req = new;
    req.setJsonPayload({username : "newuser", mobile : "0771234567"});
    // Send a POST request to register
    var response = httpEndpoint->post("/sms", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Successfully registered: username:newuser mobile:+94771234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    req.setJsonPayload({username : "newuser", mobile : "0771234567"});
    // Register the same number for the second time
    response = httpEndpoint->post("/sms", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Registration failed: username:newuser is already registered with "
                                        + "mobile:+94771234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    req.setJsonPayload({username : "newuser", mobile : "0711234567"});
    // Send a DELETE request to unregister unavailable number
    response = httpEndpoint->delete("/sms", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Unregistration failed: No entry found for username:newuser mobile:+94711234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    req.setJsonPayload({username : "myuser", mobile : "0771234567"});
    // Send a DELETE request to unregister unavailable username
    response = httpEndpoint->delete("/sms", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Unregistration failed: No entry found for username:myuser mobile:+94771234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    req.setJsonPayload({username : "newuser", mobile : "0771234567"});
    // Send a DELETE request to unregister successfully
    response = httpEndpoint->delete("/sms", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Successfully unregistered: username:newuser mobile:+94771234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }
}

@test:Config {}
function testValidateFunction() {

    // validate number starting with zero
    test:assertTrue(validate("0771234567") == "+94771234567", msg = "Failed assertion : 0771234567");

    // validate number starting with 94
    test:assertTrue(validate("94716181194") == "+94716181194", msg = "Failed assertion : 94716181194");

    // validate invalid local numbers
    error err = <error> validate("07161811948979870");
    string detail = <string> err.detail()?.message;
    test:assertTrue(stringutils:contains(detail, "Invalid mobile number. Resend the request as follows: If the " +
            "mobile no is 0771234567, send POST request to  '/sms' with JSON payload '{\"username\":\"myuser\", " +
            "\"mobile\":\"0771234567\"}'"));

    // validate invalid local numbers with non numeric chars
    err = <error> validate("07161811AB");
    detail = <string> err.detail()?.message;
    test:assertTrue(stringutils:contains(detail, "Invalid mobile number. Given mobile number contains non numeric " +
                                                    "characters: 07161811AB"));

    // validate invalid local numbers with special chars
    err = <error> validate("9471 618*19");
    detail = <string> err.detail()?.message;
    //log:printInfo(detail);
    test:assertTrue(stringutils:contains(detail, "Invalid mobile number. Given mobile number contains non numeric " +
                                                    "characters: 9471 618*19"));
}

@test:Config {}
function testNotificationResource() {
    http:Client httpEndpoint = new("http://localhost:8181");
    http:Request req = new;
    req.setJsonPayload({electionCode:"2015-PRE-REPLAY-000", 'type:"PRESIDENTIAL-FIRST", resultCode:"07A",
                        level:"POLLING-DIVISION", ed_name:"Galle", pd_name:"Balapitiya"});
    // Send a POST with notification json of polling division
    var response = httpEndpoint->post("/result/notification", req);
    if (response is http:Response) {
        test:assertEquals(response.statusCode, 202);
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    req.setJsonPayload({electionCode:"2015-PRE-REPLAY-000", 'type:"PRESIDENTIAL-FIRST", resultCode:"07",
                        level:"ELECTORAL-DISTRICT", ed_name:"Galle"});
    // Send a POST with notification json of electoral district
    response = httpEndpoint->post("/result/notification", req);
    if (response is http:Response) {
        test:assertEquals(response.statusCode, 202);
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    req.setJsonPayload({electionCode:"2015-PRE-REPLAY-000", 'type:"PRESIDENTIAL-FIRST", resultCode:"AIVOT",
                        level:"NATIONAL-FINAL"});
    // Send a POST with notification json of national final
    response = httpEndpoint->post("/result/notification", req);
    if (response is http:Response) {
        test:assertEquals(response.statusCode, 202);
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }
}
