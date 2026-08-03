# Stage 4 Plan: Reliable Photo Metadata Extraction

## Objective
Make photo metadata extraction reliable and understandable, ensuring the app never silently replaces values the user has already entered.

## Planning Date
August 3, 2026

---

## 1. Current Photo Workflow Analysis

### 1.1 Workflow Tracing

#### Taking a New Photo with Camera
**Entry Point:** `_takePhoto()` in `add_catch_screen.dart`

**Flow:**
1. User taps camera button
2. `ImagePicker.pickImage(source: ImageSource.camera)` called
3. Image picker returns `XFile` with path to captured photo
4. `_processPickedFile(file, 'camera')` called
5. `_extractGpsData(originalPath)` extracts GPS coordinates
6. GPS data applied to form fields:
   - `_latitudeController.text = latitude.toString()`
   - `_longitudeController.text = longitude.toString()`
7. SnackBar shown: "GPS coordinates found in photo"
8. Photo added to `_mediaItems` with role 'primary' (if first) or 'other'

**Key Characteristics:**
- Date/time: NOT extracted from EXIF, uses `DateTime.now()` (line 874)
- Location: Auto-populated without user confirmation
- No difference between Add Catch and Edit Catch

#### Selecting Photo from Gallery
**Entry Point:** `_pickImage()` in `add_catch_screen.dart`

**Flow:**
1. User taps gallery button
2. `ImagePicker.pickImage(source: ImageSource.gallery)` called
3. Image picker returns `XFile` with path to selected photo
4. `_processPickedFile(file, 'gallery')` called
5. Same extraction and auto-population as camera photos
6. No difference in behavior between camera and gallery

#### Adding First Photo to New Catch
**Behavior:**
- Photo marked with role 'primary' (line 879)
- GPS coordinates auto-populated to form
- Date/time set to current device time (not from photo)
- No user confirmation

#### Adding Additional Photo
**Behavior:**
- Photo marked with role 'other'
- GPS coordinates auto-populated to form (overwrites previous)
- Date/time set to current device time (overwrites previous)
- No user confirmation
- **ISSUE:** Subsequent photos silently overwrite metadata from first photo

#### Editing Existing Catch
**Behavior:**
- Loads existing media from database via `_loadMediaForCatch()`
- Adding new photos follows same workflow as new catch
- No special handling for existing catch metadata
- **ISSUE:** New photos can overwrite existing catch data without confirmation

#### Recovering Photo via `retrieveLostData()`
**Entry Point:** `_retrieveLostData()` in `add_catch_screen.dart`

**Flow:**
1. Called in `initState()` and `didChangeAppLifecycleState()`
2. `ImagePicker.retrieveLostData()` called
3. Lost files processed via `_processPickedFile(file, 'lost_data')`
4. Same extraction and auto-population as normal photos
5. SnackBar shown: "Recovered photo from previous camera session"

**Key Characteristics:**
- Preserves lost-photo workflow
- No special handling for recovered photos

### 1.2 Photo Metadata Extraction Initiation
**Location:** `_extractGpsData()` in `add_catch_screen.dart` (lines 905-930)

**Initiation Points:**
- Camera photo selection
- Gallery photo selection
- Lost data recovery

**Primary Photo Source:**
- First photo added to catch is marked 'primary'
- Subsequent photos marked 'other'
- **ISSUE:** All photos (primary and other) trigger metadata extraction
- **ISSUE:** Subsequent photos can overwrite values from primary photo

### 1.3 Extracted Values Application
**When Applied:** Immediately after photo selection (synchronous)

**Fields Populated:**
- `_latitudeController.text` (if GPS found)
- `_longitudeController.text` (if GPS found)
- **NOT POPULATED:** `_dateCaught` (uses `DateTime.now()` instead)

**User Feedback:**
- SnackBar: "GPS coordinates found in photo" (if GPS present)
- No feedback if GPS not found
- No confirmation dialog

### 1.4 Workflow Differences

#### Camera vs Gallery Photos
**No Difference:**
- Same extraction method
- Same auto-population behavior
- Same user feedback

#### Add Catch vs Edit Catch
**No Difference:**
- Same extraction method
- Same auto-population behavior
- **ISSUE:** Edit Catch should be more conservative about overwriting existing data

#### Trip Photos
**Location:** `trip_details_screen.dart` (line 161)

**Behavior:**
- Uses `ImagePicker.pickImage()`
- Does NOT extract EXIF metadata
- Does NOT populate location or date/time
- Only stores file path and role

#### Journal Entry Photos
**Location:** `journal_entry_screen.dart` (line 179)

**Behavior:**
- Uses `ImagePicker.pickImage()`
- Does NOT extract EXIF metadata
- Does NOT populate location or date/time
- Only stores file path

---

## 2. Current EXIF Implementation Review

### 2.1 Packages Used
**Primary Package:** `exif: ^3.3.0` (from pubspec.yaml)

**Usage Location:** `add_catch_screen.dart` (lines 905-930)

**Method Call:**
```dart
final data = await readExifFromBytes(bytes);
```

### 2.2 EXIF Tags Currently Inspected

#### GPS Tags
**Currently Read:**
- `GPSLatitude` - Latitude in degrees/minutes/seconds
- `GPSLatitudeRef` - 'N' or 'S' reference
- `GPSLongitude` - Longitude in degrees/minutes/seconds
- `GPSLongitudeRef` - 'E' or 'W' reference

**NOT Read:**
- `GPSAltitude` - Altitude
- `GPSDateStamp` - GPS date
- `GPSTimeStamp` - GPS time
- `GPSImgDirection` - Image direction
- `GPSProcessingMethod` - GPS processing method

#### Date/Time Tags
**NOT Read:**
- `DateTimeOriginal` - Original capture date/time
- `DateTimeDigitized` - Digitization date/time
- `DateTime` - Modification date/time
- `OffsetTime` - Timezone offset
- `OffsetTimeOriginal` - Timezone offset for original
- `OffsetTimeDigitized` - Timezone offset for digitized

#### Orientation Tags
**NOT Read:**
- `Orientation` - Image orientation

### 2.3 GPS Conversion Implementation
**Location:** `_convertToDecimalDegrees()` (lines 932-945)

**Conversion Formula:**
```dart
final decimal = degrees + (minutes / 60) + (seconds / 3600);
```

