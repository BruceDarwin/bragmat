# Tide Reference Location - Stage 2 Implementation Plan

## Objective
Allow users to choose a default tide reference that Bragmat will use for all new catches, regardless of where the catch occurs.

## Stage 2 Scope
- Initial options: Automatic (catch location) and Darwin (fixed reference)
- Design for future extensibility to additional fixed references
- No database migration required (Stage 1 v28 fields sufficient)

---

## 1. Settings Design

### Recommended Control: Radio Button Group
**Rationale:** Radio buttons provide clear visibility of the current selection and are ideal for small option sets (2-3 items). They're more discoverable than dropdowns and don't require navigating to a separate screen.

### Settings Layout
```
Settings Screen
├── Tide Reference Location
│   ├── ◉ Automatic (catch location)
│   └── ○ Darwin
```

### Alternative: Segmented Control
For a more modern UI, a segmented control (horizontal button group) could be used:
```
[ Automatic | Darwin ]
```

### Current Selection Visibility
- The selected option is visually indicated (filled radio button or highlighted segment)
- Do not repeat the selected value in the Settings section title to avoid redundancy

### Navigation Path
Settings → Tide Reference Location → Selection screen (if using separate screen)
OR
Settings → Tide Reference Location (inline radio buttons)

**Recommendation:** Inline radio buttons in Settings for simplicity and immediate visibility.

---

## 2. Darwin Reference Definition

### Coordinates
Using the actual WorldTides Darwin station coordinates returned by the API response:

**Display Name:** Darwin
**Latitude:** -12.4667
**Longitude:** 130.8500
**Expected WorldTides Source:** Darwin station

**Rationale:** These are the actual WorldTides Darwin station coordinates, more precisely representing the selected Darwin tide reference than general Darwin city center coordinates. They most reliably and consistently return Darwin station data.

### Storage Location
Store in a new service class `TideReferenceService` with predefined references:

```dart
class TideReferenceService {
  static const Map<String, TideReference> _predefinedReferences = {
    'darwin': TideReference(
      id: 'darwin',
      displayName: 'Darwin',
      latitude: -12.4667,
      longitude: 130.8500,
    ),
  };
}
```

---

## 3. Preference Storage

### Storage Approach: SharedPreferences
SharedPreferences is sufficient for the initial Darwin-only implementation. It provides:
- Simple key-value storage
- Persistence across app restarts
- Easy migration to more complex storage if needed

### Preference Keys
```dart
// Current mode
'tide_reference_mode' -> 'automatic' | 'fixed'

// For fixed mode
'tide_reference_id' -> 'darwin' | (future: other IDs)
```

### Future Extensibility Design
For multiple saved references, evolve to:
```dart
// Option 1: SharedPreferences with JSON
'tide_references' -> JSON array of TideReference objects
'tide_reference_default' -> reference ID

// Option 2: SQLite table (if many references)
CREATE TABLE tide_references (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  is_user_created INTEGER DEFAULT 0
)
```

**Recommendation:** Start with SharedPreferences, migrate to SQLite if >5 references or user-created references needed.

### Reference Data Structure
```dart
class TideReference {
  final String id;
  final String displayName;
  final double latitude;
  final double longitude;
  final bool isUserCreated;
}
```

---

## 4. Add Catch Behavior

### Automatic Mode (Current Stage 1 Behavior)
- **Tide-request coordinates:** Catch coordinates
- **tide_reference_mode:** `automatic`
- **tide_reference_name:** NULL
- **tide_request_lat/lon:** Catch coordinates
- **Display:** "Catch location"

### Darwin Mode (New Stage 2 Behavior)
- **Tide-request coordinates:** Darwin reference coordinates (-12.4634, 130.8456)
- **tide_reference_mode:** `fixed`
- **tide_reference_name:** "Darwin"
- **tide_request_lat/lon:** Darwin reference coordinates
- **Catch coordinates:** Stored separately in catch table (unchanged)
- **Display:** "Darwin"

