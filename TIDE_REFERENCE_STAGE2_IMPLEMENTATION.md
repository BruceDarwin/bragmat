# Stage 2 Tide Reference Implementation Summary

## Overview
Stage 2 implementation for user-selected tide reference locations has been completed. This feature allows users to choose between automatic mode (using catch location coordinates) and fixed references (e.g., Darwin) for tide data requests.

## Implementation Date
August 2026

## Components Implemented

### 1. Core Infrastructure (Phase 1)
- **TideReference Model** (`lib/models/tide_reference.dart`)
  - Data model for tide reference locations
  - Supports automatic and fixed reference modes
  - Includes coordinate storage and display name

- **TideReferenceService** (`lib/services/tide_reference_service.dart`)
  - Manages user-selected tide reference preferences
  - SharedPreferences storage for mode and reference ID
  - Predefined references (Darwin with actual WorldTides station coordinates: -12.4667, 130.8500)
  - Helper methods for mode checking and reference retrieval

### 2. Settings UI (Phase 2)
- **Settings Screen** (`lib/screens/settings_screen.dart`)
  - Added "Tide Reference Location" section
  - Inline radio buttons for Automatic and Darwin modes
  - Real-time preference updates
  - No redundant display in section title

### 3. Environmental Conditions Integration (Phase 3)
- **EnvironmentalConditionsService** (`lib/services/environmental_conditions_service.dart`)
  - Updated `upsertCalculatedConditionsForCatch` to use current tide reference
  - Tide-request coordinates determined by reference mode:
    - Automatic: Uses catch location coordinates
    - Fixed: Uses reference location coordinates (e.g., Darwin)
  - Records reference mode and name in environmental condition records

- **Add Catch Screen** (`lib/screens/add_catch_screen.dart`)
  - Added tide reference display in Environmental Conditions section
  - Shows current reference mode and name
  - FutureBuilder for dynamic reference loading

### 4. Catch Details Display (Phase 4)
- **Catch Details Screen** (`lib/screens/catch_details_screen.dart`)
  - Updated Tide Context card to display reference information
  - Distance calculation for fixed references using Haversine formula
  - Distance formatting rules:
    - Under 0.5 km: omit distance display
    - Under 10 km: one decimal place (e.g., "5.3 km from catch")
    - 10 km or more: nearest whole kilometre (e.g., "12 km from catch")
  - Added `_calculateDistance` and `_degreesToRadians` helper methods

### 5. Edit and Recalculation (Phase 5)
- **EnvironmentalConditionsService**
  - Added `recalculateEnvironmentalConditionForCatch` method
  - Supports explicit reference choice (recorded vs. current default)
  - Preserves manual data during recalculation
  - Updates reference mode and coordinates

- **Add Catch Screen**
  - Added "Recalculate Environmental Data" button (Edit mode only)
  - Dialog with reference choice prompt
  - Shows current recorded reference and default reference
  - Defaults to recorded reference per Stage 2 plan

### 6. Cache Behavior (Phase 6)
- **WorldTidesService** (`lib/services/worldtides_service.dart`)
  - Cache lookup uses tide-request coordinates (not catch coordinates)
  - Enables cache reuse across locations when using fixed reference mode
  - Darwin mode: All catches share same cache entry for given date
  - Automatic mode: Cache entries per catch location

### 7. Offline and API Failure (Phase 7)
- **EnvironmentalConditionsService**
  - Always records selected tide reference even if tide data unavailable
  - Graceful degradation on API failures
  - WorldTides source displays as "Not recorded" when unavailable
  - Catch save continues without failing

## Data Model Changes

### Environmental Condition Fields (v28 - already existed)
- `tideReferenceMode`: 'automatic' or 'fixed'
- `tideReferenceName`: Reference display name (NULL for automatic)
- `tideRequestLat`: Latitude used for tide request
- `tideRequestLon`: Longitude used for tide request
- `worldtidesStation`: WorldTides station name
- `worldtidesAtlas`: WorldTides atlas/model name
- `worldtidesResponseLat`: API response latitude
- `worldtidesResponseLon`: API response longitude

No new database migration required - all fields existed from Stage 1.

## Key Design Decisions

1. **Reference Preservation**: Ordinary edits preserve the original tide reference without recalculation
2. **Explicit Recalculation**: Recalculation requires user action with reference choice prompt
3. **Default to Recorded**: Recalculation dialog defaults to using the catch's recorded reference
4. **Cache Efficiency**: Fixed reference mode enables cache reuse across locations
5. **Graceful Degradation**: Offline/API failures record reference but show "Not recorded" for source
6. **Distance Display**: Only shown for fixed references, with formatting rules per plan
7. **Extensibility**: Architecture supports adding more fixed references in Stage 3

## Testing Recommendations

### Automated Tests (Unit Tests Only)
- **Unit tests for TideReferenceService methods** (8 tests)
- **Unit tests for TideReference model** (3 tests)
- **Unit tests for distance calculation** (4 tests)
- **Unit tests for EnvironmentalCondition with Stage 2 fields** (4 tests)
- **Unit tests for display logic** (6 tests)
- **Unit tests for WorldTides parsing** (2 tests)
- **Unit tests for tide context phrase generation** (3 tests)
- **Total**: 31 unit tests passing