**Reference Handling:**
```dart
if (ref == 'S' || ref == 'W') {
  return -decimal;
}
```

**Assessment:**
- ✅ Correctly handles degrees/minutes/seconds to decimal conversion
- ✅ Correctly handles south (S) and west (W) references as negative
- ✅ Assumes reference is single character ('N', 'S', 'E', 'W')

### 2.4 Date/Time Extraction
**Current Status:** NOT IMPLEMENTED

**Current Behavior:**
```dart
final photoDateTime = DateTime.now();  // Line 874
```

**Issues:**
- Does not read EXIF date/time tags
- Always uses current device time
- No timezone handling
- No distinction between original, digitized, and modification times

---

## 3. Test Files and Controlled Reproduction

### 3.1 Test Photo Categories Required

#### Category 1: Phone Photo with GPS and Date/Time Metadata
**Expected EXIF Tags:**
- GPSLatitude, GPSLatitudeRef, GPSLongitude, GPSLongitudeRef
- DateTimeOriginal
- DateTimeDigitized
- DateTime
- OffsetTime or timezone information

**Test Points:**
- Verify GPS extraction accuracy
- Verify date/time extraction accuracy
- Verify timezone handling

#### Category 2: Phone Photo with Date/Time but No GPS
**Expected EXIF Tags:**
- DateTimeOriginal
- DateTimeDigitized
- DateTime
- NO GPS tags

**Test Points:**
- Verify date/time extraction without GPS
- Verify graceful handling of missing GPS
- Verify no location auto-population

#### Category 3: Photo with GPS but No Timezone Offset
**Expected EXIF Tags:**
- GPSLatitude, GPSLatitudeRef, GPSLongitude, GPSLongitudeRef
- DateTimeOriginal (without timezone)
- NO OffsetTime tags

**Test Points:**
- Verify GPS extraction
- Verify ambiguous timezone handling
- Verify user notification about timezone ambiguity

#### Category 4: Screenshot or Edited Image with No EXIF
**Expected EXIF Tags:**
- Minimal or no EXIF data
- May have basic DateTime only

**Test Points:**
- Verify graceful handling of missing metadata
- Verify no crash or error
- Verify photo can still be added

#### Category 5: Photo Downloaded from Messaging/Social Media
**Expected EXIF Tags:**
- Often stripped of EXIF metadata
- May have only basic file metadata

**Test Points:**
- Verify handling of stripped metadata
- Verify no crash or error
- Verify photo can still be added

#### Category 6: Photo Taken in Darwin
**Expected EXIF Tags:**
- GPS coordinates in Darwin area
- DateTimeOriginal with ACST timezone (+09:30)
- May have OffsetTime: +09:30

**Test Points:**
- Verify GPS extraction
- Verify timezone offset parsing
- Verify no timezone shift applied incorrectly

#### Category 7: Historical Photo from Different Timezone
**Expected EXIF Tags:**
- GPS coordinates from different location
- DateTimeOriginal with different timezone
- May have OffsetTime from original timezone

**Test Points:**
- Verify GPS extraction
- Verify timezone offset preservation
- Verify no timezone shift when user returns home

### 3.2 Test Plan Execution
**Status:** NOT YET EXECUTED

**Required:**
- User to provide representative test photos
- Execute EXIF extraction on each
- Document available tags
- Document parsed results
- Document form population behavior

**Privacy Consideration:**
- Do not log full image paths
- Do not expose personal photo contents
- Report only EXIF tag names and values (not photo data)

---

## 4. Date and Time Priority Rules

### 4.1 Approved Priority Order

**Primary Priority (EXIF):**
1. **DateTimeOriginal** - When photo was actually captured
2. **DateTimeDigitized** - When photo was digitized (for scanned photos)
3. **DateTime** - Last modification time (least reliable)

**Fallback Priority (File System):**
4. File modification timestamp - ONLY if explicitly labelled as low-confidence fallback
   - Label: "File date: 3 August 2026, 2:35 PM — this may not be when the photo was taken"
   - Do NOT automatically populate catch date/time from file timestamp without confirmation

**NOT Used:**
- Current device time - Should not be used as though from photo

### 4.2 Timezone Handling

#### Missing Timezone Information
**Approved Behavior:**
- If EXIF has no timezone offset (OffsetTime, OffsetTimeOriginal, OffsetTimeDigitized):
  - Preserve the clock value exactly as recorded
  - Classify internally as unspecified local photo time
  - Display warning: "The photo does not include timezone information. Check that the time is correct."
  - Allow user to adjust before applying
  - Do NOT perform timezone conversion
  - Do NOT assume Darwin time, device current timezone, or catch location timezone

#### Timezone Offset Tags
**Behavior:**
- Read OffsetTimeOriginal if available (most accurate for DateTimeOriginal)
- Fall back to OffsetTimeDigitized for DateTimeDigitized
- Fall back to OffsetTime for DateTime
- Apply offset to convert to UTC for storage
- Display local time to user based on current device timezone

#### Valid UTC Timestamps
**Approved Behavior:**
- If EXIF timestamp is in UTC (no offset or offset +00:00):
  - Parse and retain offset
  - Show photo's local date and time
  - Do NOT convert to phone's current timezone unless user explicitly requests

#### Photos Taken in Darwin
**Approved Behavior:**
- Darwin timezone: ACST (+09:30 standard, +10:30 daylight saving)
- If OffsetTime present: parse and retain it, show photo's local date and time
- If no OffsetTime: preserve clock value, classify as unspecified local time, show warning
- Do NOT assume Darwin timezone automatically

#### Photos Taken Interstate/Overseas
**Approved Behavior:**
- If OffsetTime present: parse and retain it, show photo's local date and time
- If no OffsetTime: preserve clock value, classify as unspecified local time, show warning
- Do NOT apply current device timezone
- Allow user to manually adjust

#### Historical Photos Imported After Return
**Approved Behavior:**
- Preserve original timezone offset from EXIF
- Do NOT apply current device timezone
- Display as local time at capture location
- Example: Photo taken in Sydney (AEST +10:00) while user was there, imported in Darwin - should still show Sydney time

#### Daylight-Saving Locations
**Approved Behavior:**
- OffsetTime includes daylight saving if present in EXIF
- If OffsetTime is +10:00 (Sydney DST), use that
- If OffsetTime is +09:30 (Darwin non-DST), use that
- Do NOT attempt to calculate DST automatically

