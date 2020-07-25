import ballerina/file;
import ballerina/io;
import ballerina/log;
import ballerina/test;

// This test asserts the calculated values in the distribution flow.
// Test source : Test driver/FakeElection
// Before enabling the test, make sure the aforementioned test is executed and json files exist in the subscriber root
@test:Config { enable : false }
function testReceivedDataViaTesDriverFakeElection() {
    testR_VI("0002-R_VI-ED-01--Colombo.json", 15, 65, 10, 90, 10, 100, 150);
    testR_VI("0004-R_VI-ED-01--Colombo.json", 105, 100, 35, 240, 30, 270, 350);
    testR_VI("0006-R_VI-ED-01--Colombo.json", 115, 100, 47, 262, 33, 295, 380);
    testR_VI("0008-R_VI-ED-02--Gampaha.json", 10, 50, 20, 80, 10, 90, 100);
    testR_VI("0010-R_VI-ED-02--Gampaha.json", 60, 70, 40, 170, 20, 190, 225);

    testNational("0012-R_SI-N.json", "Foo", 10, "Bar", 5, "Baz", 3);
    testNational("0014-R_SI-N.json", "Bar", 25, "Foo", 18, "Baz", 4);

    testNational("0015-R_VS-N.json", "Foo", 100, "Bar", 75, "Baz", 25);
    testNational("0016-R_VSN-N.json", "Foo", 100, "Bar", 75, "Baz", 25);
}

function testNational(string filePath, string top, int topCount, string mid, int midCount, string last, int lastCount) {

    map<json> value = getJson(filePath);
    json[] parties = <json[]>value.by_party;

    map<json> party = <map<json>>parties[0];
    test:assertEquals(party["party_code"], top);
    test:assertEquals(party["seat_count"], topCount);

    party = <map<json>>parties[1];
    test:assertEquals(party["party_code"], mid);
    test:assertEquals(party["seat_count"], midCount);

    party = <map<json>>parties[2];
    test:assertEquals(party["party_code"], last);
    test:assertEquals(party["seat_count"], lastCount);
}


function testR_VI(string filePath, int fooCount, int barCount, int bazCount, int valid, int rejected, int polled,
        int electors) {

    map<json> value = getJson(filePath);
    json[] parties = <json[]>value.by_party;

    map<json> party = <map<json>>parties[0];
    test:assertEquals(party["party_name"], "Foo foo");
    test:assertEquals(party["vote_count"], fooCount);
    test:assertEquals(party["vote_percentage"], io:sprintf("%.2f", ((fooCount*1.0)/valid)));

    party = <map<json>>parties[1];
    test:assertEquals(party["party_name"], "Bar bar");
    test:assertEquals(party["vote_count"], barCount);
    test:assertEquals(party["vote_percentage"], io:sprintf("%.2f", ((barCount*1.0)/valid)));

    party = <map<json>>parties[2];
    test:assertEquals(party["party_name"], "Baz baz");
    test:assertEquals(party["vote_count"], bazCount);
    test:assertEquals(party["vote_percentage"], io:sprintf("%.2f", ((bazCount*1.0)/valid)));

    map<json> edSummary = <map<json>>value.summary;
    test:assertEquals(edSummary["valid"], valid);
    test:assertEquals(edSummary["rejected"], rejected);
    test:assertEquals(edSummary["polled"], polled);
    test:assertEquals(edSummary["electors"], electors);
}

function getJson(string filePath) returns @tainted map<json> {
    log:printInfo(filePath);
    if !file:exists(filePath) {
        test:assertFail(msg = "File does not exist");
    }
    var resValue = readJson(filePath);
    if resValue is error {
        test:assertFail(msg = resValue.toString());
    }

    return <map<json>>resValue;
}

function readJson(string path) returns @tainted json|error {
    return readJsonFile(path);
}

function readJsonFile(string path) returns @tainted json|error {
    var rblCharChnl = check getRblCharChnl(getRblByteChnl(path));
    return readJsonFromCharChnl(rblCharChnl);
}

function readJsonFromCharChnl(io:ReadableCharacterChannel rblCharChnl) returns @tainted json|error {
    var content = rblCharChnl.readJson();
    var err = rblCharChnl.close();
    if err is error {
        log:printError("Failed to close the character channel");
    }
    return content;
}

function getRblByteChnl(string path) returns @tainted io:ReadableByteChannel|error {
    return io:openReadableFile(path);
}

function getRblCharChnl(io:ReadableByteChannel|error rblByteChnl) returns io:ReadableCharacterChannel|error {
    return rblByteChnl is error ? rblByteChnl : new io:ReadableCharacterChannel(rblByteChnl, "UTF8");
}