**Note**: No widget tests or integration tests exist. The following UI interactions require manual physical-device testing:
- Recalculate, Keep existing information, and Cancel save-prompt outcomes
- Combined location/date-time prompt behavior
- Selection between recorded reference and current default in recalculation dialog
- Radio button interactivity and state management
- Dialog appearance and dismissal behavior

### Physical Device Tests (Manual)
1. **Settings UI**
   - Verify radio button selection works
   - Verify preference persistence across app restarts

2. **Add Catch - Automatic Mode**
   - Create catch with coordinates
   - Verify tide-request coordinates match catch location
   - Verify reference display shows "Automatic"

3. **Add Catch - Darwin Mode**
   - Set Darwin as default reference
   - Create catch at different location
   - Verify tide-request coordinates match Darwin
   - Verify reference display shows "Darwin"
   - Verify distance calculation and formatting

4. **Catch Details Display**
   - Verify tide reference display for both modes
   - Verify distance display for Darwin mode
   - Verify WorldTides source display

5. **Edit Without Recalculation**
   - Edit catch without changing location/date
   - Verify original reference preserved
   - Verify no API call made

6. **Recalculation**
   - Use recalculation button
   - Verify reference choice dialog appears
   - Verify recorded reference is default
   - Verify recalculation updates data correctly

7. **Cache Behavior**
   - Create multiple catches with Darwin mode on same date
   - Verify only one API call made (cache reuse)
   - Verify automatic mode creates separate cache entries

8. **Offline/API Failure**
   - Disable network or remove API key
   - Create catch with coordinates
   - Verify reference is recorded
   - Verify WorldTides source shows "Not recorded"
   - Verify catch save succeeds

## Physical Device Test Results (Moto G15)

### Test Date
August 2, 2026

### Tests Performed
All physical-device tests passed successfully:

1. **Time Change → Cancel**
   - Changed catch time, pressed Save
   - Prompt appeared with "Recalculate", "Keep existing information", "Cancel" options
   - Cancel returned to edit screen without saving

2. **Time Change → Keep existing information**
   - Changed catch time, pressed Save
   - Prompt appeared
   - "Keep existing information" preserved original environmental data
   - Catch saved successfully

3. **Time Change → Recalculate**
   - Changed catch time, pressed Save
   - Prompt appeared
   - "Recalculate" fetched new tide data
   - Environmental data updated successfully

4. **Automatic-Mode Location Change**
   - Changed catch coordinates (automatic mode)
   - Prompt appeared with location-specific message
   - "The catch location has changed. The existing tide information relates to the previous location. Would you like to recalculate it for the new location?"
   - All three options (Recalculate, Keep existing, Cancel) worked correctly

5. **Fixed-Mode Location Change**
   - Changed catch coordinates (Darwin fixed mode)
   - No prompt appeared (correct behavior)
   - Distance display updated automatically
   - Darwin tide reference remained unchanged

6. **Explicit Recalculation Using Recorded Reference**
   - Clicked recalculation button (autorenew icon in app bar)
   - Dialog appeared with reference choice
   - Recorded reference selected by default
   - Radio buttons were selectable and functional
   - Recalculation used recorded reference correctly

7. **Explicit Recalculation Using Current Default Reference**
   - Changed default reference in Settings
   - Clicked recalculation button
   - Dialog showed both recorded and current default references
   - Selected current default reference
   - Recalculation used current default correctly

8. **Historical Catch (No tideReferenceMode)**
   - Edited catch created before Stage 2
   - Location change triggered prompt (correct behavior)
   - Date/time change triggered prompt (correct behavior)
   - Recalculation used current default reference

### Additional Corrections During Testing
- Removed 0.001 degree (~100m) behavioral threshold
- Changed to floating-point comparison tolerance (1e-9) only
- Extended prompt to historical catches (no tideReferenceMode)
- Confirmed date/time prompt works for both automatic and fixed modes
- Confirmed fixed-mode location changes do not trigger prompt

## Stage 2 Acceptance Status

**Status**: FULLY ACCEPTED ✓

**Acceptance Date**: August 2, 2026

**Acceptance Criteria Met**:
- All automated tests passing (38/38)
- No new analysis issues (151 issues, baseline unchanged)
- Physical-device tests passed on Moto G15
- Prompt and recalculation workflows manually verified
- UI interactions working as designed
- Reference preservation behavior confirmed
- Historical catch support verified

**Final Release APK**:
- Version: 1.0.0+3
- Location: `build\app\outputs\flutter-apk\app-release.apk`
- Size: 56.7MB

**Note**: Stage 3 implementation deferred until user provides next requirements.
- Add more fixed references (e.g., other tide stations)
- Per-catch reference override (deferred from Stage 2)
- Custom user-defined reference locations
- Reference location management UI

## Files Modified
1. `lib/models/tide_reference.dart` - Created
2. `lib/services/tide_reference_service.dart` - Created
3. `lib/screens/settings_screen.dart` - Modified
4. `lib/services/environmental_conditions_service.dart` - Modified
5. `lib/screens/add_catch_screen.dart` - Modified
6. `lib/screens/catch_details_screen.dart` - Modified

## Backward Compatibility
- Stage 1 historical records remain unchanged
- No database migration required
- Existing catches without reference data default to automatic mode
- Manual tide observations preserved across all operations