#### Ambiguous EXIF Timestamps (No Timezone)
**Approved Behavior:**
- Preserve clock value exactly as recorded
- Classify internally as unspecified local photo time
- Display warning: "The photo does not include timezone information. Check that the time is correct."
- Allow user to manually adjust date/time if needed
- Do NOT silently apply current device timezone
- Do NOT assume Darwin, device, or catch location timezone

### 4.3 Critical Requirement
**The app must not silently shift a correctly recorded local photo time by applying the phone's current timezone incorrectly.**

**Example:**
- Photo taken in Darwin at 2:35 PM ACST (+09:30)
- EXIF: DateTimeOriginal = 2026-08-03 14:35:00, OffsetTime = +09:30
- User imports photo while in Sydney (AEST +10:00)
- **CORRECT:** Display as 2:35 PM (Darwin time)
- **INCORRECT:** Display as 3:05 PM (shifted by Sydney timezone)

---

## 5. Location Priority Rules

### 5.1 Photo Has Valid GPS Metadata
**Behavior:**
- Extract GPS coordinates from EXIF
- Offer to populate form fields via confirmation dialog
- Do NOT auto-populate without user consent
- Display extracted location on map preview in confirmation dialog

### 5.2 Photo Has Incomplete GPS Metadata
**Behavior:**
- If only latitude or only longitude present:
  - Treat as no GPS metadata
  - Do not populate any location fields
  - Offer current device location as alternative (with clear labelling)

### 5.3 Photo Has No GPS Metadata
**Behavior:**
- Do not populate location fields
- Offer current device location as alternative (with clear labelling)
- Allow manual entry

### 5.4 User Has Already Entered Location
**Behavior:**
- Detect if form fields already populated:
  - `_latitudeController.text.isNotEmpty`
  - `_longitudeController.text.isNotEmpty`
  - `_locationController.text.isNotEmpty`
- Show conflict in confirmation dialog:
  - "Current location: [entered values]"
  - "Photo location: [extracted values]"
  - Options: "Use photo location", "Keep current location", "Use both (merge)"

### 5.5 Device Current Location Available
**Behavior:**
- Offer as alternative to photo GPS
- Clearly label as "Current device location"
- Distinguish from photo GPS
- User must explicitly choose

### 5.6 Multiple Photos with Different Locations
**Behavior:**
- First photo: Offer to populate form
- Subsequent photos: Do NOT offer to overwrite
- If subsequent photo has different location:
  - Show notification: "Photo location differs from catch location"
  - Do not auto-populate
  - Allow user to view photo location separately

### 5.7 Critical Requirement
**Photo metadata and current device location must remain distinct concepts.**

**Do NOT substitute current device location for missing photo GPS without clearly informing the user.**

---

## 6. Primary-Photo Behavior

### 6.1 Definition
**Primary Photo:** First photo added to a catch (role = 'primary')

**Subsequent Photos:** Additional photos (role = 'other')

### 6.2 Approved Behavior

#### First Photo to New Catch
**Approved Behavior:**
- Extract metadata from first photo
- Show confirmation dialog with extracted values
- User chooses which fields to apply
- Mark photo as 'primary'
- Record which photo supplied metadata (in CatchMedia)
- Only first photo may automatically trigger "Photo details found" prompt

#### Subsequent Photos
**Approved Behavior:**
- Extract metadata for internal use only
- Do NOT show confirmation dialog
- Do NOT auto-populate form fields
- Mark photo as 'other'
- Subsequent photos must never silently update catch metadata
- Subsequent photos should NOT produce repeated notifications merely because their metadata differs
- Provide explicit "Use photo details" action for any photo when user deliberately wants to inspect and apply its metadata
- This allows user to use a later photo if first photo contains no useful metadata

#### Replacing or Removing Primary Photo
**Approved Behavior:**
- Replacing primary photo:
  - Do NOT automatically rewrite catch information
  - Offer to extract metadata from new photo
  - Show confirmation dialog
- Removing primary photo:
  - Do NOT automatically clear catch information
  - Preserve existing catch metadata
  - Promote next photo to primary if available

#### Photos Added While Editing Existing Catch
**Approved Behavior:**
- Extract metadata
- Compare with existing catch values
- If differs:
  - Do NOT automatically display overwrite prompt
  - Metadata should only be applied through explicit "Use photo details" action
  - Clearly show which existing values would change
  - Applying new date, time or location must use existing environmental-recalculation safeguards
- If same:
  - No action needed
- Do NOT silently overwrite recorded catch details

### 6.3 Explicit "Use Photo Details" Action
**Approved:** YES, implement explicit action

**Rationale:**
- Prevents silent overwrites
- Gives user control
- Clear when metadata is being applied
- Avoids confusion about source of values
- Allows user to use later photo if first photo has no useful metadata

**Implementation:**
- Confirmation dialog on first photo selection
- "Use photo details" button on photo item
- Manual trigger option in overflow menu
- Available for any photo, not just first
- Clearly shows which existing values would change

---

## 7. User Confirmation Interface

### 7.1 Dialog Title
**"Photo Details Found"**

### 7.2 Content Display

**Show only metadata actually available.**

**Example:**
```
Date and time: 3 August 2026, 2:35 PM
Timezone: not recorded
Location: -12.38, 130.85
```

**Map Preview:**
- Show pin at extracted GPS coordinates
- Allow user to verify location visually

### 7.3 Location Validation

**Approved Validation Rules:**

Continue using existing GPS conversion logic, but add validation for:
- Latitude between -90 and 90
- Longitude between -180 and 180
- Missing latitude or longitude references (GPSLatitudeRef, GPSLongitudeRef)
- Malformed rational values (non-numeric, out of range)
- Zero coordinates (0,0) - do NOT treat as valid without explicit confirmation
- Incomplete GPS tag sets (latitude without longitude or vice versa)

**Validation Implementation:**
- Reject coordinates outside valid ranges
- Reject coordinates with missing references
- Reject malformed rational values
- Flag 0,0 as requiring explicit user confirmation
- Flag incomplete GPS as rejected

### 7.4 Options

**Approved Interface:** Checkboxes for individual field selection

**Checkboxes:**
- ☑ Use photo date
- ☑ Use photo time
- ☑ Use photo location

**Buttons:**
- Apply selected details
- Keep current catch details

