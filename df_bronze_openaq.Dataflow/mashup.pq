[DefaultOutputDestinationSettings = [DestinationDefinition = [Kind = "Reference", QueryName = "DefaultDestination", IsNewTarget = true], UpdateMethod = [Kind = "Replace"], DestinationTypeSettings = [Kind = "Table"]], StagingDefinition = [Kind = "FastCopy"]]
section Section1;
shared q_locations_source = let
  Response =
    Json.Document(
      Web.Contents(
        "https://api.openaq.org",
        [
          RelativePath = "v3/locations",
          Query = [
            bbox = "-74.259,40.477,-73.700,40.917",
            limit = "1000",
            page = "1"
          ],
          Headers = [
            #"X-API-Key" = p_openaq_api_key
          ],
          Timeout = #duration(0, 0, 2, 0)
        ]
      )
    ),
  Navigation = Response[results],
  #"Converted to table" = Table.FromList(Navigation, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
  #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to table", "Column1", {"id", "name", "locality", "timezone", "country", "isMobile", "isMonitor", "sensors", "coordinates"}, {"id", "name", "locality", "timezone", "country", "isMobile", "isMonitor", "sensors", "coordinates"})
in
  #"Expanded Column1";
[Description = "API key for OpenAQ API v3 connection"]
shared p_openaq_api_key = "50a2f340f9f8dd015c388efc8128c31fe564ef4ff637e07eaa3ea8e56de61981" meta [IsParameterQuery = true, IsParameterQueryRequired = true, Type = type text];
[BindToDefaultDestination = true]
shared openaq_locations = let
  Source = q_locations_source,
  #"Choose columns" = Table.SelectColumns(Source, {"id", "name", "locality", "timezone", "country", "isMobile", "isMonitor", "coordinates"}),
  #"Expanded country" = Table.ExpandRecordColumn(#"Choose columns", "country", {"code", "name"}, {"country.code", "country.name"}),
  #"Expanded coordinates" = Table.ExpandRecordColumn(#"Expanded country", "coordinates", {"latitude", "longitude"}, {"latitude", "longitude"}),
  #"Renamed columns" = Table.RenameColumns(#"Expanded coordinates", {{"id", "location_id"}, {"name", "location_name"}, {"country.code", "country_code"}, {"country.name", "country_name"}, {"isMobile", "is_mobile"}, {"isMonitor", "is_monitor"}}),
  #"Changed column type" = Table.TransformColumnTypes(#"Renamed columns", {{"location_name", type text}, {"locality", type text}, {"timezone", type text}, {"country_code", type text}, {"country_name", type text}, {"location_id", Int64.Type}, {"is_mobile", type logical}, {"is_monitor", type logical}, {"latitude", type number}, {"longitude", type number}})
in
  #"Changed column type";
[BindToDefaultDestination = true]
shared openaq_sensors = let
  Source = q_locations_source,
  #"Choose columns" = Table.SelectColumns(Source, {"id", "sensors"}),
  #"Renamed columns" = Table.RenameColumns(#"Choose columns", {{"id", "location_id"}}),
  #"Changed column type" = Table.TransformColumnTypes(#"Renamed columns", {{"location_id", Int64.Type}}),
  #"Expanded sensors" = Table.ExpandListColumn(#"Changed column type", "sensors"),
  #"Expanded sensors 1" = Table.ExpandRecordColumn(#"Expanded sensors", "sensors", {"id", "name", "parameter"}, {"id", "name", "parameter"}),
  #"Renamed columns 1" = Table.RenameColumns(#"Expanded sensors 1", {{"id", "sensor_id"}, {"name", "sensor_name"}}),
  #"Expanded parameter" = Table.ExpandRecordColumn(#"Renamed columns 1", "parameter", {"id", "name", "units", "displayName"}, {"parameter.id", "parameter.name", "parameter.units", "parameter.displayName"}),
  #"Renamed columns 2" = Table.RenameColumns(#"Expanded parameter", {{"parameter.id", "parameter_id"}, {"parameter.name", "parameter_name"}, {"parameter.units", "parameter_units"}, {"parameter.displayName", "parameter_display_name"}}),
  #"Changed column type 1" = Table.TransformColumnTypes(#"Renamed columns 2", {{"sensor_id", Int64.Type}, {"location_id", Int64.Type}, {"parameter_id", Int64.Type}, {"sensor_name", type text}, {"parameter_name", type text}, {"parameter_units", type text}, {"parameter_display_name", type text}})
in
  #"Changed column type 1";
shared DefaultDestination = let
  Source = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = true]),
  Navigation = Source{[workspaceId = "c14a1c5d-5b0f-4b1a-af7d-bcb009b8c85f"]}[Data],
  #"Navigation 1" = Navigation{[lakehouseId = "c08039f2-25eb-4d23-a8ff-b81ef50a55bb"]}[Data],
  #"Navigation 2" = #"Navigation 1"{[Id = "bronze", ItemKind = "Schema"]}[Data]
