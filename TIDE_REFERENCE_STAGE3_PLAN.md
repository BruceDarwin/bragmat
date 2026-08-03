# Stage 3 Plan: Per-Catch Tide Reference Selection

## Objective
Allow the user to override the default tide reference for an individual catch. The Settings value remains the default for new catches, but users can select a different reference while adding or editing a catch.

## Planning Date
August 2, 2026

## Initial Available References
- Automatic — use the catch location
- Darwin — use the predefined Darwin reference coordinates

## Architecture Requirements
- Continue to support additional predefined or user-created references in the future
- No database migration unless genuinely necessary
- Maintain backward compatibility with Stage 2

---

## 1. Add Catch User Experience

### Recommended Control: Dropdown
**Rationale**: 
- Compact and consistent with existing Bragmat design (fish type, lure, bait, etc. all use dropdowns)
- Minimal screen space usage
- Familiar interaction pattern
- Easy to extend with future references

### Label and Options
**Label**: "Tide Reference"

**Initial Options**:
- Automatic (catch location)
- Darwin

### Default Behavior
- When Add Catch opens, load the default reference from Settings
- Use that reference as the initial selection
- Allow user to change it for this catch
- Do not update Settings when user changes per-catch selection
- Show the effective tide reference clearly before saving

### Automatic Mode Without Coordinates
If Automatic is selected and valid catch coordinates are not available:
- Explain that the catch can be saved but automatic tide information cannot be retrieved until a location is provided
- Allow save with reference recorded but tide data unavailable

### UI Placement
- Located in Environmental Conditions section of Add Catch screen
- Appears above the tide context display
- Consistent styling with other dropdown controls

---

## 2. Default and Override Behavior

### New Catch
1. Load default reference from Settings (`TideReferenceService.getCurrentReference()`)
2. Set as initial selection in dropdown
3. User can override for this catch
4. When saved, store the selected reference in environmental condition record
5. Settings preference remains unchanged

### Edit Catch
1. Load the catch's recorded reference from environmental condition
2. Display that reference in dropdown (not the current Settings default)
3. Changing global Settings does not alter selection shown for existing catch
4. User can change the catch's recorded reference
5. Changing reference requires recalculation (see Section 5)

---

## 3. Edit Catch Behavior - Reference Change Confirmation

### Trigger
Reference change detected when:
- User selects different reference in dropdown
- AND presses Save

### Confirmation Wording
**Title**: "Tide Reference Changed"

**Message**: "The tide reference has changed. Tide information must be recalculated using the new reference."

**Options**:
- "Recalculate and save"
- "Revert to recorded reference"
- "Cancel"

### Behavior
- **Recalculate and save**: Use the newly selected reference and save the recalculated result
- **Revert to recorded reference**: Restore the dropdown to the recorded reference, preserve the existing tide information and continue saving any unrelated edits
- **Cancel**: Return to the edit screen without saving

### Invariant
Never save a newly selected reference with tide information calculated from the previous reference.

---

## 4. Interaction with Location, Date and Time Changes

### Consolidated Prompt Strategy
Show one consolidated prompt when multiple relevant changes occur, rather than multiple sequential prompts.

### Change Detection Matrix

| Change Type | Automatic Mode | Fixed Mode (Darwin) | Historical (No Reference) |
|-------------|----------------|-------------------|---------------------------|
| Location change | Optional recalculation | No prompt (distance updates) | Optional recalculation |
| Date/time change | Optional recalculation | Optional recalculation | Optional recalculation |
| Reference change | Mandatory recalculation | Mandatory recalculation | Mandatory recalculation |
| Multiple changes | Consolidated prompt | Consolidated prompt | Consolidated prompt |

### Consolidated Prompt Logic

#### Case 1: Reference Changed (Mandatory)
**Always show prompt regardless of other changes**

**Message**: "The tide reference has changed. Tide information must be recalculated using the new reference."

**Options**:
- "Recalculate and save"
- "Revert to recorded reference"
- "Cancel"

**Precedence**: Reference change takes precedence over location/date/time changes. Show one consolidated prompt. Do not show mandatory reference-change prompt followed by second optional prompt.

#### Case 2: Location Changed (Automatic/Historical) + Date/Time Changed
**Show consolidated prompt**

**Message**: "The catch location and date/time have changed. The existing environmental information relates to the previous catch details. Would you like to recalculate it?"

**Options**:
- "Recalculate"
- "Keep existing information"
- "Cancel"

