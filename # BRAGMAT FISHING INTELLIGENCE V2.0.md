# BRAGMAT FISHING INTELLIGENCE

## Fishing Intelligence Vision and Design Philosophy

**Version:** 2.0
**Last Updated:** July 2026

---

# Purpose

This document defines the vision, philosophy and long-term direction of Bragmat's Fishing Intelligence.

It describes **why** Fishing Intelligence exists, **what** it aims to achieve, and the principles that should guide every future enhancement.

Unlike the Architecture and Database documents, this document deliberately avoids implementation details. Its purpose is to provide the guiding philosophy for future development.

---

# Vision

Bragmat is not simply a fishing log.

It is a **personal fishing intelligence system**.

Every catch, trip and observation contributes to a continually expanding personal fishing knowledge base.

Rather than simply recording fishing experiences, Bragmat seeks to understand them.

The ultimate objective is to help anglers answer questions such as:

* Why did I catch fish?
* Why didn't I catch fish?
* What conditions consistently produce success?
* What decisions improved my chances?
* How can I improve my next trip?

---

# What is Fishing Intelligence?

Fishing Intelligence is the process of transforming fishing experiences into knowledge.

A traditional fishing log records events.

Bragmat seeks to explain those events.

Every catch becomes another piece of evidence.

Over months and years those pieces combine into an increasingly accurate understanding of an individual's fishing.

Fishing Intelligence is therefore not about producing more statistics.

It is about discovering meaningful relationships between:

* the angler
* the fish
* the environment
* the location
* the tackle
* the decisions that were made

---

# Guiding Principle

Every new feature should answer one question:

**"Will this help an angler understand why they caught fish, or help them catch more fish next time?"**

If the answer is yes, it belongs in Bragmat.

If the answer is no, it probably belongs somewhere else.

---

# Intelligence Domains

Fishing Intelligence is built from several complementary knowledge domains.

## Species Intelligence

Understanding individual fish species.

Examples

* preferred locations
* preferred seasons
* preferred weather
* preferred tide windows
* preferred moon phases
* average sizes
* personal best history

---

## Location Intelligence

Understanding each fishing location.

Examples

* best months
* productive weather
* productive tides
* productive species
* average catch rate
* historical success

---

## Environmental Intelligence

Understanding environmental influences.

Examples

* weather
* moon
* sunrise
* sunset
* tides
* wind
* rainfall
* water clarity
* river flow
* water temperature
* barometric pressure

---

## Trip Intelligence

Learning from complete fishing trips.

Examples

* successful trips
* unsuccessful trips
* effort versus reward
* companions
* seasonal comparisons
* trip summaries

---

## Tackle Intelligence

Understanding which equipment consistently performs best.

Future analysis may include

* lure performance
* bait performance
* lure colour
* lure depth
* fishing techniques
* retrieves
* hook styles
* leader materials
* line classes
* rod and reel combinations

The objective is not to build an inventory system.

The objective is to understand which tackle consistently performs best under different fishing conditions.

---

# Fishing Intelligence Hierarchy

Fishing Intelligence is built from three different types of information.

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
* Lure
* Bait
* Technique
* Retrieve
* Target species

Observed data is considered the highest quality because it represents what actually occurred.

---

## Level 2 — Official

Information obtained from authoritative sources.

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
* Tide windows
* Dry season / Wet season
* Fishing session
* Morning / Afternoon
* Moon illumination
* Weather categories

Derived values should never replace observed values.

They exist solely to improve analysis.

---

# Controllable and Uncontrollable Factors

Fishing success is influenced by two different types of factors.

## Uncontrollable

The angler cannot influence these.

Examples

* Moon
* Tide
* Weather
* Wind
* Sunrise
* Sunset
* Water level
* Season

---

## Controllable

These are decisions made by the angler.

Examples

* Fishing location
* Lure
* Bait
* Technique
* Retrieve
* Fishing duration
* Fishing companions

The greatest value of Fishing Intelligence comes from understanding how controllable decisions interact with uncontrollable environmental conditions.

---

# Environmental Context

Every catch occurs within an environmental context.

Bragmat should progressively build this context automatically.

Current

* Moon
* Sunrise
* Sunset
* Weather

Future

