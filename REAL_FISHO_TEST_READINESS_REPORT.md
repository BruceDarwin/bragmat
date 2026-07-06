# Real Fisho Test Readiness Report

**Phase 4B – Tide Polish and Real-World Testing Readiness**

**Date:** July 6, 2026  
**Status:** Ready for Testing  
**Target Testers:** ~10 Fishos

---

## Executive Summary

Bragmat is now ready for real-world testing by approximately 10 fishos. The tide information system has been polished to provide credible, useful, and well-presented tide data. The application supports both official WorldTides API data and manual tide entry, with clear separation between the two sources. API usage is controlled through caching and user warnings.

---

## 1. Tide Information Captured

### 1.1 Official WorldTides Data (Automatic)

When WorldTides API is configured and available, the following data is automatically captured:

- **Tide Context Phrase**: Human-readable description (e.g., "2 hours 15 minutes before the nearest high tide of 6.50 m at 3:45 PM")
- **Reference Tide Event**: Type (High/Low), time, height, relation to catch time (Before/After)
- **Previous Tide Event**: Type, time, height
- **Next Tide Event**: Type, time, height
- **Minutes from Reference Event**: Time difference between catch and reference tide
- **Data Source**: "WorldTides"
- **Confidence Level**: "High" (for official API data)
- **Station Information**: Name and distance (when available from API)

### 1.2 Manual Tide Data (User-Entered)

Users can manually enter tide information when WorldTides is unavailable or they prefer manual entry:

- **Reference Tide Event**: Type (High/Low), time, height, relation to catch time
- **Previous Tide Event**: Type, time, height (optional)
- **Next Tide Event**: Type, time, height (optional)
- **Tide Station**: Optional station name
- **Legacy Manual Fields**: Tide stage, strength, movement, height, notes (preserved for backward compatibility)
- **Data Source**: "Manual"
- **Confidence Level**: "Medium" (for manual entry)

### 1.3 Legacy Manual Fields (Preserved)

The following legacy manual tide fields are preserved for backward compatibility:

- Tide Stage (e.g., "Incoming", "Outgoing", "Slack")
- Tide Strength (e.g., "Spring", "Neap")
- Tide Movement (e.g., "Run-in", "Run-out", "Slack")
- Tide Height (meters)
- Tide Notes (free text)
- Tide Station (free text)

---

## 2. Tide Information Displayed

### 2.1 Catch Details Screen

#### Official Tide Context Card (Blue)
- **Header**: "Official Tide Context" with wave icon
- **Source Label**: "Source: WorldTides"
- **Context Phrase**: Bold, prominent display
- **Previous Tide**: Type, height, time (if available)
- **Next Tide**: Type, height, time (if available)
- **Styling**: Blue background with blue border

#### Manual Tide Context Card (Orange)
- **Header**: "Manual Tide Context" with edit icon
- **Source Label**: "Source: Manual"
- **Context Phrase**: Bold, prominent display
- **Previous Tide**: Type, height, time (if available)
- **Next Tide**: Type, height, time (if available)
- **Styling**: Orange background with orange border

#### Legacy Manual Tide Observation Card (Orange)
- **Header**: "Manual Tide Observation" with edit icon
- **Fields**: Stage, strength, movement, height, notes (if entered)
- **Styling**: Orange background with orange border

#### Missing Tide Context (Grey)
- **Message**: "Tide context not available"
- **Styling**: Grey background with grey border

### 2.2 Add Catch Screen

#### Manual Tide Context Section
- **Label**: "Manual Tide Context (Optional)"
- **Subtitle**: "Enter tide information from tide charts if WorldTides is unavailable"
- **Fields**:
  - Reference Tide Event (dropdown: High/Low)
  - Reference Tide Height (meters)
  - Reference Tide Time (date/time picker)
  - Relation to Catch Time (dropdown: Before/After/Auto-detect)
  - Previous Tide (optional, dropdown: High/Low)
  - Previous Tide Height (optional, meters)
  - Previous Tide Time (optional, date/time picker)
  - Next Tide (optional, dropdown: High/Low)
  - Next Tide Height (optional, meters)
  - Next Tide Time (optional, date/time picker)

