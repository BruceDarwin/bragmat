# Bragmat Development Handover Document

**Project Name:** Bragmat  
**Version:** 1.0.0+1  
**Last Updated:** June 2026  
**Database Version:** 16

---

## 1. Project Overview

### Purpose
Bragmat is a mobile fishing log application designed for anglers to track their catches, fishing trips, and statistics. The app allows users to record detailed information about each catch including photos, GPS location, species, length, and fishing conditions.

### Current Vision
Bragmat serves as a personal fishing companion that helps anglers:
- Log catches with rich metadata (photos, location, species, length)
- Track fishing trips with journal entries and photos
- View comprehensive statistics about their fishing activities
- Manage favourite fishing spots for quick location access
- Export and backup their fishing data

### Planned Evolution Towards TEBS Competition
The application is designed to evolve into a competitive fishing platform supporting:
- **TEBS Competition Module:** Structured competitions with rules, scoring, and leaderboards
- **Species Leaderboards:** Track and compare catches across users
- **Achievements System:** Unlock badges and milestones for fishing accomplishments
- **Cloud Sync:** Share data across devices and enable social features
- **Competition Records:** Track official competition catches with verification

The current database schema and data models are designed to support these future features without major refactoring.

---

## 2. Technology Stack

### Core Technologies
- **Flutter Version:** SDK ^3.12.0
- **Dart:** ^3.12.0
- **Database:** SQLite (via sqflite ^2.3.0)
- **Target Platform:** Android (primary), iOS (future)

### Key Packages
- `sqflite: ^2.3.0` - Local SQLite database
- `path: ^1.9.0` - File path manipulation
- `image_picker: ^1.0.7` - Camera and gallery photo selection
- `exif: ^3.3.0` - EXIF data extraction from photos
- `path_provider: ^2.1.4` - Access to device file system
- `share_plus: 12.0.2` - Sharing functionality
- `shared_preferences: ^2.2.2` - Simple key-value storage
- `flutter_map: ^6.1.0` - Interactive map display
- `latlong2: ^0.9.0` - Latitude/longitude utilities
- `geolocator: ^10.1.0` - GPS location services
- `connectivity_plus: ^6.0.5` - Network connectivity monitoring

### Testing Environment
- **Primary Test Device:** Moto G15 (Android)
- **Screen Resolution:** 1080x2400
- **Performance Status:** Application runs smoothly on low-end device
- **Known Device Issues:** Camera issues on Edit Catch screen (see Known Issues)

---

## 3. Current Application Features

### Catch Management

#### Add/Edit/Delete Catch
- Full CRUD operations for fishing catches
- Edit screen allows modification of all catch details
- Delete with confirmation dialog

#### Multiple Photos
- Support for multiple photos per catch
- Primary photo designation
- Photo viewer with zoom and pan
- EXIF data extraction (date taken, GPS coordinates)
- Photo deletion with cascade to database

#### Date/Time Caught
- Separate date/time fields for when fish was caught
- Defaults to current date/time
- Can be manually adjusted
- Stored separately from creation timestamp

#### GPS Location Capture
- Three coordinate sources:
  - Device GPS (current location)
  - Map selection (pick on map)
  - Favourite Fishing Spots (pre-saved locations)
- Latitude/longitude stored with coordinate source tracking
- Location name field for human-readable location

#### Favourite Fishing Spots
- Pre-saved fishing locations with coordinates
- Quick selection in Add Catch screen
- Dropdown selection in location input
- Automatically clears when using GPS or map selection
- Managed from Settings screen

#### Default Fish Type
- User can set a default fish species in settings
- Automatically selected when adding new catch
- Stored in SharedPreferences
- Applied via FishTypePreferenceService

#### Current Location
- GPS button to get current device location
- Uses Geolocator for accurate positioning
- Permission handling for location services
- Fallback to manual entry if GPS unavailable

#### Map Location Selection
- Interactive map to pick catch location
- Tap to select coordinates
- Returns to Add Catch screen with selected location
- Uses flutter_map with OpenStreetMap tiles

### Fishing Buddies

