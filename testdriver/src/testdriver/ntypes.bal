// type decls to map to Nuwan's json data model

type NPartyResult record {|
  string party;
  string candidate;
  int votes;
|};

type NSummaryStats record {|
  int valid_votes;
  int rejected_votes;
  int total_polled;
  int registered_voters;
|};

type NPDResult record {|
  int pd_num;
  string pd_name;
  NPartyResult[] by_party;
  NSummaryStats summary_stats;
|};

type NEDResult record {|
  int ed_num;
  string ed_name;
  NPDResult[] by_pd;
|};

type NNationalResult record {|
  int year;
  NEDResult[] by_ed;
|};