**If existing form values would be replaced:**
- Show both current and photo values
- Example: "Current: 2 August 2026, 5:15 PM → Photo: 3 August 2026, 2:35 PM"

**Do NOT use separate buttons** such as "Use date/time only" and "Use location only" - checkboxes provide clearer and more extensible interface.

### 7.5 Dynamic Options
**Rule:** Only show checkboxes for metadata actually found

**Examples:**
- If only GPS present: Show only "Use photo location" checkbox
- If only date/time present: Show only "Use photo date" and "Use photo time" checkboxes
- If both present: Show all checkboxes
- If neither present: Do not show dialog

### 7.6 Form Field State Detection
**Empty Fields:**
- `_dateCaught == null`
- `_latitudeController.text.isEmpty`
- `_longitudeController.text.isEmpty`
- `_locationController.text.isEmpty`

**Populated Fields:**
- Any of the above not empty

---

## 8. Conflicts with Existing Values

### 8.1 Behavior Definition
**Do NOT silently overwrite:**
- Catch date (`_dateCaught`)
- Catch time (part of `_dateCaught`)
- Latitude (`_latitudeController`)
- Longitude (`_longitudeController`)
- Selected favourite spot or named location (`_locationController`)

**Approved Add Catch Behavior:**
- First photo may offer metadata for fields that are empty or still contain initial defaults
- Always obtain confirmation before replacing user-edited values

**Approved Edit Catch Behavior:**
- Adding a photo must NOT automatically display an overwrite prompt
- Metadata should only be applied through explicit "Use photo details" action
- Clearly show which existing values would change
- Applying new date, time or location must use existing environmental-recalculation safeguards
- Example: Changing photo-derived date, time or location on existing catch may require same tide and environmental recalculation prompt

### 8.2 Conflict Detection
**Check Before Extraction:**
```dart
final hasExistingDate = _dateCaught != null;
final hasExistingLocation = _latitudeController.text.isNotEmpty ||
                          _longitudeController.text.isNotEmpty ||
                          _locationController.text.isNotEmpty;
```

### 8.3 Conflict Wording

#### Date/Time Conflict
**Dialog:**
```
Photo Details Found

Photo date/time: 3 August 2026, 2:35 PM
Current date/time: 2 August 2026, 5:15 PM

The photo date/time differs from the catch date/time.

Options:
- Use photo date/time
- Keep current date/time
```

#### Location Conflict
**Dialog:**
```
Photo Details Found

Photo location: -12.4634, 130.8416
Current location: -12.4500, 130.8000 (Darwin Harbour)

The photo location differs from the catch location.

Options:
- Use photo location
- Keep current location
```

#### Both Conflict
**Dialog:**
```
Photo Details Found

Photo date/time: 3 August 2026, 2:35 PM
Current date/time: 2 August 2026, 5:15 PM

Photo location: -12.4634, 130.8416
Current location: -12.4500, 130.8000 (Darwin Harbour)

The photo details differ from the catch details.

Options:
- Use photo date/time and location
- Use photo date/time, keep current location
- Use photo location, keep current date/time
- Keep current values
```

### 8.4 Individual Field Selection
**Recommendation:** Allow user to choose individual fields

**Implementation:**
- Checkbox-style selection in confirmation dialog
- User can select which fields to apply
- Unselected fields remain unchanged

**Example:**
```
☑ Use photo date/time
☐ Use photo location
☑ Use photo timezone
```

---

## 9. Multiple-Photo Conflicts

### 9.1 Approved Rule
**Do NOT combine date from one photo with location from another automatically.**

**Each metadata application must come from one identified photo.**

**Approved Behavior:**
- If user selects "Use photo details" for another image later:
  - Clearly show that it will replace previously applied values
  - Do not merge metadata from multiple photos
  - User must choose which single photo to use as source

**Record primary photo independently from the photo that supplied metadata if those concepts differ.**

### 9.2 Scenarios

#### First Photo Has No Metadata, Second Photo Does
**Approved Behavior:**
- First photo: No confirmation dialog (no metadata)
- Second photo: Show confirmation dialog
- Offer to populate form
- User chooses which fields to apply

#### Two Photos Contain Different Times
**Approved Behavior:**
- First photo: Show confirmation dialog, user applies time
- Second photo: Do NOT show notification about time difference
- User can use explicit "Use photo details" action if they want to switch

#### Two Photos Contain Different GPS Coordinates
**Approved Behavior:**
- First photo: Show confirmation dialog, user applies location
- Second photo: Do NOT show notification about location difference
- User can use explicit "Use photo details" action if they want to switch

#### Photos Were Several Minutes Apart
**Approved Behavior:**
- Treat as independent photos
- Do not auto-merge or auto-select
- User chooses which photo to use for metadata

#### One Photo Was Edited or Exported
**Approved Behavior:**
- Exported photos may have altered metadata
- Validation should detect suspicious metadata
- Allow user to verify
- Do not auto-populate from suspicious metadata

---

## 10. Camera Photos

### 10.1 Photo Timestamp vs Catch Form Time
**Approved Behavior:** Use photo timestamp from EXIF if reliably available

**Rationale:**
- Photo timestamp is more accurate than form time
- Form time is when user entered data, not when fish was caught
- EXIF DateTimeOriginal is when photo was taken (closest to catch time)

**Investigation Required:**
- Do NOT assume photos taken from Bragmat will reliably contain EXIF GPS or timestamp metadata
- Investigate actual Moto G15 camera output and Android image_picker behavior

**Fallback:**
- If no EXIF metadata in camera photo:
  - Retain Add Catch form's existing date, time and location
  - Do NOT replace form time with DateTime.now() after camera returns
  - Do NOT substitute current device GPS while presenting it as photo GPS

### 10.2 Camera Output GPS Metadata
**Investigation Required:**
- Does Android camera output reliably contain GPS metadata?
- Does it depend on camera settings?
- Does it depend on location permissions?

**Assumptions:**
- GPS metadata depends on:
  - Location permission granted
  - Location services enabled
  - Camera app settings (location tagging enabled)
- Not guaranteed to be present

**Fallback:**
- If no GPS in camera photo:
  - Offer current device location
  - Clearly label as "Current device location"
  - Do not auto-populate

### 10.3 Camera Location Tagging Dependencies
**Android Camera App:**
- Location tagging must be enabled in camera settings
- Location permission must be granted
- Location services must be enabled