#### Functionality Implemented
- Add/Edit/Delete fishing buddies
- Select buddy when adding catch
- Associates catches with fishing companions
- Default "Me" buddy pre-created

#### Data Model
```dart
class FishingBuddy {
  final int? id;
  final String name;
}
```
- Simple name-based model
- Unique constraint on name
- Referenced by catches via fishing_buddy_id

### Fishing Trips

#### Trip Management
- Create fishing trips with name, dates, location, notes
- Edit and delete trips
- Trip list with sorting by date
- Trip details screen with comprehensive information

#### Current Trip
- Persistent "current trip" selection
- Stored via CurrentTripService using SharedPreferences
- Quick access to active trip when adding catches
- Can set/clear current trip from Fishing Trips screen

#### Trip Journal
- Add journal entries to trips
- Multiple journal types (general, catch, weather, notes)
- Rich text entries with title and body
- Timestamped entries
- Photo support for journal entries

#### Trip Photos
- Multiple photos per trip
- Primary photo designation
- Photo viewer integration
- EXIF data extraction
- Cascade delete on trip deletion

### Maps & Locations

#### Catch Map
- Displays all catches on interactive map
- Markers for each catch location
- Tap marker to view catch details
- Different marker styles for catches
- Filter by species (future enhancement)

#### Favourite Fishing Spots
- Display favourite spots on map
- Separate marker style from catches
- Tap to view spot details
- Managed from Settings screen

#### Offline Behaviour
- Uses OpenStreetMap tiles
- Requires internet connection for map tiles
- Offline mode banner displayed when no connectivity
- GPS still works offline (device GPS, not network)
- Known limitation: Map tiles not cached for offline use

#### Known Limitations
- Map tiles require internet connection
- No offline tile caching implemented
- Large number of markers may impact performance
- Map tile loading can be slow on poor connections

### Statistics

#### Statistics Dashboard v2
- Comprehensive statistics screen with multiple sections
- Activity summary (total catches, trips, species, photos)
- Highlights section with key metrics
- Species statistics with detailed breakdowns
- Location summary with productivity metrics

#### Personal Best
- Displays largest fish ever caught
- Shows species, length, date, location
- Primary photo display
- Tap to view catch details
- Renamed from "Largest Fish" to "Personal Best"

#### Species Records
- Shows largest catch per species
- Top 10 displayed with "View All" button (placeholder)
- Each record shows: species, length, date, location, photo
- Sorted by length descending
- Tap to view catch details
- Uses Wrap layout for chips to prevent overflow

#### Species Statistics
- Shows top 5 species by catch count
- Displays: total catches, average length, largest length, smallest length
- Uses Wrap layout for statistic chips
- Handles long fish names with ellipsis overflow
- Smallest length tracking added in latest update

### Search & Filtering

#### Search Functionality
- Search catches by fish type, location, notes
- Real-time search as user types
- Search across multiple fields

#### Filters
- Filter by fish species
- Filter by date range
- Filter by fishing buddy
- Filter by trip

#### Sorting
- Sort by date (newest/oldest)
- Sort by length (largest/smallest)
- Sort by species

#### Pagination
- Not currently implemented
- All catches loaded at once
- Consider pagination for large datasets (future)

### Backup & Restore

#### Backup Format
- JSON format containing all database data
- Includes: catches, fish types, fishing buddies, trips, journal entries, media references, favourite spots
- File stored in app documents directory
- Filename includes timestamp

#### Restore Functionality
- Restore from JSON backup file
- Validates backup format
- Clears existing data before restore
- Preserves database integrity
- Foreign key relationships maintained

#### CSV Export
- Export catches to CSV format
- Includes all catch fields
- Suitable for spreadsheet analysis
- Does not include photos (file paths only)

---

## 4. Database Schema

### Current Database Version
**Version:** 16

### Tables

