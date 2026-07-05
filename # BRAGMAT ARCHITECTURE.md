# BRAGMAT ARCHITECTURE

## Technical Architecture and Development Standards

Version: 1.2
Last Updated: July 2026

---

# Purpose

This document describes the technical architecture of Bragmat.

It is intended for:

- future development
- onboarding new developers
- AI development assistants (ChatGPT, Devin, Codex)
- documenting design decisions
- maintaining consistency

---

# Architecture Principles

Bragmat follows several guiding principles.

## 1. Business Logic separated from UI

Business rules belong in Services.

Screens should primarily:

- display information
- collect user input
- call Services

Avoid placing business logic directly in Widgets.

---

## 2. Reusable Components

If a UI element appears more than once it should become a reusable widget.

Examples

BragmatSectionCard

BragmatDataRow

BragmatChip

BragmatEmptyState

LocationActionButtons

---

## 3. Automatic Data Collection

Automatically derive information wherever possible.

Examples

Moon Phase

Moon Illumination

Sunrise

Sunset

Weather

Estimated Tide

GPS

Photo metadata

The user should only enter information that cannot be determined automatically.

---

## 4. Manual Override

Manual observations always take precedence over estimated values.

Priority order

Manual Observation

↓

Official API

↓

Estimated API

↓

Derived values

---

# Application Structure

lib/

models/

services/

screens/

widgets/

helpers/

database/

theme/

---

# Models

Current major models

Catch

FishingTrip

FishingBuddy

FavouriteSpot

EnvironmentalCondition

TripSummary

TripJournal

Achievement

UserAchievement

---

# Database

SQLite

sqflite

Current Version

23

Migration philosophy

Never delete user data.

Always migrate.

Support editing legacy records.

---

# Major Tables

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

# Relationships

Fishing Trip

↓

Many Catches

↓

Many Photos

↓

One EnvironmentalCondition

↓

Achievements

---

# Services

DatabaseHelper

Single database access point.

Responsibilities

CRUD

Migrations

Queries

Statistics

---

EnvironmentalConditionsService

Responsible for

Moon

Sunrise

Sunset

Weather

Estimated Tide

Manual Tide

Environmental Insights

Automatic updates

---

MoonPhaseService

Calculates

Moon phase

Illumination

Emoji

---

SunTimesService

Calculates

Sunrise

Sunset

Uses Sunrise API

---

WeatherService

Provider

Open-Meteo

Responsibilities

Temperature

Humidity

Cloud Cover

Wind

Pressure

Rainfall

Weather code

---

TideService

Provider

Open-Meteo Marine

Responsibilities

Estimated movement

Run-In

Run-Out

Slack

Future

WorldTides

---

TripSummaryService

Responsible for

Trip statistics

Trip recap

Catch highlights

Environmental summaries

Sharing

---

AchievementService

Responsible for

Unlocking

Progress

Notifications

Statistics

---

BackupService

Responsible for

Backup

Restore

Export

Import

Migration compatibility

---

# Helper Classes

TideContextHelper

Generates

Human-readable tide phrases

Example

1 hr 35 min before the Darwin high tide of 6.37 m at 3:09 pm

---

Statistics Helpers

Species

Weather

Moon

Temperature

Tide

Trip summaries

---

# Widgets

Standard widgets

BragmatSectionCard

BragmatDataRow

BragmatChip

BragmatEmptyState

LocationActionButtons

Future widgets should follow the same design language.

---

# Screen Structure

Catch List

↓

Catch Details

↓

Add/Edit Catch

↓

Trips

↓

Trip Details

↓

Statistics

↓

Map

↓

Settings

---

# Navigation

Bottom Navigation

Catches

Statistics

Trips

Map

Settings

Floating Action Buttons

Create Catch

Create Trip

Create Favourite Spot

---

# Environmental Intelligence

Automatically calculated

Moon Phase

Illumination

Sunrise

Sunset

Weather

Estimated Tide

Manually entered

Water Clarity

River Flow

Weather Override

Tide

Tide Strength

Tide Notes

Tide Context

---

# Tide Architecture

Current

Open-Meteo Marine

Purpose

Movement estimation

Run-In

Run-Out

Slack

Confidence

Future

WorldTides

Purpose

Official tide stations

High Tide

Low Tide

Height

Datum

Time before high

Time after high

---

# Tide Context

Purpose

Record tides the way anglers think.

Example

1 hr 35 min before the Darwin high tide of 6.37 m at 3:09 pm

Future analysis

Best tide windows

Species by tide window

AI recommendations

---

# Weather Architecture

Current

Open-Meteo

Automatic

Temperature

Humidity

Cloud cover

Wind

Pressure

Rainfall

Future

Forecasts

Historical weather

Fishing forecasts

---

# AI Architecture

Current

Rule-based summaries

Trip Recap

Environmental Insights

Future

Natural language assistant

Pattern recognition

Fishing recommendations

Species prediction

Trip comparison

Season review

---

# API Providers

Current

Open-Meteo Weather

Open-Meteo Marine

Sunrise API

Future

WorldTides

Potential river flow APIs

Potential water temperature APIs

---

# Error Handling

API failures should never prevent:

Saving catches

Saving trips

Editing records

Manual data entry

Offline operation

Graceful degradation is preferred.

---

# Offline Philosophy

Bragmat must remain usable with no internet.

Unavailable APIs should simply leave automatic fields blank.

Manual entry must always be available.

---

# Backup Philosophy

Backup includes

Database

Photos

Environmental data

Achievements

Trips

Journal

Favourite Spots

Fishing Buddies

Fish Types

Future additions must automatically become part of BackupService.

---

# Coding Standards

Prefer immutable models.

Use copyWith()

Keep services small.

Separate UI from business logic.

Prefer reusable widgets.

Avoid duplicate logic.

Comment complex algorithms.

---

# Testing Strategy

Primary device

Moto G15

Secondary

Android Emulator

Future

Pixel

Samsung

iPhone

TestFlight

---

# Future Architecture

Cloud Sync

Firebase

Multi-device sync

User accounts

AI assistant

Competition mode

Shared trips

Shared fishing spots

Community reports

---

# Technical Debt

Known issues

Legacy record compatibility

Dropdown validation

Further UI refinement

Weather caching

Tide station integration

---

# Development Checklist

Before every release

✓ Database migration tested

✓ Backup tested

✓ Restore tested

✓ Legacy data tested

✓ New catch tested

✓ Edit catch tested

✓ Trip summary tested

✓ Environmental calculations tested

✓ Statistics tested

✓ Share functionality tested

✓ Offline behaviour tested

✓ Performance acceptable

---

# Design Philosophy

The architecture should always favour:

Simplicity

Maintainability

Backward compatibility

Automatic intelligence

User-entered observations

Extensibility

Every new feature should integrate with the existing architecture rather than introducing parallel systems.