### Cache Lookup Confirmation
**Cache lookup uses tide-request coordinates:**
- Automatic mode: Cache lookup uses catch coordinates
- Darwin mode: Cache lookup uses Darwin reference coordinates
- This allows geographically separate catches to share the same Darwin tide cache

### Implementation Location
Update `EnvironmentalConditionsService.saveEnvironmentalConditionForCatch()`:
```dart
final tideRef = await TideReferenceService.getCurrentReference();
final requestLat = tideRef.mode == 'automatic' 
  ? catchItem.latitude 
  : tideRef.latitude;
final requestLon = tideRef.mode == 'automatic' 
  ? catchItem.longitude 
  : tideRef.longitude;
```

---

## 5. Add Catch Screen Display

### Recommended Location
Display in the Environmental Conditions section, above the tide fields:

```
Environmental Conditions
├── Tide Reference: Automatic (catch location)
├── Tide Stage: [Dropdown]
├── Tide Movement: [Dropdown]
└── ...
```

### Display Wording
- Automatic: "Tide reference: Automatic (catch location)"
- Darwin: "Tide reference: Darwin"

### Tap Behavior (Initial Stage 2)
**Recommendation:** No tap-to-change in Add Catch screen initially. Changes made only through Settings to:
- Keep the Add Catch screen focused on catch entry
- Avoid UI complexity
- Establish clear separation between global settings and per-catch overrides

### Future Stage 3 Enhancement
- Tap to show reference selection dialog
- Allow per-catch override of global default
- Show distance for fixed references

---

## 6. Existing and Historical Catches

### Settings Change Behavior
**Changing the default reference in Settings must NOT alter existing catches.**
- Existing catches continue to display their originally recorded reference
- Historical catches with no recorded reference continue to display "Not recorded"
- No database updates triggered by settings change

### Edit Behavior Matrix

| Action | Tide Reference Behavior |
|--------|------------------------|
| Edit ordinary catch details (fish type, length, notes) | Preserve original tide reference and tide context |
| Change catch location (automatic mode) | **Warn** that stored tide information relates to previous location, offer to recalculate. Do not silently retain tide data that appears to relate to new location. If user declines, preserve existing data but treat as unchanged historical environmental data. |
| Change catch location (fixed Darwin mode) | No new tide data needed for same date (reference remains Darwin). Recalculate displayed distance from catch to Darwin. |
| Change catch date or time (any mode) | Tide-context phrase may no longer be valid. Offer to recalculate tide context using the catch's recorded reference and revised date/time. |
| Explicitly recalculate environmental data | **Prompt for reference choice** (see below) |
| Edit and save without recalculation | Preserve original tide reference and tide context |

### Location Change Warning (Automatic Mode)
When user changes catch location in automatic mode:
- Show dialog: "The stored tide information relates to the previous catch location. Do you want to recalculate tide data for the new location?"
- Options: "Recalculate" or "Keep existing data"
- If "Keep existing data": Preserve tide data but mark as historical (unchanged)

### Date/Time Change Behavior
When user changes catch date or time:
- Tide-context phrase may no longer be valid
- Offer to recalculate tide context using the catch's recorded reference
- Use same reference (automatic or fixed) with new date/time

### Recalculation Trigger
Add explicit "Recalculate Environmental Data" button in Edit Catch screen:
- When tapped, prompt for reference choice (see Explicit Recalculation section)
- Updates tide_reference_mode, tide_reference_name, tide_request_lat/lon based on choice
- Preserves catch coordinates

### Rationale
- Silent replacement of original reference would be confusing
- Explicit recalculation gives user control
- Distinguishes between metadata updates and full recalculation

### Explicit Recalculation Prompt
When user taps "Recalculate Environmental Data" on an existing catch:
- Show dialog: "Choose tide reference for recalculation:"
- Options:
  - "Use catch's recorded reference" (default selection)
  - "Use current default reference"