#### catches
Main table storing fishing catch records.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `fish_type` (TEXT) - Species of fish
- `length_cm` (INTEGER) - Length in centimeters
- `notes` (TEXT) - User notes about the catch
- `created_at` (TEXT) - Timestamp when record was created
- `date_caught` (TEXT) - When the fish was actually caught
- `image_path` (TEXT) - Legacy single photo path (deprecated)
- `photo_datetime` (TEXT) - EXIF datetime from photo
- `latitude` (REAL) - GPS latitude
- `longitude` (REAL) - GPS longitude
- `location` (TEXT) - Human-readable location name
- `fishing_buddy_id` (INTEGER) - Foreign key to fishing_buddies
- `trip_id` (INTEGER) - Foreign key to fishing_trips
- `coordinate_source` (TEXT) - Source of coordinates (GPS/Map/Favourite)

**Relationships:**
- fishing_buddy_id → fishing_buddies(id)
- trip_id → fishing_trips(id)

#### fish_types
Stores available fish species.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `name` (TEXT UNIQUE NOT NULL) - Species name

**Default Data:**
- Barramundi
- Mangrove Jack
- Saratoga
- Jewfish
- Queenfish
- Red Snapper

#### fishing_buddies
Stores fishing companions.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `name` (TEXT UNIQUE NOT NULL) - Buddy name

**Default Data:**
- "Me" (default user)

#### catch_media
Stores multiple photos per catch (replaces single image_path).

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `catch_id` (INTEGER NOT NULL) - Foreign key to catches
- `file_path` (TEXT NOT NULL) - Path to photo file
- `media_type` (TEXT NOT NULL DEFAULT 'photo') - Type of media
- `role` (TEXT NOT NULL DEFAULT 'other') - 'primary' or 'other'
- `date_taken` (TEXT) - EXIF date from photo
- `latitude` (REAL) - GPS from photo EXIF
- `longitude` (REAL) - GPS from photo EXIF
- `created_at` (TEXT NOT NULL) - When media record was created

**Relationships:**
- catch_id → catches(id) ON DELETE CASCADE

#### fishing_trips
Stores fishing trip records.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `name` (TEXT NOT NULL) - Trip name
- `start_date` (TEXT NOT NULL) - Trip start date
- `end_date` (TEXT) - Trip end date (nullable)
- `location` (TEXT) - Trip location
- `notes` (TEXT) - Trip notes
- `created_at` (TEXT NOT NULL) - When trip was created

#### trip_media
Stores photos for trips.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `trip_id` (INTEGER NOT NULL) - Foreign key to fishing_trips
- `file_path` (TEXT NOT NULL) - Path to photo file
- `media_type` (TEXT NOT NULL DEFAULT 'photo') - Type of media
- `role` (TEXT NOT NULL DEFAULT 'other') - 'primary' or 'other'
- `date_taken` (TEXT) - EXIF date from photo
- `latitude` (REAL) - GPS from photo EXIF
- `longitude` (REAL) - GPS from photo EXIF
- `created_at` (TEXT NOT NULL) - When media record was created

**Relationships:**
- trip_id → fishing_trips(id) ON DELETE CASCADE

#### trip_journal
Stores journal entries for trips.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `trip_id` (INTEGER NOT NULL) - Foreign key to fishing_trips
- `journal_date_time` (TEXT NOT NULL) - When entry was made
- `journal_type` (TEXT NOT NULL DEFAULT 'general') - Type of entry
- `title` (TEXT NOT NULL) - Entry title
- `entry_text` (TEXT NOT NULL) - Entry content
- `created_at` (TEXT NOT NULL) - When entry was created
- `updated_at` (TEXT NOT NULL) - When entry was last updated

**Relationships:**
- trip_id → fishing_trips(id) ON DELETE CASCADE

#### journal_media
Stores photos for journal entries.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `journal_entry_id` (INTEGER NOT NULL) - Foreign key to trip_journal
- `file_path` (TEXT NOT NULL) - Path to photo file
- `media_type` (TEXT NOT NULL DEFAULT 'photo') - Type of media
- `is_primary` (INTEGER NOT NULL DEFAULT 0) - Primary photo flag
- `date_taken` (TEXT) - EXIF date from photo
- `latitude` (REAL) - GPS from photo EXIF
- `longitude` (REAL) - GPS from photo EXIF
- `created_at` (TEXT NOT NULL) - When media record was created

