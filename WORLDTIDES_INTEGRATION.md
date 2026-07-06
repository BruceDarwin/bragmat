# WorldTides Integration

## Overview

WorldTides API v3 integration provides official high/low tide event data for catches with GPS coordinates. This integration delivers credible tide context without blocking catch save operations.

## Implementation Status

**✅ Production-Ready**

- WorldTides API v3 fully integrated
- Credibility validation for Darwin region
- Non-blocking API calls during catch save
- Caching to avoid unnecessary API calls
- Environmental backfill support
- Comprehensive error handling

## Request Pattern

### API Endpoint
- Base URL: `https://www.worldtides.info/api/v3`
- Requires API key (stored in SharedPreferences)

### Request Parameters
```
extremes          # Request high/low tide events only
lat={latitude}    # Catch latitude
lon={longitude}   # Catch longitude
date={YYYY-MM-DD} # Catch date
key={apiKey}      # API key
days=3            # Request 3 days of tide data
datum=CD          # Chart Datum (critical for accurate heights)
```

**Important:** The `stations` parameter is NOT included because it causes `extremes: null` when combined with `datum=CD`. Station names are therefore not available with the current request pattern.

### Response Format
```json
{
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

## Service Architecture

### WorldTidesService

**Main Method:** `getTideContextForLocation(latitude, longitude, observationTime)`

**Separated Concerns:**
- `_fetchTideData()` - API communication with timeout handling
- `_parseStationInfo()` - Station information parsing
- `_parseTideEvents()` - Tide event parsing and UTC time handling
- `_convertToLocalTime()` - UTC to local time conversion
- `_validateTideCredibility()` - Darwin region height validation
- `_calculateTideContext()` - Tide context calculation
- `_findReferenceEvent()` - Find nearest tide event
- `_findPreviousEvent()` - Find previous tide event
- `_findNextEvent()` - Find next tide event
- `_determineRelation()` - Determine before/after relation

### Error Handling

**Logged Errors:**
- Invalid API key (401)
- Rate limit exceeded (429)
- Request timeout (30s)
- Network errors
- Unexpected API response

**Never Logged:**
- API key (redacted from any logs)
- Raw JSON responses
- Request URLs
- Event parsing details

## Persistence Model

### EnvironmentalCondition Table

Tide context fields:
- `tide_station_name`: Station name (null when unavailable)
- `tide_station_distance_km`: Distance to station (null when unavailable)
- `reference_tide_event_type`: "High" or "Low"
- `reference_tide_event_time`: DateTime of reference event
- `reference_tide_event_height`: Tide height in meters
- `reference_tide_event_relation`: "Before" or "After"
- `minutes_from_reference_tide_event`: Time delta in minutes
- `previous_tide_event_type`: Previous event type
- `previous_tide_event_time`: Previous event time
- `previous_tide_event_height`: Previous event height
- `next_tide_event_type`: Next event type
- `next_tide_event_time`: Next event time
- `next_tide_event_height`: Next event height
- `tide_context_phrase`: Human-readable phrase
- `tide_context_data_source`: "WorldTides"
- `tide_context_confidence`: "High"

## Manual Tide Rules

**Preserved Fields:**
- `tide_stage` - User-entered tide stage
- `tide_strength` - User-entered tide strength
- `tide_notes` - User-entered notes
- `tide_height` - User-entered height
- `tide_movement` - User-entered movement
- `tide_station` - User-entered station name

**Never Overwritten:**
- Manual tide observations are preserved during WorldTides context updates
- WorldTides only populates tide context fields (not manual fields)

## Caching Behaviour

**Cache Invalidation Conditions:**
WorldTides API is called only when:
1. No existing WorldTides context exists
2. Date/time changed by more than 1 hour
3. GPS coordinates changed by more than ~100 meters (0.001 degrees)

**Cache Valid:**
- Existing WorldTides context with same date/time and coordinates
- No API call made, existing context reused

## Environmental Backfill

**Backfill Process:**
1. Calculates moon, sun, and weather data
2. Preserves all manual tide observations
3. Fetches WorldTides context if:
   - API key is configured
   - No existing WorldTides context
   - GPS coordinates available
4. Merges WorldTides context with calculated data
5. Preserves manual data over calculated data

**Backfill Result:**
- Historical catches gain official tide context
- Manual observations remain intact
- Moon/sun/weather data populated

## UI Display

### Catch Details Screen

**Official Tide Context Card (Blue):**
- Shows when `tide_context_data_source == "WorldTides"`
- Displays tide context phrase
- Shows "WorldTides" label (top-right, smaller font)
- Example: "2 hr 51 min before the nearest high tide of 6.49 m at 9:24 am"

**No Context Card (Grey):**
- Shows when WorldTides context unavailable
- Displays "Tide context not available"

**Manual Tide Card (Orange):**
- Shows when user entered manual tide observations
- Preserved independently of WorldTides

### Add Catch Screen

**Placeholder:**
- Shows "Official Tide Context not available" placeholder
- Indicates tide context will be calculated after save
- No blocking API calls during form entry

## Credibility Validation

### Darwin Region Validation

**Bounds:** Latitude -13.0 to -11.0, Longitude 130.0 to 132.0

**Validation Rule:**
- High tide heights must be at least 4.0 meters
- If validation fails, tide context is rejected
- Returns "Tide context not available"

**Rationale:**
- Darwin has very high tides (typically 4-7m range)
- Low heights may indicate wrong datum or API issue
- Ensures data credibility before display

## Known Limitations

1. **Station Names Not Available**
   - WorldTides API does not return station information when using `extremes` with `datum=CD`
   - Including `stations` parameter causes `extremes: null`
   - Current workaround: Use "the nearest" wording in context phrase
   - Future: May need separate API call for station names

2. **Non-Blocking Save**
   - WorldTides API calls are non-blocking during catch save
   - Tide context may not appear immediately after save
   - User must navigate away and back to see updated context
   - Trade-off: Better UX vs immediate data availability

3. **API Rate Limits**
   - WorldTides has rate limits (free tier: ~1000 requests/day)
   - Caching reduces but does not eliminate API usage
   - Backfill can trigger many API calls
   - Recommendation: Monitor usage and consider paid tier if needed

4. **Darwin-Specific Validation**
   - Credibility validation only applies to Darwin region
   - Other locations accept any reasonable tide data
   - May need region-specific validation for other areas

## Future Enhancements

1. **Station Name Resolution**
   - Investigate alternative API patterns for station names
   - Consider separate station lookup API call
   - Cache station names by location

2. **Real-time Updates**
   - Add manual refresh button for tide context
   - Consider periodic background updates
   - Implement optimistic UI updates

3. **Offline Support**
   - Cache tide data for common locations
   - Implement offline fallback to cached data
   - Queue API calls for when connectivity returns

4. **Bite Window Analysis**
   - Group catches by tide time bands
   - Analyze catch success rates by tide phase
   - Identify optimal tide conditions for species
   - Provide bite window predictions

## Configuration

### API Key Setup

1. Open Settings screen
2. Navigate to WorldTides section
3. Enter API key
4. Test API connection
5. Save configuration

### API Key Storage
- Stored in SharedPreferences
- Encrypted on supported platforms
- Never logged or displayed in debug output

## Testing

### Test Scenarios

1. **New Catch with GPS**
   - Save catch with coordinates
   - Verify tide context appears in Catch Details
   - Check "WorldTides" label displayed

2. **Edit Catch**
   - Edit catch without changing coordinates/time
   - Verify existing tide context preserved (no API call)
   - Edit catch with new coordinates
   - Verify new tide context fetched

3. **Darwin Validation**
   - Save catch in Darwin region
   - Verify high tide heights >= 4m
   - Check context phrase credibility

4. **API Failure**
   - Disable network connection
   - Save catch with coordinates
   - Verify catch saves successfully
   - Check "Tide context not available" displayed

5. **Backfill**
   - Run environmental backfill
   - Verify historical catches gain tide context
   - Check manual observations preserved

## Summary

WorldTides integration is production-ready with:
- ✅ Official tide data from WorldTides API v3
- ✅ Credibility validation for Darwin region
- ✅ Non-blocking API calls during catch save
- ✅ Smart caching to reduce API usage
- ✅ Environmental backfill support
- ✅ Comprehensive error handling
- ✅ Manual tide observation preservation
- ⚠️ Station names not available (uses "the nearest" wording)
- ⚠️ Non-blocking save requires navigation refresh for immediate display
