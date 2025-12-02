//! CRDT (Conflict-free Replicated Data Types) implementation for chat sync.
//!
//! Uses vector clocks to track causality and enable conflict-free merging
//! across multiple devices.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A device identifier (random 128-bit ID, generated once per device)
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct DeviceId(pub String);

impl DeviceId {
    /// Generate a new random device ID
    pub fn new() -> Self {
        Self(uuid::Uuid::new_v4().to_string())
    }

    /// Create from existing string
    pub fn from_string(s: String) -> Self {
        Self(s)
    }
}

impl Default for DeviceId {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for DeviceId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Vector clock for tracking causality across devices.
///
/// Each device maintains a counter that increments on each update.
/// Comparing vector clocks tells us if one event happened-before another,
/// or if they are concurrent (conflict).
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct VectorClock {
    /// Map of device ID to logical timestamp
    clocks: HashMap<String, u64>,
}

impl VectorClock {
    /// Create a new empty vector clock
    pub fn new() -> Self {
        Self::default()
    }

    /// Increment the clock for a specific device
    pub fn increment(&mut self, device_id: &DeviceId) {
        let counter = self.clocks.entry(device_id.0.clone()).or_insert(0);
        *counter += 1;
    }

    /// Get the current value for a device
    pub fn get(&self, device_id: &DeviceId) -> u64 {
        self.clocks.get(&device_id.0).copied().unwrap_or(0)
    }

    /// Merge two vector clocks (take max of each component)
    pub fn merge(&self, other: &VectorClock) -> VectorClock {
        let mut merged = self.clocks.clone();

        for (device, &timestamp) in &other.clocks {
            let entry = merged.entry(device.clone()).or_insert(0);
            *entry = (*entry).max(timestamp);
        }

        VectorClock { clocks: merged }
    }

    /// Check if this clock happened-before another clock
    ///
    /// Returns true if all components of self are <= other,
    /// and at least one component is strictly less.
    pub fn happened_before(&self, other: &VectorClock) -> bool {
        let mut dominated = false;

        // Check all keys in self
        for (device, &timestamp) in &self.clocks {
            let other_time = other.clocks.get(device).copied().unwrap_or(0);
            if timestamp > other_time {
                return false; // Not dominated
            }
            if timestamp < other_time {
                dominated = true;
            }
        }

        // Check for keys only in other
        for device in other.clocks.keys() {
            if !self.clocks.contains_key(device) && other.clocks[device] > 0 {
                dominated = true;
            }
        }

        dominated
    }

    /// Check if two clocks are concurrent (neither happened-before the other)
    pub fn concurrent_with(&self, other: &VectorClock) -> bool {
        !self.happened_before(other) && !other.happened_before(self) && self != other
    }

    /// Check if this clock is newer or equal to another
    pub fn is_newer_or_equal(&self, other: &VectorClock) -> bool {
        !self.happened_before(other)
    }
}

/// Ordering relationship between two vector clocks
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClockOrdering {
    /// First happened before second
    Before,
    /// Second happened before first
    After,
    /// Neither happened before the other
    Concurrent,
    /// Clocks are identical
    Equal,
}

impl VectorClock {
    /// Compare two vector clocks
    pub fn compare(&self, other: &VectorClock) -> ClockOrdering {
        if self == other {
            ClockOrdering::Equal
        } else if self.happened_before(other) {
            ClockOrdering::Before
        } else if other.happened_before(self) {
            ClockOrdering::After
        } else {
            ClockOrdering::Concurrent
        }
    }
}

/// Sync state for tracking what has been synced with a peer/server
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SyncState {
    /// Last known vector clock from each peer
    pub peer_clocks: HashMap<String, VectorClock>,
    /// Our local clock
    pub local_clock: VectorClock,
    /// Our device ID
    pub device_id: DeviceId,
}

impl SyncState {
    /// Create new sync state for a device
    pub fn new(device_id: DeviceId) -> Self {
        Self {
            peer_clocks: HashMap::new(),
            local_clock: VectorClock::new(),
            device_id,
        }
    }

    /// Record a local update
    pub fn local_update(&mut self) {
        self.local_clock.increment(&self.device_id);
    }

    /// Update our knowledge of a peer's clock
    pub fn update_peer_clock(&mut self, peer_id: &str, clock: VectorClock) {
        self.peer_clocks.insert(peer_id.to_string(), clock);
    }

    /// Get the clock we last synced with a peer
    pub fn get_peer_clock(&self, peer_id: &str) -> Option<&VectorClock> {
        self.peer_clocks.get(peer_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vector_clock_increment() {
        let device = DeviceId::from_string("device-a".to_string());
        let mut clock = VectorClock::new();

        assert_eq!(clock.get(&device), 0);
        clock.increment(&device);
        assert_eq!(clock.get(&device), 1);
        clock.increment(&device);
        assert_eq!(clock.get(&device), 2);
    }

    #[test]
    fn test_vector_clock_merge() {
        let device_a = DeviceId::from_string("device-a".to_string());
        let device_b = DeviceId::from_string("device-b".to_string());

        let mut clock1 = VectorClock::new();
        clock1.increment(&device_a);
        clock1.increment(&device_a);

        let mut clock2 = VectorClock::new();
        clock2.increment(&device_b);
        clock2.increment(&device_b);
        clock2.increment(&device_b);

        let merged = clock1.merge(&clock2);
        assert_eq!(merged.get(&device_a), 2);
        assert_eq!(merged.get(&device_b), 3);
    }

    #[test]
    fn test_vector_clock_ordering() {
        let device = DeviceId::from_string("device-a".to_string());

        let mut clock1 = VectorClock::new();
        clock1.increment(&device);

        let mut clock2 = clock1.clone();
        clock2.increment(&device);

        assert_eq!(clock1.compare(&clock2), ClockOrdering::Before);
        assert_eq!(clock2.compare(&clock1), ClockOrdering::After);
        assert_eq!(clock1.compare(&clock1), ClockOrdering::Equal);
    }

    #[test]
    fn test_vector_clock_concurrent() {
        let device_a = DeviceId::from_string("device-a".to_string());
        let device_b = DeviceId::from_string("device-b".to_string());

        let mut clock1 = VectorClock::new();
        clock1.increment(&device_a);

        let mut clock2 = VectorClock::new();
        clock2.increment(&device_b);

        assert_eq!(clock1.compare(&clock2), ClockOrdering::Concurrent);
    }
}