#### Official Tide Context Placeholder
- **Message**: "Official Tide Context will be fetched automatically when you save the catch with GPS coordinates"
- **Styling**: Grey info box

---

## 3. Manual vs. WorldTides Data Separation

### 3.1 Data Source Tracking

- **WorldTides Data**: Marked with `tideContextDataSource = 'WorldTides'`
- **Manual Data**: Marked with `tideContextDataSource = 'Manual'`
- **No Data**: `tideContextDataSource = null`

### 3.2 Display Separation

- **Official Context**: Displayed in blue card with "Source: WorldTides" label
- **Manual Context**: Displayed in orange card with "Source: Manual" label
- **Both Can Coexist**: If both manual and official data exist, both cards are shown separately

### 3.3 Data Preservation Rules

- **Manual data is never overwritten by WorldTides** unless the user explicitly re-enters manual data
- **WorldTides data is fetched only if no existing WorldTides context exists**
- **Legacy manual fields are preserved** during backfill operations
- **Manual tide context is preserved** during environmental data recalculation

### 3.4 User Choice

- Users can choose to enter manual tide data even when WorldTides is available
- Manual entry is useful when:
  - WorldTides API is not configured
  - User has local tide charts they trust more
  - User wants to record observed tide conditions
  - API quota is limited

---

## 4. API Usage Control

### 4.1 Caching System

#### Cache Table Structure
- **Location**: Latitude, longitude (rounded to ~100m precision)
- **Date**: Date string (YYYY-MM-DD)
- **Datum**: Chart datum (default: CD)
- **Data**: JSON-encoded tide extremes
- **Timestamps**: Cached at, expires at
- **Expiry**: 7 days (configurable)
- **Uniqueness**: Unique constraint on (latitude, longitude, date, datum)

#### Cache Behavior
- **Check Before API Call**: Always check cache before making WorldTides API request
- **Cache Hit**: Return cached data if not expired
- **Cache Miss**: Fetch from API, then cache the response
- **Cache Expiry**: Expired entries are ignored and will be re-fetched
- **Cache Cleanup**: Expired entries can be manually cleared

#### Cache Benefits
- **Reduced API Calls**: Multiple catches from same location/date share cached data
- **Faster Response**: Cached data is returned instantly
- **Cost Savings**: Fewer API credits consumed
- **Offline Capability**: Cached data available without internet

### 4.2 Smart Fetching Logic

The system only fetches WorldTides data when:
- No existing WorldTides context exists, OR
- Date/time has changed significantly (>1 hour difference), OR
- GPS coordinates have changed significantly (>100m difference)

This prevents unnecessary API calls when:
- Editing a catch without changing time/location
- Saving multiple catches from the same fishing session
- Re-calculating environmental data for existing catches

### 4.3 Backfill Safety Warnings

#### Recalculate Environmental Data Dialog
- **Counts API Calls**: Estimates number of WorldTides API calls needed
- **Warning Box**: Orange warning box showing:
  - "WorldTides API Usage" header
  - Estimated API call count
  - "This will consume API credits from your WorldTides account"
- **User Confirmation**: User must explicitly confirm before proceeding
- **Cancellation**: User can cancel to avoid API usage

#### Cache Impact on Backfill
- Cached data is used during backfill when available
- Only unique location/date combinations trigger API calls
- Multiple catches from same fishing day = 1 API call (after first)

---

## 5. Known Limitations

### 5.1 WorldTides API Limitations

- **API Key Required**: Users must obtain and configure their own WorldTides API key
- **API Quota**: Free tier has limited monthly requests
- **Rate Limiting**: API may rate limit excessive requests
- **No Station Names**: Current API request pattern doesn't return station names (uses "the nearest" wording)
- **Datum Fixed**: Uses CD (Chart Datum) - may not match all local tide charts
- **Coverage**: API may not have data for all remote locations