* Official tide stations
* Water temperature
* River height
* Rainfall history
* River flow
* Wind history
* Barometric trends

The angler should only enter information that cannot be determined automatically.

---

# Tide Philosophy

Tides should be recorded the way anglers think.

Not

* Rising
* Falling
* Run-in
* Run-out

Instead

* 45 minutes before High Tide
* 1 hour after Low Tide
* Last hour of the incoming tide
* First half of the outgoing tide

Future analysis should focus on

* Previous tide event
* Next tide event
* Time before or after tide
* Tide height
* Tide station
* Tide windows

Manual observations always take precedence over automatically obtained information.

---

# Tackle Philosophy

Fishing tackle is one of the strongest influences on fishing success.

Bragmat should treat tackle as reusable reference information rather than free-text notes.

Future versions should maintain reusable libraries for

* Lures
* Baits
* Techniques

Each catch should reference these records.

This enables analysis such as

* Best lure for metre barramundi
* Best lure colour at Dundee
* Best bait during the Dry Season
* Average fish size by lure
* Catch rate by retrieve

---

# Correlation Rather Than Statistics

Fishing Intelligence is not about counting catches.

It is about discovering relationships.

Examples

Large barramundi may correlate with

* shallow-diving hardbody lures
* the final two hours of the incoming tide
* low cloud cover
* afternoon sessions

Golden snapper may correlate with

* vibration lures
* neap tides
* deeper water
* calm conditions

These relationships should emerge naturally from historical fishing records.

---

# Pattern Recognition

Fishing Intelligence should continually search for patterns.

Examples

Species

* largest fish
* average size
* preferred locations
* preferred tide windows
* preferred moon phases

Locations

* most productive spots
* seasonal differences
* species diversity

Trips

* best trips
* average catch rate
* weather influence

Environmental

* moon
* weather
* wind
* tide
* temperature
* water clarity
* river flow

Tackle

* lure performance
* bait performance
* technique effectiveness
* retrieve effectiveness

---

# Bite Window Intelligence

Future versions should identify productive bite windows.

Examples

* two hours before high tide
* first hour of the outgoing tide
* dawn during a rising tide
* afternoon on neap tides
* evening with falling pressure

These windows should be learned from the user's own fishing history.

---

# AI Philosophy

Artificial Intelligence should explain patterns.

Not replace the angler.

Bragmat AI should eventually become a personal fishing mentor.

Examples

"When do I usually catch my biggest barramundi?"

"Which lure has produced my largest fish?"

"What lure should I start with today?"

"What conditions usually produce metre barra?"

"Compare this trip with my most successful Dundee trip."

Every recommendation should be supported by the user's own fishing history.

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

Weak patterns should never be presented as facts.

---

# Knowledge Growth

Fishing Intelligence develops through five stages.

## Stage 1

Recording

"What happened?"

---

## Stage 2

Understanding

"Why did it happen?"

---

## Stage 3

Prediction

"What is likely to happen?"

---

## Stage 4

Recommendation

"What should I do next?"

---

## Stage 5

Learning

"How has my understanding improved over the years?"

---

# Learning Over Time

Fishing Intelligence should become progressively more valuable as more catches are recorded.

Early users may receive simple summaries.

Experienced users should receive

* trend analysis
* seasonal comparisons
* location comparisons
* environmental correlations
* tackle correlations
* species predictions
* personalised recommendations

---

# Future Intelligence Modules

Possible future modules include

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
* Technique Effectiveness
* Retrieve Analysis
* Fishing Opportunity Scoring

---

# Success Measure

Bragmat succeeds when it helps anglers make better fishing decisions.

Every trip should contribute to an expanding personal fishing knowledge base.

The application should eventually become the angler's most trusted fishing companion—not because it knows everything about fishing, but because it understands that individual's own fishing experiences better than anyone else.

---

# Closing Philosophy

Fishing Intelligence is not about replacing the judgement of experienced anglers.

It is about helping anglers recognise patterns that would otherwise remain hidden within years of fishing memories, photographs and notes.

Every catch, every trip and every observation becomes another piece of evidence contributing to a richer understanding of how, when and why fish are caught.

Bragmat is not building a database of fish.

It is building a lifetime of fishing knowledge.

With every trip, Bragmat should become a little wiser—just like the angler using it.
