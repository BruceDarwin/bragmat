# BRAGMAT DATABASE

## Database Design, Schema and Business Rules

Version: 1.2
Database Version: 23
Last Updated: July 2026

---

# Purpose

This document describes the Bragmat database architecture.

It provides:

- database schema
- table relationships
- business rules
- migration history
- data ownership
- future database roadmap

The database has been designed to support:

- personal fishing records
- environmental intelligence
- statistics
- achievements
- future AI analysis
- future TEBS competition mode

---

# Design Principles

## Preserve User Data

User data is never deleted during upgrades.

Database migrations should always preserve existing records.

---

## One Source of Truth

Each fact should be stored only once.

Derived values should be calculated rather than duplicated wherever practical.

---

## Automatic Before Manual

Automatically capture information wherever possible.

Examples

GPS

Moon

Weather

Sunrise

Sunset

Estimated Tide

---

## Manual Overrides Automatic

User observations always override estimated values.

---

# Database Version History

Version 1

Initial Catch database

---

Version 9

Multiple photos

catch_media table

---

Version 10

Fishing Trips

trip_id added to catches

---

Version 17

Achievements

Environmental Conditions

---

Version 18

Environmental Conditions expanded

Moon

Sun

Weather

Tide

---

Version 19

Manual Tide

Strength

Notes

---

Version 20

Humidity

Cloud Cover

Open-Meteo Weather

---

Version 21

Estimated Tide

Open-Meteo Marine

---

Version 22

Tide Diagnostics

Temporary

(Removed from UI)

---

Version 23

Tide Context

Reference tide event

Time before/after

Future WorldTides support

---

# Table Overview

Current tables

catches

catch_media

fishing_trips

trip_journal

fish_types

fishing_buddies

favourite_spots

environmental_conditions

achievements

user_achievements

---

# Table Relationships

Fishing Trip

↓

Catches

↓

Catch Media

↓

Environmental Conditions

↓

Achievements

Favourite Spots

↓

Catch Location

Fishing Buddies

↓

Catch

---

# catches

Purpose

Primary fishing record.

One record per fish caught.

Major fields

id

fish_type

length_cm

date_caught

notes

trip_id

buddy_id

location

latitude

longitude

created_at

Business Rules

One catch represents one fish.

Photos stored separately.

Environmental conditions stored separately.

Statistics built primarily from this table.

---

# catch_media

Purpose

Stores multiple photos for each catch.

Fields

id

catch_id

image_path

photo_datetime

is_primary

display_order

Business Rules

One catch

↓

Many photos

Primary photo always available.

Future

Video support

---

# fishing_trips

Purpose

Groups catches into trips.

Fields

id

name

location

start_date

end_date

notes

Business Rules

Trip may have zero catches.

Trip Summary generated from related catches.

---

# trip_journal

Purpose

Diary entries during trips.

Fields

id

trip_id

journal_datetime

entry

Business Rules

Many journal entries per trip.

Used by Trip Recap.

---

# fish_types

Purpose

User-defined species list.

Fields

id

fish_name

display_order

Business Rules

Editable.

Deleted fish types remain readable in historic catches.

---

# fishing_buddies

Purpose

People fishing together.

Fields

id

name

notes

Business Rules

Optional.

Referenced by catches.

---

# favourite_spots

Purpose

Saved fishing locations.

Fields

id

name

latitude

longitude

notes

Business Rules

Can populate catch locations.

Future AI hotspot analysis.

---

# environmental_conditions

Purpose

Stores all environmental observations and derived information.

One record per catch.

Fields

## Moon

moon_phase

moon_illumination

---

## Sun

sunrise

sunset

---

## Weather

weather_condition

temperature

humidity

cloud_cover

wind_speed

wind_direction

barometric_pressure

rainfall

---

## Water

water_clarity

river_flow

---

## Manual Tide

tide_stage

tide_strength

tide_height

tide_notes

tide_station

tide_movement

---

## Estimated Tide

derived_tide_stage

tide_data_source

tide_confidence

tide_observed_or_estimated

---

## Tide Context

tide_station_name

tide_station_distance_km

reference_tide_event_type

reference_tide_event_time

reference_tide_event_height

reference_tide_event_relation

minutes_from_reference_tide_event

previous_tide_event_type

previous_tide_event_time

previous_tide_event_height

next_tide_event_type

next_tide_event_time

next_tide_event_height

tide_context_phrase

tide_context_data_source

tide_context_confidence

Business Rules

One EnvironmentalCondition

↓

One Catch

Manual values override estimated values.

Future APIs should update estimated values only.

---

# achievements

Purpose

Master achievement catalogue.

Contains

id

name

description

icon

criteria

category

Business Rules

Static reference data.

---

# user_achievements

Purpose

Achievements unlocked by user.

Fields

achievement_id

date_unlocked

progress_value

Business Rules

One achievement

↓

One unlock

Future

Multiple levels

---

# Statistics

Generated.

Not stored.

Examples

Largest Fish

Average Size

Species Counts

Trip Counts

Environmental Insights

Achievement Counts

---

# Environmental Intelligence

Automatically Generated

Moon

Sun

Weather

Estimated Tide

Future

River Flow

Water Temperature

Fishing Forecast

---

# Tide Data Hierarchy

Highest priority

Manual Observation

↓

Official Tide API

↓

Estimated Tide

↓

Derived Values

Manual always wins.

---

# Future Tables

Possible additions

competition_rounds

competition_entries

competition_series

shared_trips

weather_cache

tide_cache

user_preferences

cloud_sync

ai_insights

---

# Database Migrations

Rules

Never remove columns without migration.

Always preserve user data.

Support editing legacy records.

Test backup after every migration.

---

# Backup Coverage

Current

Catches

Photos

Trips

Journal

Fish Types

Fishing Buddies

Favourite Spots

Environmental Conditions

Achievements

User Achievements

Future tables must automatically become part of backup.

---

# Index Strategy

Currently minimal.

Future indexes

catches(date_caught)

catches(fish_type)

catches(trip_id)

environmental_conditions(moon_phase)

environmental_conditions(weather_condition)

environmental_conditions(tide_stage)

environmental_conditions(reference_tide_event_type)

environmental_conditions(minutes_from_reference_tide_event)

Only add indexes when justified by performance.

---

# Future AI Queries

Examples

Largest Barra

↓

Weather

↓

Moon

↓

Tide

↓

Location

↓

Season

Questions

When do I catch the biggest barra?

Which moon phase catches the most jewfish?

Which tide window produces the highest average golden snapper?

Compare Dundee against Shady Camp.

Summarise my Dry Season.

---

# Data Quality Rules

Latitude

-90 to +90

Longitude

-180 to +180

Fish length

Positive only

Moon Illumination

0–100%

Humidity

0–100%

Cloud Cover

0–100%

Temperature

Reasonable local limits

Reference Tide Height

Positive

Minutes Before/After Tide

Calculated

Not manually entered

---

# Database Philosophy

The Bragmat database is more than a fishing log.

It is designed to become a long-term personal fishing knowledge base.

Every new field should answer one question:

**"Will this help anglers understand why they caught fish?"**

If the answer is yes, it belongs in the database.

If the answer is no, it probably belongs somewhere else.