**Bragmat Requirements:**
- Request location permission at app startup
- Check location services before camera
- Guide user to enable camera location tagging if needed

### 10.4 Recovered-Photo Workflow
**Approved Behavior:** Preserve existing workflow

**Requirements:**
- Preserve existing `_retrieveLostData()` workflow
- Ensure recovered photos go through same metadata extraction and confirmation process
- Do NOT break lost-data recovery
- Do NOT reintroduce previously observed intermittent camera-navigation issue

---

## 11. Gallery and Android File Access

### 11.1 File Paths vs Content URIs
**Current Implementation:**
- Uses `pickedFile.path` from ImagePicker
- ImagePicker handles content URI to file path conversion
- Creates temporary copy in app cache

**Investigation Required:**
- Does ImagePicker preserve EXIF in temporary copy?
- Does scoped storage affect EXIF access?
- Are there differences between file:// and content:// URIs?

### 11.2 Scoped Storage
**Android 10+ Scoped Storage:**
- May restrict direct file access
- ImagePicker should handle this
- Verify EXIF reading works with scoped storage

**Testing Required:**
- Test on Android 10+ device
- Test with photos from different sources
- Test with Google Photos

### 11.3 Temporary Copies
**ImagePicker Behavior:**
- Creates temporary copy of selected image
- Applies compression and resizing (imageQuality, maxWidth, maxHeight)
- **RISK:** May strip EXIF during compression

**Current Settings:**
```dart
imageQuality: 85,
maxWidth: 1920,
maxHeight: 1080,
```

**Investigation Required:**
- Does ImagePicker preserve EXIF during compression?
- If not, need to read EXIF before compression
- May need to use original file before processing

### 11.4 HEIC/HEIF Images
**Current Support:**
- ImagePicker may return HEIC on iOS
- Android typically uses JPEG
- exif package may not support HEIC

**Investigation Required:**
- Test HEIC/HEIF support on Android
- If not supported, convert to JPEG first
- May need additional package for HEIC handling

### 11.5 JPEG Images
**Expected Behavior:**
- JPEG should preserve EXIF
- exif package supports JPEG
- Should work reliably

### 11.6 Cloud-Backed Providers
**Google Photos:**
- May return content URI
- May download full resolution or thumbnail
- EXIF may be preserved or stripped

**Investigation Required:**
- Test with Google Photos selection
- Verify EXIF preservation
- Handle stripped metadata gracefully

**Other Cloud Providers:**
- Similar concerns
- Test with WhatsApp, Messenger, etc.
- Handle stripped metadata gracefully

### 11.7 Metadata Reading Timing
**Critical Requirement:**
**Metadata should be read from the original selected file before any operation that may strip EXIF data.**

**Implementation:**
- Read EXIF immediately after file selection
- Before compression
- Before copying
- Before any image processing

**Current Issue:**
- ImagePicker may compress before returning file
- May need to access original file directly
- May need to use different ImagePicker settings

---

## 12. Error and Fallback Behavior

### 12.1 No EXIF Metadata
**Behavior:**
- Photo can still be added
- No confirmation dialog
- No auto-population
- User can manually enter data
- No error shown to user

### 12.2 Malformed EXIF
**Behavior:**
- Catch parsing exception
- Log error for diagnostics
- Photo can still be added
- No auto-population
- Show subtle notification: "Photo metadata could not be read"
- User can manually enter data

### 12.3 Unsupported Image Format
**Behavior:**
- Catch format exception
- Log error for diagnostics
- Photo can still be added (if displayable)
- No metadata extraction
- Show subtle notification: "Photo format not supported for metadata extraction"

### 12.4 Permission Failure
**Behavior:**
- Catch permission exception
- Log error for diagnostics
- Photo can still be added
- No metadata extraction
- Show user-friendly error: "Permission denied. Photo added without metadata."

### 12.5 Inaccessible Cloud Image
**Behavior:**
- Catch file access exception
- Log error for diagnostics
- Photo may not be added
- Show user-friendly error: "Could not access photo. Please try again."

### 12.6 Invalid GPS Coordinates
**Behavior:**
- Detect invalid values (NaN, infinity, out of range)
- Do not populate location fields
- Show subtle notification: "Photo GPS coordinates are invalid"
- User can manually enter location

### 12.7 Invalid Date/Time
**Behavior:**
- Detect invalid values (null, out of range, future dates)
- Do not populate date/time fields
- Show subtle notification: "Photo date/time is invalid"
- User can manually enter date/time

### 12.8 Metadata Parsing Exception
**Behavior:**
- Catch general exception
- Log full stack trace for diagnostics
- Photo can still be added
- No auto-population
- Show subtle notification: "Photo metadata could not be read"

### 12.9 Critical Requirement
**Do not block saving a catch because metadata extraction failed.**

**Implementation:**
- All metadata extraction errors are non-blocking
- User can always complete catch manually
- Metadata is enhancement, not requirement

---

## 13. Logging and Privacy

### 13.1 Temporary Diagnostic Logging
**Sufficient to Trace:**
- Metadata tags detected (tag names only, not values)
- Parsing path selected (which priority rule used)
- Whether a field was accepted or rejected
- Whether the user applied or declined extracted values
- Errors and exceptions (without sensitive data)

### 13.2 Privacy Protections
**Do NOT Log:**
- Full image paths (log filename only)
- Photo contents or thumbnails
- API keys
- Personal information from EXIF (camera model, serial number, etc.)
- User location coordinates in production logs
- Exact timestamp values in production logs

### 13.3 Example Logging
**Acceptable:**
```dart
debugPrint('EXIF: GPSLatitude tag found');
debugPrint('EXIF: DateTimeOriginal tag found');
debugPrint('EXIF: Using DateTimeOriginal priority rule');
debugPrint('EXIF: Field accepted: latitude');
debugPrint('EXIF: User declined extracted values');
debugPrint('EXIF: Parsing error: invalid GPS format');
```

**Not Acceptable:**
```dart
debugPrint('EXIF: GPSLatitude: -12.4634');  // Too specific
debugPrint('EXIF: DateTimeOriginal: 2026-08-03 14:35:00');  // Too specific
debugPrint('EXIF: File path: /storage/emulated/0/DCIM/...');  // Full path
debugPrint('EXIF: Camera serial: ABC12345');  // Personal info
```

### 13.4 Production Build
**Remove:**
- All temporary diagnostic logging before production release
- Keep only essential error logging (without sensitive data)

