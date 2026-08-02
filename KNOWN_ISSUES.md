# Known Issues

This document tracks known issues in the Bragmat application that have been observed but are not yet reproducible or resolved.

## Dundee Beach Cache Metadata Issue (Resolved)

**Status:** Resolved  
**Date:** 2026-08-02  
**Device:** Moto G15 (ZY32MLB4MB)  
**Build:** Release APK (v1.0.0+1)

### Description
When creating a new catch at Dundee Beach, the WorldTides source displayed "Not recorded" instead of "FES2022 model". The atlas metadata was correctly stored in the tide_cache but was not being properly reconstructed when retrieved from cache.

### Root Cause
The cached data stored metadata in `worldtides_*` fields (e.g., `worldtides_atlas`), but the `_parseStationInfo()` method expected the raw API response format with fields named `station`, `atlas`, `responseLat`, `responseLon`. When cached data was returned, it was passed directly to `_parseStationInfo()` without reconstructing the expected format, resulting in NULL values for all metadata fields.

### Fix
Added reconstruction logic in `WorldTidesService._fetchTideData()` to convert cached data format to the expected API response format:
```dart
final reconstructedData = {
  'extremes': cachedData['extremes'],
  'station': cachedData['worldtides_station'],
  'atlas': cachedData['worldtides_atlas'],
  'responseLat': cachedData['worldtides_response_lat'],
  'responseLon': cachedData['worldtides_response_lon'],
};
```

### Verification
After the fix, Dundee Beach catches correctly display "FES2022 model" as the WorldTides source.

### Related Code
- `lib/services/worldtides_service.dart` - `_fetchTideData()` method

---

## Camera Workflow Issue (Intermittent)

**Status:** Unconfirmed / Intermittent  
**Date:** 2026-08-02  
**Device:** Moto G15 (ZY32MLB4MB)  
**Build:** Release APK (v1.0.0+1)

### Description
On one occasion, launching the camera from a new catch returned the app to the Catches screen instead of returning to the Add Catch screen.

### Observed Behavior
- User tapped "Take Photo" on a new catch
- Camera launched successfully
- After taking the photo, the app unexpectedly returned to the Catches screen
- The captured photo was recovered and appeared when Add Catch was reopened
- User was able to continue with the catch entry normally

### Subsequent Testing Results
- Subsequent camera attempts worked correctly
- Choosing an existing photo from the gallery works as expected
- Taking a photo while editing a catch with an existing photo works as expected
- The original unexpected return to the Catches screen could not be reproduced

### Diagnostic Findings
- The camera app launch may have caused the Flutter activity to be destroyed or the navigation stack to be modified
- The app's `didChangeAppLifecycleState` handler and `_retrieveLostData()` function successfully recovered the photo
- The issue appears to be related to Android activity lifecycle management during camera launch
- No direct connection to tide-reference implementation was found

### Notes
- This is classified as an intermittent issue that could not be reproduced
- Gallery selection and camera use in Edit mode work correctly
- The issue should only be reopened if the behavior recurs or becomes reproducible
- No code changes were made to address this issue

### Related Code
- `lib/screens/add_catch_screen.dart` - `_takePhoto()`, `_processPickedFile()`, `didChangeAppLifecycleState()`, `_retrieveLostData()`
