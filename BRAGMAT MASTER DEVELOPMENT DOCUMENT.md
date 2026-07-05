BRAGMAT MASTER DEVELOPMENT DOCUMENT
Project Handover & Development Guide

Version: 1.2 (July 2026)

Project Vision

Bragmat is not simply a fishing log.

Its purpose is to become a personal fishing intelligence system that helps anglers:

record catches
remember trips
understand patterns
improve future success
eventually receive AI-powered fishing advice based on their own historical data.

Competition features (TEBS) will eventually be added as an optional mode.

The application should always remain valuable to anglers who never participate in competitions.

Long-Term Vision

Bragmat should become:

Your personal fishing knowledge base.

Not:

Just another fishing diary.

Everything added to the application should support learning from previous fishing experiences.

Technology Stack

Flutter Stable 3.44.1

Dart 3.12.1

SQLite (sqflite)

Google Maps

GPS

Image Picker

Share Plus

CSV Export

Open-Meteo Weather API

Open-Meteo Marine API

Sunrise API

Moto G15 primary Android test device

Current Development Phase

Bragmat v1.2

User Experience & Visual Refinement

Status:

Largely complete.

Completed Features
Catch Management

Complete CRUD

Multiple photos

Primary photo

Photo gallery

Photo timestamps

GPS capture

Location name

Favourite Spots

Fishing Buddy

Trip assignment

Environmental conditions

Sticky Save button

Unsaved changes detection

Trips

Create/edit/delete trips

Trip journals

Trip summaries

Trip recap generation

Trip sharing

Statistics

Achievements earned during trip

Environmental summary

Statistics

Lifetime Fishing

Highlights

Species Records

Location Summary

Environmental Insights

Achievements summary

Maps

Catch locations

Favourite fishing spots

GPS selection

Current location

Map picker

Achievements

16 achievements

Progress tracking

Categories

Notifications

Achievement screen

Statistics integration

Backup support

Environmental Intelligence

Moon Phase

Moon illumination

Sunrise

Sunset

Weather (Open-Meteo)

Estimated Tide (Open-Meteo Marine)

Manual Tide

Manual Tide Context

Environmental Insights

UI Philosophy

Bragmat v1.2 introduced a consistent design language.

Every screen should follow the same structure.

Cards

Icons

Spacing

Typography

Rounded corners

Friendly empty states

Progressive disclosure

Navigation Philosophy

Bottom Navigation

Navigation only

Current:

Catches

Statistics

Trips

Map

Settings

Actions

Performed using FABs

Examples:

Add Catch

New Trip

New Favourite Spot

Standard Screen Structure

Example:

Catch Details

Photo

Catch Details

Date & Time

Location

Trip

Environmental Conditions

Notes

The same structure should be used in Add/Edit Catch.

Environmental Data Philosophy

Automatically capture wherever possible.

User should not have to enter data that can be derived.

Automatically captured:

Moon Phase

Moon Illumination

Sunrise

Sunset

Weather

Estimated Tide

Manually entered:

Water clarity

River flow

Weather override

Tide Stage

Tide Strength

Tide Notes

Tide Context

Manual observations always override estimated values.

Tide Philosophy

Current:

Estimated movement from Open-Meteo Marine

Manual tide observations

Manual Tide Context

Future:

Official tide station integration

WorldTides (preferred)

Current Open-Meteo use:

Determine

Run-In

Run-Out

Slack

Confidence

Do NOT use Open-Meteo tide heights as official tide heights.

Tide Context

New concept.

Rather than simply:

Run-In Tide

Record:

1 hr 35 min before the Darwin high tide of 6.37 m at 3:09 pm

Future analyses will use:

Time before high

Time after high

Time before low

Time after low

Tide windows

Species by tide window

Environmental Insights

Currently includes:

Moon

Weather

Wind

Temperature

Tide

Future:

Humidity

Cloud Cover

Rainfall

River Flow

Water Clarity

Season

Water Temperature

Barometer trends

AI Vision

Bragmat AI should eventually answer questions like:

"When do I usually catch metre barra?"

"What conditions produce my biggest jewfish?"

"Compare this trip with previous Dundee trips."

"Summarise my Dry Season."

"Which moon phases produce the biggest fish?"

"Should I fish tomorrow afternoon?"

Future AI Data Sources

Personal history

Moon

Weather

Tides

Trips

Photos

Species

Location

Season

River flow

Water temperature

Bite windows

Future Roadmap
v1.2

UX Refinement

Navigation

Cards

Settings

Consistency

Accessibility

Polish

v1.3

Fishing Intelligence

Bite Windows

Better Tide Analysis

Species Correlations

Trip Comparisons

Environmental Analysis

v1.4

AI Assistant

Trip Recaps

Season Reviews

Recommendations

Natural Language Queries

v1.5

TEBS Competition Mode

Competition rules

Scoring

Leaderboards

Rounds

Series

Achievements

Development Principles

Always:

Preserve backward compatibility.

Older catches should continue to load.

Never lose data.

Manual observations override estimates.

Prefer automatic capture over manual entry.

Avoid duplicate data.

Keep business logic separate from UI.

Create reusable widgets.

Keep UX consistent.

Coding Standards

Reusable widgets preferred.

BragmatSectionCard

BragmatDataRow

BragmatEmptyState

LocationActionButtons

Future common widgets should extend this design language.

Current Known Issue

Outstanding:

Edit Catch

Older records

Dropdown assertion

Needs identifying by exact widget rather than broad validation.

Future Major Features

Official tide stations

Bite Windows

River flow APIs

Weather forecasts

Fishing forecasts

AI summaries

AI recommendations

Species prediction

Season comparisons

Cloud backup

Cross-device sync

iPhone support

TestFlight

Testing Philosophy

Development:

Moto G15

Android Emulator

Future:

Small Android beta

iPhone TestFlight

TEBS members

Casual anglers

Target Users

Primary:

Northern Territory recreational anglers

Secondary:

Australian recreational anglers

Future:

Competition anglers

General fishing community

Guiding Principle

Every new feature should answer one question:

"Will this help an angler catch more fish, remember more about their fishing, or learn something useful from their own experiences?"

If the answer is yes, it belongs in Bragmat.

If the answer is no, think carefully before adding it.