#### Case 3: Location Changed (Automatic/Historical) Only
**Show prompt**

**Message**: "The catch location has changed. The existing tide information relates to the previous location. Would you like to recalculate it for the new location?"

**Options**:
- "Recalculate"
- "Keep existing information"
- "Cancel"

#### Case 4: Date/Time Changed Only
**Show prompt**

**Message**: "The catch date or time has changed. Would you like to recalculate the environmental information?"

**Options**:
- "Recalculate"
- "Keep existing information"
- "Cancel"

#### Case 5: Location Changed (Fixed Mode) Only
**No prompt** - distance display updates automatically

#### Case 6: No Changes
**No prompt** - normal save

### Recalculation Rules

**Mandatory Recalculation**:
- Reference change (any mode)
- Cannot be skipped

**Optional Recalculation**:
- Location change (automatic/historical mode)
- Date/time change (any mode)
- User can choose to preserve existing data

**No Recalculation**:
- Location change (fixed mode only)
- Distance display updates automatically

### User Cancellation
- Returns to edit screen without saving
- All changes preserved in UI
- No data written to database

### Preserve Existing Data
- User chooses "Keep existing information" or "Keep existing reference"
- Environmental condition record not updated
- Catch saved with original tide data
- Reference unchanged (for reference change case)

---

## 5. Mandatory Recalculation When Reference Changes

### Invariant
A tide-reference change must not be saved while retaining tide information from the previous reference.

### Enforcement
When reference changes:
1. Detect change in `_saveCatch` before saving
2. Show mandatory recalculation prompt
3. User must choose:
   - **Recalculate and save**: Update reference, fetch new tide data, save
   - **Keep existing reference**: Revert dropdown to recorded reference, save with original
   - **Cancel**: Return to edit screen

### No "Keep Existing Tide Information" Option
- Do not offer "Keep existing tide information" while retaining newly selected reference
- This would violate the invariant
- User must either recalculate or revert to original reference

### Implementation
```dart
// In _saveCatch
if (referenceChanged) {
  // Mandatory recalculation - no option to preserve old data with new reference
  final result = await _showReferenceChangePrompt();
  if (result == 'recalculate') {
    // Recalculate with new reference
  } else if (result == 'keep') {
    // Revert to recorded reference
  } else {
    // Cancel
    return;
  }
}
```

---

## 6. New Catches Without Tide Data

### API Failure or Offline Mode

#### New Catch
If user selects a reference but tide data cannot be retrieved:

1. **Save the selected reference** in environmental condition record
2. **Save tide-request coordinates** based on selected reference
3. **Leave WorldTides fields NULL**:
   - `worldtidesStation` = NULL
   - `worldtidesAtlas` = NULL
   - `worldtidesResponseLat` = NULL
   - `worldtidesResponseLon` = NULL
4. **Show selected tide reference** in UI
5. **Show WorldTides source**: "Not recorded"
6. **Display non-blocking notification**: "Catch saved without tide data"

#### Existing Catch with Valid Tide Data
If recalculation after a reference change fails:

Do not automatically overwrite the existing tide data.

**Prompt**: "Tide information could not be retrieved for the new reference."

**Options**:
- "Save without tide information"
- "Revert to recorded reference"
- "Cancel"

**Behavior**:
- **Save without tide information**: Save the newly selected reference and clear only the tide result fields that no longer apply
- **Revert to recorded reference**: Restore the previous reference and preserve the previous tide information
- **Cancel**: Return to editing without saving

### Notification Design
- SnackBar at bottom of screen
- Auto-dismiss after 5 seconds
- Non-blocking (user can continue)
- Message: "Catch saved without tide data. Tide information unavailable."

### Graceful Degradation
- Catch save succeeds
- Reference is recorded
- Other environmental data (moon/sun) still calculated if coordinates available
- User can recalculate later via explicit recalculation button

---

## 7. Historical Catches

### Initial Display
For historical catches with no recorded reference (`tideReferenceMode` = NULL or empty):

- Display "Not recorded" in tide reference dropdown
- Do not silently substitute the current Settings default in the dropdown
- Allow user to select Automatic or Darwin
- Require recalculation before newly selected reference is saved
- Current default may be suggested, but must be clear it was not the catch's recorded reference

### Reference Selection Prompt
When user selects a reference for historical catch:

**Message**: "No tide reference was recorded for this catch. Would you like to set a reference and recalculate the environmental information?"

**Options**:
- "Set reference and recalculate"
- "Cancel"