---

## 14. Data Model

### 14.1 Existing Fields Assessment
**coordinate_source Field:**
- **Type:** TEXT (free text)
- **Current Values in Use:**
  - 'Device GPS' (set by `_getCurrentLocation()`)
  - 'Map Selected' (set by map selection)
  - 'Favourite Spot' (set by favourite spot selection)
- **Location:** catches table only
- **Usage:** Reports, exports, filters may reference this field

**Assessment:** Free text field, not constrained by application logic

**Approved Stable Internal Values:**
- `manual` - for manually entered coordinates
- `device_gps` - for current device GPS (replace 'Device GPS')
- `photo_gps` - for photo EXIF GPS (new value)
- `favourite_spot` - for favourite spots (replace 'Favourite Spot')
- `map_selected` - for map selection (replace 'Map Selected')

**Caution:** Do not add `photo_gps` without confirming it will not break existing comparisons. Inspect all reports, exports, and filters that reference `coordinate_source`.

**CatchMedia.date_taken Field:**
- **Type:** TEXT (DateTime ISO8601 string)
- **Current Usage:**
  - Stored in catch_media table
  - Used in database migration to populate from catches.photo_datetime
  - Displayed in catch details screen
  - Included in CSV export
- **Meaning:** Currently represents EXIF date from photo
- **Assessment:** Can be used for EXIF timestamp, no conflict with existing usage

**Assessment:** Existing fields are sufficient, no database migration required

### 14.2 Recommendation
**No Database Migration Required**

**Rationale:**
- Existing fields are sufficient
- Extend `coordinate_source` to use stable internal values
- `role` field already tracks primary photo
- Additional fields provide minimal user benefit
- Can add later if needed

**Implementation:**
- Use existing `coordinate_source` field with stable values:
  - Add `photo_gps` for photo metadata (after confirming no breaking changes)
  - Keep `device_gps` for current device location
  - Keep `map_selected` for map selection
  - Keep `favourite_spot` for favourite spots
  - Add `manual` for manual entry
- Use existing `role` field to track primary photo
- Use existing `date_taken` in CatchMedia for EXIF timestamp
- No schema changes needed

---

## 15. Testing Plan

### 15.1 Automated Tests

#### EXIF GPS Conversion
- Test degrees/minutes/seconds to decimal conversion
- Test north/south reference handling
- Test east/west reference handling
- Test edge cases (0, 90, 180 degrees)
- Test invalid reference values
- Test latitude between -90 and 90 validation
- Test longitude between -180 and 180 validation
- Test zero coordinates (0,0) rejection
- Test missing latitude/longitude references
- Test malformed rational values
- Test incomplete GPS tag sets

#### DateTimeOriginal Priority
- Test DateTimeOriginal is used when present
- Test DateTimeDigitized fallback when DateTimeOriginal missing
- Test DateTime fallback when both missing
- Test file modification timestamp as last resort (with low-confidence label)
- Test that file timestamp is NOT used without confirmation

#### Timezone Offset Parsing
- Test OffsetTimeOriginal parsing
- Test OffsetTimeDigitized parsing
- Test OffsetTime parsing
- Test missing timezone handling (preserve clock value, show warning)
- Test UTC offset (+00:00)
- Test positive offsets
- Test negative offsets
- Test malformed offset
- Test daylight-saving timezone

#### Missing Timezone Handling
- Test warning shown when no timezone
- Test clock value preserved exactly
- Test classified as unspecified local photo time
- Test no timezone conversion performed
- Test user can manually adjust

#### Malformed GPS and Timestamp Values
- Test invalid GPS format
- Test invalid date format
- Test out-of-range values
- Test null values
- Test NaN values
- Test future date rejection

#### Metadata with Date/Time Only
- Test date/time extraction without GPS
- Test no location auto-population
- Test confirmation dialog shows only date/time options

#### Metadata with GPS Only
- Test GPS extraction without date/time
- Test no date/time auto-population
- Test confirmation dialog shows only location options

#### Metadata with Neither
- Test graceful handling
- Test no confirmation dialog
- Test photo can still be added

#### Preserving User-Entered Values
- Test existing values not overwritten without confirmation
- Test conflict dialog shown
- Test user can keep current values

#### First-Photo vs Subsequent-Photo Behavior
- Test first photo shows confirmation dialog
- Test subsequent photos do not show dialog
- Test subsequent photos do NOT show repeated notifications
- Test explicit "Use photo details" action for any photo

#### Add Catch vs Edit Catch Behavior
- Test Add Catch: confirmation dialog on first photo for empty fields
- Test Add Catch: confirmation before replacing user-edited values
- Test Edit Catch: no automatic overwrite prompt
- Test Edit Catch: metadata only through explicit action
- Test Edit Catch: environmental-recalculation safeguards triggered

#### Additional Approved Tests
- Test timestamp with explicit positive UTC offset
- Test timestamp with explicit negative UTC offset
- Test timestamp with no offset
- Test malformed offset
- Test daylight-saving timezone photo
- Test southern and western GPS references
- Test zero coordinates rejection
- Test first photo without metadata followed by second photo with metadata
- Test photo metadata applied to existing catch with valid tide information
- Test user applying only date, only time, or only location
- Test user declining all fields
- Test photo removal after metadata has been applied
- Test lost-data recovery with metadata extraction
- Test metadata extraction failure while photo attachment still succeeds

### 15.2 Physical-Device Tests (Moto G15)

**Use real Moto G15 photos and controlled sample images with known EXIF values for physical-device verification.**

#### Camera Photo
- Take photo with camera
- Investigate actual Moto G15 camera output for EXIF metadata
- Verify GPS extraction if location tagging enabled
- Verify date/time extraction
- Verify confirmation dialog appears
- Verify user can choose which fields to apply
- Verify timezone handling
- Verify fallback when no EXIF metadata (retain form values)

#### Gallery Photo with GPS
- Select photo from gallery with GPS
- Verify GPS extraction
- Verify confirmation dialog appears
- Verify map preview shows location
- Verify user can apply or decline

#### Gallery Photo without GPS
- Select photo from gallery without GPS
- Verify no GPS extraction
- Verify confirmation dialog shows only date/time options
- Verify location not auto-populated
- Verify user can manually enter location

