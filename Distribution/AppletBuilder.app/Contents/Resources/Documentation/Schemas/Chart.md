# ActionUI.Chart

JSON schema and usage documentation for `Chart`.

```jsonc
// Sources/Views/Chart.swift
// JSON specification for ActionUI.Chart:
 {
   "type": "Chart",
   "id": 10,             // Required when the chart is replaced or fed at runtime (setElementProperty, rows) or selects
   "properties": {
     "valueChangeActionID": "chart.selected", // Optional: fires when the user changes the selection (below)
     "selectionActionTiming": "settled",      // Optional: "settled" (default): the action fires once the selection has
                                              //   rested for 150 ms, and at once when it is cleared; "continuous": on every change
     "chart": {          // Optional: the chart description. Absent = an empty plot area.
                         //   Replace it whole at runtime with setElementProperty(10, "chart", {...}).
       "columns": ["week", "platform", { "name": "users", "type": "number" }],
                         // Optional: names and types of the row cells. An item is a name or {"name", "type"};
                         //   types: "string", "number", "integer", "date"; a bare name is a string column. Names are
                         //   identifiers (letters, digits, _).
       "data": [["2026-08-03", "iOS", 1180], ["2026-08-03", "macOS", 790]],
                         // Optional: inline rows (strings, numbers, booleans, null). Setting a description that
                         //   has "data" replaces the chart's rows with it, at load and at runtime; a description
                         //   without "data" keeps the rows. The stored description keeps no "data".
       "content": [      // ForEach, Plot and the marks, in Swift Charts' vocabulary
         { "type": "ForEach", "content": [  // Draws its content once per row
           { "type": "Plot",                // Groups marks; its modifiers apply to each mark inside
             "foregroundStyle": { "by": { "label": "Platform", "value": "$platform" } }, // or a color: "blue"
             "content": [
               { "type": "LineMark",
                 "x": { "label": "Week", "value": "$week", "type": "date", "unit": "weekOfYear" },
                 "y": { "label": "Users", "value": "$users" },
                 "interpolationMethod": "catmullRom" },
               { "type": "PointMark",
                 "x": { "label": "Week", "value": "$week", "type": "date", "unit": "weekOfYear" },
                 "y": { "label": "Users", "value": "$users" } }
             ] }
         ] },
         { "type": "RuleMark", "y": { "label": "Goal", "value": 1500 }, "lineStyle": { "lineWidth": 1, "dash": [4, 3] },
           "annotation": { "position": "top", "alignment": "leading",  // A view drawn next to the mark (below)
             "content": { "type": "Text", "properties": { "text": "Goal", "font": "caption" } } } }
       ],
       "chartXScale": { "domain": [0, 100] },  // Optional: "domain": two numbers or two dates (a range), a list of strings
                                              //   (categories), or {"automatic": {"includesZero": false, "reversed": true}};
                                              //   "range": {"startPadding", "endPadding"}, {"padding"} or two numbers (points);
                                              //   "type": "linear" | "log" | "date" | "category" | "squareRoot" | "symmetricLog" |
                                              //   {"power": {"exponent": 2}} | {"symmetricLog": {"slopeAtZero": 1}}. On a number axis
                                              //   "log", "squareRoot" and "power" need a "domain" inside theirs (log: low end above 0);
                                              //   "date" and "category" never apply to a number or date axis (Swift Charts stops the app).
                                              //   Marks beyond a fixed domain (stacked bars add up) draw outside the plot area;
                                              //   chartPlotStyle {"clipShape": "rectangle"} cuts them off
       "chartYScale": { "domain": { "automatic": { "includesZero": true } } },
       "chartForegroundStyleScale": { "domain": ["iOS", "macOS"], "range": ["blue", "orange"] },
                                              // Optional style scales, each {"domain", "range"}: the domain is typed by the
                                              //   {"by"} values the scale styles (a list of strings, two numbers or dates, or
                                              //   {"automatic": {...}}). Ranges: chartForegroundStyleScale a list of colors or
                                              //   {"gradient": [colors]}; chartSymbolScale a list of symbol names;
                                              //   chartLineStyleScale a list of stroke styles; chartSymbolSizeScale two numbers,
                                              //   the smallest and largest symbol area
       "chartXAxis": "automatic",             // Optional: "automatic" | "visible" | "hidden", or up to 4 AxisMarks (below);
                                              //   also chartYAxis
       "chartYAxis": [
         { "type": "AxisMarks", "preset": "automatic", "position": "leading",
           "values": [0, 500, 1000, 1500],    // "automatic", {"automatic": {"desiredCount" (1 to 100), "roundLowerBound",
                                              //   "roundUpperBound"}}, {"stride": {"by": "month", "count": 1}} (a calendar unit, dates),
                                              //   {"stride": {"by": 10}} (numbers), or a list of values typed by the axis. A stride
                                              //   that would draw more than 1000 marks over the axis falls back to "automatic"
           "format": "decimal", "fractionLength": 0, // Without "content" only: labels' format (below); "stroke" likewise
           "content": [                       // Optional: up to 4 marks; absent = Swift's default marks, [] = none
             { "type": "AxisGridLine", "centered": false, "stroke": { "lineWidth": 0.5, "dash": [2, 2] } },
             { "type": "AxisTick", "length": "automatic" }, // or a number, "label", "longestLabel", {"label": {"extendPastBy": 2}}
             { "type": "AxisValueLabel", "format": "percent", "anchor": "top", "orientation": "automatic",
               "collisionResolution": "automatic", "font": "caption", "foregroundStyle": "gray", "offset": { "x": 0, "y": 2 } }
           ] }                                // AxisValueLabel also takes "centered", "multiLabelAlignment", "offsetsMarks",
       ],                                     //   "horizontalSpacing", "verticalSpacing"; every mark takes foregroundStyle, font, offset.
                                              //   Formats: on a number axis "integer" | "decimal" | "percent" | "currency" with
                                              //   "fractionLength" (n or {"min", "max"}) and "currencyCode"; on a date axis
                                              //   {"dateTime": {"year", "quarter", "month", "day", "weekday", "hour", "minute", "second"}}
                                              //   (Date.FormatStyle symbol names) or {"date": "abbreviated", "time": "omitted"}
       "chartXAxisLabel": "Week",             // Optional: axis title, or {"text", "position", "alignment", "spacing"};
                                              //   also chartYAxisLabel
       "chartLegend": "automatic",            // Optional: "automatic" | "visible" | "hidden", or {"position": "bottom"}
       "chartPlotStyle": { "background": "gray.opacity(0.1)", "cornerRadius": 4 }, // Optional: View properties for the plot area: padding,
                                              //   background, border, frame, cornerRadius, clipShape, shadow, opacity, offset, foregroundStyle
       "chartXSelection": "value",            // Optional: the user selects on the x axis: "value" | "range" (a number or date
                                              //   axis); also chartYSelection;
                                              //   "chartAngleSelection": "value" selects a SectorMark. Without these keys the chart
                                              //   installs no selection gesture. Swift Charts draws nothing for a selection: draw it
                                              //   with "$selection" marks (below)
       "chartScrollableAxes": "horizontal",   // Optional: "horizontal" | "vertical" | ["horizontal", "vertical"]; the chart scrolls.
                                              //   Without it the chart installs no scrolling, and the two keys below are ignored
       "chartXVisibleDomain": { "length": 30 }, // Optional: how much of a scrolling axis shows: data units on a number axis,
                                              //   seconds on a date axis, a whole count of categories on a string axis; also
                                              //   chartYVisibleDomain. A length so short that the axis would lay out more than
                                              //   100 automatic marks is lengthened to the shortest that does not, with a warning
       "chartScrollPosition": { "initialX": "2026-09-01" } // Optional: where a scrolling axis starts, a value of the axis's
                                              //   type; also "initialY"
     }
   }
   // Marks: every argument is a key named like Swift's initializer argument. A plottable value is an object
   //   (below); a number means points. The keys must match one initializer:
   //   BarMark   x + y | x (+ yStart/yEnd points) | x + yStart + yEnd | (xStart/xEnd points +) y |
   //             (xStart/xEnd points +) yStart + yEnd | xStart + xEnd + y | xStart + xEnd (+ yStart/yEnd points);
   //             "width" / "height" (where the initializer has them): a number (fixed), "automatic", {"ratio"},
   //             {"inset"} or {"fixed"}; "stacking": "standard" | "normalized" | "center" | "unstacked"
   //   LineMark  x + y | x + y + series
   //   PointMark x + y | (x point +) y | x (+ y point)
   //   RuleMark  (x point +) yStart + yEnd | x (+ yStart/yEnd points) | x + yStart + yEnd | (xStart/xEnd points +) y |
   //             xStart + xEnd (+ y point) | xStart + xEnd + y
   //   AreaMark  x + y | xStart + xEnd + y | x + yStart + yEnd, each (+ series); "stacking" on x + y (+ series)
   //   RectangleMark x + y | x (+ yStart/yEnd points) | (xStart/xEnd points +) y | xStart + xEnd + y |
   //             xStart + xEnd (+ yStart/yEnd points) | x + yStart + yEnd | (xStart/xEnd points +) yStart + yEnd |
   //             xStart + xEnd + yStart + yEnd | xStart/xEnd/yStart/yEnd points; "width" / "height" as BarMark
   //   SectorMark angle (+ angularInset points); the angle is a number or integer value, each sector's share of the
   //             sum; "innerRadius" / "outerRadius" take the forms of "width" (a pie or a donut: {"ratio": 0.6})
   //   A start and its end have one type.
   // ForEach: {"type": "ForEach", "content": [...]} draws its content once per row of the chart's rows. With
   //   "data" (inline rows, as the chart's "data") it draws over those rows instead, laid out by its own
   //   "columns" when it has them, else by the chart's. A ForEach's data stays in the description (only the
   //   chart's "data" becomes the rows), so it suits fixed series such as targets next to streamed rows.
   // Plot: {"type": "Plot", "content": [...], modifiers}. Its modifiers apply to every mark inside, after the
   //   mark's own. Inside a ForEach a Plot holds marks (and Plots); outside it may also hold a ForEach, and
   //   its modifiers then read no row ("$..." is literal there, as for any mark outside a ForEach).
   // Mark modifiers (a modifier that does not apply to a mark changes nothing):
   //   "foregroundStyle": color or {"by": value}   "symbol": circle|square|triangle|diamond|pentagon|plus|cross|asterisk or {"by"}
   //   "symbolSize": area, {"width", "height"} or {"by"}   "lineStyle": {"lineWidth", "lineCap", "lineJoin", "miterLimit",
   //   "dash", "dashPhase"} or {"by"}   "interpolationMethod": linear|cardinal|catmullRom|monotone|stepStart|stepCenter|
   //   stepEnd, {"cardinal": {"tension"}} or {"catmullRom": {"alpha"}}   "position": {"by", "axis": horizontal|vertical,
   //   "span": dimension}   "cornerRadius": number or {"radius", "style": continuous|circular}   "opacity", "zIndex",
   //   "blur": number   "offset": {"x", "y"} with start/end forms for ranges   "shadow": {"radius", "color", "x", "y"}
   //   "alignsMarkStylesWithPlotArea", "accessibilityHidden": bool   "accessibilityLabel", "accessibilityValue",
   //   "accessibilityIdentifier": text, which inside a ForEach may embed "$N" / "$name" references
   //   "annotation": a view drawn next to the mark (below)
   // Annotations: {"content": a view element, "position", "alignment", "spacing", "overflowResolution"}.
   //   "content" is any element but a Chart, built for each row as a template row is: inside a ForEach its text
   //   reads the row's cells through "$N" / "$name" ({"type": "Text", "properties": {"text": "$users"}}), and
   //   controls in it act with the chart's id as viewID and the 0-based row as viewPartID (a row of a ForEach's
   //   own data when it has some; -1 outside a ForEach).
   //   "position": automatic | overlay | top | bottom | leading | trailing | topLeading | topTrailing |
   //   bottomLeading | bottomTrailing; "alignment": center | leading | trailing | top | bottom | topLeading |
   //   topTrailing | bottomLeading | bottomTrailing; "spacing": points from the mark; "overflowResolution":
   //   {"x", "y"}, each automatic | fit | padScale | disabled | {"fit": "plot" | "chart" | "automatic"}.
   //   Swift Charts takes long to draw many annotations (0.1 s for 1000, 2 s for 5000, on every render), so
   //   past 1000 the chart draws its marks without them, with a warning: annotate a few marks (a goal, the
   //   selection, the largest values), not every row of a long series.
   // Plottable values: {"label": text, "value": v, "type": optional, "unit": optional}.
   //   Inside a ForEach, "$N" (1-based) or "$name" reads that cell of each row. Every column reference needs
   //   a type, from its column or the value's own "type" (which wins); an untyped one is plotted as text.
   //   Outside a ForEach, and when it names no column, a "$..." string is literal text (with a warning
   //   unless the value has "type": "string").
   //   A literal number is "number" (or "integer" with "type": "integer"); a literal string is "string"
   //   (or a date with "type": "date" or a "unit").
   //   "unit" is year | quarter | month | weekOfYear | weekOfMonth | day | hour | minute | second (dates).
   //   Dates are ISO 8601: "YYYY-MM-DD" is a calendar day; a zone designator ("Z", "+hh:mm") makes an instant.
   // Selection marks: outside a ForEach, a plotted value "$selection" reads the selection: on x, xStart or xEnd the
   //   x selection, on y, yStart or yEnd the y selection; a range selection is read by xStart / xEnd (yStart / yEnd)
   //   as its start and end. Such a mark (with its annotation) is drawn only while there is a selection and takes
   //   the axis's type, e.g.
   //   { "type": "RuleMark", "x": { "label": "Selected", "value": "$selection" }, "foregroundStyle": "gray.opacity(0.4)" }
   //   or a RectangleMark with "xStart" and "xEnd" "$selection" for a range. A selected category the chart does not
   //   plot is not drawn (it would add a category). Only these marks are rebuilt on a selection change.
   // One axis plots one type: number and integer may share an axis; a mark plotting another type is dropped.
   // A row whose referenced cell does not parse under its type is skipped, with one warning.
   // Note: Baseline View properties (padding, hidden, frame, background, opacity, animation, accessibility...)
   //   are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   //   Without "value", the baseline "animation" modifier animates every property set, a replaced description included.
 }
// Observable state:
//   value               String       The selection as a JSON string, "" when nothing is selected: {"x": "Tue"},
//                                    {"x": [2.5, 7]} (a range), {"x": "2026-09-01", "y": 140}, {"angle": 51.2, "row": 1}
//                                    ("row": the 0-based data row of the selected sector). Dates print as "yyyy-MM-dd" when
//                                    the axis's first mark has a unit of a day or coarser, else as a local
//                                    "yyyy-MM-ddTHH:mm:ss". setElementValue with the same shape selects (no action fires); a
//                                    part that does not fit the axes reads as nothing selected, and a replaced description
//                                    clears a selection it cannot hold.
//   states["content"]   [[String]]   The chart's data rows (getElementRows / setElementRows / appendElementRows /
//                                    clearElementRows). Changing the rows never changes the description.
```

### Host differences

- **Android** and **Web** have no chart renderer: they draw a "Chart Unavailable" placeholder (the ContentUnavailableView look) in the chart's place, sized by its frame and padding, and log one warning. The value (`""` until a host sets one), the rows API and setting the `chart` property work as on Apple; the description is not read, so its inline `data` does not become the rows, and no action fires.
- **Apple** draws it with Swift Charts on every platform ActionUI supports.