in
  #"Navigation 2";
shared openaq_sensor_test = let
    Response =
        Json.Document(
            Web.Contents(
                "https://api.openaq.org",
                [
                    RelativePath = "v3/sensors/1534",
                    Headers = [
                        #"X-API-Key" = p_openaq_api_key
                    ],
                    Timeout = #duration(0, 0, 2, 0)
                ]
            )
        ),

    Results = Response[results],
    Sensor = Results{0},
  Navigation = Sensor[coverage]

in
    Navigation;
shared openaq_hourly_measurements_test = let
    GetPage = (page as number) as list =>
        let
            PageResponse =
                Json.Document(
                    Web.Contents(
                        "https://api.openaq.org",
                        [
                            RelativePath = "v3/sensors/1534/hours",
                            Query = [
                                datetime_from =
                                    Date.ToText(
                                        p_openaq_start_date,
                                        [Format = "yyyy-MM-dd"]
                                    ) & "T00:00:00Z",

                                datetime_to =
                                    Date.ToText(
                                        p_openaq_end_date,
                                        [Format = "yyyy-MM-dd"]
                                    ) & "T23:59:59Z",

                                limit = "1000",
                                page = Text.From(page)
                            ],
                            Headers = [
                                #"X-API-Key" = p_openaq_api_key
                            ],
                            Timeout = #duration(0, 0, 2, 0)
                        ]
                    )
                ),

            PageResults = PageResponse[results]
        in
            PageResults,

    Pages =
        List.Generate(
            () => [Page = 1, Results = GetPage(1)],

            each List.Count([Results]) > 0,

            each [
                Page = [Page] + 1,
                Results =
                    if List.Count([Results]) = 1000
                    then GetPage([Page] + 1)
                    else {}
            ],

            each [Results]
        ),

    Navigation = List.Combine(Pages),

    #"Converted to table" =
        Table.FromList(Navigation, Splitter.SplitByNothing(), null, null, ExtraValues.Error),

    #"Expanded Column1" =
        Table.ExpandRecordColumn(
            #"Converted to table",
            "Column1",
            {"value", "flagInfo", "parameter", "period", "summary", "coverage"},
            {"value", "flagInfo", "parameter", "period", "summary", "coverage"}
        ),

    #"Expanded period" =
        Table.ExpandRecordColumn(
            #"Expanded Column1",
            "period",
            {"label", "interval", "datetimeFrom", "datetimeTo"},
            {"period.label", "period.interval", "period.datetimeFrom", "period.datetimeTo"}
        ),

    #"Expanded period.datetimeFrom" =
        Table.ExpandRecordColumn(
            #"Expanded period",
            "period.datetimeFrom",
            {"utc", "local"},
            {"utc", "local"}
        ),

    #"Expanded period.datetimeTo" =
        Table.ExpandRecordColumn(
            #"Expanded period.datetimeFrom",
            "period.datetimeTo",
            {"utc", "local"},
            {"utc.1", "local.1"}
        ),

    #"Renamed columns" =
        Table.RenameColumns(
            #"Expanded period.datetimeTo",
            {
                {"utc", "datetime_from_utc"},
                {"local", "datetime_from_local"},
                {"utc.1", "datetime_to_utc"},
                {"local.1", "datetime_to_local"},
                {"period.label", "period_label"},
                {"period.interval", "period_interval"}
            }
        ),

    #"Expanded parameter" =
        Table.ExpandRecordColumn(
            #"Renamed columns",
            "parameter",
            {"id", "name", "units", "displayName"},
            {"id", "name", "units", "displayName"}
        ),

    #"Renamed columns 1" =
        Table.RenameColumns(
            #"Expanded parameter",
            {
                {"id", "parameter_id"},
                {"name", "parameter_name"},
                {"units", "parameter_units"},
                {"displayName", "parameter_display_name"}
            }
        ),

    #"Expanded flagInfo" =
        Table.ExpandRecordColumn(
            #"Renamed columns 1",
            "flagInfo",
            {"hasFlags"},
            {"hasFlags"}
        ),

    #"Expanded summary" =
        Table.ExpandRecordColumn(
            #"Expanded flagInfo",
            "summary",
            {"min", "q02", "q25", "median", "q75", "q98", "max", "avg", "sd"},
            {"min", "q02", "q25", "median", "q75", "q98", "max", "avg", "sd"}
        ),

    #"Expanded coverage" =
        Table.ExpandRecordColumn(
            #"Expanded summary",
            "coverage",
            {
                "expectedCount",
                "expectedInterval",
                "observedCount",
                "observedInterval",
                "percentComplete",
                "percentCoverage",
                "datetimeFrom",
                "datetimeTo"
            },
            {
                "coverage.expectedCount",
                "coverage.expectedInterval",
                "coverage.observedCount",
                "coverage.observedInterval",
                "coverage.percentComplete",
                "coverage.percentCoverage",
                "coverage.datetimeFrom",
                "coverage.datetimeTo"
            }
        ),

    #"Expanded coverage.datetimeFrom" =
        Table.ExpandRecordColumn(
            #"Expanded coverage",
            "coverage.datetimeFrom",
            {"utc", "local"},
            {"coverage.datetimeFrom.utc", "coverage.datetimeFrom.local"}
        ),

    #"Expanded coverage.datetimeTo" =
        Table.ExpandRecordColumn(
            #"Expanded coverage.datetimeFrom",
            "coverage.datetimeTo",
            {"utc", "local"},
            {"coverage.datetimeTo.utc", "coverage.datetimeTo.local"}
        ),

    #"Renamed columns 2" =
        Table.RenameColumns(
            #"Expanded coverage.datetimeTo",
            {
                {"coverage.expectedCount", "coverage_expected_count"},
                {"coverage.expectedInterval", "coverage_expected_interval"},
                {"coverage.observedCount", "coverage_observed_count"},
                {"coverage.observedInterval", "coverage_observed_interval"},
                {"coverage.percentComplete", "coverage_percent_complete"},
                {"coverage.percentCoverage", "coverage_percent_coverage"},
                {"coverage.datetimeFrom.utc", "coverage_datetime_from_utc"},
                {"coverage.datetimeFrom.local", "coverage_datetime_from_local"},
                {"coverage.datetimeTo.utc", "coverage_datetime_to_utc"},
                {"coverage.datetimeTo.local", "coverage_datetime_to_local"},
                {"hasFlags", "has_flags"}
            }
        ),

    #"Removed columns" =
        Table.RemoveColumns(
            #"Renamed columns 2",
            {
                "coverage_datetime_from_utc",
                "coverage_datetime_from_local",
                "coverage_datetime_to_utc",
                "coverage_datetime_to_local"
            }
        ),

    #"Renamed columns 3" =
        Table.RenameColumns(
            #"Removed columns",
            {
                {"min", "summary_min"},
                {"q02", "summary_q02"},
                {"q25", "summary_q25"},
                {"median", "summary_median"},
                {"q75", "summary_q75"},
                {"q98", "summary_q98"},
                {"max", "summary_max"},
                {"avg", "summary_avg"},
                {"sd", "summary_sd"}
            }
        ),

    #"Added custom" =
        Table.AddColumn(
            #"Renamed columns 3",
            "sensor_id",
            each 1534,
            Int64.Type
        ),

    #"Reordered columns" =
        Table.ReorderColumns(
            #"Added custom",
            {
                "value",
                "has_flags",
                "parameter_id",
                "sensor_id",
                "parameter_name",
                "parameter_units",
                "parameter_display_name",
                "period_label",
                "period_interval",
                "datetime_from_utc",
                "datetime_from_local",
                "datetime_to_utc",
                "datetime_to_local",
                "summary_min",
                "summary_q02",
                "summary_q25",
                "summary_median",
                "summary_q75",
                "summary_q98",
                "summary_max",
                "summary_avg",
                "summary_sd",
                "coverage_expected_count",
                "coverage_expected_interval",
                "coverage_observed_count",
                "coverage_observed_interval",
                "coverage_percent_complete",
                "coverage_percent_coverage"
            }
        ),

    #"Changed column type" =
        Table.TransformColumnTypes(
            #"Reordered columns",
            {
                {"sensor_id", Int64.Type},
                {"parameter_id", Int64.Type},
                {"coverage_expected_count", Int64.Type},
                {"coverage_observed_count", Int64.Type},
                {"value", type number},
                {"summary_min", type number},
                {"summary_q02", type number},
                {"summary_q25", type number},
                {"summary_median", type number},
                {"summary_q75", type number},
                {"summary_q98", type number},
                {"summary_max", type number},
                {"summary_avg", type number},
                {"summary_sd", type number},
                {"coverage_percent_complete", type number},
                {"coverage_percent_coverage", type number},
                {"has_flags", type logical},
                {"parameter_name", type text},
                {"parameter_units", type text},
                {"parameter_display_name", type text},
                {"period_label", type text},
                {"period_interval", type text},
                {"datetime_from_utc", type text},
                {"datetime_from_local", type text},
                {"datetime_to_utc", type text},
                {"datetime_to_local", type text},
                {"coverage_observed_interval", type text},
                {"coverage_expected_interval", type text}
            }
        )

in
    #"Changed column type";
shared p_openaq_start_date = #date(2025, 1, 1) meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type date];
shared p_openaq_end_date = #date(2025, 12, 31) meta [IsParameterQuery = true, IsParameterQueryRequired = false, Type = type date];
