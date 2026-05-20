//! Bloom filter deduplication

use bloomfilter::Bloom;
use std::sync::RwLock;

pub struct DedupFilter {
    bloom: RwLock<Bloom<String>>,
}

impl DedupFilter {
    pub fn new(size: usize, fp_rate: f64) -> Self {
        let bloom = Bloom::new_for_fp_rate(size, fp_rate);
        Self {
            bloom: RwLock::new(bloom),
        }
    }

    /// Check if key is new (not duplicate)
    pub fn check(&self, key: &str) -> bool {
        let mut bloom = self.bloom.write().unwrap();
        if bloom.check(&key.to_string()) {
            false // duplicate
        } else {
            bloom.set(&key.to_string());
            true // new
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dedup_new_key() {
        let dedup = DedupFilter::new(1000, 0.01);
        assert!(dedup.check("key1"));
    }

    #[test]
    fn test_dedup_duplicate_key() {
        let dedup = DedupFilter::new(1000, 0.01);
        assert!(dedup.check("key1"));
        assert!(!dedup.check("key1"));
    }

    #[test]
    fn test_dedup_different_keys() {
        let dedup = DedupFilter::new(1000, 0.01);
        assert!(dedup.check("key1"));
        assert!(dedup.check("key2"));
        assert!(dedup.check("key3"));
    }

    #[test]
    fn test_dedup_sequence() {
        let dedup = DedupFilter::new(1000, 0.01);
        assert!(dedup.check("SYMBOL-A:1000"));
        assert!(dedup.check("SYMBOL-A:1001"));
        assert!(!dedup.check("SYMBOL-A:1000"));
        assert!(dedup.check("SYMBOL-B:1000"));
    }

    #[test]
    fn test_dedup_empty_string() {
        let dedup = DedupFilter::new(1000, 0.01);
        assert!(dedup.check(""));
        assert!(!dedup.check(""));
    }

    #[test]
    fn test_dedup_large_size() {
        let dedup = DedupFilter::new(1_000_000, 0.001);
        for i in 0..100 {
            let key = format!("key{}", i);
            assert!(dedup.check(&key));
        }
    }
}
