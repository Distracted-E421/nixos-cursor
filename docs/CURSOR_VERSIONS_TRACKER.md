# Cursor Versions Tracker

## Purpose

Track Cursor IDE releases to:
1. Update our version management system
2. Monitor feature additions/removals
3. Plan workarounds for removed features
4. Research new internal changes

---

## Version History (Recent)

### v2.2.x Series (Current)
- **Status**: Need to research
- **Notable**: Custom modes removed?
- **Links**: TBD (user to provide)

### v2.1.x Series
- **Status**: Need to research
- **Notable**: Changes to agent/plan modes?
- **Links**: TBD

### v2.0.x Series
- **v2.0.77**: Known stable
- **v2.0.71**: Previous stable
- **v2.0.64**: Archived

### v1.7.x Series (Legacy)
- Still supported for compatibility
- More stable, fewer features

---

## Feature Tracking

### ✅ Features We Support
- Version management (import, switch, launch)
- AppImage handling
- SQLite chat database reading
- Configuration sync detection

### ❌ Features Removed by Cursor
- **Custom Modes** (removed ~v2.1?)
  - System prompt customization
  - Tool locking per mode
  - Model selection per mode
  - **OUR PRIORITY: Rebuild this externally**

### 🔍 Features to Research
- Agent mode internals
- Plan mode implementation
- Composer file selection
- Context window management

---

## Links Collection

*To be filled with user-provided links*

### Official
- Cursor Website: https://cursor.com
- Changelog: https://cursor.com/changelog
- Download: https://download.cursor.sh/

### Version-Specific
- v2.2.x: [TBD]
- v2.1.x: [TBD]
- v2.0.x: [TBD]

### Research Resources
- [TBD]

---

## Version Database Schema

```sql
-- versions table in cursor-studio
CREATE TABLE cursor_versions (
    version TEXT PRIMARY KEY,
    release_date TEXT,
    download_url TEXT,
    sha256_hash TEXT,
    features_added TEXT,  -- JSON array
    features_removed TEXT, -- JSON array
    known_issues TEXT,     -- JSON array
    notes TEXT
);
```

---

## Update Process

1. Check Cursor changelog/releases
2. Download new AppImage
3. Compute SHA256 hash
4. Update versions database
5. Test basic functionality
6. Document changes

---

## TODO

- [ ] User to provide v2.1.x and v2.2.x links
- [ ] Research what changed in each version
- [ ] Document custom modes removal
- [ ] Plan external mode system

