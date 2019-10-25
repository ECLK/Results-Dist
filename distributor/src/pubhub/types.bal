const SUMMARY_RESULT = "SUMMARY";
const PARTY_RESULT = "PARTY";
type ResultLevel "NATIONAL" | "ELECTORAL-DISTRICT" | "POLLING-DISTRICT";

type SummaryResult record {|
    SUMMARY_RESULT 'type;
    string timestamp;
    ResultLevel level;
    string ed_code?;
    string ed_name?;
    string pd_code?;
    string pd_name?;
    int valid;
    int rejected;
    int polled;
    int electors;
|};

type PartyResult record {|
    PARTY_RESULT 'type;
    string timestamp;
    ResultLevel level;
    string ed_code?;
    string ed_name?;
    string pd_code?;
    string pd_name?;
    record {
        string party;
        int votes;
        decimal percentage;
    }[] by_party;
|};
