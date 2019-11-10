import ballerina/stringutils;
import ballerina/test;
import ballerina/http;

@test:Config {}
function testSubscriberRegistration() {
    http:Client httpEndpoint = new("http://localhost:9090");

    // Send a GET request to register
    var response = httpEndpoint->get("/sms/0771234567");
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Successfully registered: +94771234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    // Register the same number for the second time
    response = httpEndpoint->get("/sms/94771234567");
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Registration failed: +94771234567 is already registered");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    // Send a DELETE request to unregister
    response = httpEndpoint->delete("/sms/0771234567");
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Successfully unregistered: +94771234567");
        } else {
            test:assertFail(msg = "Invalid response message:");
        }
    } else {
        test:assertFail(msg = "Failed to call the endpoint:");
    }

    // Send a DELETE request to unregister unavailable number
    response = httpEndpoint->delete("/sms/0711234567");
    if (response is http:Response) {
        var result = response.getTextPayload();
        if (result is string) {
            test:assertEquals(result, "Unregistration failed: +94711234567 is not registered");
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
                                                    "mobile no is 0771234567, send request as \"/sms/94771234567\"."));

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