- Default selection is the catch's recorded reference to prevent silent changes
- Updates tide_reference_mode, tide_reference_name, tide_request_lat/lon based on choice
- Preserves catch coordinates

---

## 7. Distance Display

### Recommendation: Display Distance for Fixed References
**Format:** "Tide reference: Darwin — 128 km from catch"

### When to Display
- **Fixed reference mode:** Show distance
- **Automatic mode:** Do not show distance (reference = catch location)

### Calculation
Use existing `_calculateDistance()` method from DatabaseHelper:
```dart
final distanceKm = _calculateDistance(
  catchLat, catchLon,
  refLat, refLon
);
```

### Display Location
In Catch Details Tide Context card:
```
Tide Context
├── Tide reference: Darwin — 128 km from catch
├── WorldTides source: Darwin station
└── [tide context phrase]
```

### Formatting Rules
- **Under 10 km:** One decimal place (e.g., "5.2 km from catch")
- **10 km or more:** Nearest whole kilometre (e.g., "128 km from catch")
- **Very close to reference:** "at catch location" or omit distance entirely (e.g., <0.5 km)

---

## 8. WorldTides and Cache Behavior

### Cache Lookup Coordinates Confirmation
| Mode | Cache Lookup Coordinates | Tide-Request Coordinates |
|------|------------------------|-------------------------|
| Automatic | Catch coordinates | Catch coordinates |
| Darwin | Darwin reference coordinates | Darwin reference coordinates |

### Cache Reuse Scenario
**Two geographically separate catches using Darwin mode on same date:**
1. Catch A at Dundee Beach (-12.5, 130.5) on 2026-08-02
   - Cache lookup: Darwin coordinates (-12.4634, 130.8456)
   - Stores cache entry for Darwin coordinates
2. Catch B at Nightcliff (-12.4, 130.8) on 2026-08-02
   - Cache lookup: Darwin coordinates (-12.4634, 130.8456)
   - **Reuses cache entry from Catch A**
   - Tide-context phrase recalculated for Catch B's time

### Metadata Preservation
- Cached WorldTides station and atlas metadata preserved across cache reuse
- Each catch gets same station/atlas but different tide-context phrase (different times)

### Implementation
No changes needed to cache logic - already uses tide-request coordinates. Just ensure tide-request coordinates are set correctly based on reference mode.

---

## 9. Offline and API Failure Behavior

### Failure Scenarios

**Selected reference must still be recorded even when tide information cannot be retrieved.**

| Scenario | Behavior |
|----------|----------|
| Darwin selected, no cached data | API request attempted. If fails, save: tide_reference_mode=fixed, tide_reference_name=Darwin, tide_request_lat/lon=Darwin coords, worldtides_*=NULL |
| Device offline | Cache checked. If miss, save reference metadata with worldtides_*=NULL |
| API key missing/invalid | Save reference metadata with worldtides_*=NULL |
| API request fails (timeout, error) | Save reference metadata with worldtides_*=NULL |

### Display Behavior

**Darwin mode with API failure:**
- Tide reference: Darwin
- WorldTides source: Not recorded

**Automatic mode with API failure:**
- Tide reference: Catch location
- WorldTides source: Not recorded

**Important:** Do not show "Tide reference: Not recorded" for a new catch where Bragmat knows which reference it attempted to use.

### Graceful Degradation
- Catch save never fails due to tide data unavailability
- Selected reference is always recorded
- WorldTides metadata shows NULL when unavailable
- User can manually enter tide observations if needed
- Existing manual tide data preserved

### User Feedback
Show non-blocking notification:
- "Tide information unavailable. Catch saved without tide data."
- Allow catch save to proceed

