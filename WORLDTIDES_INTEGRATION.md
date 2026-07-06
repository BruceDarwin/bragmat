# WorldTides Integration - Future Architecture

## Overview

This document outlines the planned architecture for integrating official WorldTides API data into Bragmat to provide credible tide context for catches.

## Current Status

- **Placeholder Service**: `WorldTidesService` exists as a placeholder returning null/empty
- **Database Schema**: EnvironmentalCondition table already has all required fields for tide context
- **Models**: TideStation and TideEvent models defined
- **UI**: Catch Details displays "Tide context not available" when official data is missing
- **Manual Tide**: Users can still manually record tide observations (stage, strength, movement, height, notes)

## Planned Integration Flow

### 1. Catch Creation/Update Trigger

When a catch is saved with GPS coordinates and date/time:

```
Catch saved (with lat/lon + dateCaught)
→ EnvironmentalConditionsService.upsertCalculatedConditionsForCatch()
→ Check if WorldTides API is available
→ If available: fetch official tide context
→ If not available: continue without tide context
```

### 2. WorldTides API Flow

```
Catch coordinates (lat, lon) + catch date/time
→ WorldTidesService.getNearestTideStation(lat, lon)
→ Returns: TideStation (stationId, name, distance, timezone)

→ WorldTidesService.getTideEvents(stationId, catchDate)
→ Returns: List<TideEvent> (eventType, eventTime, height)

→ WorldTidesService.calculateTideContext(tideEvents, catchTime)
→ Returns: TideContext (previous/next events, time delta, context phrase)
```

### 3. Data Storage

Tide context data stored in `environmental_conditions` table:

- `tide_station_name`: Name of nearest tide station
- `tide_station_distance_km`: Distance from catch to station
- `reference_tide_event_type`: "High" or "Low"
- `reference_tide_event_time`: DateTime of reference event
- `reference_tide_event_height`: Tide height in meters
- `reference_tide_event_relation`: "Before" or "After"
- `minutes_from_reference_tide_event`: Time delta
- `previous_tide_event_type`: Previous event type
- `previous_tide_event_time`: Previous event time
- `previous_tide_event_height`: Previous event height
- `next_tide_event_type`: Next event type
- `next_tide_event_time`: Next event time
- `next_tide_event_height`: Next event height
- `tide_context_phrase`: Human-readable phrase
- `tide_context_data_source`: "WorldTides"
- `tide_context_confidence`: "High" (official data)

### 4. UI Display

**Catch Details Screen:**

- If `tide_context_data_source == "WorldTides"`:
  - Display blue "Official Tide Context" card with phrase
  - Show station name, event details, time delta

- If no official context:
  - Display grey "Tide context not available" card
  - Show manual tide observations if entered (orange card)

**Add/Edit Catch Screen:**

- Display grey "Official Tide Context not available" placeholder
- No automatic tide data fetching (manual entry only)
- When WorldTides is integrated, this will auto-fetch

## WorldTides API Details

### API Endpoint
- Base URL: `https://www.worldtides.info/api`
- Requires API key

### Key Endpoints

1. **Nearest Station**
   - `GET /v3?stations&lat={lat}&lon={lon}&key={key}`
   - Returns nearest tide stations with metadata

2. **Tide Extremes**
   - `GET /v3?extremes&lat={lat}&lon={lon}&date={date}&key={key}`
   - Returns high/low tide events for a date

### Response Format

```json
{
  "stations": [
    {
      "name": "Darwin",
      "lat": -12.46,
      "lon": 130.84,
      "distance": 5.2
    }
  ],
  "extremes": [
    {
      "type": "High",
      "date": "2024-01-15T03:09:00",
      "height": 6.37
    },
    {
      "type": "Low",
      "date": "2024-01-15T09:24:00",
      "height": 1.12
    }
  ]
}
```

## Implementation Checklist

- [ ] Configure WorldTides API key (environment variable or secure storage)
- [ ] Implement `WorldTidesService.getNearestTideStation()`
- [ ] Implement `WorldTidesService.getTideEvents()`
- [ ] Implement `WorldTidesService.calculateTideContext()`
- [ ] Add error handling for API failures
- [ ] Add rate limiting/caching to avoid excessive API calls
- [ ] Update `EnvironmentalConditionsService` to call WorldTides when available
- [ ] Update Add/Edit Catch UI to show loading state during tide fetch
- [ ] Add "Refresh Tide Context" button for manual refresh
- [ ] Test with various locations and dates

## Important Rules

1. **No Open-Meteo Marine**: Do not use Open-Meteo tide data (not credible enough)
2. **No Estimated Data**: Never generate or display estimated tide context
3. **Manual Only Until Official**: Users can only manually record tide observations until WorldTides is integrated
4. **Clear Messaging**: Always show "Tide context not available" when official data is missing
5. **Source Attribution**: Always label tide context as "Official" when from WorldTides

## Future Bite Window Analysis

Once tide context is established, this enables:

- Group catches by tide time bands (0-1 hr before high, 1-2 hr after low, etc.)
- Analyze catch success rates by tide phase
- Identify optimal tide conditions for specific species
- Provide bite window predictions based on historical data

## Notes

- Database schema already supports all required fields (no migration needed)
- Models (TideStation, TideEvent) are defined and ready
- TideContextHelper has phrase generation logic
- UI is prepared to display official context when available