#### Historical Photo
- Select historical photo from different timezone
- Verify timezone offset preserved
- Verify no timezone shift applied
- Verify display as local time at capture location

#### Multiple Photos
- Add first photo with metadata
- Verify confirmation dialog appears
- Add second photo with different metadata
- Verify no repeated notifications
- Verify explicit "Use photo details" action works
- Verify user can switch to later photo

#### User Declining Extracted Values
- Select photo with metadata
- Decline all values in confirmation dialog
- Verify form fields unchanged
- Verify photo still added

#### User Applying Only Selected Values
- Select photo with date/time and location
- Apply only date/time
- Verify location not populated
- Verify date/time populated
- Test applying only date, only time, only location

#### Photo Recovery After Interruption
- Start camera, interrupt app
- Restart app
- Verify photo recovered
- Verify metadata extraction works
- Verify confirmation dialog appears

#### Imported HEIC or Cloud-Hosted Photo
- Select HEIC photo (if produced by Moto G15)
- Select photo from Google Photos
- Select photo from WhatsApp
- Verify metadata extraction works or fails gracefully
- Verify photo can still be added
- Verify format limitations reported

#### Additional Approved Physical-Device Tests
- Test JPEG selected from local storage
- Test HEIC/HEIF from Moto G15 if produced
- Test content-provider selection (Google Photos)
- Test copied or temporary files from image_picker
- Test images with metadata stripped during compression
- Test photo metadata applied to existing catch with valid tide information
- Test photo removal after metadata has been applied
- Test lost-data recovery with metadata extraction
- Test metadata extraction failure while photo attachment still succeeds

---

## 16. Implementation Sequence

### Stage 4A: Investigation and Diagnostics (CURRENT)
**Duration:** 2-3 hours

**Approved Scope:**
- Inspect the current implementation
- Build the dedicated metadata extraction result model
- Create controlled parsing tests
- Inspect representative Moto G15 and gallery-photo metadata
- Document confirmed package and format limitations
- Do NOT yet alter Add Catch or Edit Catch behaviour

**Tasks:**
1. ✅ Create PhotoMetadataResult model with enums for status, source, confidence
2. ✅ Create controlled parsing tests for GPS conversion, priority rules, timezone handling
3. Build diagnostic tool to read and display all EXIF tags from test photos
4. Test on Moto G15 with real photos:
   - Camera photo with GPS
   - Gallery photo with GPS
   - Gallery photo without GPS
   - Historical photo
   - Cloud-hosted photo (Google Photos, WhatsApp)
5. Test image format support:
   - JPEG from local storage
   - HEIC/HEIF from Moto G15 (if produced)
   - Content-provider selection
   - Temporary files from image_picker
6. Document actual EXIF tags found in each test image
7. Document parsed date, time, timezone and GPS results
8. Document image formats successfully supported
9. Document content-URI and temporary-file behaviour
10. Document confirmed causes of previous failures
11. Document any changes needed to approved Stage 4B–4E design

**Deliverables:**
- PhotoMetadataResult model ✅
- Controlled parsing tests ✅
- Stage 4A investigation report
- Test photo EXIF tag inventory
- Package and format limitations documentation

**Approval Required:** After Stage 4A before implementing Stage 4B

---

### Stage 4B: Reliable EXIF Parsing Service (PENDING APPROVAL)
**Duration:** 4-6 hours

**Tasks:**
1. Create PhotoMetadataService class
2. Implement EXIF reading with priority rules
3. Implement GPS coordinate extraction and validation
4. Implement timezone offset parsing
5. Implement validation and error handling
6. Write unit tests

**Deliverables:**
- PhotoMetadataService class
- Unit tests
- Error handling

**Approval Required:** Before proceeding to Stage 4C

---

### Stage 4C: User Confirmation and Conflict Handling (PENDING APPROVAL)
**Duration:** 6-8 hours

**Tasks:**
1. Design confirmation dialog UI with checkboxes
2. Implement conflict detection
3. Implement confirmation dialog
4. Implement conflict dialog for existing values
5. Integrate with photo workflow
6. Implement subsequent photo behavior
7. Add diagnostic logging

**Deliverables:**
- Confirmation dialog component
- Conflict handling logic
- Integration with photo workflow

**Approval Required:** Before proceeding to Stage 4D

---

### Stage 4D: Camera, Gallery and Lost-Data Integration (PENDING APPROVAL)
**Duration:** 4-6 hours

**Tasks:**
1. Update _takePhoto() to use new service
2. Update _pickImage() to use new service
3. Update _retrieveLostData() to use new service
4. Verify lost-data workflow preserved
5. Test camera photo behavior
6. Test gallery photo behavior
7. Test recovered photo behavior
8. Fix any camera navigation issues
9. Test on Moto G15

**Deliverables:**
- Updated photo workflows
- Camera navigation fix (if needed)
- Physical-device test results

**Approval Required:** Before proceeding to Stage 4E

---

### Stage 4E: Physical-Device Verification and Documentation (PENDING APPROVAL)
**Duration:** 4-6 hours

**Tasks:**
1. Perform all physical-device test scenarios
2. Verify timezone handling
3. Verify conflict resolution
4. Verify error handling
5. Remove temporary diagnostic logging
6. Update documentation
7. Increment build number
8. Run automated tests
9. Run Flutter analysis
10. Build release APK
11. Deploy to Moto G15
12. Final verification

**Deliverables:**
- Physical-device test report
- Implementation documentation
- Release APK
- Stage 4 acceptance

---

**Current Status:** Stage 4A in progress. Stages 4B-4E pending approval after Stage 4A completion.

---

## 17. Decisions Approved

The following decisions have been approved by the user:

### 17.1 Date/Time Priority Order 
**Approved:** DateTimeOriginal > DateTimeDigitized > DateTime
**File modification timestamp:** Only as low-confidence fallback with explicit label
**Label:** "File date: 3 August 2026, 2:35 PM — this may not be when the photo was taken"
**Requirement:** Do NOT automatically populate catch date/time from file timestamp without confirmation

### 17.2 Timezone Handling for Missing Offset 
**Approved:** Preserve clock value exactly as recorded, classify as unspecified local photo time
**Warning:** "The photo does not include timezone information. Check that the time is correct."
**Requirement:** Do NOT assume Darwin time, device current timezone, or catch location timezone
**Requirement:** Do NOT perform timezone conversion