### Implementation
Current error handling in `EnvironmentalConditionsService` already supports this:
```dart
try {
  tideContext = await _worldTidesService.getTideContextForLocation(...);
} catch (e) {
  debugPrint('WorldTides: Error fetching tide context: $e');
  // Continue without tide context - don't fail the catch save
}
```

---

## 10. Future Extensibility

### Design Principles
1. **Reference abstraction:** Use `TideReference` class for all references
2. **Mode-based logic:** Switch on mode (automatic/fixed) not reference name
3. **Preference isolation:** Store reference ID, not coordinates directly
4. **UI scalability:** Design selection UI to handle 5+ references

### Future Features Support

| Future Feature | Current Design Support |
|----------------|----------------------|
| Additional predefined references | ✓ Add to `_predefinedReferences` map |
| User-created reference locations | ✓ Add `isUserCreated` flag, SQLite storage |
| Select from map | ✓ Reference coordinates stored, can integrate map picker |
| Per-catch reference override (general) | Defer to Stage 3 |
| Per-catch reference override (recalculation) | ✓ Explicit recalculation prompt with reference choice |
| Reference groups/regions | ✓ Add category to `TideReference` class |

### Data Model Evolution
Stage 1 v28 fields are sufficient for Stage 2. Future stages may add:
- `tide_reference_distance_km` (pre-calculate for performance)
- `user_selected_reference_id` (for per-catch overrides)

---

## 11. Data Model Review

### Stage 1 v28 Fields Sufficiency
**Current fields are sufficient for Stage 2:**
- `tide_reference_mode` - Can store 'automatic' or 'fixed'
- `tide_reference_name` - Can store 'Darwin' or other reference names
- `tide_request_lat/lon` - Store tide-request coordinates (catch or reference)
- `worldtides_*` fields - Store API response metadata

### No Database Migration Required
Stage 2 can be implemented without schema changes:
- Preference stored in SharedPreferences (outside catch database)
- Each catch stores its actual reference metadata in existing v28 fields
- Historical catches with NULL values remain unchanged

### Storage Architecture
```
SharedPreferences (Global Default)
├── tide_reference_mode: 'automatic' | 'fixed'
└── tide_reference_id: 'darwin' | (future: other IDs)

Environmental Conditions Table (Per-Catch)
├── tide_reference_mode: 'automatic' | 'fixed'
├── tide_reference_name: 'Darwin' | NULL
├── tide_request_lat/lon: actual request coordinates
└── worldtides_*: API response metadata
```

### Future Migration Considerations
If per-catch reference overrides needed in Stage 3:
- Add `user_selected_reference_id` to environmental_conditions
- Migration: NULL for existing catches (use global default)
- UI: Allow override in Add/Edit Catch screen

---

## 12. Testing Plan

### Automated Tests

#### Unit Tests
1. **TideReferenceService tests**
   - Get current reference (automatic mode)
   - Get current reference (Darwin mode)
   - Get reference by ID
   - Distance calculation

2. **EnvironmentalConditionsService tests**
   - Save catch with automatic mode
   - Save catch with Darwin mode
   - Preserve reference on edit without recalculation
   - Update reference on explicit recalculation

3. **Cache behavior tests**
   - Cache lookup uses tide-request coordinates
   - Darwin mode cache reuse across locations
   - Automatic mode cache miss on location change

#### Integration Tests
1. **Settings integration**
   - Change setting to Darwin
   - Verify preference stored
   - Verify subsequent catches use Darwin

2. **End-to-end flow**
   - Create catch with automatic mode
   - Change setting to Darwin
   - Create catch with Darwin mode
   - Verify both catches display correct references

### Physical Device Tests (Moto G15)

#### Core Functionality
1. **Automatic mode at Nightcliff**
   - Create catch at Nightcliff
   - Verify: "Tide reference: Automatic (catch location)"
   - Verify: WorldTides source shows Nightcliff station

2. **Automatic mode at Dundee Beach**
   - Create catch at Dundee Beach
   - Verify: "Tide reference: Automatic (catch location)"
   - Verify: WorldTides source shows FES2022 model