### Cancellation
- Revert dropdown to "Not recorded"
- Preserve existing historical tide context
- No changes to database

### Explicit Recalculation Behavior
When no recorded reference exists:

1. User clicks "Recalculate Environmental Data" button
2. Dialog shows:
   - "No reference recorded for this catch"
   - "Choose reference for recalculation:"
   - Radio buttons: Automatic (catch location), Darwin (current default)
   - Default to current default from Settings
3. User selects reference
4. Recalculate with selected reference
5. Save new reference in environmental condition

---

## 8. Settings Relationship

### Settings Scope
Settings defines only the default for future catches.

### Invariants
1. **Per-catch reference change does not update Settings**
   - Changing reference for a catch only affects that catch
   - Settings preference remains unchanged

2. **Settings change does not update existing catches**
   - Changing default in Settings affects only new catches
   - Existing catches retain their recorded references

3. **Recalculate Environmental Data dialog behavior**
   - Always offers recorded reference (if exists)
   - Always offers current default from Settings
   - Suppress redundant options when both resolve to same reference

### Implementation
```dart
// Recalculate dialog logic
final recordedReference = existing?.tideReferenceMode;
final currentDefault = await TideReferenceService.getCurrentReference();

final optionsAreSame = (recordedReference == 'automatic' && 
                       TideReferenceService.isAutomatic(currentDefault)) ||
                      (recordedReference == currentDefault.id);

if (optionsAreSame) {
  // Show single option: "Both options are the same: [reference name]"
} else {
  // Show radio buttons for both options
}
```

---

## 9. Distance Display

### Display Rules
- **Show distance only for fixed references**
- **Do not show distance for Automatic mode**

### Examples
- Automatic: "Tide reference: Catch location"
- Darwin: "Tide reference: Darwin — 128 km from catch"

### Real-time Updates
- Distance must update immediately when catch location changes
- Update in `_onFieldChanged` or location controller listener
- Calculate distance before saving if practical

### Distance Display Rules
- **Fixed references**: Calculate distance from edited catch coordinates to fixed reference, update when coordinates change, omit when catch coordinates unavailable
- **Automatic mode**: Do not display distance

### Implementation
```dart
// In _buildEnvironmentalConditionsSection
if (selectedReference != null && !TideReferenceService.isAutomatic(selectedReference)) {
  final distance = _calculateDistance(catchLat, catchLon, selectedReference);
  final distanceText = _formatDistance(distance);
  displayText = "$selectedReference.displayName — $distanceText from catch";
} else {
  displayText = "Tide reference: Catch location";
}
```

---

## 10. Cache Behavior

### Cache Lookup Coordinates
- **Automatic**: Uses catch coordinates for cache lookup
- **Darwin**: Uses fixed Darwin coordinates for cache lookup
- **Per-catch reference change**: Changes tide-request coordinates

### Cache Reuse
- Cached tide events can be reused across catches using:
  - Same fixed reference (e.g., Darwin)
  - Same date
- Automatic mode creates separate cache entries per catch location

### Tide Context Phrase
- Recalculated for catch date and time
- Not cached independently
- Generated from WorldTides response

### Stale Cache Prevention
- No stale cache metadata from previous reference retained
- Cache lookup uses current tide-request coordinates
- Reference change triggers new cache lookup

### Implementation
```dart
// In WorldTidesService.getTideEvents
final cacheKey = '${tideRequestLat}_${tideRequestLon}_${dateKey}';
// tideRequestLat/Lon determined by reference mode, not catch coordinates
```

---

## 11. Data Model

### Existing Version 28 Fields
The following fields already exist and remain sufficient:

- `tideReferenceMode`: 'automatic' or 'fixed' (or reference ID for extensibility)
- `tideReferenceName`: Reference display name (NULL for automatic)
- `tideRequestLat`: Latitude used for tide request
- `tideRequestLon`: Longitude used for tide request
- `worldtidesStation`: WorldTides station name
- `worldtidesAtlas`: WorldTides atlas/model name
- `worldtidesResponseLat`: API response latitude
- `worldtidesResponseLon`: API response longitude

### No Database Migration Required
- All required fields exist from Stage 1/2
- No schema changes needed
- Backward compatible with historical data

### Temporary UI State
Add to `_AddCatchScreenState`:

```dart
TideReference? _selectedTideReference;       // Currently selected in dropdown
TideReference? _recordedTideReference;       // Original reference for edit
TideReference? _settingsDefaultReference;    // Current Settings default
DateTime? _originalDateCaught;               // Original catch date/time
double? _originalLatitude;                   // Original catch latitude
double? _originalLongitude;                  // Original catch longitude
bool _hasValidTideData = false;               // Whether valid existing tide information is present
bool _recalculationSucceeded = false;         // Whether recalculation succeeded
bool _referenceChanged = false;               // Track if user changed reference
```

### State Management Rules
- Do not derive the recorded reference from the current Settings value
- Maintain separate state for all tracked values
- Initialize from appropriate source (Settings for new catch, recorded for edit)

### State Flow
- **New catch**: `_selectedTideReference` = Settings default, `_recordedTideReference` = NULL
- **Edit catch**: `_selectedTideReference` = recorded reference, `_recordedTideReference` = recorded reference
- **User changes**: `_selectedTideReference` = new selection, `_referenceChanged` = true
- **Save**: Use `_selectedTideReference`, reset state
- **Cancel**: Revert to `_recordedTideReference`

---

## 12. Future Reference Library Design

### Extensibility Requirements
Design selector to support future additions:
- Additional predefined locations
- Favourites
- User-created references
- Map-based reference selection
- Reference names and coordinates
- Editing or deleting user-created references

### Recommended Selector Evolution

#### Stage 3 (Current)
- Simple dropdown with 2 options
- Hardcoded Automatic and Darwin

#### Stage 4 (Future)
- Dropdown with dynamic list from `TideReferenceService.getAllReferences()`
- Add "Manage References..." option at bottom
- Opens reference management screen

#### Reference Management Screen (Future)
- List of all references
- Add new reference (coordinates + name)
- Edit user-created references
- Delete user-created references
- Set as favourite
- Map-based selection

### Data Model Extensions (Future)
```dart
class TideReference {
  String id;
  String displayName;
  double latitude;
  double longitude;
  bool isPredefined;  // true for Darwin, false for user-created
  bool isFavourite;   // user can favourite
  DateTime? createdAt;  // for user-created references
}
```

### Database Migration (Future)
- Add `tide_references` table for user-created references
- Not required for Stage 3

---

## 13. Validation and Safeguards

### Automatic Mode Validation
- **Requirement**: Automatic cannot be used without valid catch coordinates
- **Validation**: Check `latitude` and `longitude` are not NULL before saving
- **Fallback**: If coordinates invalid, show error: "Automatic mode requires valid catch coordinates. Please enter location or select a fixed reference."

### Fixed Mode Without Catch Location
- **Requirement**: Fixed Darwin mode can retrieve tide data even if catch location unavailable
- **Behavior**: Use Darwin coordinates for tide request
- **Limitation**: Distance cannot be calculated (show "Distance unavailable")
- **Display**: "Tide reference: Darwin — Distance unavailable"

### Coordinate Separation
- **Requirement**: App must not confuse catch coordinates with tide-request coordinates
- **Implementation**:
  - Catch coordinates: `catch.latitude`, `catch.longitude`
  - Tide-request coordinates: `environmentalCondition.tideRequestLat`, `environmentalCondition.tideRequestLon`
  - Always use tide-request coordinates for API calls
  - Always use catch coordinates for distance calculation

### Failed Recalculation Safeguard
- **Requirement**: Failed recalculation must not unintentionally erase valid existing environmental data
- **Implementation**:
  - Check if existing tide data is valid before recalculation
  - For new catches: Save reference, clear metadata, show notification
  - For existing catches with valid data: Prompt user with options
  - Do not automatically overwrite existing tide data
  - Allow user to choose between saving without tide info or reverting

### Clearing Stale Metadata
Whenever a reference change is saved without successful tide retrieval, clear all metadata from the previous WorldTides result:
- `worldtidesStation` = NULL
- `worldtidesAtlas` = NULL
- `worldtidesResponseLat` = NULL
- `worldtidesResponseLon` = NULL
- Tide-context phrase and tide-event values that relate to the previous reference

**Invariant**: Do not leave stale Darwin station data attached to a catch whose new reference is Automatic, or vice versa.

### User Feedback for API Failure
- **Requirement**: Clear feedback if new tide information cannot be retrieved
- **Implementation**:
  - Show SnackBar: "Unable to retrieve tide data. Check network connection and API key."
  - Keep existing reference in dropdown
  - Allow user to retry or cancel
  - Do not save catch with new reference but old tide data

---

## 14. Testing Plan