### 17.3 User Confirmation Interface 
**Approved:** Checkboxes for individual field selection
**Checkboxes:** Use photo date, Use photo time, Use photo location
**Buttons:** Apply selected details, Keep current catch details
**Requirement:** Show both current and photo values if replacement would occur
**Requirement:** Do NOT use separate buttons - checkboxes provide clearer interface

### 17.4 Primary-Photo Behavior 
**Approved:** Only first photo may automatically trigger "Photo details found" prompt
**Requirement:** Subsequent photos must never silently update catch metadata
**Requirement:** Subsequent photos should NOT produce repeated notifications
**Requirement:** Provide explicit "Use photo details" action for any photo

### 17.5 Explicit "Use Photo Details" Action 
**Approved:** YES, implement explicit action
**Available for:** Any photo, not just first
**Requirement:** Clearly show which existing values would change

### 17.6 Conflict Handling 
**Approved:** Show conflict dialog when extracted values differ from existing form values
**Add Catch:** First photo may offer metadata for empty fields, always confirm before replacing user-edited values
**Edit Catch:** No automatic overwrite prompt, metadata only through explicit action
**Requirement:** Applying new date/time/location must use existing environmental-recalculation safeguards

### 17.7 Multiple-Photo Rule 
**Approved:** Do NOT combine date from one photo with location from another
**Requirement:** Each metadata application must come from one identified photo
**Requirement:** Record primary photo independently from photo that supplied metadata

### 17.8 Camera Photo Timestamp 
**Approved:** Use photo timestamp from EXIF if reliably available
**Investigation Required:** Do NOT assume photos from Bragmat will reliably contain EXIF GPS or timestamp
**Fallback:** Retain Add Catch form's existing date/time/location if no EXIF metadata
**Requirement:** Do NOT replace form time with DateTime.now() after camera returns
**Requirement:** Do NOT substitute current device GPS while presenting it as photo GPS

### 17.9 Database Migration 
**Approved:** No database migration required
**Requirement:** Use existing fields

### 17.10 Metadata Source Tracking 
**Approved:** Extend coordinate_source to use stable internal values
**Stable Values:** manual, device_gps, photo_gps, favourite_spot, map_selected
**Caution:** Do not add photo_gps without confirming no breaking changes
**Requirement:** Inspect all reports, exports, and filters that reference coordinate_source
**CatchMedia.date_taken:** Can be used for EXIF timestamp, no conflict with existing usage

### 17.11 Implementation Sequence 
**Approved:** 5-stage sequence (4A through 4E) with approval at each stage
**Current:** Stage 4A only, await approval after Stage 4A before implementing 4B-4E

### 17.12 Location Validation 
**Approved:** Add validation for latitude between -90 and 90, longitude between -180 and 180
**Requirement:** Reject missing references, malformed rational values, zero coordinates (0,0), incomplete GPS tag sets
**Requirement:** Do NOT treat 0,0 as valid without explicit confirmation

### 17.13 Parsing Architecture 
**Approved:** Create dedicated immutable PhotoMetadataResult model
**Distinguish:** Value present/absent/malformed/rejected, timezone known/unknown, metadata source, confidence level
**Requirement:** Do not make UI infer metadata quality from NULL values alone

### 17.14 Applying Metadata 
**Approved:** Separate extraction from application
**Flow:** Extract → Validate → Present to user → Apply selected fields → Trigger recalculation → Leave photo attached even if metadata fails

### 17.15 Failure Handling 
**Approved:** Metadata failure must never prevent photo from being added
**Messages:** "No date, time or location details were found in this photo", "Some photo details could not be read", "The photo was added, but its location could not be used"
**Requirement:** Avoid technical EXIF terminology in user-facing messages

### 17.16 Diagnostic Logging 
**Approved:** Temporary diagnostics may record image format, tag names, priority tag selected, validation outcome, timezone present/absent, user application decisions
**Do NOT log:** Full file paths, raw photo contents, full precise GPS coordinates (unless essential for controlled test), unrelated EXIF fields, personal device information
**Requirement:** Remove temporary diagnostics before final accepted build

### 17.17 Testing Requirements 
**Approved:** Include additional tests for timestamp with positive/negative/no offset, malformed offset, daylight-saving timezone, southern/western GPS references, zero coordinates, first photo without metadata followed by second with metadata, photo metadata applied to existing catch with valid tide information, user applying only date/time/location, user declining all fields, photo removal after metadata applied, lost-data recovery with metadata extraction, metadata extraction failure while photo attachment succeeds
**Requirement:** Use real Moto G15 photos and controlled sample images with known EXIF values

### 17.18 Image Format and Access Testing 
**Approved:** Stage 4A must confirm actual support for JPEG from local storage, HEIC/HEIF from Moto G15 (if produced), Google Photos or content-provider selection, copied or temporary files from image_picker, images with metadata stripped during compression
**Requirement:** Read metadata from original accessible image before resizing, compression or copying
**Requirement:** If exif package cannot reliably parse a format, report limitation rather than silently falling back

---

**All design decisions approved. Proceeding with Stage 4A investigation.**

### Key Design Principles
1. **Never silently overwrite** user-entered values
2. **User confirmation** before applying metadata
3. **Clear distinction** between photo metadata and device location
4. **Primary photo only** may populate catch metadata
5. **Timezone preservation** for historical photos
6. **Graceful degradation** for missing or invalid metadata
7. **No database migration** (use existing fields)
8. **Privacy protection** in logging

### Implementation Complexity
- **Medium:** Requires new service, UI changes, conflict handling
- **No database changes:** Use existing schema
- **Backward compatible:** Existing data preserved
- **Testable:** Clear unit and physical-device test cases

### Estimated Effort
- **Stage 4A (Investigation):** 2-3 hours
- **Stage 4B (Service):** 4-6 hours
- **Stage 4C (UI/Conflict):** 6-8 hours
- **Stage 4D (Integration):** 4-6 hours
- **Stage 4E (Verification):** 4-6 hours
- **Total:** 20-29 hours

### Approval Required
Please review and approve:
1. Date/time priority order
2. Timezone handling approach
3. User confirmation interface design
4. Primary-photo behavior
5. Explicit "Use photo details" action
6. Conflict handling approach
7. Multiple-photo rule
8. Camera photo timestamp approach
9. No database migration decision
10. Metadata source tracking approach
11. Implementation sequence

**Do not begin implementation until approved.**