**Relationships:**
- journal_entry_id → trip_journal(id) ON DELETE CASCADE

#### favourite_spots
Stores user's favourite fishing locations.

**Columns:**
- `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
- `name` (TEXT NOT NULL) - Spot name
- `latitude` (REAL NOT NULL) - GPS latitude
- `longitude` (REAL NOT NULL) - GPS longitude
- `notes` (TEXT) - Notes about the spot

**Added in:** Database version 16

---

## 5. Current Navigation Structure

### Main Navigation (Bottom Navigation Bar)
The app uses a 6-tab bottom navigation bar:

1. **Catches** (index 0)
   - Screen: `CatchListScreen`
   - Displays list of all catches
   - Search and filter functionality
   - Tap to view catch details

2. **Add** (index 1)
   - Screen: `AddCatchScreen`
   - Add new fishing catch
   - Auto-switches to Catches tab after saving

3. **Stats** (index 2)
   - Screen: `StatisticsScreen`
   - Statistics dashboard v2
   - Personal Best, Species Records, Species Statistics

4. **Trips** (index 3)
   - Screen: `FishingTripsScreen`
   - List of fishing trips
   - Current trip management
   - Tap to view trip details

5. **Map** (index 4)
   - Screen: `CatchMapScreen`
   - Interactive map of catches
   - Favourite spots display
   - Tap markers for details

6. **Settings** (index 5)
   - Screen: `SettingsScreen`
   - App settings and configuration
   - Navigation to management screens

### Settings Sections
From Settings screen, users can access:

- **Theme Selection** - Choose color palette
- **Default Fish Type** - Set default species for new catches
- **Manage Fish Types** - Add/remove fish species
- **Manage Fishing Buddies** - Add/remove fishing companions
- **Favourite Fishing Spots** - Manage saved locations
- **Backup & Restore** - Data backup and restore
- **CSV Export** - Export catches to CSV
- **Clear All Data** - Reset application data

### Secondary Screens
- `CatchDetailsScreen` - View detailed catch information
- `TripDetailsScreen` - View detailed trip information
- `AddTripScreen` - Add new fishing trip
- `JournalEntryScreen` - Add/edit journal entries
- `PhotoViewerScreen` - View photos with zoom
- `LocationPickerScreen` - Pick location on map
- `FavouriteSpotsScreen` - Manage favourite spots
- `AddEditFavouriteSpotScreen` - Add/edit favourite spot

---

## 6. Real Device Testing Findings

### Moto G15 Testing Status
- **Device:** Moto G15 (Android)
- **Screen:** 1080x2400 pixels
- **Performance:** Application runs smoothly
- **Testing Duration:** Extensive testing during development

### Issues Encountered

#### Camera Issues on Edit Catch
- **Problem:** Camera functionality fails when editing existing catches
- **Symptoms:** Camera may not open or photo selection fails
- **Workaround:** Delete and re-add catch with new photos
- **Status:** Known issue, requires investigation
- **Priority:** Medium

#### GPS Findings
- **Performance:** GPS works reliably on Moto G15
- **Accuracy:** Acceptable accuracy for fishing locations
- **Permission:** Location permission handling works correctly
- **Offline:** Device GPS works without internet connection
- **Recommendation:** Continue using device GPS as primary method

#### Offline Map Behaviour
- **Map Tiles:** Require internet connection to load
- **Offline Mode:** Banner displayed when no connectivity
- **GPS:** Works offline (device GPS, not network-based)
- **Limitation:** No tile caching implemented
- **User Impact:** Map shows blank tiles when offline
- **Future:** Consider offline tile caching for better offline experience

#### Performance on Low-End Device
- **Scrolling:** Smooth scrolling in catch lists
- **Statistics:** Statistics calculations complete quickly
- **Map:** Map rendering acceptable, may slow with many markers
- **Photos:** Photo loading from file system is fast
- **Recommendation:** Consider pagination for large datasets

### Lessons Learned

#### UI Layout
- **RenderFlex Overflow:** Common issue on narrow screens
- **Solution:** Use Wrap widgets for chip rows, add maxLines/overflow to text
- **Best Practice:** Test on actual device, not just emulator

#### Photo Handling
- **EXIF Data:** Valuable for auto-populating date and location
- **File Paths:** Store relative paths where possible
- **Media Management:** Separate media table works well for multiple photos

#### Database Performance
- **Statistics:** Single-pass calculations are efficient
- **Indexes:** Consider adding indexes for frequently queried fields
- **Migrations:** Keep migration logic simple and test thoroughly

---

## 7. Current Known Issues

### Open Bugs

#### Map Tile Loading
- **Severity:** Low
- **Description:** Map tiles load slowly on poor connections
- **Impact:** Poor user experience in areas with weak signal
- **Workaround:** Wait for tiles to load or use GPS coordinates only
- **Status:** Acceptable for current use case

### UI Improvements Desired

#### Species Records "View All" Screen
- **Status:** Placeholder implemented
- **Description:** "View All" button shows "coming soon" snackbar
- **Requirement:** Full screen showing all species records
- **Priority:** Medium

#### Pagination for Large Datasets
- **Status:** Not implemented
- **Description:** All catches loaded at once
- **Impact:** May impact performance with 1000+ catches
- **Priority:** Low (current performance acceptable)

#### Offline Map Tile Caching
- **Status:** Not implemented
- **Description:** Map tiles not cached for offline use
- **Impact:** Blank map when offline
- **Priority:** Low (GPS still works offline)

### Technical Debt

#### Legacy image_path Field
- **Status:** Deprecated but not removed
- **Description:** catches.image_path replaced by catch_media table
- **Impact:** Database has unused column
- **Priority:** Low (no negative impact)
- **Action:** Remove in future migration

#### Code Organization
- **Status:** Generally well-organized
- **Description:** Some screens are large (500+ lines)
- **Impact:** Maintainability
- **Priority:** Low
- **Action:** Consider breaking large screens into smaller widgets

---

## 8. Future Backlog

### High Priority

#### TEBS Competition Module
- **Description:** Implement structured competition system
- **Features:**
  - Competition creation and management
  - Competition rules and scoring
  - Competition-specific catch records
  - Leaderboards and rankings
  - Competition timeline management
- **Database Impact:** New tables for competitions, competition_entries, competition_rules
- **UI Impact:** New screens for competition management
- **Dependencies:** Species Records data structure already supports this

#### Achievements System
- **Description:** Gamification with badges and milestones
- **Features:**
  - Achievement definitions and criteria
  - Achievement tracking and unlocking
  - Achievement display in profile
  - Notification system for achievements
- **Database Impact:** New tables for achievements, user_achievements
- **UI Impact:** Profile screen, achievement popups

#### Species Leaderboards
- **Description:** Compare catches across users
- **Features:**
  - Leaderboard by species
  - Leaderboard by location
  - Leaderboard by time period
  - User ranking display
- **Database Impact:** May require user accounts and cloud sync
- **UI Impact:** Leaderboard screens, ranking displays
- **Dependencies:** Cloud sync infrastructure

### Medium Priority

#### Cloud Sync
- **Description:** Sync data across devices
- **Features:**
  - User account system
  - Cloud storage integration
  - Conflict resolution
  - Sync status indicators
- **Database Impact:** Add sync status fields to tables
- **UI Impact:** Account management, sync settings
- **Complexity:** High - requires backend infrastructure

#### Offline Fishing Mode Improvements
- **Description:** Better offline experience
- **Features:**
  - Offline map tile caching
  - Offline data queueing
  - Sync when online
  - Offline indicators
- **Database Impact:** Add sync queue table
- **UI Impact:** Enhanced offline mode banner
- **Complexity:** Medium

#### Enhanced Search & Filtering
- **Description:** More powerful search capabilities
- **Features:**
  - Advanced search filters
  - Saved search queries
  - Search by multiple criteria
  - Search within journal entries
- **Database Impact:** May require full-text search indexes
- **UI Impact:** Enhanced search UI
- **Complexity:** Low

### Low Priority

#### APK Release Preparation
- **Description:** Prepare for public release
- **Features:**
  - App signing
  - Play Store listing
  - Privacy policy
  - Terms of service
  - Beta testing program
- **Database Impact:** None
- **UI Impact:** None
- **Complexity:** Low (administrative)

#### iOS Support
- **Description:** Port to iOS platform
- **Features:**
  - iOS-specific adaptations
  - App Store submission
  - iOS testing
- **Database Impact:** None (SQLite works on iOS)
- **UI Impact:** iOS-specific UI adjustments
- **Complexity:** Medium

#### Social Features
- **Description:** Share catches with friends
- **Features:**
  - Share to social media
  - In-app sharing
  - Catch of the day
  - Community features
- **Database Impact:** May require social tables
- **UI Impact:** Sharing UI, community screens
- **Complexity:** Medium (depends on cloud sync)

#### Weather Integration
- **Description:** Add weather data to catches
- **Features:**
  - Weather at time of catch
  - Weather history
  - Weather forecasts for trips
- **Database Impact:** Add weather fields to catches/trips
- **UI Impact:** Weather display in catch/trip details
- **Complexity:** Medium (requires weather API)

---

## 9. Suggested Next Development Priorities

### Priority 1: Fix Camera Issues on Edit Catch
- **Estimated Time:** 2-4 hours
- **Impact:** High - affects core functionality
- **Complexity:** Medium
- **Action:** Debug camera/photo picker in edit mode
- **Dependencies:** None

### Priority 2: Implement Species Records "View All" Screen
- **Estimated Time:** 4-6 hours
- **Impact:** Medium - completes current feature
- **Complexity:** Low
- **Action:** Create full-screen species records list
- **Dependencies:** None (data already available)

### Priority 3: Add Pagination for Catch List
- **Estimated Time:** 6-8 hours
- **Impact:** Medium - improves performance with large datasets
- **Complexity:** Medium
- **Action:** Implement lazy loading for catch list
- **Dependencies:** None

### Priority 4: Implement Offline Map Tile Caching
- **Estimated Time:** 8-12 hours
- **Impact:** Medium - improves offline experience
- **Complexity:** High
- **Action:** Cache map tiles for offline use
- **Dependencies:** flutter_map tile caching packages

### Priority 5: Add Achievements System
- **Estimated Time:** 16-24 hours
- **Impact:** High - adds gamification
- **Complexity:** Medium
- **Action:** Design achievement system, implement tracking
- **Dependencies:** None

### Priority 6: Implement Cloud Sync Infrastructure
- **Estimated Time:** 32-40 hours
- **Impact:** High - enables multi-device and social features
- **Complexity:** High
- **Action:** Design sync architecture, implement backend
- **Dependencies:** Backend infrastructure decision

### Priority 7: Implement TEBS Competition Module
- **Estimated Time:** 40-48 hours
- **Impact:** High - core future feature
- **Complexity:** High
- **Action:** Design competition system, implement UI
- **Dependencies:** Cloud sync (optional for local competitions)

### Priority 8: Implement Species Leaderboards
- **Estimated Time:** 16-24 hours
- **Impact:** Medium - adds social comparison
- **Complexity:** Medium
- **Action:** Design leaderboard system, implement UI
- **Dependencies:** Cloud sync or local-only version

### Priority 9: Enhanced Search & Filtering
- **Estimated Time:** 8-12 hours
- **Impact:** Low - improves usability
- **Complexity:** Low
- **Action:** Add advanced filters, saved searches
- **Dependencies:** None

### Priority 10: Prepare for APK Release
- **Estimated Time:** 8-12 hours
- **Impact:** High - enables distribution
- **Complexity:** Low
- **Action:** App signing, Play Store preparation, documentation
- **Dependencies:** Final testing on target devices

---

## 10. Lessons Learned

### What Worked Well

#### Database Design
- **Foreign Key Relationships:** Proper use of foreign keys with CASCADE delete ensures data integrity
- **Separate Media Tables:** Storing media in separate tables (catch_media, trip_media) provides flexibility
- **Migration Strategy:** Incremental database versioning with upgrade logic works well
- **Lesson:** Continue using this pattern for future features

#### Service Layer Pattern
- **ThemeService:** Centralized theme management works well
- **ConnectivityService:** Network monitoring is clean and reusable
- **CurrentTripService:** Simple SharedPreferences wrapper for persistent state
- **Lesson:** Continue using service classes for cross-screen state

#### UI Component Reuse
- **Detail Chips:** _buildDetailChip method reused across multiple screens
- **Photo Handling:** Consistent photo viewer and error handling
- **Icon Widgets:** Default icons for missing photos provide good UX
- **Lesson:** Extract reusable widgets to reduce code duplication

#### State Management
- **setState Pattern:** Simple setState works well for current app complexity
- **Callback Pattern:** onCatchSaved callback for navigation works cleanly
- **Lesson:** Consider state management (Provider/Riverpod) if complexity grows

### What Should Be Avoided

#### RenderFlex Overflow Issues
- **Problem:** Multiple overflow errors on narrow screens
- **Cause:** Fixed-width widgets in Row without proper constraints
- **Solution:** Use Wrap widgets, add maxLines/overflow to text
- **Lesson:** Always test on actual device, use flexible layouts

#### Camera on Edit Screen
- **Problem:** Camera fails when editing catches
- **Cause:** Unknown (needs investigation)
- **Lesson:** Test camera functionality thoroughly on edit screens

#### Large Screen Files
- **Problem:** Some screens exceed 500 lines
- **Cause:** Too much logic in single widget
- **Lesson:** Break large screens into smaller, reusable widgets

#### Legacy Fields
- **Problem:** image_path field deprecated but not removed
- **Cause:** Fear of breaking existing data
- **Lesson:** Clean up deprecated fields in migrations

### Development Patterns to Continue

#### Database Helper Pattern
- Single DatabaseHelper instance with singleton pattern
- Clear separation of CRUD methods
- Consistent error handling
- **Continue:** This pattern works well

#### Model Classes
- Separate model classes (Catch, FishingBuddy, FavouriteSpot, etc.)
- fromMap/toMap methods for serialization
- **Continue:** Keep models separate from UI

#### File Organization
- Clear separation: models/, screens/, services/, database/
- Consistent naming conventions
- **Continue:** Maintain this structure

#### Testing on Real Device
- Regular testing on Moto G15 caught issues early
- Performance testing on low-end device valuable
- **Continue:** Test on target hardware throughout development

#### Incremental Development
- Features added incrementally with database migrations
- Each feature tested before moving to next
- **Continue:** This approach reduces risk

---

## Appendix: Quick Reference

### Key File Locations

#### Database
- `lib/database/database_helper.dart` - All database operations
- `lib/models/` - Data models

#### Screens
- `lib/screens/catch_list_screen.dart` - Main catch list
- `lib/screens/add_catch_screen.dart` - Add/edit catch
- `lib/screens/statistics_screen.dart` - Statistics dashboard
- `lib/screens/fishing_trips_screen.dart` - Trip management
- `lib/screens/catch_map_screen.dart` - Map view
- `lib/screens/settings_screen.dart` - Settings

#### Services
- `lib/services/theme_service.dart` - Theme management
- `lib/services/connectivity_service.dart` - Network monitoring
- `lib/services/current_trip_service.dart` - Current trip state
- `lib/services/backup_service.dart` - Backup/restore
- `lib/services/fish_type_preference_service.dart` - Default fish type

### Common Commands

#### Run App
```bash
flutter run
```

#### Build APK
```bash
flutter build apk --release
```

#### Clean Build
```bash
flutter clean
flutter pub get
```

#### Database Migration
When adding new tables or columns:
1. Increment `_databaseVersion` in DatabaseHelper
2. Add migration logic in `_onUpgrade` method
3. Test migration from previous version

### Important Notes

#### Photo Storage
- Photos stored in app's documents directory
- Use path_provider to get correct path
- Handle missing files gracefully (default icons)

#### GPS Permissions
- Add location permissions to AndroidManifest.xml
- Handle permission requests in app
- Provide fallback when GPS unavailable

#### Theme System
- Multiple color palettes available
- User selection persisted in SharedPreferences
- ThemeService handles theme changes globally

---

**End of Handover Document**