3. **Darwin mode for catch at Dundee Beach**
   - Set reference to Darwin in Settings
   - Create catch at Dundee Beach
   - Verify: "Tide reference: Darwin"
   - Verify: WorldTides source shows Darwin station
   - Verify: Distance displayed (e.g., "128 km from catch")

4. **Darwin mode for catch in remote location**
   - Set reference to Darwin
   - Create catch at remote location (e.g., 500km away)
   - Verify: "Tide reference: Darwin"
   - Verify: WorldTides source shows Darwin station
   - Verify: Distance displayed

5. **Cache reuse between geographically separate catches**
   - Set reference to Darwin
   - Create catch A at Dundee Beach on date X
   - Create catch B at Nightcliff on same date X
   - Verify: Both use same Darwin tide cache
   - Verify: No additional API credit consumed
   - Verify: Different tide-context phrases (different times)

#### Settings and Edit Behavior
6. **Change setting without affecting existing catches**
   - Create catch with automatic mode
   - Change setting to Darwin
   - Verify: Original catch still shows "Automatic (catch location)"
   - Create new catch
   - Verify: New catch shows "Darwin"

7. **Edit catch after setting change**
   - Create catch with automatic mode
   - Change setting to Darwin
   - Edit catch (change fish type only)
   - Verify: Reference still shows "Automatic (catch location)"

8. **Explicit recalculation**
   - Create catch with automatic mode
   - Change setting to Darwin
   - Edit catch, tap "Recalculate Environmental Data"
   - Verify: Reference updates to "Darwin"

#### Failure Scenarios
9. **Offline behavior**
   - Set reference to Darwin
   - Enable airplane mode
   - Create catch
   - Verify: Catch saves successfully
   - Verify: Tide reference shows "Darwin"
   - Verify: WorldTides source shows "Not recorded"

10. **API failure behavior**
    - Temporarily invalidate API key
    - Create catch with Darwin mode
    - Verify: Catch saves successfully
    - Verify: Tide reference shows "Darwin"
    - Verify: WorldTides source shows "Not recorded"

#### Migration and Compatibility
11. **Stage 1 record compatibility**
    - Open historical catch from Stage 1
    - Verify: Displays "Not recorded" for reference
    - Verify: Displays existing tide-context phrase
    - Verify: No data corruption

12. **Settings persistence**
    - Set reference to Darwin
    - Close and reopen app
    - Verify: Setting persists

---

## 13. Staged Implementation Sequence

### Phase 1: Core Infrastructure
1. Create `TideReferenceService` with predefined references
2. Implement SharedPreferences storage for reference selection
3. Add `TideReference` data model

### Phase 2: Settings UI
1. Add "Tide Reference Location" section to Settings screen
2. Implement radio button group for selection
3. Connect to `TideReferenceService`
4. Add preference persistence

### Phase 3: Add Catch Integration
1. Update `EnvironmentalConditionsService` to use current reference
2. Modify tide-request coordinate logic based on mode
3. Add tide reference display to Add Catch screen
4. Test automatic and Darwin modes

### Phase 4: Catch Details Display
1. Update Catch Details Tide Context card
2. Add distance calculation for fixed references
3. Format display with distance when applicable
4. Test display formatting

### Phase 5: Edit Behavior
1. Implement edit without recalculation (preserve reference)
2. Add "Recalculate Environmental Data" button
3. Implement recalculation with current default
4. Test edit scenarios

### Phase 6: Cache Verification
1. Verify cache lookup uses tide-request coordinates
2. Test cache reuse across locations with Darwin mode
3. Verify metadata preservation
4. Add cache behavior tests

### Phase 7: Error Handling
1. Verify offline behavior
2. Verify API failure behavior
3. Add user feedback for failures
4. Test failure scenarios