### Automated Tests (Unit Tests)

#### Default Reference Loading
- Test that new catch loads Settings default
- Test that Settings default is initial selection
- Test that changing selection does not update Settings

#### Per-Catch Override
- Test that per-catch selection is saved independently
- Test that Settings remains unchanged after per-catch override
- Test that multiple catches can have different references

#### Existing Catch Display
- Test that edit catch shows recorded reference
- Test that edit catch does not show Settings default
- Test that changing Settings does not affect existing catch display

#### Reference Changes
- Test changing Automatic to Darwin
- Test changing Darwin to Automatic
- Test that reference change triggers mandatory recalculation
- Test that "Revert to recorded reference" reverts selection

#### Mandatory Recalculation
- Test that reference change requires recalculation
- Test that "Revert to recorded reference" preserves original data
- Test that recalculation updates tide-request coordinates
- Test that failed recalculation prompts user (existing catch)
- Test that failed recalculation saves with notification (new catch)

#### Cancellation
- Test that cancel reverts to recorded reference
- Test that cancel does not save changes
- Test that cancel preserves existing environmental data

#### Historical Catch
- Test that historical catch shows "Not recorded"
- Test that historical catch can select Automatic or Darwin
- Test that reference selection requires recalculation
- Test that cancel preserves historical data

#### Cache Separation
- Test that Automatic uses catch coordinates for cache
- Test that Darwin uses fixed coordinates for cache
- Test that cache entries are separate for different references
- Test that cache reuse works for same reference and date

#### Distance Calculation
- Test that distance is calculated for fixed references
- Test that distance updates when location changes
- Test that distance is not shown for Automatic mode
- Test that distance formatting rules are applied
- Test that distance is omitted when coordinates unavailable

#### Settings Independence
- Test that Settings change does not update existing catches
- Test that per-catch change does not update Settings
- Test that recalculation dialog offers both options

#### Stale Metadata Clearing
- Test that reference change clears WorldTides metadata
- Test that Darwin station data not attached to Automatic reference
- Test that Automatic data not attached to Darwin reference

#### Failed Recalculation Dialog
- Test that "Save without tide information" clears metadata
- Test that "Revert to recorded reference" preserves data
- Test that cancel returns to editing without saving

### Widget Tests (New)

Where practical, add widget tests for:
- Loading the Settings default for a new catch
- Loading the recorded reference for an existing catch
- Changing the dropdown without changing Settings
- Reverting the dropdown to the recorded reference
- Mandatory reference-change dialog outcomes
- Failed recalculation dialog outcomes
- Historical "Not recorded" state
- Suppression of redundant or multiple prompts

### Physical Device Tests (Manual)

#### Interactive Controls
- Test dropdown opens and displays options from TideReferenceService
- Test selection changes are reflected in UI
- Test initial selection is Settings default
- Test selection persists during edit session

#### Prompts
- Test reference change prompt appears with refined wording
- Test consolidated prompt for multiple changes
- Test all prompt options work correctly (Recalculate, Revert, Cancel)
- Test prompt cancellation behavior
- Test failed recalculation prompt (existing catch)

#### Combined Change Scenarios
- Test reference + location change (reference takes precedence)
- Test reference + date/time change (reference takes precedence)
- Test location + date/time change (no reference change)
- Test all three changes together
- Verify single consolidated prompt

#### Real-time Distance Updates
- Test distance updates when location changes
- Test distance updates before saving
- Test distance formatting is correct
- Test distance omitted when coordinates unavailable

#### API Failure Scenarios
- Test offline mode behavior (new catch)
- Test offline mode behavior (existing catch with valid data)
- Test API key missing behavior
- Test network error behavior
- Verify graceful degradation

#### Historical Catch Workflow
- Test opening historical catch shows "Not recorded"
- Test Settings default not silently substituted
- Test selecting reference
- Test recalculation prompt
- Test cancellation preserves data
- Test current default suggested but clearly not recorded

---

## 15. Staged Implementation Sequence

### Phase 1: UI Control and State Management
1. Add state variables to `_AddCatchScreenState` (selected, recorded, Settings default, original values, flags)
2. Add dropdown control in Environmental Conditions section
3. Structure dropdown options through `TideReferenceService.getAllReferences()`
4. Load Settings default on new catch
5. Load recorded reference on edit catch (or "Not recorded" for historical)
6. Implement dropdown change handler
7. Add real-time distance display updates
8. Add Automatic mode coordinate validation message

