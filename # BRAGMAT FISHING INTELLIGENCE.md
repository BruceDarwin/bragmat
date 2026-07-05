# BRAGMAT FISHING INTELLIGENCE

## Fishing Intelligence Vision and Design Philosophy

Version: 1.0

---

# Purpose

This document describes the philosophy behind Bragmat's Fishing Intelligence.

It defines how Bragmat should transform simple fishing records into meaningful knowledge that helps anglers:

* understand past success
* recognise patterns
* make better future decisions
* continually improve as anglers

This document intentionally focuses on **why** Bragmat exists rather than **how** it is implemented.

---

# Vision

Bragmat is not simply a fishing log.

It is a personal fishing intelligence system.

Every catch recorded contributes to a growing personal knowledge base.

The objective is to answer questions that anglers naturally ask:

* Why did I catch fish?
* Why didn't I catch fish?
* What conditions consistently produce success?
* How can I improve my next trip?

---

# Guiding Principle

Every new feature should answer one question:

**"Will this help an angler understand why they caught fish, or help them catch more fish next time?"**

If the answer is yes, it belongs in Bragmat.

If the answer is no, it probably belongs somewhere else.

---

# Fishing Intelligence Hierarchy

Fishing Intelligence is built from three types of information.

## Level 1 — Observed

Information directly entered by the angler.

Examples

* Species
* Length
* Location
* Notes
* Manual tide observations
* Water clarity
* River flow
* Fishing method
* Lure
* Bait

Observed data is considered the highest quality because it represents what the angler actually experienced.

---

## Level 2 — Official

Information obtained from authoritative external sources.

Examples

* Official tide stations
* Sunrise
* Sunset
* Moon phase
* Historical weather
* Water temperature
* River levels

Official information provides objective environmental context.

---

## Level 3 — Derived

Information calculated from observed and official data.

Examples

* Time before high tide
* Time after low tide
* Tide window
* Dry season / Wet season
* Fishing session
* Morning / Afternoon
* Moon illumination
* Weather categories

Derived values should never replace observed values.

They exist to support analysis.

---

# Environmental Context

Every catch occurs within an environmental context.

Bragmat should gradually build this context automatically.

Current

* Moon
* Sunrise
* Sunset
* Weather

Future

* Official tide events
* Water temperature
* River height
* River flow
* Rainfall history
* Barometric trends
* Wind history

The angler should only enter information that cannot be determined automatically.

---

# Tide Philosophy

Tide information should reflect how anglers think.

Not:

Run-in

Run-out

Rising

Falling

Instead:

* 45 minutes before high tide
* 2 hours after low tide
* Last hour of the run-in
* First half of the ebb

Future analysis should focus on:

* Previous tide event
* Next tide event
* Time before or after tide
* Tide height
* Tide station
* Tide window

Manual observations always override automatically obtained information.

---

# Pattern Recognition

Fishing Intelligence should identify patterns over time.

Examples

Species

* Largest fish
* Average size
* Preferred locations
* Preferred tide windows
* Preferred moon phases

Locations

* Most productive spots
* Seasonal differences
* Species diversity

Trips

* Best trips
* Average catch rate
* Weather influence

Environmental

* Moon
* Weather
* Wind
* Tide
* Temperature
* Water clarity
* River flow

---

# Bite Window Intelligence

Future versions should identify productive bite windows.

Possible examples

* Two hours before high tide
* First hour of the run-out
* Dawn during a rising tide
* Afternoon on neap tides
* Evening with falling pressure

These windows should be learned from the user's own fishing history.

---

# AI Philosophy

Artificial Intelligence should explain patterns.

Not replace the angler.

AI should answer questions such as:

"When do I usually catch my biggest barramundi?"

"What conditions produce the best jewfish?"

"Compare this trip with my previous Dundee trips."

"What changed compared with my most successful trip?"

AI should always explain its reasoning using the user's own historical data.

---

# Confidence

Not all insights are equally reliable.

Bragmat should indicate confidence.

Examples

High confidence

* Based on 150 catches

Medium confidence

* Based on 25 catches

Low confidence

* Based on 5 catches

The application should avoid presenting weak patterns as facts.

---

# Learning Over Time

Fishing Intelligence should become progressively better as more catches are recorded.

Early users may receive simple summaries.

Experienced users should receive:

* trend analysis
* seasonal comparisons
* location comparisons
* environmental correlations
* species predictions
* personalised recommendations

---

# Future Intelligence Modules

Possible future modules include:

* Bite Window Analysis
* Species Prediction
* Trip Planning
* Seasonal Reviews
* Personal Best Forecasts
* Location Comparison
* Weather Correlation
* Moon Correlation
* Tide Correlation
* Lure Effectiveness
* Bait Effectiveness
* Fishing Method Analysis

---

# Success Measure

The success of Fishing Intelligence is not measured by the number of statistics produced.

It is measured by whether an angler can genuinely say:

"I understand my fishing better today than I did yesterday."

Every enhancement should contribute to building a long-term personal fishing knowledge base that becomes more valuable with every trip.