### Phase 8: Testing and Documentation
1. Run automated test suite
2. Execute physical device test plan
3. Update documentation
4. Prepare Stage 2 completion summary

---

## 14. Decisions Requiring Approval

### 1. Darwin Reference Coordinates ✓ APPROVED
**Decision:** Use actual WorldTides Darwin station coordinates
**Coordinates:** -12.4667, 130.8500
**Rationale:** These are the actual WorldTides Darwin station coordinates returned by the API response, more precisely representing the selected Darwin tide reference than general Darwin city center coordinates. They most reliably and consistently return Darwin station data.

### 2. Settings UI Control Type ✓ APPROVED
**Decision:** Radio button group (inline in Settings)
**Requirement:** Do not repeat the selected value in the Settings section title to avoid redundancy

### 3. Distance Display ✓ APPROVED
**Decision:** Show distance for fixed references only
**Format:** "Tide reference: Darwin — 128 km from catch"
**Formatting rules:**
- Under 10 km: One decimal place (e.g., "5.2 km from catch")
- 10 km or more: Nearest whole kilometre (e.g., "128 km from catch")
- Very close to reference: "at catch location" or omit distance entirely (<0.5 km)

### 4. Edit Behavior ✓ APPROVED
**Decision:**
- Ordinary edits (fish type, length, notes): Preserve original tide reference and tide context
- Location change (automatic mode): Warn that stored tide information relates to previous location, offer to recalculate. Do not silently retain tide data. If user declines, preserve existing data but treat as unchanged historical environmental data.
- Location change (fixed Darwin mode): No new tide data needed for same date. Recalculate displayed distance from catch to Darwin.
- Date/time change (any mode): Offer to recalculate tide context using catch's recorded reference and revised date/time.
- Explicit recalculation: Prompt for reference choice (see below)

### 5. Explicit Recalculation ✓ APPROVED
**Decision:** Do not automatically replace existing catch's recorded reference with current global default without confirmation.
**Prompt:** When recalculating an existing catch, offer:
- "Use catch's recorded reference" (default selection)
- "Use current default reference"
**Rationale:** Prevents existing catches from being silently changed by later Settings preference changes.

### 6. Per-Catch Override ✓ APPROVED
**Decision:** Defer general per-catch overrides to Stage 3.
**Exception:** Explicit recalculation choice required in Stage 2 to prevent silent changes.
**Rationale:** Explicit recalculation prompt with reference choice provides necessary control without full per-catch override UI.

### 7. Offline/API Failure Behavior ✓ APPROVED
**Decision:** Selected reference must still be recorded even when tide information cannot be retrieved.
**Display:**
- Darwin mode with API failure: "Tide reference: Darwin", "WorldTides source: Not recorded"
- Automatic mode with API failure: "Tide reference: Catch location", "WorldTides source: Not recorded"
**Important:** Do not show "Tide reference: Not recorded" for a new catch where Bragmat knows which reference it attempted to use.

---

## 15. Risk Assessment

### Low Risk
- Settings UI implementation (standard Flutter widgets)
- SharedPreferences storage (well-tested)
- Distance calculation (existing method available)

### Medium Risk
- Cache behavior verification (needs thorough testing)
- Edit behavior complexity (multiple scenarios)
- Offline/API failure handling (edge cases)

### Mitigation
- Comprehensive test plan for cache and edit behavior
- Explicit recalculation button to avoid confusion
- Graceful degradation with clear user feedback

---

## 16. Success Criteria

Stage 2 is successful when:
1. User can select Automatic or Darwin in Settings
2. New catches use selected reference correctly
3. Tide reference displays correctly in Add Catch and Catch Details
4. Distance displays for Darwin mode
5. Existing catches unaffected by settings changes
6. Edit behavior preserves reference unless explicitly recalculated
7. Cache reuse works across locations with Darwin mode
8. Offline/API failures handled gracefully
9. All automated and physical device tests pass
10. Stage 1 records remain compatible
