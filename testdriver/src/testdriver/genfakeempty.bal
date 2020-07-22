import ballerina/lang.'int;
import ballerina/math;

function genFakeEmptyData () returns error? {
    map<json>[] by_party = [
        {
            "party_name":"Yakada Party",
            "candidate":"Yakada Yaka",
            "party_code":"XXX",
            "vote_count":0,
            "vote_percentage":"0.00"
        },
        {
            "party_name":"Maara Gus Party",
            "candidate":"Honda Lamaya",
            "party_code":"GGG",
            "vote_count":0,
            "vote_percentage":"0.00"
        },
        {
            "party_name":"Saturday Night Dance Party",
            "candidate":"Dancing Girl",
            "party_code":"WWW",
            "vote_count":0,
            "vote_percentage":"0.00"
        },
        {
            "party_name":"Hari Honda Party",
            "candidate":"Harima Honda Eki",
            "party_code":"YYY",
            "vote_count":0,
            "vote_percentage":"0.00"
        },
        {
            "party_name":"Shaaaaa Party",
            "candidate":"Sharima Shari Ekaa",
            "party_code":"ZZZ",
            "vote_count":0,
            "vote_percentage":"0.00"
        }
    ];
    json summary = {
      "valid": 0, 
      "rejected": 0, 
      "polled": 0, 
      "electors": 0,
      "percent_valid": "0.00",
      "percent_polled": "0.00",
      "percent_rejected": "0.00"
    };

    // go thru the 2015 data and copy over and replace the by_party and summary info
    foreach json j in data2015 {
        map<json>[] by_partyCopy = by_party.clone();
        json summaryCopy = summary.clone();
        map<json> jj = {
                'type: "PRESIDENTIAL-FIRST",
                level: check j.level,
                ed_code: check j.ed_code,
                ed_name: check j.ed_name, 
                pd_code: check j.pd_code,
                pd_name: check j.pd_name, 
                by_party: by_partyCopy,
                summary: summaryCopy
        };

        // save it in the right place
        int districtCode = check 'int:fromString(jj.ed_code.toString());
        string divisionCode = jj.pd_code.toString().substring(2);
        resultsFake[districtCode-1][divisionCode] = jj;
        resultsByPDFake.push(jj);
    }

    // do it for the 2nd round with only 2 candites
    int c1 = check math:randomInRange(0, 5);
    int c2 = (c1 + 2) % 5; // 2 over from c1
    json prefvotes = {
        votes1st: 0,
        votes2nd: 0,
        votes3rd: 0
    };
    foreach json j in data2015 { 
        json j1 = check by_party[c1].clone().mergeJson(prefvotes);
        json j2 = check by_party[c2].clone().mergeJson(prefvotes);
        map<json>[] bp = [<map<json>>j1, <map<json>>j2];
        json summaryCopy = summary.clone();

        map<json> jj = {
                'type: "PRESIDENTIAL-PREFS",
                level: check j.level,
                ed_code: check j.ed_code,
                ed_name: check j.ed_name, 
                pd_code: check j.pd_code,
                pd_name: check j.pd_name, 
                by_party: bp.clone(),
                summary: summary.clone()
        };

        // save it in the right place
        int districtCode = check 'int:fromString(jj.ed_code.toString());
        string divisionCode = jj.pd_code.toString().substring(2);
        resultsFake2[districtCode-1][divisionCode] = jj;
        resultsByPDFake2.push(jj);
    }

}
