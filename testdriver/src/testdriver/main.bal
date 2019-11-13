import ballerina/lang.'int;

// data loaded from file
json[] data2015 = [];

// loaded results data:
// - index is district code (0 to 21)
// - value is map containing a json object (map<json>) of per PD results with PD code as key 
map<map<json>>[] results2015 = [];
// same result json objects but by PD index as loaded
map<json>[] resultsByPD2015 = [];

map<map<json>>[] results2019 = [];
map<json>[] resultsByPD2019 = [];


int sleeptime = 0;
string resultsURL = "";

public function main(string url = "http://resultstest.ecdev.opensource.lk:8181", int delay = 10000) returns error? {
    resultsURL = <@untainted> url;
    sleeptime = <@untainted> delay;

    // avoiding compiler bug
    foreach int i in 0...21 {
        results2015[i] = {};
        results2019[i] = {};
    }

    // load 2015 presidential election data from Nuwan
    check loadNuwanData();

    // generate empty 2019 data
    check gen2019EmptyData();
    
    // test run will be started via the controller service
}

function loadNuwanData () returns error? {
    data2015 = <@untainted json[]> check readJson("data/elections.lk.presidential.2015.json");

    foreach json j in data2015 { // can't use data.forEach because I want to use check in the body
        // note: sequence # will be reset by the saving logic of the distributor

        // save it in the right place
        int districtCode = check 'int:fromString(j.ed_code.toString());
        string divisionCode = j.pd_code.toString().substring(2);
        results2015[districtCode-1][divisionCode] = <map<json>>j;
        resultsByPD2015.push(<map<json>>j);
    }
}
