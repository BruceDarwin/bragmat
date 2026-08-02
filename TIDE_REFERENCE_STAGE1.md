# Tide Reference Location - Stage 1 Implementation

## Overview
Stage 1 implements automatic tide reference location with WorldTides API integration, including database migration, caching, and UI display of tide context with source information.

## Implementation Date
2026-08-02

## Database Migration (v27 → v28)

### New Columns in `environmental_conditions`
- `tide_reference_mode` TEXT - Mode: 'automatic' or 'manual'
- `tide_reference_name` TEXT - Name of reference (NULL for automatic mode)
- `tide_request_lat` REAL - Latitude used for tide request
- `tide_request_lon` REAL - Longitude used for tide request
- `worldtides_station` TEXT - WorldTides station name (if available)
- `worldtides_atlas` TEXT - WorldTides atlas/model (e.g., 'FES2022', 'Australia')
- `worldtides_response_lat` REAL - WorldTides response latitude
- `worldtides_response_lon` REAL - WorldTides response longitude

### Existing Table: `tide_cache` (v27)
- Stores WorldTides API responses with metadata
- Distance-based matching (within 2km)
- 7-day expiry
- v28 added metadata columns: worldtides_station, worldtides_atlas, worldtides_response_lat, worldtides_response_lon

## WorldTides Service Integration

### API Response Handling
- Parses station name from `station` field (named stations)
- Parses atlas/model from `atlas` field (global model FES2022)
- Parses response coordinates from `responseLat`/`responseLon`
- Cache reconstruction: converts cached `worldtides_*` fields to expected API format

### Cache Logic
- Key: latitude, longitude, date, datum
- Matching: distance-based within 2km
- Expiry: 7 days from cache time
- Metadata preservation: station, atlas, response coordinates

## Environmental Conditions Service

### Automatic Mode (Stage 1)
- Always uses automatic mode with catch coordinates
- `tide_reference_mode` = 'automatic'
- `tide_reference_name` = NULL
- `tide_request_lat`/`tide_request_lon` = catch coordinates
- WorldTides metadata populated from API or cache

### Historical Catch Updates
- When updating historical catches, WorldTides context is fetched if available
- Existing manual tide data is preserved
- WorldTides metadata is added to environmental record

## UI Display

### Catch Details Screen
- Tide Context card shows:
  - Tide context phrase
  - Tide reference mode (automatic)
  - WorldTides source (station name or atlas/model)
  - "Not recorded" if no WorldTides data available

### Tide Context Helper
- Uses actual station name when available
- Falls back to "the nearest" for generic references
- Preserves historical phrase format

## Testing Results

### Physical Device Testing (Moto G15)
- **Current location (Nightcliff):** Nightcliff station ✓
- **Darwin Harbour:** Darwin station ✓
- **Dundee Beach:** FES2022 model ✓ (after cache fix)
- **Historical catch update:** Point Stuart station ✓
- **Cache test:** Second catch used cache, no API call, same metadata, recalculated context ✓

### Automated Tests
- Database migration test (v27 → v28) ✓
- Cache integration test ✓
- Tide reference test ✓

## Known Issues

### Camera Workflow (Intermittent)
- Single occurrence of unexpected navigation after camera launch
- Photo recovered via lost data handling
- Could not reproduce
- Documented in KNOWN_ISSUES.md

### Dundee Beach Cache Metadata (Resolved)
- Cache metadata not reconstructed correctly
- Fixed by adding reconstruction logic in WorldTidesService
- Now displays FES2022 model correctly

## Residual Risks

1. **Camera workflow issue:** Intermittent, not reproducible. Monitor for recurrence.
2. **WorldTides API availability:** Service may be unavailable or rate-limited. Graceful degradation in place.
3. **Historical data:** Large backfill operations may be slow. Consider batch processing for future Stage 2.

## Next Steps (Stage 2)
- Manual tide reference mode (user-selectable stations)
- Tide reference management UI
- Advanced cache management
- Performance optimization for bulk operations