### 5.2 Manual Entry Limitations

- **User Knowledge Required**: Users need to read tide charts correctly
- **Time Entry**: Manual date/time entry can be error-prone
- **No Validation**: System doesn't validate manual tide heights against local knowledge
- **No Automatic Updates**: Manual data doesn't update if conditions change

### 5.3 Caching Limitations

- **Cache Expiry**: 7-day expiry may not match all use cases
- **Location Precision**: ~100m precision may group distinct locations
- **Manual Cache Clearing**: No UI for users to clear cache (must use developer tools)
- **Cache Size**: Unlimited cache growth (no automatic size limits)

### 5.4 UI Limitations

- **No Tide Graph**: Visual tide graph not implemented
- **No Tide Prediction**: No future tide prediction beyond current day
- **No Tide Alerts**: No alerts for upcoming tide events
- **Manual Entry Complexity**: Many fields to fill for manual entry

### 5.5 Data Separation Limitations

- **No Migration Path**: No UI to convert manual data to WorldTides or vice versa
- **No Conflict Resolution**: If both manual and WorldTides exist, both are shown (no way to choose)
- **No Bulk Manual Entry**: Manual entry must be done catch-by-catch

---

## 6. Testing Focus Areas

### 6.1 For Testers with WorldTides API Key

#### Primary Focus
1. **API Configuration**: Test setting up WorldTides API key in Settings
2. **Automatic Tide Fetching**: Create catches with GPS and verify automatic tide context
3. **Cache Effectiveness**: Create multiple catches from same location/day and verify only 1 API call
4. **Display Accuracy**: Compare displayed tide context with local tide charts
5. **Backfill Warning**: Test "Recalculate Environmental Data" and verify warning appears

#### Edge Cases
- Test with no GPS coordinates (should not fetch tide)
- Test with invalid API key (should handle gracefully)
- Test with rate-limited API (should handle gracefully)
- Test editing catch time/location (should re-fetch if significant change)

### 6.2 For Testers Without WorldTides API Key

#### Primary Focus
1. **Manual Tide Entry**: Test entering manual tide context fields
2. **Manual Display**: Verify manual tide context displays correctly in orange card
3. **Context Phrase Generation**: Verify auto-generated phrase from manual data
4. **Legacy Fields**: Test legacy manual tide fields (stage, strength, movement)
5. **Data Persistence**: Verify manual data persists after editing catch

#### Edge Cases
- Test partial manual entry (only some fields filled)
- Test manual entry with invalid data (negative heights, future times)
- Test switching between manual and official (if API key added later)

### 6.3 For All Testers

#### UI/UX Focus
1. **Readability**: Can you understand the tide context phrase?
2. **Color Coding**: Is the blue/orange color distinction clear?
3. **Information Hierarchy**: Is the most important tide information prominent?
4. **Missing Data**: Is the "Tide context not available" message clear?
5. **Form Usability**: Is the manual tide entry form easy to use?

#### Data Integrity Focus
1. **Data Separation**: Can you distinguish between manual and official data?
2. **Data Persistence**: Does tide data survive app restart?
3. **Data Editing**: Can you edit tide data without breaking anything?
4. **Data Deletion**: What happens to tide data when a catch is deleted?

#### Performance Focus
1. **Catch Save Speed**: Does tide fetching slow down catch save?
2. **Cache Speed**: Is cached data returned instantly?
3. **Backfill Speed**: How long does environmental recalculation take?
4. **Offline Behavior**: Does the app work offline with cached data?

---

## 7. Success Criteria

### 7.1 Functional Success
- [ ] WorldTides API integration works correctly with valid API key
- [ ] Manual tide entry works and displays correctly
- [ ] Caching reduces API calls for same location/date
- [ ] Backfill warnings appear and prevent accidental API usage
- [ ] Manual and official data are clearly separated

### 7.2 UX Success
- [ ] Tide context phrases are readable and useful
- [ ] Color coding makes data sources obvious
- [ ] Manual entry form is usable on mobile
- [ ] Missing data is handled gracefully
- [ ] Testers understand the difference between manual and official data

