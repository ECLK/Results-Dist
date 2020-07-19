import ballerina/auth;
import ballerina/config;
import ballerina/http;
import ballerina/stringutils;
import ballerina/test;

// Before enabling following test, update ballerina.conf with auth users
//
// [b7a.users.test]
// password="password"
// scopes="ECAdmin"
@test:Config { enable: false, after: "testResetRecipients" }
function testSubscriberRegistration() {
    auth:OutboundBasicAuthProvider outboundBasicAuthProvider1 = new({
        username: "test",
        password: config:getAsString("b7a.users.test.password")
    });
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
            test:assertEquals(result, "Successfully registered: username:newuser mobile:0771234567");
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
                                        + "mobile:0771234567");
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
            test:assertEquals(result, "Unregistration failed: No entry found for username:newuser mobile:0711234567");
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
            test:assertEquals(result, "Unregistration failed: No entry found for username:myuser mobile:0771234567");
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
            test:assertEquals(result, "Successfully unregistered: username:newuser mobile:0771234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    // Test bulk success registration
    req = new;
    req.setFileAsPayload("src/distributor/tests/resources/contact1.json");
    response = httpEndpoint->post("/sms/addall", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Successfully registered all");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    // Test bulk registration with invalid nos
    req = new;
    req.setFileAsPayload("src/distributor/tests/resources/contact2.json");
    response = httpEndpoint->post("/sms/addall", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Validation failed: invalid recipient mobile no: newuser1:+00771234562");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    // Test bulk registration with malformed JSON
    req = new;
    req.setFileAsPayload("src/distributor/tests/resources/contact3.json");
    response = httpEndpoint->post("/sms/addall", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertTrue(stringutils:contains(result, "Error occurred while converting json: malformed Recipient"));
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }
}

@test:Config { before: "testSubscriberRegistration" }
function testResetRecipients() {
    auth:OutboundBasicAuthProvider outboundBasicAuthProvider1 = new({
        username: "test",
        password: config:getAsString("b7a.users.test.password")
    });
    http:BasicAuthHandler outboundBasicAuthHandler1 = new(outboundBasicAuthProvider1);
    http:Client httpEndpoint = new("http://localhost:9090", {
        auth: {
            authHandler: outboundBasicAuthHandler1
        }
    });
    http:Request req = new;
    var response = httpEndpoint->delete("/sms/reset", req);
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Successfully unregistered all");
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
    test:assertTrue(validate("0771234567") == "0771234567", msg = "Failed assertion : 0771234567");

    // validate number starting with 94
    test:assertTrue(validate("94716181194") == "94716181194", msg = "Failed assertion : 94716181194");

    // validate number starting with +94
    test:assertTrue(validate("+94716181195") == "94716181195", msg = "Failed assertion : 94716181195");

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
    string path = "/result/notification/2015-PRE-REPLAY-000/PRESIDENTIAL-FIRST/07A" +
                  "?level=POLLING-DIVISION&ed_name=Galle&pd_name=Balapitiya";

    var response = httpEndpoint->post(path, req);
    if (response is http:Response) {
        test:assertEquals(response.statusCode, 202);
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    path = "/result/notification/2015-PRE-REPLAY-000/PRESIDENTIAL-FIRST/02?level=ELECTORAL-DISTRICT&ed_name=Gampaha";

    response = httpEndpoint->post(path, req);
    if (response is http:Response) {
        test:assertEquals(response.statusCode, 202);
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    req = new;
    path = "/result/notification/2015-PRE-REPLAY-000/PRESIDENTIAL-FIRST/FINAL?level=NATIONAL-FINAL";

    response = httpEndpoint->post(path, req);
    if (response is http:Response) {
        test:assertEquals(response.statusCode, 202);
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    // Negative case with dropping "level" query param
    req = new;
    path = "/result/notification/2015-PRE-REPLAY-000/PRESIDENTIAL-FIRST/02?ed_name=Gampaha";

    response = httpEndpoint->post(path, req);
    if (response is http:Response) {
        test:assertEquals(response.statusCode, 400);
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }
}