### Phase 2: Save Logic
1. Update `_saveCatch` to use `_selectedTideReference`
2. Pass selected reference to `EnvironmentalConditionsService`
3. Update `upsertCalculatedConditionsForCatch` to accept reference parameter
4. Store reference in environmental condition record
5. Ensure Settings is not updated

### Phase 3: Edit and Recalculation
1. Implement reference change detection
2. Add reference change prompt with refined wording
3. Implement mandatory recalculation for reference changes
4. Implement "Revert to recorded reference" logic
5. Add failed recalculation prompt for existing catches
6. Implement stale metadata clearing on reference change
7. Update consolidated prompt logic (reference change takes precedence)

### Phase 4: Historical Catch Support
1. Detect historical catches (no recorded reference)
2. Show "Not recorded" in dropdown
3. Add reference selection prompt for historical catches
4. Implement recalculation with selected reference
5. Preserve historical data on cancellation

### Phase 5: Validation and Safeguards
1. Add Automatic mode coordinate validation
2. Add fixed mode without location handling
3. Implement failed recalculation safeguard
4. Add API failure user feedback
5. Add non-blocking notification for offline saves

### Phase 6: Testing
1. Add automated unit tests
2. Add widget tests where practical
3. Perform physical-device testing on Moto G15
4. Fix any issues found
5. Final verification

---

## 16. Decisions Requiring Approval

### 1. Selector Design
**Recommendation**: Dropdown (approved)
**Implementation**: Structure option source through `TideReferenceService` rather than hard-coding dropdown entries in the screen
**Rationale**: Consistent with existing design, compact, familiar, extensible for future references, extensible

### 2. Consolidated Prompt Wording
**Status**: Approved with refinements
- Reference change: "The tide reference has changed. Tide information must be recalculated using the new reference."
- Options: "Recalculate and save", "Revert to recorded reference", "Cancel"
- Reference change takes precedence (mandatory)
- Single consolidated prompt for multiple changes

### 3. Mandatory Recalculation Enforcement
**Status**: Approved with refinements
- Do not offer "Keep existing tide information" for reference changes
- For existing catches with valid data: prompt with "Save without tide information", "Revert to recorded reference", "Cancel"
- For new catches: save with notification if tide data unavailable
- Clear stale metadata on reference change

### 4. Historical Catch Initial Display
**Status**: Approved with clarification
- Show "Not recorded" in dropdown
- Do not silently substitute Settings default
- Current default may be suggested but must be clear it wasn't recorded
- Require recalculation before saving selected reference

### 5. Distance Display Real-time Update
**Status**: Approved
- Update immediately when location changes
- For fixed references: calculate from edited coordinates, omit when coordinates unavailable
- For Automatic: no distance display

### 6. Future Reference Library Scope
**Status**: Approved
- Design for extensibility but do not implement in Stage 3
- Structure dropdown through `TideReferenceService` for future additions
- Keep Stage 3 focused

### 7. Validation Error Handling
**Status**: Approved
- Block save with error message for invalid Automatic mode
- Explain tide info unavailable until location provided
- Allow save with reference recorded but tide data unavailable
- Clear user feedback for all validation errors

---

## 17. Summary

### Key Design Principles
1. **Settings as default only**: Per-catch selection independent of Settings
2. **Mandatory recalculation**: Reference change requires recalculation
3. **Consolidated prompts**: Single prompt for multiple changes
4. **Data integrity**: Prevent inconsistent reference/tide data combinations
5. **Graceful degradation**: Handle API failures without data loss
6. **Extensibility**: Design for future reference library
7. **No database migration**: Use existing v28 fields

### Implementation Complexity
- **Low to Medium**: Mostly UI changes and prompt logic
- **No database changes**: Use existing schema
- **Backward compatible**: Historical data preserved
- **Testable**: Clear unit and physical-device test cases

### Estimated Effort
- **Phase 1 (UI)**: 2-3 hours
- **Phase 2 (Save)**: 1-2 hours
- **Phase 3 (Edit/Recalc)**: 2-3 hours
- **Phase 4 (Historical)**: 1-2 hours
- **Phase 5 (Validation)**: 1-2 hours
- **Phase 6 (Testing)**: 2-3 hours
- **Total**: 9-15 hours

### Approval Required
Please review and approve:
1. Selector control type (dropdown)
2. Prompt wording and consolidation strategy
3. Mandatory recalculation enforcement
4. Historical catch handling
5. Any other design decisions

Do not begin implementation until approved.
