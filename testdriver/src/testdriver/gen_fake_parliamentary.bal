function genFakeParliamentary() {
    map<json>[] data = [
        {
            "type": "RP_V",
            "sequence_number": "0101",
            "timestamp": 1420085460.0,
            "level": "POLLING-DIVISION",
            "ed_code": "01",
            "ed_name": "Colombo",
            "pd_code": "01A",
            "pd_name": "Colombo-North",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 15,
                    "vote_percentage": "16.67%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 65,
                    "vote_percentage": "72.22%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 10,
                    "vote_percentage": "11.11%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 90,
                "rejected": 10,
                "polled": 100,
                "electors": 150
            }
        },
        {
            "type": "RP_V",
            "sequence_number": "0102",
            "timestamp": 1420086260.0,
            "level": "POLLING-DIVISION",
            "ed_code": "01",
            "ed_name": "Colombo",
            "pd_code": "01B",
            "pd_name": "Colombo-Central",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 90,
                    "vote_percentage": "60.00%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 35,
                    "vote_percentage": "23.33%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 25,
                    "vote_percentage": "16.67%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 150,
                "rejected": 20,
                "polled": 170,
                "electors": 200
            }
        },
        {
            "type": "RP_V",
            "sequence_number": "0103",
            "timestamp": 1420087260.0,
            "level": "POLLING-DIVISION",
            "ed_code": "01",
            "ed_name": "Colombo",
            "pd_code": "PV",
            "pd_name": "Postal Votes",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 10,
                    "vote_percentage": "45.45%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 0,
                    "vote_percentage": "0.00%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 12,
                    "vote_percentage": "54.55%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 22,
                "rejected": 3,
                "polled": 25,
                "electors": 30
            }
        },
        {
            "type": "RP_V",
            "sequence_number": "0107",
            "timestamp": 1420087561.0,
            "level": "POLLING-DIVISION",
            "ed_code": "02",
            "ed_name": "Gampaha",
            "pd_code": "02J",
            "pd_name": "Mahara",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 10,
                    "vote_percentage": "12.50%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 50,
                    "vote_percentage": "62.50%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 20,
                    "vote_percentage": "25.00%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 80,
                "rejected": 10,
                "polled": 90,
                "electors": 100
            }
        },
        {
            "type": "RP_V",
            "sequence_number": "0109",
            "timestamp": 1420087980.0,
            "level": "POLLING-DIVISION",
            "ed_code": "02",
            "ed_name": "Gampaha",
            "pd_code": "02A",
            "pd_name": "Wattala",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 50,
                    "vote_percentage": "55.56%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 20,
                    "vote_percentage": "22.22%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 20,
                    "vote_percentage": "22.22%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 90,
                "rejected": 10,
                "polled": 100,
                "electors": 125
            }
        },
        {
            "type": "RE_V",
            "sequence_number": "0110",
            "timestamp": 1420087982.0,
            "level": "ELECTORAL-DISTRICT",
            "ed_code": "02",
            "ed_name": "Gampaha",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 350,
                    "vote_percentage": "46.66%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 220,
                    "vote_percentage": "29.33%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 180,
                    "vote_percentage": "24.00%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 750,
                "rejected": 50,
                "polled": 800,
                "electors": 925
            }
        },
        {
            "type": "RE_S",
            "sequence_number": "0120",
            "timestamp": 1420087983.0,
            "level": "ELECTORAL-DISTRICT",
            "ed_code": "02",
            "ed_name": "Gampaha",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 0,
                    "vote_percentage": "0.00%",
                    "seat_count": 10,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 0,
                    "vote_percentage": "0.00%",
                    "seat_count": 5,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 0,
                    "vote_percentage": "0.00%",
                    "seat_count": 3,
                    "national_list_seat_count": 0
                }
            ]
        },
        {
            "type": "RE_V",
            "sequence_number": "0123",
            "timestamp": 1420087991.0,
            "level": "ELECTORAL-DISTRICT",
            "ed_code": "01",
            "ed_name": "Colombo",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 950,
                    "vote_percentage": "28.35%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 2220,
                    "vote_percentage": "66.26%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 180,
                    "vote_percentage": "05.37%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 3350,
                "rejected": 250,
                "polled": 3500,
                "electors": 765
            }
        },
        {
            "type": "RE_S",
            "sequence_number": "0125",
            "timestamp": 1420087992.0,
            "level": "ELECTORAL-DISTRICT",
            "ed_code": "01",
            "ed_name": "Colombo",
            "by_party": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 0,
                    "vote_percentage": "0.00%",
                    "seat_count": 8,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 0,
                    "vote_percentage": "0.00%",
                    "seat_count": 20,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 0,
                    "vote_percentage": "0.00%",
                    "seat_count": 1,
                    "national_list_seat_count": 0
                }
            ]
        },
        {
            "type": "RN_V",
            "sequence_number": "0126",
            "timestamp": 1420087998.0,
            "level": "NATIONAL",
            "by_party": [
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 12540,
                    "vote_percentage": "32.79%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 7500,
                    "vote_percentage": "19.61%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 18200,
                    "vote_percentage": "47.59%",
                    "seat_count": 0,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 38240,
                "rejected": 300,
                "polled": 38540,
                "electors": 40000
            }
        },
        {
            "type": "RN_VS",
            "sequence_number": "0127",
            "timestamp": 1420087998.0,
            "level": "NATIONAL",
            "by_party": [
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 12540,
                    "vote_percentage": "32.79%",
                    "seat_count": 75,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 7500,
                    "vote_percentage": "19.61%",
                    "seat_count": 25,
                    "national_list_seat_count": 0
                },
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 18200,
                    "vote_percentage": "47.59%",
                    "seat_count": 100,
                    "national_list_seat_count": 0
                }
            ],
            "summary": {
                "valid": 38240,
                "rejected": 300,
                "polled": 38540,
                "electors": 40000
            }
        },
        {
            "type": "RN_VSN",
            "sequence_number": "0128",
            "timestamp": 1420088001.0,
            "level": "NATIONAL",
            "by_party": [
                {
                    "party_code": "Baz",
                    "party_name": "Baz baz",
                    "vote_count": 7500,
                    "vote_percentage": "19.61%",
                    "seat_count": 25,
                    "national_list_seat_count": 4
                },
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "vote_count": 18200,
                    "vote_percentage": "47.59%",
                    "seat_count": 100,
                    "national_list_seat_count": 12
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "vote_count": 12540,
                    "vote_percentage": "32.79%",
                    "seat_count": 75,
                    "national_list_seat_count": 9
                }
            ],
            "summary": {
                "valid": 38240,
                "rejected": 300,
                "polled": 38540,
                "electors": 40000
            }
        },
        {
            "type": "RE_SC",
            "sequence_number": "0130",
            "timestamp": 1420088002.0,
            "level": "ELECTORAL-DISTRICT",
            "ed_code": "01",
            "ed_name": "Colombo",
            "by_candidate": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "candidate_number": "12",
                    "candidate_name": "Lorem Ipsum",
                    "candidate_type" : "Normal"
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "candidate_number": "3",
                    "candidate_name": "Dolor sit",
                    "candidate_type" : "Normal"

                }
            ]
        },
        {
            "type": "RN_NC",
            "sequence_number": "0137",
            "timestamp": 142008005.0,
            "level": "NATIONAL",
            "by_candidate": [
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "candidate_number": "15",
                    "candidate_name": "Baz Qux",
                    "candidate_type" : "National List"
                }
            ]
        },
        {
            "type": "RN_SCNC",
            "sequence_number": "0138",
            "timestamp": 1420088007.0,
            "level": "NATIONAL",
            "by_candidate": [
                {
                    "party_code": "Foo",
                    "party_name": "Foo foo",
                    "candidate_number": "12",
                    "candidate_name": "Lorem Ipsum",
                    "candidate_type" : "Normal"
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "candidate_number": "3",
                    "candidate_name": "Dolor Sit",
                    "candidate_type" : "Normal"
                },
                {
                    "party_code": "Bar",
                    "party_name": "Bar bar",
                    "candidate_number": "15",
                    "candidate_name": "Baz Qux",
                    "candidate_type" : "National List"
                }
            ]
        }
    ];

    // load date to parliamentaryFake[]
    parliamentaryFake.push(...data);
}