### 7.3 Performance Success
- [ ] Catch save is not blocked by tide fetching (non-blocking)
- [ ] Cached data is returned instantly
- [ ] Backfill completes in reasonable time (<5 minutes for 100 catches)
- [ ] App remains responsive during tide operations

### 7.4 Reliability Success
- [ ] No crashes when API is unavailable
- [ ] No crashes when API returns errors
- [ ] No crashes when manual data is invalid
- [ ] No data corruption during backfill
- [ ] Cache doesn't cause stale data issues

---

## 8. Post-Testing Enhancements (Future Work)

### 8.1 High Priority
- **Tide Graph Visualization**: Add visual tide graph for better context
- **Cache Management UI**: Add UI for users to view/clear cache
- **Manual Data Migration**: Add UI to convert manual to official or vice versa
- **Bulk Manual Entry**: Add ability to enter manual tide for multiple catches

### 8.2 Medium Priority
- **Tide Alerts**: Add alerts for upcoming tide events
- **Future Tide Prediction**: Show tide for next 7 days
- **Station Name Display**: Improve API request to get station names
- **Datum Selection**: Allow users to select chart datum

### 8.3 Low Priority
- **Tide History**: Show historical tide data for location
- **Tide Comparison**: Compare tide conditions across catches
- **Tide Analytics**: Analyze catch success vs. tide conditions
- **Custom Tide Sources**: Support other tide data providers

---

## 9. Configuration Notes

### 9.1 WorldTides API Setup
1. Obtain API key from https://www.worldtides.info/
2. Open Bragmat Settings
3. Navigate to WorldTides section
4. Enter API key
5. Test API connection
6. Save settings

### 9.2 Cache Configuration
- **Default Expiry**: 7 days
- **Location Precision**: ~100m (0.001 degrees)
- **Datum**: CD (Chart Datum)
- **Storage**: SQLite database (tide_cache table)
- **Cleanup**: Manual (via developer tools or future UI)

### 9.3 Database Version
- **Current Version**: 27
- **Migration**: Automatic on app upgrade
- **New Tables**: tide_cache
- **New Indexes**: idx_tide_cache_location_date

---

## 10. Support and Feedback

### 10.1 Known Issues
- None at this time

### 10.2 Feedback Channels
- Report issues via app feedback mechanism
- Document any discrepancies between Bragmat tide data and local tide charts
- Note any performance issues during tide operations

### 10.3 Testing Timeline
- **Testing Period**: 2 weeks
- **Feedback Due**: [Insert Date]
- **Issue Resolution**: [Insert Date]
- **Production Release**: [Insert Date]

---

## Appendix A: Tide Context Phrase Examples

### WorldTides Generated
- "2 hours 15 minutes before the nearest high tide of 6.50 m at 3:45 PM"
- "45 minutes after the nearest low tide of 1.20 m at 9:30 AM"
- "3 hours 30 minutes before the Sydney Harbour high tide of 5.80 m at 2:15 PM"

### Manual Generated
- "1 hour 30 minutes after the high tide of 7.20 m at 4:00 PM"
- "2 hours before the low tide of 0.80 m at 10:15 AM"
- "3 hours 45 minutes after the Darwin high tide of 6.90 m at 5:30 PM"

---

## Appendix B: API Credit Estimation

### Free Tier WorldTides
- **Monthly Requests**: 500
- **Cost**: Free
- **Estimated Catches per Month**: ~500 (with caching, potentially more)

### Paid Tier WorldTides
- **Monthly Requests**: 10,000+
- **Cost**: ~$10/month
- **Estimated Catches per Month**: ~10,000+ (with caching, potentially much more)

### Caching Impact
- **Without Caching**: 1 API call per catch
- **With Caching**: 1 API call per unique location/day
- **Typical Reduction**: 50-90% fewer API calls (depending on fishing patterns)

---

**End of Report**
